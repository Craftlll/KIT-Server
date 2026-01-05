# KIT-Rserve Unified Service

这是一个基于 R Plumber 的统一单细胞数据微服务架构。它将多个数据集整合到一个高效、低内存占用的服务中，提供基因表达数据的查询和可视化功能。

## 目录结构

```
KIT-Rserve/
├── app/                  # 应用代码
│   ├── app.R             # Plumber 主程序
│   ├── config.yaml       # 系统配置文件 (指定数据路径)
│   ├── run_service.sh    # 启动脚本
│   ├── verify_unified_comprehensive.R # 验证脚本
│   └── logs/             # 日志目录
└── data/                 # 数据文件 (Lite 格式: .h5 和 .csv)
```

## 环境依赖

*   **R Version**: 4.x
*   **System Libraries**: `libhdf5-dev`
*   **R Packages**:
    *   `plumber`
    *   `rhdf5`
    *   `ggplot2`
    *   `jsonlite`
    *   `parallel` (用于并行测试)

## 快速启动

### 1. 启动服务

服务启动脚本位于 `app` 目录中。

```bash
cd app
chmod +x run_service.sh
./run_service.sh
```

服务将在后台运行，监听 **8000** 端口。
日志文件位于 `app/logs/service.log`。

### 2. 验证服务状态

你可以使用内置的综合验证脚本来确保服务运行正常：

```bash
cd app
Rscript verify_unified_comprehensive.R
```

如果所有测试通过，你将看到 `Summary: 40 / 40 Tests Passed` 的输出。

或者手动检查健康状态：

```bash
curl http://localhost:8000/health
# 预期输出: {"status":["UP"],"mode":["Unified"]}
```

## API 接口说明

详细接口文档请参考 [API_REFERENCE.md](API_REFERENCE.md)。

以下是常用接口简述：

### 1. 获取数据集列表
```bash
curl http://localhost:8000/datasets
```

### 2. 获取基因表达图 (Plot API)
```bash
# 参数:
# - dataset: 数据集编号 (如 NO1)
# - gene: 基因名称 (如 GAPDH, 支持大小写)
# - type: 图片类型 (png)

curl "http://localhost:8000/plot?dataset=NO1&gene=GAPDH" --output plot.png
```

## 维护与扩展

*   **添加数据集**: 只需将处理好的 Lite 数据 (.h5/.csv) 文件夹放入 `data_path` 指定的目录中，服务重启后会自动识别，无需修改配置文件。
*   **修改配置**: 编辑 `app/config.yaml` 可修改数据源根目录。
*   **重启服务**: 修改配置或添加数据后需要重启服务。

```bash
# 查找进程并终止
lsof -i :8000
kill -9 <PID>

# 重新启动
./run_service.sh
```
