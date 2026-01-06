# R Plot Service API 文档

## 概述

基于 Nacos 服务发现的 R 绘图服务 API，通过 Gateway 提供负载均衡和统一访问入口。

- **版本**: 1.2.0
- **基础 URL**: `http://localhost:8080/api/v1`
- **协议**: HTTP
- **数据格式**: JSON

## 架构说明

```
前端应用
    ↓
Gateway (localhost:8080)
    ├─ 负载均衡 (Round-Robin)
    ├─ 服务发现 (Nacos)
    └─ 请求转发
    ↓
R 服务集群 (3个实例)
```

---

## API 端点

### 1. 健康检查

检查 Gateway 和后端 R 服务的健康状态。

**端点**: `GET /health`

**请求示例**:
```bash
curl http://localhost:8080/api/v1/health
```

**响应示例**:
```json
{
  "status": "UP",
  "instances": 3
}
```

**响应字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| status | string | 服务状态 (UP/DOWN) |
| instances | integer | 可用的 R 服务实例数 |

---

### 2. 获取数据集列表

获取所有可用的单细胞数据集。

**端点**: `GET /datasets`

**请求示例**:
```bash
curl http://localhost:8080/api/v1/datasets
```

**响应示例**:
```json
{
  "datasets": [
    {
      "id": "NO1",
      "name": "Dataset NO1"
    },
    {
      "id": "NO2",
      "name": "Dataset NO2"
    },
    {
      "id": "NO3",
      "name": "Dataset NO3"
    }
  ]
}
```

**响应字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| datasets | array | 数据集列表 |
| datasets[].id | string | 数据集 ID |
| datasets[].name | string | 数据集名称 |

---

### 3. 检查基因是否存在

检查指定基因在数据集中是否存在。

**端点**: `GET /genes/check`

**请求参数**:
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 数据集 ID |
| gene | string | 是 | 基因名称 |

**请求示例**:
```bash
curl "http://localhost:8080/api/v1/genes/check?id=NO1&gene=GAPDH"
```

**成功响应** (200):
```json
{
  "found": true,
  "gene": "GAPDH"
}
```

**数据集不存在** (404):
```json
{
  "error": "Dataset ID not found"
}
```

**基因不存在** (440):
```json
{
  "error": "Gene GAPDH not found"
}
```

---

### 4. 获取所有图表

生成并返回指定基因的所有图表路径（包括基因特异性图表和基础图表）。

**端点**: `GET /plots/all`

**请求参数**:
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 数据集 ID |
| gene | string | 是 | 基因名称 |

**请求示例**:
```bash
curl "http://localhost:8080/api/v1/plots/all?id=NO1&gene=GAPDH"
```

**成功响应** (200):
```json
{
  "gene": "GAPDH",
  "plots": [
    "/data/NO1/lite/cache/GAPDH/feature.png",
    "/data/NO1/lite/cache/GAPDH/dot_withanno.png",
    "/data/NO1/lite/cache/GAPDH/heat_withanno.png",
    "/data/NO1/lite/cache/GAPDH/dot_noanno.png",
    "/data/NO1/lite/cache/GAPDH/heat_noanno.png"
  ],
  "base_plots": [
    "/data/NO1/lite/base/uas.png",
    "/data/NO1/lite/base/ucd45.png",
    "/data/NO1/lite/base/ucta_withanno.png",
    "/data/NO1/lite/base/ucta_noanno.png"
  ]
}
```

**响应字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| gene | string | 基因名称 |
| plots | array | 基因特异性图表的绝对路径数组 |
| base_plots | array | 基础图表的绝对路径数组 |

**图表类型说明**:

**基因特异性图表** (plots):
- `feature.png`: 特征图 (UMAP 上的基因表达)
- `dot_withanno.png`: 点图 (按细胞类型注释)
- `heat_withanno.png`: 热图 (按细胞类型注释)
- `dot_noanno.png`: 点图 (按聚类/无注释)
- `heat_noanno.png`: 热图 (按聚类/无注释)

**基础图表** (base_plots):
- `uas.png`: UMAP 按样本着色
- `ucd45.png`: UMAP 按 CD45 表达着色
- `ucta_withanno.png`: UMAP 按细胞类型着色 (带注释)
- `ucta_noanno.png`: UMAP 按聚类着色 (无注释)

**错误响应**:
- `404`: 数据集不存在
- `440`: 基因不存在
- `500`: 图表生成失败

---

### 5. 获取可用图表类型

获取指定数据集支持的图表类型列表。

**端点**: `GET /plots/types`

**请求参数**:
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 数据集 ID |

**请求示例**:
```bash
curl "http://localhost:8080/api/v1/plots/types?id=NO1"
```

**响应示例**:
```json
{
  "types": [
    "feature",
    "dot_anno",
    "heat_anno",
    "dot_cluster",
    "heat_cluster"
  ]
}
```

---

## 前端集成示例

### JavaScript/Fetch

```javascript
const API_BASE = 'http://localhost:8080/api/v1';

// 获取数据集列表
async function getDatasets() {
  const response = await fetch(`${API_BASE}/datasets`);
  const data = await response.json();
  return data.datasets;
}

// 检查基因
async function checkGene(datasetId, gene) {
  const response = await fetch(
    `${API_BASE}/genes/check?id=${datasetId}&gene=${gene}`
  );
  const data = await response.json();
  return data;
}

// 获取图表
async function getPlots(datasetId, gene) {
  const response = await fetch(
    `${API_BASE}/plots/all?id=${datasetId}&gene=${gene}`
  );
  const data = await response.json();
  return {
    gene: data.gene,
    plots: data.plots,
    basePlots: data.base_plots
  };
}

// 使用示例
async function example() {
  // 1. 获取数据集
  const datasets = await getDatasets();
  console.log('可用数据集:', datasets);
  
  // 2. 检查基因
  const geneCheck = await checkGene('NO1', 'GAPDH');
  if (geneCheck.found) {
    // 3. 获取图表
    const plots = await getPlots('NO1', 'GAPDH');
    console.log('基因图表:', plots.plots);
    console.log('基础图表:', plots.basePlots);
  }
}
```

### React/Axios

```javascript
import axios from 'axios';

const API_BASE = 'http://localhost:8080/api/v1';

// 创建 axios 实例
const api = axios.create({
  baseURL: API_BASE,
  timeout: 30000
});

// 获取数据集
export const getDatasets = async () => {
  const response = await api.get('/datasets');
  return response.data.datasets;
};

// 检查基因
export const checkGene = async (datasetId, gene) => {
  try {
    const response = await api.get('/genes/check', {
      params: { id: datasetId, gene }
    });
    return response.data;
  } catch (error) {
    if (error.response?.status === 440) {
      return { found: false, error: '基因不存在' };
    }
    throw error;
  }
};

// 获取图表
export const getPlots = async (datasetId, gene) => {
  const response = await api.get('/plots/all', {
    params: { id: datasetId, gene }
  });
  return response.data;
};

// React 组件示例
function PlotViewer({ datasetId, gene }) {
  const [plots, setPlots] = useState(null);
  const [loading, setLoading] = useState(false);
  
  useEffect(() => {
    async function fetchPlots() {
      setLoading(true);
      try {
        const data = await getPlots(datasetId, gene);
        setPlots(data);
      } catch (error) {
        console.error('获取图表失败:', error);
      } finally {
        setLoading(false);
      }
    }
    
    if (datasetId && gene) {
      fetchPlots();
    }
  }, [datasetId, gene]);
  
  if (loading) return <div>加载中...</div>;
  if (!plots) return null;
  
  return (
    <div>
      <h3>基因: {plots.gene}</h3>
      <div>
        {plots.plots.map((path, idx) => (
          <img key={idx} src={path} alt={`Plot ${idx}`} />
        ))}
      </div>
    </div>
  );
}
```

### Vue 3

```javascript
import { ref } from 'vue';
import axios from 'axios';

const API_BASE = 'http://localhost:8080/api/v1';

export function usePlotService() {
  const loading = ref(false);
  const error = ref(null);
  
  const getDatasets = async () => {
    loading.value = true;
    error.value = null;
    try {
      const response = await axios.get(`${API_BASE}/datasets`);
      return response.data.datasets;
    } catch (e) {
      error.value = e.message;
      throw e;
    } finally {
      loading.value = false;
    }
  };
  
  const getPlots = async (datasetId, gene) => {
    loading.value = true;
    error.value = null;
    try {
      const response = await axios.get(`${API_BASE}/plots/all`, {
        params: { id: datasetId, gene }
      });
      return response.data;
    } catch (e) {
      error.value = e.message;
      throw e;
    } finally {
      loading.value = false;
    }
  };
  
  return {
    loading,
    error,
    getDatasets,
    getPlots
  };
}
```

---

## 错误处理

### HTTP 状态码

| 状态码 | 说明 |
|--------|------|
| 200 | 请求成功 |
| 404 | 数据集不存在 |
| 440 | 基因不存在 (自定义状态码) |
| 500 | 服务器内部错误 |
| 503 | 服务不可用 (无可用实例) |

### 错误响应格式

```json
{
  "error": "错误描述信息"
}
```

### 错误处理示例

```javascript
async function safeGetPlots(datasetId, gene) {
  try {
    const response = await fetch(
      `${API_BASE}/plots/all?id=${datasetId}&gene=${gene}`
    );
    
    if (!response.ok) {
      const error = await response.json();
      
      switch (response.status) {
        case 404:
          console.error('数据集不存在:', error.error);
          break;
        case 440:
          console.error('基因不存在:', error.error);
          break;
        case 500:
          console.error('图表生成失败:', error.error);
          break;
        default:
          console.error('未知错误:', error.error);
      }
      
      return null;
    }
    
    return await response.json();
  } catch (error) {
    console.error('网络错误:', error);
    return null;
  }
}
```

---

## 性能说明

- **首次请求**: 图表生成需要 2-3 秒
- **缓存请求**: 后续相同请求 < 100ms (使用缓存)
- **并发支持**: 支持 100+ 并发请求
- **负载均衡**: 请求自动分发到 3 个 R 服务实例

---

## 注意事项

1. **路径格式**: API 返回的是服务器端绝对路径，前端需要根据实际情况处理
2. **缓存机制**: 图表会被缓存，相同请求会直接返回缓存结果
3. **超时设置**: 建议设置 30 秒超时时间（首次生成图表可能较慢）
4. **错误重试**: 建议实现自动重试机制（最多 3 次）
5. **基因名称**: 基因名称大小写敏感，建议使用标准基因符号

---

## 支持与反馈

如有问题或建议，请联系技术支持团队。
