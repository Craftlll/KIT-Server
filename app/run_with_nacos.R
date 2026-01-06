#!/usr/bin/env Rscript
# run_with_nacos.R
# 启动脚本 - 集成 Nacos 注册

library(plumber)

# 加载 Nacos 注册模块
source("R/nacos_register.R")

# 创建 Plumber API
cat("[Server] Creating Plumber API...\n")
pr <- plumb("app_nacos.R")

# 延迟注册到 Nacos（等待 Plumber 完全初始化）
cat("[Server] Registering to Nacos...\n")
Sys.sleep(2)

tryCatch(
    {
        register_to_nacos()
        start_heartbeat_task(interval = 10)
        cat("[Server] Nacos registration complete\n")
    },
    error = function(e) {
        cat(sprintf("[Server] Nacos registration failed: %s\n", e$message))
        cat("[Server] Service will continue without Nacos registration\n")
    }
)

# 启动服务器（阻塞）
cat("[Server] Starting Plumber API on port 8000...\n")
pr$run(host = "0.0.0.0", port = 8000)
