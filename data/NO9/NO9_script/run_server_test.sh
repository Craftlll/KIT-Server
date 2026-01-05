#!/bin/bash

# ==============================================================================
# Script Name: run_server_test.sh (NO9 Version)
# ==============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

SERVICE_SCRIPT="NO9_lite_plumber.R"
PORT=8009
GENE_TO_TEST="Gnai3" 

echo "=========================================================="
echo "          Lite Service Deployment Verification (NO9)"
echo "=========================================================="
echo "Work Dir: $SCRIPT_DIR"
echo "Service Script: $SERVICE_SCRIPT"
echo "Data Dir (Relative): ../lite"

if [ ! -f "$SERVICE_SCRIPT" ]; then
    echo "[ERROR] Service script $SERVICE_SCRIPT not found!"
    exit 1
fi

DATA_DIR_CHECK="../lite/expression.h5"
if [ ! -f "$DATA_DIR_CHECK" ]; then
    echo "[ERROR] Lite data not found at $DATA_DIR_CHECK"
    echo "Please run the conversion pipeline first."
    exit 1
fi

echo ""
echo "[Step 1] Starting Service on port $PORT..."
Rscript -e "r <- plumber::plumb('$SERVICE_SCRIPT'); r\$run(port=$PORT)" > service_test.log 2>&1 &
SERVICE_PID=$!
echo "Service PID: $SERVICE_PID"

echo "[Step 2] Waiting for service to initialize..."
SERVICE_UP=false
for i in {1..30}; do
    if curl -s "http://localhost:$PORT/health" | grep -q "UP"; then
        SERVICE_UP=true
        echo "Service is UP and Ready!"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

if [ "$SERVICE_UP" = false ]; then
    echo "[ERROR] Service timeout."
    cat service_test.log
    kill $SERVICE_PID
    exit 1
fi

echo ""
echo "[Step 3] Running Functional Tests..."

echo -n "Test A: /plots/base ... "
curl -s "http://localhost:$PORT/plots/base" > base.json
if grep -q "uas.png" base.json; then
    echo "PASS"
else
    echo "FAIL"
    echo "Response: $(cat base.json)"
fi

echo -n "Test B: /plots/all?gene=$GENE_TO_TEST ... "
START_TIME=$(date +%s%N)
curl -s "http://localhost:$PORT/plots/all?gene=$GENE_TO_TEST" > all.json
END_TIME=$(date +%s%N)
elapsed=$(( ($END_TIME - $START_TIME) / 1000000 ))

if grep -q "feature_plot.png" all.json; then
    echo "PASS (Latency: ${elapsed}ms)"
else
    echo "FAIL"
    echo "Response: $(cat all.json)"
fi

echo -n "Test C: /genes/check?gene=INVALID_X (Exp 440) ... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/genes/check?gene=INVALID_X")
if [ "$HTTP_CODE" == "440" ]; then
    echo "PASS (440)"
else
    echo "FAIL ($HTTP_CODE)"
fi

echo -n "Test D: Case Insensitivity (GNAI3) ... "
curl -s "http://localhost:$PORT/genes/check?gene=GNAI3" > case.json
if grep -q "Gnai3" case.json; then
    echo "PASS"
else
    echo "FAIL - $(cat case.json)"
fi


echo ""
echo "[Step 4] Teardown..."
kill $SERVICE_PID
rm -f base.json all.json service_test.log case.json

echo "=========================================================="
if [ "$SERVICE_UP" = true ]; then
    echo "       NO9 VERIFICATION SUCCESSFUL"
else
    echo "       NO9 VERIFICATION FAILED"
fi
echo "=========================================================="
