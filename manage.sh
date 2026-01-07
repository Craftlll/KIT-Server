#!/bin/bash

# R Plot Service 管理脚本
# 使用方法: ./manage.sh [命令]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印函数
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 打印横幅
print_banner() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                        ║${NC}"
    echo -e "${CYAN}║        R Plot Service - 管理脚本                       ║${NC}"
    echo -e "${CYAN}║        Service Management Script                       ║${NC}"
    echo -e "${CYAN}║                                                        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 显示帮助信息
show_help() {
    print_banner
    echo -e "${CYAN}使用方法:${NC}"
    echo -e "  ./manage.sh [命令] [选项]"
    echo ""
    echo -e "${CYAN}命令列表:${NC}"
    echo ""
    echo -e "  ${GREEN}启动相关:${NC}"
    echo -e "    ${YELLOW}start${NC}           启动所有服务"
    echo -e "    ${YELLOW}start-dev${NC}       开发模式启动（快速）"
    echo -e "    ${YELLOW}start-prod${NC}      生产模式启动（完整检查）"
    echo ""
    echo -e "  ${GREEN}停止相关:${NC}"
    echo -e "    ${YELLOW}stop${NC}            停止所有服务"
    echo -e "    ${YELLOW}stop [服务名]${NC}   停止指定服务"
    echo ""
    echo -e "  ${GREEN}重启相关:${NC}"
    echo -e "    ${YELLOW}restart${NC}         重启所有服务"
    echo -e "    ${YELLOW}restart [服务名]${NC} 重启指定服务"
    echo ""
    echo -e "  ${GREEN}状态查看:${NC}"
    echo -e "    ${YELLOW}status${NC}          查看服务状态"
    echo -e "    ${YELLOW}health${NC}          健康检查"
    echo -e "    ${YELLOW}logs${NC}            查看所有日志"
    echo -e "    ${YELLOW}logs [服务名]${NC}   查看指定服务日志"
    echo ""
    echo -e "  ${GREEN}更新部署:${NC}"
    echo -e "    ${YELLOW}update${NC}          更新代码并重新部署"
    echo -e "    ${YELLOW}rebuild${NC}         重新构建镜像"
    echo -e "    ${YELLOW}rebuild [服务名]${NC} 重新构建指定服务"
    echo ""
    echo -e "  ${GREEN}清理相关:${NC}"
    echo -e "    ${YELLOW}clean${NC}           停止并删除容器"
    echo -e "    ${YELLOW}clean-all${NC}       清理容器和数据卷"
    echo -e "    ${YELLOW}prune${NC}           清理 Docker 缓存"
    echo ""
    echo -e "  ${GREEN}其他:${NC}"
    echo -e "    ${YELLOW}config${NC}          查看配置"
    echo -e "    ${YELLOW}shell [服务名]${NC}  进入服务容器"
    echo -e "    ${YELLOW}help${NC}            显示此帮助信息"
    echo ""
    echo -e "${CYAN}服务名称:${NC}"
    echo -e "  nacos, gateway, r-service-1, r-service-2, r-service-3"
    echo ""
    echo -e "${CYAN}示例:${NC}"
    echo -e "  ./manage.sh start-dev              # 开发模式启动"
    echo -e "  ./manage.sh logs gateway           # 查看 Gateway 日志"
    echo -e "  ./manage.sh restart r-service-1    # 重启 R 服务 1"
    echo -e "  ./manage.sh shell gateway          # 进入 Gateway 容器"
    echo ""
}

# 检查 Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker 未运行，请启动 Docker"
        exit 1
    fi
}

# 检查配置文件
check_config() {
    if [ ! -f .env ]; then
        print_error ".env 配置文件不存在"
        print_info "请先运行: cp .env.example .env"
        exit 1
    fi
}

# 检测 docker compose 命令
detect_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        print_error "未找到 docker compose 或 docker-compose 命令"
        exit 1
    fi
}

# 启动服务
start_service() {
    detect_compose_cmd
    print_info "使用命令: $COMPOSE_CMD"
    print_info "启动所有服务..."
    $COMPOSE_CMD up -d
    print_success "服务已启动"
    sleep 5
    show_status
}

# 开发模式启动
start_dev() {
    print_info "开发模式启动（快速）..."
    check_docker
    check_config
    
    detect_compose_cmd
    $COMPOSE_CMD down 2>/dev/null || true
    $COMPOSE_CMD up -d
    
    print_info "等待服务启动..."
    sleep 15
    
    show_health
    print_success "开发环境已启动"
}

# 生产模式启动
start_prod() {
    print_info "生产模式启动（完整检查）..."
    ./deploy.sh
}

# 停止服务
stop_service() {
    detect_compose_cmd
    if [ -z "$1" ]; then
        print_info "停止所有服务..."
        $COMPOSE_CMD down
        print_success "所有服务已停止"
    else
        print_info "停止服务: $1"
        $COMPOSE_CMD stop "$1"
        print_success "服务 $1 已停止"
    fi
}

# 重启服务
restart_service() {
    detect_compose_cmd
    if [ -z "$1" ]; then
        print_info "重启所有服务..."
        $COMPOSE_CMD restart
        print_success "所有服务已重启"
        sleep 5
        show_status
    else
        print_info "重启服务: $1"
        $COMPOSE_CMD restart "$1"
        print_success "服务 $1 已重启"
    fi
}

# 查看状态
show_status() {
    detect_compose_cmd
    print_info "服务状态:"
    echo ""
    $COMPOSE_CMD ps
}

# 健康检查
show_health() {
    print_info "健康检查:"
    echo ""
    
    # Gateway 健康检查
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        HEALTH=$(curl -s http://localhost:8080/health)
        print_success "Gateway: $HEALTH"
    else
        print_error "Gateway: 无法访问"
    fi
    
    # Nacos 检查
    if curl -s http://localhost:8848/nacos > /dev/null 2>&1; then
        print_success "Nacos: 运行正常"
    else
        print_error "Nacos: 无法访问"
    fi
    
    # R 服务注册检查
    if curl -s http://localhost:8848/nacos/v1/ns/instance/list?serviceName=r-plot-service > /dev/null 2>&1; then
        INSTANCES=$(curl -s "http://localhost:8848/nacos/v1/ns/instance/list?serviceName=r-plot-service" | grep -o '"healthy":true' | wc -l | tr -d ' ')
        print_success "R 服务: $INSTANCES 个实例已注册"
    else
        print_warning "R 服务: 无法检查注册状态"
    fi
    
    echo ""
    print_info "访问地址:"
    echo -e "  Gateway API:  ${GREEN}http://localhost:8080/api/v1${NC}"
    echo -e "  Nacos 控制台: ${GREEN}http://localhost:8848/nacos${NC} (nacos/nacos)"
}

# 查看日志
show_logs() {
    detect_compose_cmd
    if [ -z "$1" ]; then
        print_info "查看所有日志 (Ctrl+C 退出):"
        $COMPOSE_CMD logs -f
    else
        print_info "查看服务日志: $1 (Ctrl+C 退出)"
        $COMPOSE_CMD logs -f "$1"
    fi
}

# 更新部署
update_service() {
    print_info "更新代码并重新部署..."
    
    # 拉取最新代码
    if [ -d .git ]; then
        print_info "拉取最新代码..."
        git pull
    fi
    
    # 重新构建并启动
    print_info "重新构建镜像..."
    detect_compose_cmd
    $COMPOSE_CMD build
    
    print_info "重新启动服务..."
    $COMPOSE_CMD up -d
    
    print_success "更新完成"
    sleep 5
    show_status
}

# 重新构建
rebuild_service() {
    detect_compose_cmd
    if [ -z "$1" ]; then
        print_info "重新构建所有镜像..."
        $COMPOSE_CMD build --no-cache
        print_info "重新启动服务..."
        $COMPOSE_CMD up -d
        print_success "重新构建完成"
    else
        print_info "重新构建服务: $1"
        $COMPOSE_CMD build --no-cache "$1"
        $COMPOSE_CMD up -d "$1"
        print_success "服务 $1 重新构建完成"
    fi
}

# 清理
clean_service() {
    print_info "停止并删除容器..."
    detect_compose_cmd
    $COMPOSE_CMD down
    print_success "清理完成"
}

# 完全清理
clean_all() {
    print_warning "这将删除所有容器和数据卷"
    read -p "确认继续? (y/n): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        print_info "停止并删除容器和数据卷..."
        detect_compose_cmd
        $COMPOSE_CMD down -v
        print_success "完全清理完成"
    else
        print_info "已取消"
    fi
}

# 清理 Docker 缓存
prune_docker() {
    print_info "清理 Docker 缓存..."
    docker system prune -f
    print_success "Docker 缓存已清理"
}

# 查看配置
show_config() {
    print_info "当前配置:"
    echo ""
    if [ -f .env ]; then
        cat .env | grep -v "^#" | grep -v "^$"
    else
        print_error ".env 文件不存在"
    fi
}

# 进入容器
enter_shell() {
    if [ -z "$1" ]; then
        print_error "请指定服务名称"
        echo "示例: ./manage.sh shell gateway"
        exit 1
    fi
    
    CONTAINER_NAME="r-plot-service-$1"
    
    print_info "进入容器: $CONTAINER_NAME"
    
    # 尝试使用 bash，如果不存在则使用 sh
    if docker exec -it "$CONTAINER_NAME" bash -c "exit" 2>/dev/null; then
        docker exec -it "$CONTAINER_NAME" bash
    else
        docker exec -it "$CONTAINER_NAME" sh
    fi
}

# 主函数
main() {
    # 如果没有参数，显示帮助
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    # 解析命令
    COMMAND=$1
    shift
    
    case $COMMAND in
        start)
            check_docker
            check_config
            start_service
            ;;
        start-dev)
            start_dev
            ;;
        start-prod)
            start_prod
            ;;
        stop)
            stop_service "$@"
            ;;
        restart)
            check_docker
            restart_service "$@"
            ;;
        status)
            check_docker
            show_status
            ;;
        health)
            check_docker
            show_health
            ;;
        logs)
            check_docker
            show_logs "$@"
            ;;
        update)
            check_docker
            check_config
            update_service
            ;;
        rebuild)
            check_docker
            check_config
            rebuild_service "$@"
            ;;
        clean)
            clean_service
            ;;
        clean-all)
            clean_all
            ;;
        prune)
            prune_docker
            ;;
        config)
            show_config
            ;;
        shell)
            check_docker
            enter_shell "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "未知命令: $COMMAND"
            echo ""
            echo "运行 './manage.sh help' 查看帮助"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
