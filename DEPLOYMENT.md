# 生产环境部署指南

## 📋 部署前准备

### 系统要求

- **操作系统**: Linux (Ubuntu 20.04+, CentOS 7+) 或 macOS
- **内存**: 最少 8GB (推荐 16GB+)
- **磁盘**: 最少 20GB 可用空间
- **CPU**: 2核+ (推荐 4核+)

### 软件要求

部署脚本会自动检测并安装以下软件（Linux）：
- Docker 20.10+
- Docker Compose 2.0+

macOS 用户需要手动安装 Docker Desktop。

---

## 🚀 快速部署

### 1. 配置环境

复制配置文件模板：
```bash
cp .env.example .env
```

编辑 `.env` 文件，**必须修改**以下配置：

```bash
# 数据目录的绝对路径（必须修改）
DATA_PATH=/path/to/your/data

# 可选：调整端口
GATEWAY_PORT=8080
NACOS_PORT=8848

# 可选：调整实例数（根据服务器资源）
R_SERVICE_REPLICAS=3
```

### 2. 运行部署脚本

```bash
./deploy.sh
```

部署脚本会自动：
1. ✅ 检测操作系统
2. ✅ 检查/安装 Docker
3. ✅ 检查/安装 Docker Compose
4. ✅ 验证配置文件
5. ✅ 检查端口占用
6. ✅ 构建 Docker 镜像
7. ✅ 启动所有服务
8. ✅ 验证部署状态

---

## 📝 配置说明

### .env 配置文件详解

#### 数据配置
```bash
# 数据目录的绝对路径（必须存在）
DATA_PATH=/data/single-cell
```

#### 服务配置
```bash
# Gateway 端口
GATEWAY_PORT=8080

# Nacos 端口
NACOS_PORT=8848
NACOS_GRPC_PORT=9848

# R 服务实例数量（1-10）
R_SERVICE_REPLICAS=3

# R 服务起始端口
R_SERVICE_START_PORT=8001
```

#### 资源限制
```bash
# Nacos JVM 内存
NACOS_JVM_XMS=512m
NACOS_JVM_XMX=512m

# R 服务内存限制（每个实例）
R_SERVICE_MEMORY_LIMIT=2g
R_SERVICE_MEMORY_RESERVATION=1g

# Gateway 内存限制
GATEWAY_MEMORY_LIMIT=512m
GATEWAY_MEMORY_RESERVATION=256m
```

#### 日志配置
```bash
# 日志目录
LOG_DIR=./logs

# 日志保留天数
LOG_RETENTION_DAYS=7
```

---

## 🔧 手动部署（高级）

如果自动部署脚本失败，可以手动部署：

### 1. 安装 Docker（Linux）

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# 启动 Docker
sudo systemctl start docker
sudo systemctl enable docker
```

### 2. 安装 Docker Compose

```bash
# 下载最新版本
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# 添加执行权限
sudo chmod +x /usr/local/bin/docker-compose
```

### 3. 配置环境

```bash
cp .env.example .env
vi .env  # 编辑配置
```

### 4. 启动服务

```bash
# 构建镜像
docker-compose build

# 启动服务
docker-compose up -d

# 查看状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

---

## 📊 验证部署

### 1. 检查容器状态

```bash
docker-compose ps
```

所有容器应该显示 "Up" 或 "healthy"。

### 2. 验证 Gateway

```bash
curl http://localhost:8080/health
```

预期输出：
```json
{"status":"UP","instances":3}
```

### 3. 验证 Nacos

访问: http://your-server:8848/nacos
- 用户名: nacos
- 密码: nacos

在"服务列表"中应该看到 `r-plot-service` 有 3 个实例。

### 4. 测试 API

```bash
# 获取数据集
curl http://localhost:8080/api/v1/datasets

# 生成图表
curl "http://localhost:8080/api/v1/plots/all?id=NO1&gene=GAPDH"
```

---

## 🔄 运维操作

### 查看服务状态

```bash
docker-compose ps
```

### 查看日志

```bash
# 所有服务
docker-compose logs -f

# 特定服务
docker-compose logs -f gateway
docker-compose logs -f r-service-1
```

### 重启服务

```bash
# 重启所有服务
docker-compose restart

# 重启特定服务
docker-compose restart gateway
docker-compose restart r-service-1
```

### 停止服务

```bash
docker-compose down
```

### 更新服务

```bash
# 拉取最新代码
git pull

# 重新构建并启动
docker-compose up -d --build
```

### 扩展 R 服务实例

1. 修改 `.env`:
```bash
R_SERVICE_REPLICAS=5
```

2. 更新 `docker-compose.yml` 添加新实例（r-service-4, r-service-5）

3. 重启服务:
```bash
docker-compose up -d
```

---

## 🐛 故障排查

### 问题 1: Docker 未运行

**症状**: `Cannot connect to the Docker daemon`

**解决**:
```bash
# Linux
sudo systemctl start docker

# macOS
# 启动 Docker Desktop
```

### 问题 2: 端口被占用

**症状**: `port is already allocated`

**解决**:
```bash
# 查看占用端口的进程
lsof -i :8080

# 修改 .env 中的端口配置
GATEWAY_PORT=8081
```

### 问题 3: 数据目录不存在

**症状**: `no such file or directory`

**解决**:
```bash
# 检查 DATA_PATH 是否正确
cat .env | grep DATA_PATH

# 创建目录或修改配置
mkdir -p /path/to/data
```

### 问题 4: 内存不足

**症状**: 容器频繁重启

**解决**:
```bash
# 减少实例数
R_SERVICE_REPLICAS=2

# 减少内存限制
R_SERVICE_MEMORY_LIMIT=1g
```

### 问题 5: R 服务未注册到 Nacos

**症状**: Gateway 显示 instances:0

**解决**:
```bash
# 查看 R 服务日志
docker-compose logs r-service-1

# 检查 Nacos 连接
docker exec r-service-1 curl http://nacos:8848/nacos
```

---

## 🔐 安全建议

### 生产环境安全配置

1. **修改 Nacos 默认密码**
   - 登录 Nacos 控制台
   - 权限控制 → 用户列表 → 修改密码

2. **配置防火墙**
```bash
# 只允许必要的端口
sudo ufw allow 8080/tcp  # Gateway
sudo ufw enable
```

3. **使用 HTTPS**
   - 配置 Nginx 反向代理
   - 申请 SSL 证书

4. **限制访问 IP**
   - 在 Nginx 中配置 IP 白名单

5. **定期备份**
```bash
# 备份配置
tar -czf backup-$(date +%Y%m%d).tar.gz .env docker-compose.yml

# 备份日志
tar -czf logs-$(date +%Y%m%d).tar.gz logs/
```

---

## 📈 性能优化

### 1. 调整实例数

根据服务器资源和负载调整：
```bash
# 高负载
R_SERVICE_REPLICAS=5

# 低负载
R_SERVICE_REPLICAS=2
```

### 2. 调整内存限制

```bash
# 高性能服务器
R_SERVICE_MEMORY_LIMIT=4g
NACOS_JVM_XMX=1g

# 资源受限服务器
R_SERVICE_MEMORY_LIMIT=1g
NACOS_JVM_XMX=256m
```

### 3. 日志管理

```bash
# 定期清理日志
find logs/ -name "*.log" -mtime +7 -delete
```

---

## 📞 支持

如有问题，请：
1. 查看日志: `docker-compose logs`
2. 检查配置: `cat .env`
3. 验证网络: `docker network ls`
4. 查看资源: `docker stats`

---

## ✅ 部署检查清单

部署前检查：
- [ ] 服务器满足系统要求
- [ ] 已安装 Docker 和 Docker Compose
- [ ] 已配置 `.env` 文件
- [ ] DATA_PATH 目录存在且有数据
- [ ] 端口未被占用
- [ ] 有足够的磁盘空间

部署后验证：
- [ ] 所有容器运行正常
- [ ] Gateway 健康检查通过
- [ ] Nacos 可以访问
- [ ] R 服务已注册到 Nacos
- [ ] API 测试通过
- [ ] 日志正常输出

---

## 🎯 下一步

部署成功后：
1. 配置域名和 SSL 证书
2. 设置监控和告警
3. 配置自动备份
4. 优化性能参数
5. 编写运维文档
