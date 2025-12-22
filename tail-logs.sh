#!/bin/bash

# Tail the iCloud Bridge logs
LOG_FILE="$HOME/Library/Logs/iCloudBridge/reminders.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "Log file doesn't exist yet: $LOG_FILE"
    echo "Waiting for logs to be created..."
    while [ ! -f "$LOG_FILE" ]; do
        sleep 1
    done
fi

echo "Tailing iCloud Bridge logs..."
echo "Log file: $LOG_FILE"
echo "---"
tail -f "$LOG_FILE"
