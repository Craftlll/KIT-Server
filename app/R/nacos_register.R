# nacos_register.R
# Nacos 服务注册模块 - 改进版
library(httr)
library(jsonlite)

# 全局变量存储注册信息
.nacos_config <- new.env()

#' 注册服务到 Nacos（带重试机制）
#' @param service_name 服务名称
#' @param ip 服务 IP
#' @param port 服务端口
#' @param nacos_server Nacos 服务器地址
#' @param max_retries 最大重试次数
register_to_nacos <- function(
    service_name = Sys.getenv("SERVICE_NAME", "r-plot-service"),
    ip = Sys.getenv("SERVICE_IP", "127.0.0.1"),
    port = Sys.getenv("SERVICE_PORT", "8000"),
    nacos_server = Sys.getenv("NACOS_SERVER", "http://nacos:8848"),
    max_retries = 3) {
    # 保存配置供后续使用
    .nacos_config$service_name <- service_name
    .nacos_config$ip <- ip
    .nacos_config$port <- port
    .nacos_config$nacos_server <- nacos_server

    # 构建注册 URL
    register_url <- paste0(nacos_server, "/nacos/v1/ns/instance")

    # 注册参数
    params <- list(
        serviceName = service_name,
        ip = ip,
        port = port,
        healthy = "true",
        weight = "1.0",
        enabled = "true",
        ephemeral = "true",
        metadata = toJSON(list(
            version = "1.2.0",
            protocol = "http",
            context = "/api/v1"
        ), auto_unbox = TRUE)
    )

    # 重试逻辑
    for (attempt in 1:max_retries) {
        tryCatch(
            {
                response <- POST(
                    register_url,
                    body = params,
                    encode = "form",
                    timeout(10)
                )

                if (status_code(response) == 200) {
                    cat(sprintf("[Nacos] Service registered successfully: %s\n", service_name))
                    cat(sprintf("[Nacos] Instance: %s:%s\n", ip, port))
                    return(TRUE)
                } else {
                    warning(sprintf(
                        "[Nacos] Registration failed (attempt %d/%d): %s",
                        attempt, max_retries, content(response, "text")
                    ))
                }
            },
            error = function(e) {
                warning(sprintf(
                    "[Nacos] Registration error (attempt %d/%d): %s",
                    attempt, max_retries, e$message
                ))
            }
        )

        # 指数退避
        if (attempt < max_retries) {
            wait_time <- 2^attempt
            cat(sprintf("[Nacos] Retrying in %d seconds...\n", wait_time))
            Sys.sleep(wait_time)
        }
    }

    stop("[Nacos] Failed to register service after all retries")
}

#' 发送心跳到 Nacos
send_heartbeat <- function() {
    if (is.null(.nacos_config$service_name)) {
        warning("[Nacos] Service not registered, skipping heartbeat")
        return(FALSE)
    }

    heartbeat_url <- paste0(
        .nacos_config$nacos_server,
        "/nacos/v1/ns/instance/beat"
    )

    beat_info <- list(
        serviceName = .nacos_config$service_name,
        ip = .nacos_config$ip,
        port = as.integer(.nacos_config$port)
    )

    params <- list(
        serviceName = .nacos_config$service_name,
        beat = toJSON(beat_info, auto_unbox = TRUE)
    )

    tryCatch(
        {
            response <- PUT(
                heartbeat_url,
                body = params,
                encode = "form",
                timeout(5)
            )

            if (status_code(response) == 200) {
                cat("[Nacos] Heartbeat sent successfully\n")
                return(TRUE)
            } else {
                warning(sprintf("[Nacos] Heartbeat failed: %s", content(response, "text")))
                return(FALSE)
            }
        },
        error = function(e) {
            warning(sprintf("[Nacos] Heartbeat error: %s", e$message))
            return(FALSE)
        }
    )
}

#' 启动心跳定时任务
#' @param interval 心跳间隔（秒），默认 10 秒
start_heartbeat_task <- function(interval = 10) {
    cat(sprintf("[Nacos] Starting heartbeat task (interval: %d seconds)\n", interval))

    # 检查 later 包是否可用
    if (!requireNamespace("later", quietly = TRUE)) {
        warning("[Nacos] Package 'later' not available, heartbeat disabled")
        return(FALSE)
    }

    library(later)

    # 定义心跳循环
    heartbeat_loop <- function() {
        send_heartbeat()
        later(heartbeat_loop, interval)
    }

    # 启动第一次心跳
    later(heartbeat_loop, interval)

    return(TRUE)
}

#' 注销服务
deregister_from_nacos <- function() {
    if (is.null(.nacos_config$service_name)) {
        cat("[Nacos] Service not registered, skipping deregistration\n")
        return(TRUE)
    }

    deregister_url <- paste0(
        .nacos_config$nacos_server,
        "/nacos/v1/ns/instance"
    )

    params <- list(
        serviceName = .nacos_config$service_name,
        ip = .nacos_config$ip,
        port = .nacos_config$port
    )

    tryCatch(
        {
            response <- DELETE(
                deregister_url,
                query = params,
                timeout(5)
            )

            if (status_code(response) == 200) {
                cat("[Nacos] Service deregistered successfully\n")
                return(TRUE)
            } else {
                warning(sprintf("[Nacos] Deregistration failed: %s", content(response, "text")))
                return(FALSE)
            }
        },
        error = function(e) {
            warning(sprintf("[Nacos] Deregistration error: %s", e$message))
            return(FALSE)
        }
    )
}

#' 延迟注册（等待 Plumber 完全启动）
#' @param delay 延迟时间（秒）
delayed_register <- function(delay = 3) {
    cat(sprintf("[Nacos] Delaying registration for %d seconds to ensure service is ready...\n", delay))
    Sys.sleep(delay)
    register_to_nacos()
}
