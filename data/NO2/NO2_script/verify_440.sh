#!/bin/bash

# ==============================================================================
# Script Name: verify_440.sh
# ==============================================================================

SERVICE_SCRIPT="NO2_lite_plumber.R"
PORT=8002

echo "Starting Service for Validation..."
Rscript -e "r <- plumber::plumb('$SERVICE_SCRIPT'); r\$run(port=$PORT)" > validation_service.log 2>&1 &
PID=$!
sleep 5

echo "Test 1: Check Valid Gene (GAPDH)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/plots/gene?gene=GAPDH")
if [ "$HTTP_CODE" == "200" ]; then
    echo "  -> PASS (200)"
else
    echo "  -> FAIL ($HTTP_CODE)"
fi

echo "Test 2: Check Invalid Gene (INVALID_GENE_X)"
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
rm validation_service.log
