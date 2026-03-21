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

    # --- KIỂM TRA HEALTH CHECK ---
    log "Đang kiểm tra health_check..."
    # Dùng curl lấy status code. Thêm || echo "000" để tránh script chết do 'set -e' khi ứng dụng sập hẳn
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://telua.vn/health_check|| echo "000")
    HEALTH_LOG_FILE="health_check.log"
    
    if [ "$HTTP_STATUS" -ne 200 ]; then
        log "CẢNH BÁO: health_check thất bại! Trả về HTTP Code: $HTTP_STATUS"
        # Ghi riêng vào file log health_check theo yêu cầu
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] CẢNH BÁO: health_check thất bại! Trả về HTTP Code: $HTTP_STATUS" >> "$HEALTH_LOG_FILE"
       # systemctl restart telua_web
    else
        log "Health check OK (200)"
    fi

    # Kiểm tra RAM: Sử dụng thông số Available (Khả dụng) để chống Out of Memory chính xác nhất
    MEM_INFO=$(free -m | awk '/^Mem:/ {printf "RAM Used: %sMB, Available: %sMB / Total: %sMB", $3, $7, $2}')
    log "$MEM_INFO"

    # Lấy dung lượng RAM thực sự CÒN TRỐNG tính bằng MB (Available)
    AVAILABLE_MB=$(free -m | awk '/^Mem:/ {print $7}')

    if [ "$AVAILABLE_MB" -lt 70 ]; then
        docker system prune -f --volumes=false
    fi

    # Nếu RAM Khả dụng dưới 40MB
    if [ "$AVAILABLE_MB" -lt 40 ]; then
        log "CẢNH BÁO CRITICAL: RAM khả dụng chỉ còn ${AVAILABLE_MB}MB (< 50MB). Nguy cơ Out of Memory!"
        log "Đang khởi động lại hệ thống để bảo vệ máy chủ..."
        sleep 5
        reboot
    fi

    DISK_USAGE=$(df / | grep / | awk '{ print $5 }' | sed 's/%//g')
    log ""
    log "Dung lượng ổ đĩa hiện tại: $DISK_USAGE%"
    log ""

    if [ "$DISK_USAGE" -gt 80 ]; then
        log "Dung lượng > 80%, đang dọn dẹp sâu..."
        # Xóa build cache để giải phóng dung lượng lớn
        docker builder prune -f
        # Xóa các image cũ, rác
        docker image prune -f
    else
        log "Ổ cứng vẫn ổn, giữ lại cache để build nhanh."
        # Vẫn nên dọn dẹp nhẹ nhàng các container/network thừa
        docker system prune -f --volumes=false
    fi

    DISK_USAGE=$(df / | grep / | awk '{ print $5 }' | sed 's/%//g')
    log ""
    log "Dung lượng ổ đĩa hiện tại: $DISK_USAGE%"
    log ""

    log "Đợi 30 phút... "
    sleep $INTERVAL
done