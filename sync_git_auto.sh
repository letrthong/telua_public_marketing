#!/usr/bin/env bash

# Thoát ngay lập tức nếu một lệnh thoát với trạng thái khác không.
set -e

# git config --global credential.helper store
 

# --- CẤU HÌNH ---
SOURCE_DIR="/opt/telua_web/app/config"
DEST_DIR="."
INTERVAL=1800 # 30 phút (1800 giây)

while true
do
    echo "------------------------------------------------"
    echo "Bắt đầu đồng bộ lúc: $(date)"

    # 1. Đồng bộ file từ nguồn vào Repo B
    echo "Bước 1: Chạy rsync..."
    rsync -av --exclude='.git' "$SOURCE_DIR" "$DEST_DIR"

    # 2. Kiểm tra thay đổi trong Git
    if [[ -n $(git status --porcelain) ]]; then
        echo "Bước 2: Phát hiện thay đổi. Đang chuẩn bị push..."
        
        # Thêm tất cả thay đổi
        git add -A
        
        # Commit với thời gian
        git commit -m "Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')"
        
        # TRƯỚC KHI PUSH: Thử pull về để tránh lỗi xung đột (conflict)
        # --rebase giúp lịch sử git sạch hơn
        echo "Bước 3: Pull (rebase) để đồng bộ trước khi push..."
        if git pull --rebase origin main; then # Thay 'main' bằng tên nhánh của bạn nếu khác
            # 4. Thực hiện Push
            echo "Bước 4: Push các thay đổi..."
            if git push; then
                echo "Push thành công!"
            else
                echo "LỖI PUSH! Có thể do mạng hoặc xung đột chưa giải quyết."
                echo "Script sẽ thử lại hoàn toàn trong chu kỳ tiếp theo."
            fi
        else
            echo "LỖI PULL! Không thể pull từ remote. Có thể có xung đột (conflict)."
            echo "Vui lòng giải quyết thủ công. Script sẽ thử lại trong chu kỳ tiếp theo."
        fi

    else
        echo "Bước 2: Không có thay đổi nào. Không cần push."
    fi

    echo "Đợi 30 phút..."
    sleep $INTERVAL
done