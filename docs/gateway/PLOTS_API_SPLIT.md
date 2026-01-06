# 图像接口拆分说明

## 概述

本次改造将原有的 `GET /plots/all` 接口拆分为两个新接口，通过网关层进行过滤处理，实现了更灵活的图像获取方式。

## 架构设计

### 原有架构
- R 服务提供 `/plots/all` 接口，返回所有图像路径
- 客户端需要自己过滤需要的图像

### 新架构
- **R 服务层**：保持不变，仍然提供 `/plots/all` 接口
- **网关层**：新增两个路由 `/plots/anno` 和 `/plots/noanno`
  - 这两个路由会转发请求到 R 服务的 `/plots/all` 接口
  - 在响应返回时，通过 `ModifyResponse` 钩子过滤数据
  - 返回过滤后的结果给客户端

## 新增接口

### 1. GET /api/v1/plots/anno

**功能**：获取带注释(anno)的图像列表

**参数**：
- `id` (required): 数据集 ID，例如 "NO1"
- `gene` (required): 基因名称，例如 "GAPDH"

**返回示例**：
```json
{
  "gene": "GAPDH",
  "gene_plots": {
    "dot_withanno": "/data/NO1/lite/cache/GAPDH/dot_plot_withanno.png",
    "heat_withanno": "/data/NO1/lite/cache/GAPDH/heat_plot_withanno.png"
  },
  "base_plots": {
    "ucta_withanno": "/data/NO1/lite/base/ucta_withanno.png"
  },
  "filter_type": "anno",
  "description": "仅包含带注释(anno)的图像"
}
```

**包含的图像**：
- 基因特异性图像：`dot_withanno`, `heat_withanno`
- 基础图像：`ucta_withanno`

### 2. GET /api/v1/plots/noanno

**功能**：获取不带注释(noanno)的图像列表

**参数**：
- `id` (required): 数据集 ID，例如 "NO1"
- `gene` (required): 基因名称，例如 "GAPDH"

**返回示例**：
```json
{
  "gene": "GAPDH",
  "gene_plots": {
    "feature": "/data/NO1/lite/cache/GAPDH/feature_plot.png",
    "dot_noanno": "/data/NO1/lite/cache/GAPDH/dot_plot_noanno.png",
    "heat_noanno": "/data/NO1/lite/cache/GAPDH/heat_plot_noanno.png"
  },
  "base_plots": {
    "uas": "/data/NO1/lite/base/uas.png",
    "ucd45": "/data/NO1/lite/base/ucd45.png",
    "ucta_noanno": "/data/NO1/lite/base/ucta_noanno.png"
  },
  "filter_type": "noanno",
  "description": "仅包含不带注释(noanno)的图像"
}
```

**包含的图像**：
- 基因特异性图像：`feature`, `dot_noanno`, `heat_noanno`
- 基础图像：`uas`, `ucd45`, `ucta_noanno`

### 3. GET /api/v1/plots/all (保持不变)

**功能**：获取所有图像列表

**返回示例**：
```json
{
  "gene": "GAPDH",
  "gene_plots": {
    "feature": "/data/NO1/lite/cache/GAPDH/feature_plot.png",
    "dot_withanno": "/data/NO1/lite/cache/GAPDH/dot_plot_withanno.png",
    "dot_noanno": "/data/NO1/lite/cache/GAPDH/dot_plot_noanno.png",
    "heat_withanno": "/data/NO1/lite/cache/GAPDH/heat_plot_withanno.png",
    "heat_noanno": "/data/NO1/lite/cache/GAPDH/heat_plot_noanno.png"
  },
  "base_plots": {
    "uas": "/data/NO1/lite/base/uas.png",
    "ucd45": "/data/NO1/lite/base/ucd45.png",
    "ucta_withanno": "/data/NO1/lite/base/ucta_withanno.png",
    "ucta_noanno": "/data/NO1/lite/base/ucta_noanno.png"
  }
}
```

## 实现细节

### 网关层实现

#### 1. 路由转换 (gateway/cmd/main.go)

在 `proxy.Director` 中添加路由转换逻辑：

```go
// 路由转换：将 /plots/anno 和 /plots/noanno 转换为 /plots/all
if strings.HasPrefix(path, "/plots/anno") || strings.HasPrefix(path, "/plots/noanno") {
    path = "/plots/all"
}
```

#### 2. 响应过滤 (gateway/internal/handlers/plot_filter.go)

在 `proxy.ModifyResponse` 中根据原始请求路径调用相应的过滤函数：

```go
originalPath := c.Request.URL.Path
proxy.ModifyResponse = func(resp *http.Response) error {
    if strings.Contains(originalPath, "/plots/anno") {
        return handlers.FilterPlotsAnno(resp)
    } else if strings.Contains(originalPath, "/plots/noanno") {
        return handlers.FilterPlotsNoAnno(resp)
    }
    return nil
}
```

#### 3. 过滤逻辑

- **FilterPlotsAnno**: 过滤出所有包含 "withanno" 的图像
- **FilterPlotsNoAnno**: 过滤出所有不包含 "withanno" 的图像

## 优势

1. **关注点分离**：R 服务专注于数据处理和图像生成，网关负责路由和数据过滤
2. **向后兼容**：原有的 `/plots/all` 接口保持不变，不影响现有客户端
3. **灵活扩展**：未来可以轻松添加更多过滤规则，无需修改 R 服务
4. **性能优化**：网关层过滤比在 R 服务中实现更高效
5. **统一管理**：所有路由转换和过滤逻辑集中在网关层管理

## 测试建议

### 1. 测试 /plots/anno 接口
```bash
curl "http://localhost:8080/api/v1/plots/anno?id=NO1&gene=GAPDH"
```

### 2. 测试 /plots/noanno 接口
```bash
curl "http://localhost:8080/api/v1/plots/noanno?id=NO1&gene=GAPDH"
```

### 3. 测试 /plots/all 接口（确保向后兼容）
```bash
curl "http://localhost:8080/api/v1/plots/all?id=NO1&gene=GAPDH"
```

## 文件变更清单

### 新增文件
- `gateway/internal/handlers/plot_filter.go` - 图像过滤处理器

### 修改文件
- `gateway/cmd/main.go` - 添加路由转换和响应过滤逻辑
- `docs/gateway/API_SPEC.json` - 更新 API 规范文档

### 未修改文件
- `data/NO1/NO1_script/NO1_lite_plumber.R` - R 服务保持不变
- 其他所有 R 服务文件

## 注意事项

1. R 服务中的 lint 警告（关于 `UMAP_1`, `UMAP_2` 等变量）是 R 语言使用 dplyr 和 ggplot2 时的常见警告，这些是关于非标准求值（NSE）的警告，不影响代码运行，可以安全忽略。

2. 如果需要为其他数据集（NO2, NO3 等）应用相同的改造，只需确保它们的 R 服务也提供 `/plots/all` 接口，网关层的过滤逻辑会自动适用。

3. 过滤逻辑基于图像文件名中是否包含 "withanno" 字符串，如果未来图像命名规则发生变化，需要相应更新 `plot_filter.go` 中的过滤逻辑。
