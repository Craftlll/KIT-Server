# Unified Single-Cell Lite Service API Reference

本服务提供了一套 RESTful API，用于查询单细胞数据集的原数据、基因存在性以及获取可视化图表。

**Base URL**: `http://localhost:8000`

---

## 1. System Health (系统健康)

检查服务是否正常运行。

*   **Endpoint**: `/health`
*   **Method**: `GET`
*   **Parameters**: 无
*   **Response**:
    ```json
    {
      "status": "UP",
      "mode": "Unified"
    }
    ```

---

## 2. List Datasets (获取数据集列表)

获取当前服务中已注册的所有数据集列表。

*   **Endpoint**: `/datasets`
*   **Method**: `GET`
*   **Parameters**: 无
*   **Response**:
    ```json
    {
      "datasets": [
        {
          "id": "NO1",
          "name": "Dataset NO1"
        },
        {
          "id": "NO12",
          "name": "Dataset NO12"
        }
      ]
    }
    ```

---

## 3. Check Gene Existence (检查基因)

查询特定基因是否存在于指定的数据集中（支持大小写模糊匹配）。

*   **Endpoint**: `/genes/check`
*   **Method**: `GET`
*   **Parameters**:
    *   `id` (Required): 数据集 ID (例如 `NO1`)
    *   `gene` (Required): 基因名称 (例如 `GAPDH`)
*   **Response (Found)**: `HTTP 200`
    ```json
    {
      "found": true,
      "gene": "Gapdh"  // 返回真实的基因标准名
    }
    ```
*   **Response (Not Found)**: `HTTP 440` (Custom Code)
    ```json
    {
      "error": "Gene GAPDH not found"
    }
    ```

---

## 4. Get Base Plot (获取底图)

获取数据集的静态 UMAP/t-SNE 底图（无基因染色）。

*   **Endpoint**: `/plots/base`
*   **Method**: `GET`
*   **Parameters**:
    *   `id` (Required): 数据集 ID
*   **Response**: `image/png` (二进制图片流)
*   **Example**:
    ```bash
    curl "http://localhost:8000/plots/base?id=NO1" > base_plot.png
    ```

---

## 5. Get Gene Expression Plot (获取基因表达图)

生成或获取指定基因的表达量分布图。

*   **Endpoint**: `/plots/all`
*   **Method**: `GET`
*   **Parameters**:
    *   `id` (Required): 数据集 ID
    *   `gene` (Required): 基因名称
*   **Response**: JSON (包含所有相关图片的绝对路径)
    ```json
    {
      "gene": "GAPDH",
      "plots": {
        "feature": "/Users/craft/Desktop/KIT-Rserve/data/NO1/lite/cache/GAPDH/feature.png",
        "dot_anno": "/Users/craft/Desktop/KIT-Rserve/data/NO1/lite/cache/GAPDH/dot_anno.png",
        "heat_anno": "/Users/craft/Desktop/KIT-Rserve/data/NO1/lite/cache/GAPDH/heat_anno.png",
        "dot_cluster": "/Users/craft/Desktop/KIT-Rserve/data/NO1/lite/cache/GAPDH/dot_cluster.png",
        "heat_cluster": "/Users/craft/Desktop/KIT-Rserve/data/NO1/lite/cache/GAPDH/heat_cluster.png"
      },
      "base_plots": {
        "uas": "/Users/craft/Desktop/KIT-Rserve/data/NO1/lite/base/uas.png",
        "ucd45": "/Users/craft/Desktop/KIT-Rserve/data/NO1/lite/base/ucd45.png",
        "ucta_withanno": "/Users/craft/Desktop/KIT-Rserve/data/NO1/lite/base/ucta_withanno.png",
        "ucta_noanno": "/Users/craft/Desktop/KIT-Rserve/data/NO1/lite/base/ucta_noanno.png"
      }
    }
    ```
    *注意*: 返回的是服务器本地绝对路径。客户端可以直接读取这些文件或将其作为静态资源处理。

---

## Error Codes

*   **200**: 成功
*   **404**: 数据集未找到或资源缺失
*   **440**: 自定义状态码 - 基因未找到 (Gene Not Found)
*   **500**: 服务器内部错误
