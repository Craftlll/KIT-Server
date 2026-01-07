#!/bin/bash

# 生产环境一键部署脚本
# 自动检测环境、安装依赖、部署服务

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 打印横幅
print_banner() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}║        R Plot Service - 部署脚本                       ║${NC}"
    echo -e "${BLUE}║        Production Deployment Script                    ║${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 解析命令行参数
DEV_MODE=false
for arg in "$@"; do
    case $arg in
        --dev)
            DEV_MODE=true
            shift
            ;;
    esac
done

# 检测操作系统
detect_os() {
    print_info "检测操作系统..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
            print_success "检测到 Linux 系统: $PRETTY_NAME"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        print_success "检测到 macOS 系统"
    else
        print_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
}

# 检测 docker compose 命令
detect_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        print_success "发现 Docker Compose Plugin (v2)"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
        print_success "发现 Docker Compose (v1)"
    else
        print_warning "未找到 Docker Compose，尝试安装..."
        return 1
    fi
    return 0
}

# 检查 Docker
check_docker() {
    print_info "检查 Docker..."
    
    if ! command -v docker &> /dev/null; then
        print_warning "Docker 未安装，开始安装..."
        install_docker
    else
        DOCKER_VERSION=$(docker --version)
        print_success "Docker 已安装: $DOCKER_VERSION"
    fi
    
    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        print_warning "Docker 未运行，尝试启动..."
        if [[ "$OS" == "linux" ]]; then
            sudo systemctl start docker || true
            sudo systemctl enable docker || true
            sleep 3
        fi
        
        if ! docker info &> /dev/null; then
             print_error "无法启动 Docker，请手动启动"
             exit 1
        fi
    fi
}

# 安装 Docker
install_docker() {
    if [[ "$OS" == "linux" ]]; then
        print_info "在 Linux 上安装 Docker..."
        
        # 移除旧版本
        sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        # 更新并安装依赖
        sudo apt-get update -y
        sudo apt-get install -y ca-certificates curl gnupg
        
        # 添加官方 GPG Key
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg

        # 设置仓库 source
        # 注意: 使用 ubuntu 作为 distro, 即便是在 derivative 系统上也通常兼容
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
          
        # 安装 Docker Engine 和 Compose Plugin
        sudo apt-get update -y
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        # 启动
        sudo systemctl start docker
        sudo systemctl enable docker
        
        # 用户组
        if ! groups $USER | grep -q docker; then
            sudo usermod -aG docker $USER
            print_warning "已将用户添加到 docker 组，可能需要重新登录才能生效"
        fi
        
        print_success "Docker 安装完成"
        
    elif [[ "$OS" == "macos" ]]; then
        print_error "MacOS 请手动安装 Docker Desktop"
        exit 1
    fi
}

# 检查并安装 Compose
check_docker_compose() {
    print_info "检查 Docker Compose..."
    
    if ! detect_compose_cmd; then
        # 如果检测失败，尝试安装插件
        if [[ "$OS" == "linux" ]]; then
            print_info "尝试安装 docker-compose-plugin..."
            sudo apt-get update -y
            sudo apt-get install -y docker-compose-plugin
            
            if detect_compose_cmd; then
                print_success "Docker Compose Plugin 安装成功"
                return
            fi
        fi
        print_error "Docker Compose 安装失败，请手动安装"
        exit 1
    fi
}

# 检查配置文件
check_config() {
    print_info "检查配置文件..."
    
    if [ ! -f .env ]; then
        print_warning ".env 文件不存在，从模板创建..."
        
        if [ -f .env.example ]; then
            cp .env.example .env
            print_success "已创建 .env 文件"
            print_warning "请编辑 .env 文件，配置正确的 DATA_PATH"
            
            # 提示用户配置
            read -p "是否现在配置 DATA_PATH? (y/n): " configure_now
            if [[ $configure_now =~ ^[Yy]$ ]]; then
                read -p "请输入数据目录的绝对路径: " data_path
                sed -i.bak "s|DATA_PATH=.*|DATA_PATH=$data_path|" .env
                print_success "DATA_PATH 已配置为: $data_path"
            else
                print_error "请手动编辑 .env 文件配置 DATA_PATH 后重新运行"
                exit 1
            fi
        else
            print_error ".env.example 文件不存在"
            exit 1
        fi
    else
        print_success ".env 文件已存在"
        
        # 验证 DATA_PATH
        source .env
        if [ -z "$DATA_PATH" ] || [ "$DATA_PATH" == "/path/to/your/data" ]; then
            print_error "DATA_PATH 未配置或使用默认值"
            print_info "请编辑 .env 文件，设置正确的 DATA_PATH"
            exit 1
        fi
        
        if [ ! -d "$DATA_PATH" ]; then
            print_error "DATA_PATH 目录不存在: $DATA_PATH"
            exit 1
        fi
        
        print_success "DATA_PATH 验证通过: $DATA_PATH"
    fi
}

# 创建必要的目录
create_directories() {
    print_info "创建必要的目录..."
    
    source .env
    
    # 创建日志目录
    mkdir -p ${LOG_DIR:-./logs}/{nacos,r-service-1,r-service-2,r-service-3,gateway}
    
    print_success "目录创建完成"
}

# 检查端口占用
check_ports() {
    print_info "检查端口占用..."
    
    source .env
    
    PORTS=(${GATEWAY_PORT:-8080} ${NACOS_PORT:-8848} ${NACOS_GRPC_PORT:-9848})
    
    for port in "${PORTS[@]}"; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 || netstat -tuln 2>/dev/null | grep -q ":$port "; then
            print_warning "端口 $port 已被占用"
            read -p "是否继续? (y/n): " continue_deploy
            if [[ ! $continue_deploy =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    done
    
    print_success "端口检查完成"
}

# 构建镜像
build_images() {
    print_info "构建 Docker 镜像..."
    
    $COMPOSE_CMD build --no-cache
    
    print_success "镜像构建完成"
}

# 启动服务
start_services() {
    print_info "启动服务..."
    
    # 停止旧服务
    $COMPOSE_CMD down 2>/dev/null || true
    
    # 启动新服务
    $COMPOSE_CMD up -d
    
    print_info "等待服务启动..."
    sleep 10
}

# 验证部署
verify_deployment() {
    print_info "验证部署..."
    
    source .env
    
    # 检查容器状态
    print_info "检查容器状态..."
    $COMPOSE_CMD ps
    
    # 等待服务就绪
    print_info "等待服务就绪 (30秒)..."
    sleep 30
    
    # 验证 Gateway
    print_info "验证 Gateway..."
    if curl -s http://localhost:${GATEWAY_PORT:-8080}/health > /dev/null; then
        HEALTH=$(curl -s http://localhost:${GATEWAY_PORT:-8080}/health)
        print_success "Gateway 健康检查通过: $HEALTH"
    else
        print_error "Gateway 健康检查失败"
        return 1
    fi
    
    # 验证 Nacos
    print_info "验证 Nacos..."
    if curl -s http://localhost:${NACOS_PORT:-8848}/nacos > /dev/null; then
        print_success "Nacos 运行正常"
    else
        print_error "Nacos 访问失败"
        return 1
    fi
    
    # 验证服务注册
    print_info "验证服务注册..."
    INSTANCES=$(curl -s "http://localhost:${NACOS_PORT:-8848}/nacos/v1/ns/instance/list?serviceName=r-plot-service" | grep -o '"healthy":true' | wc -l | tr -d ' ')
    
    if [ "$INSTANCES" -ge "${R_SERVICE_REPLICAS:-3}" ]; then
        print_success "服务注册验证通过: $INSTANCES 个实例"
    else
        print_warning "只有 $INSTANCES 个实例注册 (预期 ${R_SERVICE_REPLICAS:-3})"
    fi
    
    print_success "部署验证完成"
}

# 显示部署信息
show_deployment_info() {
    source .env
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}║              🎉 部署成功！                             ║${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}服务访问信息:${NC}"
    echo -e "  Gateway API:    ${GREEN}http://localhost:${GATEWAY_PORT:-8080}/api/v1${NC}"
    echo -e "  Nacos 控制台:   ${GREEN}http://localhost:${NACOS_PORT:-8848}/nacos${NC}"
    echo -e "  用户名/密码:    ${YELLOW}nacos/nacos${NC}"
    echo ""
    echo -e "${BLUE}数据目录:${NC}"
    echo -e "  ${DATA_PATH}"
    echo ""
    echo -e "${BLUE}日志目录:${NC}"
    echo -e "  ${LOG_DIR:-./logs}"
    echo ""
    echo -e "${BLUE}常用命令:${NC}"
    echo -e "  推荐使用 manage.sh 管理服务:"
    echo -e "  查看状态:  ${YELLOW}./manage.sh status${NC}"
    echo -e "  查看日志:  ${YELLOW}./manage.sh logs${NC}"
    echo -e "  重启服务:  ${YELLOW}./manage.sh restart${NC}"
    echo -e "  停止服务:  ${YELLOW}./manage.sh stop${NC}"
    echo ""
}

# 主函数
main() {
    print_banner
    
    if [ "$DEV_MODE" = true ]; then
        print_info "开发模式: 跳过环境检测和依赖安装"
        
        # 只检查 Docker 是否运行
        if ! docker info &> /dev/null; then
            print_error "Docker 未运行，请启动 Docker"
            exit 1
        fi
        
        # 检查配置
        check_config
        create_directories
        
        # 直接部署
        print_info "开始快速部署..."
        detect_compose_cmd
        $COMPOSE_CMD down 2>/dev/null || true
        $COMPOSE_CMD up -d
        
        sleep 15
        verify_deployment
        show_deployment_info
        
    else
        # 生产模式：完整检查
        detect_os
        check_docker
        check_docker_compose
        check_config
        create_directories
        check_ports
        
        # 询问是否继续
        echo ""
        read -p "是否开始部署? (y/n): " start_deploy
        if [[ ! $start_deploy =~ ^[Yy]$ ]]; then
            print_info "部署已取消"
            exit 0
        fi
        
        build_images
        start_services
        verify_deployment
        show_deployment_info
    fi
    
    print_success "部署完成！🚀"
}

# 运行主函数
main "$@"
