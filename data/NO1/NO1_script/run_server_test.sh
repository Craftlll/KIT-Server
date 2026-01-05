#!/bin/bash

# ==============================================================================
# Script Name: run_server_test.sh
# Description: Automated verification suite for the Lite Plumber Service.
#              Designed to be run on the deployment server to verify installation.
# Usage:       bash run_server_test.sh
# ==============================================================================

# 1. 设置工作上下文
# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

SERVICE_SCRIPT="NO1_lite_plumber.R"
PORT=8080   # 使用 8080 端口避免冲突
GENE_TO_TEST="GAPDH"

echo "=========================================================="
echo "          Lite Service Deployment Verification"
echo "=========================================================="
echo "Work Dir: $SCRIPT_DIR"
echo "Service Script: $SERVICE_SCRIPT"
echo "Data Dir (Relative): ../lite"

# 检查必要文件
if [ ! -f "$SERVICE_SCRIPT" ]; then
    echo "[ERROR] Service script $SERVICE_SCRIPT not found in current directory!"
    exit 1
fi

DATA_DIR_CHECK="../lite/expression.h5"
if [ ! -f "$DATA_DIR_CHECK" ]; then
    echo "[ERROR] Lite data not found at $DATA_DIR_CHECK"
    echo "Please run the conversion pipeline first."
    exit 1
fi

# 2. 启动服务
echo ""
echo "[Step 1] Starting Service on port $PORT..."
Rscript -e "r <- plumber::plumb('$SERVICE_SCRIPT'); r\$run(port=$PORT)" > service_test.log 2>&1 &
SERVICE_PID=$!
echo "Service PID: $SERVICE_PID"

# 3. 等待服务就绪 (轮询健康检查接口)
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
    echo "[ERROR] Service succeeded timeout. Check service_test.log for details."
    cat service_test.log
    kill $SERVICE_PID
    exit 1
fi

# 4. 执行功能测试
echo ""
echo "[Step 3] Running Functional Tests..."

# Test A: Base Plots
echo -n "Test A: /plots/base ... "
curl -s "http://localhost:$PORT/plots/base" > base.json
if grep -q "uas.png" base.json; then
    echo "PASS"
else
    echo "FAIL"
    echo "Response: $(cat base.json)"
fi

# Test B: Gene Plots (All)
echo -n "Test B: /plots/all?gene=$GENE_TO_TEST ... "
START_TIME=$(date +%s%N)
curl -s "http://localhost:$PORT/plots/all?gene=$GENE_TO_TEST" > all.json
END_TIME=$(date +%s%N)
elapsed=$(( ($END_TIME - $START_TIME) / 1000000 ))

if grep -q "feature_plot.png" all.json && grep -q "heat_plot_withanno.png" all.json; then
    echo "PASS (Latency: ${elapsed}ms)"
else
    echo "FAIL"
    echo "Response: $(cat all.json)"
fi

# 5. 清理与报告
echo ""
echo "[Step 4] Teardown..."
kill $SERVICE_PID
rm -f base.json all.json service_test.log

echo "=========================================================="
if [ "$SERVICE_UP" = true ]; then
    echo "       VERIFICATION COMPLETED SUCCESSFULLY "
    echo "       Your service is ready for production."
else
    echo "       VERIFICATION FAILED"
fi
echo "=========================================================="
