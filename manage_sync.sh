#!/bin/bash

# Name of the script to manage
SCRIPT_NAME="sync_git_auto.sh"

case "$1" in
    status)
        # Check if the script is running
        PID=$(pgrep -f "$SCRIPT_NAME")
        if [ -z "$PID" ]; then
            echo "Status: $SCRIPT_NAME is NOT running."
        else
            echo "Status: $SCRIPT_NAME is running with PID: $PID"
            echo "Recent logs:"
            tail -n 5 sync_history.log 2>/dev/null || echo "No log file found."
        fi
        ;;
    stop)
        # Find and kill the process
        PID=$(pgrep -f "$SCRIPT_NAME")
        if [ -z "$PID" ]; then
            echo "Error: $SCRIPT_NAME is not running."
        else
            echo "Stopping $SCRIPT_NAME (PID: $PID)..."
            kill $PID
            echo "Done."
        fi
        ;;
    *)
        echo "Usage: $0 {status|stop}"
        exit 1
        ;;
esac