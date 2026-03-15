#!/usr/bin/env bash

# Thoát ngay lập tức nếu một lệnh thoát với trạng thái khác không.
set -e

# Load cấu hình từ file .env cùng thư mục (nếu có)
if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
fi

# git config --global credential.helper store
 

# --- CẤU HÌNH ---
SOURCE_DIRS=("/opt/telua_web/app/config" "/opt/telua_web/app/video")
DEST_DIR="."
INTERVAL=1800 # 30 phút (1800 giây)
LOG_FILE="${SYNC_LOG_FILE:-/opt/sync_history.log}"
MAX_LOG_LINES=5000

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Kiểm tra và tạo thư mục key (không sync)
if [ ! -d "/opt/telua_web/app/key" ]; then
    log "Thư mục key '/opt/telua_web/app/key' không tồn tại. Đang tạo mới..."
    mkdir -p "/opt/telua_web/app/key"
fi

LAST_PRUNE_DATE=""

while true
do
    # Kiểm tra kích thước log và xóa nếu quá dài
    if [ -f "$LOG_FILE" ]; then
        LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
            : > "$LOG_FILE"
            log "Log quá dài ($LINE_COUNT dòng). Đã xóa nội dung log cũ."
        fi
    fi

    log "------------------------------------------------"
    log "Bắt đầu đồng bộ lúc: $(date)"

    # Kiểm tra và tạo các thư mục nguồn nếu chúng không tồn tại
    for DIR in "${SOURCE_DIRS[@]}"; do
        if [ ! -d "$DIR" ]; then
            log "Thư mục nguồn '$DIR' không tồn tại. Đang tạo mới..."
            mkdir -p "$DIR"
        fi
    done

    
    # 1. Đồng bộ file từ nguồn vào Repo B
    log "Bước 1: Chạy rsync..."
    rsync -av --exclude='.git' "${SOURCE_DIRS[@]}" "$DEST_DIR"

    # 2. Kiểm tra thay đổi trong Git
    if [[ -n $(git status --porcelain) ]]; then
        log "Bước 2: Phát hiện thay đổi. Đang chuẩn bị push..."
        
        # Thêm tất cả thay đổi
        git add -A
        
        # Commit với thời gian
        git commit -m "Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')"
        
        # TRƯỚC KHI PUSH: Thử pull về để tránh lỗi xung đột (conflict)
        # --rebase giúp lịch sử git sạch hơn
        log "Bước 3: Pull (rebase) để đồng bộ trước khi push..."
        if git pull --rebase origin main; then # Thay 'main' bằng tên nhánh của bạn nếu khác
            # 4. Thực hiện Push
            log "Bước 4: Push các thay đổi..."
            if git push; then
                log "Push thành công!"
            else
                log "LỖI PUSH! Có thể do mạng hoặc xung đột chưa giải quyết."
                log "Script sẽ thử lại hoàn toàn trong chu kỳ tiếp theo."
            fi
        else
            log "LỖI PULL! Không thể pull từ remote. Có thể có xung đột (conflict)."
            log "Vui lòng giải quyết thủ công. Script sẽ thử lại trong chu kỳ tiếp theo."
        fi

    else
        log "Bước 2: Không có thay đổi nào. Không cần push."
    fi

    # Dọn dẹp bộ nhớ cache của Docker mỗi ngày một lần
    CURRENT_DATE=$(date '+%Y-%m-%d')
    if [ "$LAST_PRUNE_DATE" != "$CURRENT_DATE" ]; then
        log "Dọn dẹp Docker cache (chạy mỗi ngày một lần)..."
        docker system prune -f || log "Cảnh báo: Không thể dọn dẹp Docker cache."
        LAST_PRUNE_DATE="$CURRENT_DATE"
    fi

    # Kiểm tra RAM và khởi động lại nếu > 90%
    MEM_INFO=$(free -m | awk '/^Mem:/ {printf "RAM Usage: %sMB / %sMB", $3, $2}')
    log "$MEM_INFO"
    RAM_PERCENT=$(free | awk '/^Mem:/ {printf "%d", $3/$2 * 100}')
    if [ "$RAM_PERCENT" -gt 90 ]; then
        log "CẢNH BÁO: RAM sử dụng đã đạt $RAM_PERCENT% (> 90%). Đang khởi động lại hệ thống..."
        sleep 5
        sudo reboot
    fi

    log "Đợi 30 phút..."
    sleep $INTERVAL
done