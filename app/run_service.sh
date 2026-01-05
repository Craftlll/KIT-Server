#!/bin/bash
# run_service.sh
# Starts the Unified R Service

cd "$(dirname "$0")"

LOG_DIR="logs"
mkdir -p "$LOG_DIR"

PORT=8000
echo "Starting Unified Service on Port $PORT..."

# Start R script with Plumber
# Using nohup to keep it running? Or just foreground for now. 
# Let's run in foreground so user sees output, or background with log.
# User usually wants to verify, so let's run in background and tail log.

Rscript -e "r <- plumber::plumb('app.R'); r\$run(port=$PORT, host='0.0.0.0')" > "$LOG_DIR/service.log" 2>&1 &
PID=$!

echo "Service started with PID $PID"
echo "Logging to $LOG_DIR/service.log"
echo "Waiting for initialization..."

sleep 5
tail -n 10 "$LOG_DIR/service.log"

echo "Check health: http://localhost:$PORT/health"
