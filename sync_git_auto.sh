#!/usr/bin/env bash
# git config --global credential.helper store
 

# --- CẤU HÌNH ---
SOURCE_DIR="/opt/web/config/"
DEST_DIR="."
INTERVAL=1800 # 30 phút

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
        echo "Bước 3: Thử pull để đồng bộ trước khi push..."
        git pull --rebase origin main # Thay 'main' bằng tên nhánh của bạn nếu khác

        # 4. Thực hiện Push
        if git push; then
            echo "Bước 4: Push thành công!"
        else
            echo "Bước 4: LỖI PUSH! Có thể do mạng hoặc xung đột chưa giải quyết."
            echo "Script sẽ thử lại hoàn toàn sau 30 phút nữa."
        fi
    else
        echo "Bước 2: Không có thay đổi nào. Không cần push."
    fi

    echo "Đợi 30 phút..."
    sleep $INTERVAL
done