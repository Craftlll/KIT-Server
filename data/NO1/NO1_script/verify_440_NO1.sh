#!/bin/bash

# ==============================================================================
# Script Name: verify_440_NO1.sh
# ==============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

SERVICE_SCRIPT="NO1_lite_plumber.R"
PORT=8081

echo "Starting Service for Validation (NO1)..."
Rscript -e "r <- plumber::plumb('$SERVICE_SCRIPT'); r\$run(port=$PORT)" > validation_service_no1.log 2>&1 &
PID=$!
sleep 5

echo "Test 1: Check Valid Gene (GAPDH) - /plots/gene"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/plots/gene?gene=GAPDH")
if [ "$HTTP_CODE" == "200" ]; then
    echo "  -> PASS (200)"
else
    echo "  -> FAIL ($HTTP_CODE)"
fi

echo "Test 2: Check Invalid Gene (INVALID_GENE_X) - /plots/gene"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/plots/gene?gene=INVALID_GENE_X")
if [ "$HTTP_CODE" == "440" ]; then
    echo "  -> PASS (440)"
else
    echo "  -> FAIL: Expected 440, got $HTTP_CODE"
fi

echo "Test 3: Check Invalid Gene (INVALID_GENE_X) - /genes/check"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/genes/check?gene=INVALID_GENE_X")
if [ "$HTTP_CODE" == "440" ]; then
    echo "  -> PASS (440)"
else
    echo "  -> FAIL: Expected 440, got $HTTP_CODE"
fi

kill $PID
rm validation_service_no1.log
