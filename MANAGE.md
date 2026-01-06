# 管理脚本快速参考

## 🚀 一键操作

### 启动服务

```bash
# 开发模式（推荐，快速启动）
./manage.sh start-dev

# 生产模式（完整检查）
./manage.sh start-prod

# 普通启动
./manage.sh start
```

### 停止服务

```bash
# 停止所有服务
./manage.sh stop

# 停止指定服务
./manage.sh stop gateway
./manage.sh stop r-service-1
```

### 重启服务

```bash
# 重启所有服务
./manage.sh restart

# 重启指定服务
./manage.sh restart gateway
./manage.sh restart r-service-1
```

---

## 📊 状态查看

```bash
# 查看服务状态
./manage.sh status

# 健康检查
./manage.sh health

# 查看所有日志
./manage.sh logs

# 查看指定服务日志
./manage.sh logs gateway
./manage.sh logs r-service-1
```

---

## 🔄 更新部署

```bash
# 更新代码并重新部署
./manage.sh update

# 重新构建所有镜像
./manage.sh rebuild

# 重新构建指定服务
./manage.sh rebuild gateway
./manage.sh rebuild r-service-1
```

---

## 🗑️ 清理

```bash
# 停止并删除容器
./manage.sh clean

# 清理容器和数据卷
./manage.sh clean-all

# 清理 Docker 缓存
./manage.sh prune
```

---

## 🔧 其他操作

```bash
# 查看配置
./manage.sh config

# 进入容器调试
./manage.sh shell gateway
./manage.sh shell r-service-1

# 显示帮助
./manage.sh help
```

---

## 📝 常用工作流

### 日常开发

```bash
# 1. 启动服务
./manage.sh start-dev

# 2. 查看日志
./manage.sh logs gateway

# 3. 修改代码后重启
./manage.sh restart gateway

# 4. 停止服务
./manage.sh stop
```

### 生产部署

```bash
# 1. 首次部署
./manage.sh start-prod

# 2. 更新代码
./manage.sh update

# 3. 查看状态
./manage.sh health

# 4. 查看日志
./manage.sh logs
```

### 故障排查

```bash
# 1. 查看状态
./manage.sh status

# 2. 查看日志
./manage.sh logs gateway

# 3. 进入容器调试
./manage.sh shell gateway

# 4. 重启服务
./manage.sh restart gateway
```

---

## 🎯 快速参考表

| 操作 | 命令 |
|------|------|
| **快速启动** | `./manage.sh start-dev` |
| **停止服务** | `./manage.sh stop` |
| **重启服务** | `./manage.sh restart` |
| **查看状态** | `./manage.sh status` |
| **健康检查** | `./manage.sh health` |
| **查看日志** | `./manage.sh logs` |
| **更新部署** | `./manage.sh update` |
| **进入容器** | `./manage.sh shell gateway` |

---

## 💡 提示

- 所有命令都会自动检查 Docker 是否运行
- 日志查看使用 `Ctrl+C` 退出
- 进入容器后使用 `exit` 退出
- 使用 `./manage.sh help` 查看完整帮助

---

**就这么简单！** 🚀
