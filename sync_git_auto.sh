#!/usr/bin/env bash

# =============================
# Script: sync_git_auto.sh
# Purpose: Automatically synchronize data, monitor system status, and manage resources for the server running the telua_web application.
#
# Main features:
# 1. Sync configuration and video folders from /opt/telua_web/app to the current repo, commit & push if there are changes.
# 2. Check the health_check endpoint, only restart the telua_web service if it fails.
# 3. Monitor and clean up RAM, disk, and logs to ensure the server runs stably.
# 4. Repeat the entire process every 15 minutes.
#
# Author:  Thong LT
# =============================

# KHÔNG dùng set -e vì đây là daemon loop chạy nền liên tục.
# Bất kỳ lệnh phụ nào lỗi (rsync, docker, mạng chập chờn) sẽ không làm chết script.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Xác định thư mục chứa script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load cấu hình từ file .env cùng thư mục (nếu có)
if [ -f "$SCRIPT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
fi

# git config --global credential.helper store

# --- CẤU HÌNH ---
SOURCE_DIRS=("/opt/telua_web/app/config" "/opt/telua_web/app/video")
DEST_DIR="$SCRIPT_DIR"
INTERVAL=600 # 10 phút (600 giây)
LOG_FILE="${SYNC_LOG_FILE:-/opt/sync_history.log}"
MAX_LOG_LINES=5000
HEALTH_LOG_FILE="$SCRIPT_DIR/health_check.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Kiểm tra và tạo thư mục key (không sync)
if [ ! -d "/opt/telua_web/app/key" ]; then
    log "Thư mục key '/opt/telua_web/app/key' không tồn tại. Đang tạo mới..."
    mkdir -p "/opt/telua_web/app/key" 2>/dev/null || log "CẢNH BÁO: Không thể tạo thư mục /opt/telua_web/app/key"
fi

cd "$SCRIPT_DIR" || exit 1

while true
do
    # 0. Kiểm tra kích thước log và xóa nếu quá dài
    if [ -f "$LOG_FILE" ]; then
        LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ' || echo 0)
        if [[ "$LINE_COUNT" =~ ^[0-9]+$ ]] && [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
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
            mkdir -p "$DIR" 2>/dev/null || log "CẢNH BÁO: Không thể tạo thư mục $DIR"
        fi
    done

    # 1. Đồng bộ file từ nguồn vào Repo B
    log "Bước 1: Chạy rsync..."
    # rsync có thể trả về 24 (file vanished khi đang ghi/xóa video) hoặc 23 -> log cảnh báo và không dừng script
    if ! rsync -av --exclude='.git' "${SOURCE_DIRS[@]}" "$DEST_DIR"; then
        log "CẢNH BÁO: rsync kết thúc với mã $? (có thể do file đang ghi hoặc quyền). Tiếp tục quy trình..."
    fi

    # 2. Kiểm tra thay đổi trong Git
    GIT_STATUS_OUTPUT=$(git status --porcelain 2>/dev/null || true)
    if [[ -n "$GIT_STATUS_OUTPUT" ]]; then
        log "Bước 2: Phát hiện thay đổi. Đang chuẩn bị push..."
        
        # Thêm tất cả thay đổi
        git add -A || log "CẢNH BÁO: git add gặp sự cố."
        
        # Chỉ commit khi thực sự có thay đổi được staged
        if ! git diff --cached --quiet 2>/dev/null; then
            if ! git commit -m "Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')"; then
                log "CẢNH BÁO: git commit thất bại (có thể do lock file hoặc config user.name/email)."
            fi
        fi
        
        # TRƯỚC KHI PUSH: Thử pull về để tránh lỗi xung đột (conflict)
        # --rebase giúp lịch sử git sạch hơn
        log "Bước 3: Pull (rebase) để đồng bộ trước khi push..."
        if git pull --rebase origin main; then
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
            # Dọn dẹp trạng thái rebase dở để repo không bị kẹt giữa rebase
            if git rebase --abort 2>/dev/null; then
                log "Đã hủy rebase (git rebase --abort) để dọn dẹp trạng thái."
            else
                log "Không có rebase đang dở hoặc không thể abort. Cần kiểm tra thủ công."
            fi
            log "Vui lòng giải quyết thủ công. Script sẽ thử lại trong chu kỳ tiếp theo."
        fi

    else
        log "Bước 2: Không có thay đổi nào. Không cần push."
    fi

    # --- KIỂM TRA HEALTH CHECK ---
    log "Đang kiểm tra health_check..."
    HTTP_STATUS="000"
    for attempt in 1 2 3 4 5 6; do
        # Lấy HTTP status code một cách an toàn, tránh lỗi 000000 do lặp echo
        RAW_STATUS=$(curl -sL --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" https://telua.vn/health_check/db_ready 2>/dev/null || true)
        if [[ "$RAW_STATUS" =~ ^[0-9]{3}$ ]]; then
            HTTP_STATUS="$RAW_STATUS"
        else
            HTTP_STATUS="000"
        fi

        if [ "$HTTP_STATUS" = "200" ]; then
            break
        fi
        log "Lần thử $attempt/6: health_check trả về HTTP Code: $HTTP_STATUS"
        if [ "$attempt" -lt 6 ]; then
            sleep 30
        fi
    done
    
    if [ "$HTTP_STATUS" != "200" ]; then
        log "CẢNH BÁO: health_check thất bại sau 6 lần thử! Trả về HTTP Code: $HTTP_STATUS"
        # Ghi riêng vào file log health_check
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] CẢNH BÁO: health_check thất bại! Trả về HTTP Code: $HTTP_STATUS" >> "$HEALTH_LOG_FILE" 2>/dev/null || true
        log "Đang restart service telua_web..."
        if systemctl restart telua_web 2>/dev/null; then
            log "Restart telua_web thành công."
        else
            log "LỖI: Restart telua_web thất bại! Cần kiểm tra thủ công."
        fi
    else
        log "Health check OK (200)"
    fi

    # --- KIỂM TRA RAM ---
    # Lấy thông tin RAM hiện tại
    MEM_INFO=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "RAM Used: %sMB, Available: %sMB / Total: %sMB", $3, $7, $2}')
    if [ -n "$MEM_INFO" ]; then
        log "$MEM_INFO"
    fi

    # Lấy dung lượng RAM thực sự CÒN TRỐNG tính bằng MB (Available)
    RAW_AVAILABLE=$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}')
    if [[ "$RAW_AVAILABLE" =~ ^[0-9]+$ ]]; then
        AVAILABLE_MB="$RAW_AVAILABLE"
    else
        AVAILABLE_MB=9999 # Giá trị an toàn nếu không đọc được RAM để không trigger bừa
    fi

    # Xử lý phân cấp RAM: Dùng if/elif để không bị restart xong reboot kép
    if [ "$AVAILABLE_MB" -lt 40 ]; then
        log "CẢNH BÁO CRITICAL: RAM khả dụng chỉ còn ${AVAILABLE_MB}MB (< 40MB). Nguy cơ Out of Memory!"
        log "Đang khởi động lại hệ thống để bảo vệ máy chủ..."
        sleep 5
        if reboot 2>/dev/null; then
            log "Đã gửi lệnh reboot."
        else
            log "LỖI: Không thể reboot (cần quyền root). Cần kiểm tra thủ công ngay!"
        fi
    elif [ "$AVAILABLE_MB" -lt 70 ]; then
        log "CẢNH BÁO: RAM khả dụng thấp (${AVAILABLE_MB}MB). Docker prune không giúp giải phóng RAM."
        log "Đang thử restart telua_web để giải phóng RAM..."
        if systemctl restart telua_web 2>/dev/null; then
            log "Restart telua_web thành công để giải phóng RAM."
        else
            log "LỖI: Restart telua_web thất bại khi RAM thấp. Cần kiểm tra thủ công."
        fi
    fi

    # --- KIỂM TRA DUNG LƯỢNG Ổ ĐĨA ---
    # Dùng df -P chuẩn POSIX đảm bảo output trên đúng 1 dòng per mount
    RAW_DISK=$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
    if [[ "$RAW_DISK" =~ ^[0-9]+$ ]]; then
        DISK_USAGE="$RAW_DISK"
    else
        DISK_USAGE=0
    fi
    log ""
    log "Dung lượng ổ đĩa hiện tại: $DISK_USAGE%"
    log ""

    if [ "$DISK_USAGE" -gt 80 ]; then
        log "Dung lượng > 80%, đang dọn dẹp sâu..."
        # Xóa build cache để giải phóng dung lượng lớn
        docker builder prune -f 2>/dev/null || log "CẢNH BÁO: docker builder prune thất bại."
        # Xóa image dangling (không dùng) + image cũ hơn 24h
        docker image prune -f --filter "until=24h" 2>/dev/null || true
        # Dọn container dừng lâu hơn 24h
        docker container prune -f --filter "until=24h" 2>/dev/null || true
    else
        log "Ổ cứng vẫn ổn, giữ lại cache để build nhanh."
        docker container prune -f --filter "until=24h" 2>/dev/null || true
    fi

    # Đọc lại dung lượng ổ đĩa sau khi dọn dẹp
    RAW_DISK=$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
    if [[ "$RAW_DISK" =~ ^[0-9]+$ ]]; then
        DISK_USAGE="$RAW_DISK"
    fi
    log ""
    log "Dung lượng ổ đĩa hiện tại: $DISK_USAGE%"
    log ""

    WAIT_MINUTES=$((INTERVAL / 60))
    log "Đợi $WAIT_MINUTES phút... "
    sleep "$INTERVAL"
done
