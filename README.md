# R Plot Service

基于 Nacos 服务发现的 R 绘图服务，提供高可用的单细胞数据可视化 API。

## ✨ 特性

- 🚀 **高可用**: 3 个 R 服务实例，自动负载均衡
- 🔍 **服务发现**: Nacos 自动服务注册与发现
- ⚖️ **负载均衡**: Round-Robin 轮询算法
- 🐳 **容器化**: Docker Compose 一键部署
- 📊 **监控**: 健康检查与心跳机制
- ⚙️ **可配置**: 统一配置文件管理

## 🏗️ 架构

```
前端应用
    ↓
Gateway (localhost:8080)
    ├─ 负载均衡 (Round-Robin)
    ├─ 服务发现 (Nacos)
    └─ 请求转发
    ↓
Nacos (localhost:8848)
    ↓
R 服务集群
    ├─ r-service-1 (8001)
    ├─ r-service-2 (8002)
    └─ r-service-3 (8003)
```

## 📦 组件

| 组件 | 说明 | 端口 |
|------|------|------|
| Gateway | API 网关 + 负载均衡 | 8080 |
| Nacos | 服务注册中心 | 8848 |
| R Services | R 绘图服务 (3实例) | 8001-8003 |

## 🚀 快速开始

### 前置要求

- Docker 20.10+
- Docker Compose 2.0+
- 8GB+ 内存

### 1. 配置环境

```bash
# 复制配置文件
cp .env.example .env

# 编辑配置（必须修改 DATA_PATH）
vi .env
```

**必须配置项**:
```bash
DATA_PATH=/path/to/your/data  # 数据目录绝对路径
```

**可选配置项**:
```bash
GATEWAY_PORT=8080              # Gateway 端口
R_SERVICE_REPLICAS=3           # R 服务实例数
```

### 2. 部署服务

**方式 1: 使用管理脚本（推荐）⭐**

```bash
# 开发模式（快速启动）
./manage.sh start-dev

# 生产模式（完整检查）
./manage.sh start-prod
```

**方式 2: 使用部署脚本**

```bash
# 开发环境（快速启动）
./deploy.sh --dev

# 生产环境（完整检查）
./deploy.sh
```

**方式 3: 手动启动**

```bash
docker-compose up -d
```

部署脚本会自动：
- ✅ 检测并安装 Docker（Linux）
- ✅ 验证配置文件
- ✅ 检查端口占用
- ✅ 构建镜像
- ✅ 启动服务
- ✅ 验证部署

### 3. 验证服务

```bash
# 健康检查
curl http://localhost:8080/health

# 获取数据集
curl http://localhost:8080/api/v1/datasets

# 生成图表
curl "http://localhost:8080/api/v1/plots/all?id=NO1&gene=GAPDH"
```

## 📚 API 文档

### 基础地址
```
http://localhost:8080/api/v1
```

### 主要端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查 |
| `/datasets` | GET | 获取数据集列表 |
| `/genes/check` | GET | 检查基因是否存在 |
| `/plots/all` | GET | 获取所有图表 |
| `/plots/types` | GET | 获取可用图表类型 |

**详细文档**: 查看 [docs/gateway/API_DOCS.md](docs/gateway/API_DOCS.md)

**OpenAPI 规范**: 查看 [docs/gateway/API_SPEC.json](docs/gateway/API_SPEC.json)

## 🔧 运维操作

### 使用管理脚本（推荐）⭐

```bash
# 查看服务状态
./manage.sh status

# 健康检查
./manage.sh health

# 查看日志
./manage.sh logs              # 所有服务
./manage.sh logs gateway      # 指定服务

# 重启服务
./manage.sh restart           # 所有服务
./manage.sh restart gateway   # 指定服务

# 停止服务
./manage.sh stop

# 更新服务
./manage.sh update
```

**完整命令列表**: 查看 [MANAGE.md](MANAGE.md) 或运行 `./manage.sh help`

### 使用 Docker Compose

```bash
# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f gateway

# 重启服务
docker-compose restart

# 停止服务
docker-compose down

# 更新服务
docker-compose up -d --build
```

## ⚙️ 配置说明

### .env 配置文件

```bash
# 数据配置
DATA_PATH=/path/to/data        # 数据目录（必须）

# 服务配置
GATEWAY_PORT=8080              # Gateway 端口
NACOS_PORT=8848                # Nacos 端口
R_SERVICE_REPLICAS=3           # R 服务实例数

# 资源限制
R_SERVICE_MEMORY_LIMIT=2g      # R 服务内存限制
GATEWAY_MEMORY_LIMIT=512m      # Gateway 内存限制

# 日志配置
LOG_DIR=./logs                 # 日志目录
LOG_RETENTION_DAYS=7           # 日志保留天数
```

完整配置说明: 查看 [.env.example](.env.example)

## 📖 文档

| 文档 | 说明 |
|------|------|
| [DEPLOYMENT.md](DEPLOYMENT.md) | 生产环境部署指南 |
| [docs/gateway/API_DOCS.md](docs/gateway/API_DOCS.md) | Gateway API 文档 |
| [docs/gateway/API_SPEC.json](docs/gateway/API_SPEC.json) | OpenAPI 3.0 规范 |
| [docs/r/API_REFERENCE.md](docs/r/API_REFERENCE.md) | R 服务 API 参考 |

## 🐛 故障排查

### 问题 1: 端口被占用

```bash
# 修改 .env 中的端口
GATEWAY_PORT=8081
```

### 问题 2: 数据目录不存在

```bash
# 检查并创建目录
mkdir -p /path/to/data
```

### 问题 3: 服务未注册到 Nacos

```bash
# 查看 R 服务日志
docker-compose logs r-service-1

# 检查 Nacos 连接
docker exec r-service-1 curl http://nacos:8848/nacos
```

更多故障排查: 查看 [DEPLOYMENT.md](DEPLOYMENT.md)

## 🔐 生产环境建议

1. **修改 Nacos 默认密码**
2. **配置防火墙规则**
3. **使用 HTTPS（配置 Nginx）**
4. **定期备份配置和日志**
5. **监控资源使用情况**

详细安全配置: 查看 [DEPLOYMENT.md](DEPLOYMENT.md)

## 📊 性能指标

- **首次请求**: 2-3 秒（生成图表）
- **缓存请求**: < 100ms
- **并发支持**: 100+ 请求/秒
- **实例数**: 3 个（可扩展到 10+）

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

## 📞 支持

如有问题，请：
1. 查看文档: [DEPLOYMENT.md](DEPLOYMENT.md)
2. 检查日志: `docker-compose logs`
3. 访问 Nacos 控制台: http://localhost:8848/nacos

---

**快速开始**: `./deploy.sh --dev`

**生产部署**: 查看 [DEPLOYMENT.md](DEPLOYMENT.md)
