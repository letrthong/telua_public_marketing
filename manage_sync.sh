#!/bin/bash

# Load cấu hình từ file .env cùng thư mục (nếu có)
if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
fi

# Name of the script to manage
SCRIPT_NAME="sync_git_auto.sh"

# Định nghĩa log file thông qua biến môi trường (hoặc dùng mặc định)
LOG_FILE="${SYNC_LOG_FILE:-/opt/sync_history.log}"

case "$1" in
    restart)
        systemctl restart sync-git
        ;;
    status)
        # Check if the script is running
        PID=$(pgrep -f "$SCRIPT_NAME")
        
        # Lấy thông tin RAM hiện tại
        MEM_INFO=$(free -m | awk '/^Mem:/ {printf "RAM Used: %sMB, Available: %sMB / Total: %sMB", $3, $7, $2}')
        
        if [ -z "$PID" ]; then
            echo "Status: $SCRIPT_NAME is NOT running."
            echo "Current time: $(date '+%H:%M:%S')"
            echo ""
            echo "$MEM_INFO"
            echo "CPU Cores: $(nproc)"
        else
            echo "Status: $SCRIPT_NAME is running with PID: $PID"
            echo "Current time: $(date '+%H:%M:%S')"
            echo "$MEM_INFO"
            echo "CPU Cores: $(nproc)"
            echo ""
            echo "Recent logs:"
            tail -n 15 "$LOG_FILE" 2>/dev/null || echo "No log file found."
        fi

        docker stats --no-stream
        
        ;;
    stop)
        # Find and kill the process
        PID=$(pgrep -f "$SCRIPT_NAME")
        if [ -z "$PID" ]; then
            echo "Error: $SCRIPT_NAME is not running."
        else
            echo "Stopping $SCRIPT_NAME (PID: $PID)..."
            systemctl stop sync-git
            echo "Done."
        fi
        ;;
    sync)
        echo "Syncing config back to /opt/telua_web/app/config..."
        if [ -d "./config" ]; then
            rsync -av ./config/ /opt/telua_web/app/config/
            echo "Sync completed."
        else
            echo "Error: ./config directory not found in the current path."
        fi
        ;;
    *)
        echo "Usage: $0 {restart|status|stop|sync}"
        exit 1
        ;;
esac