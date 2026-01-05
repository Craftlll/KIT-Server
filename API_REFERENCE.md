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
*   **Response**: JSON 包含图片生成路径
    ```json
    {
      "gene_plots": {
        "feature": "/Users/craft/Desktop/data/NO1/lite/cache/Gapdh_feature.png"
      }
    }
    ```
    *注意*: 目前返回的是服务器本地绝对路径。在开发 Web UI 时，可能需要通过通过静态文件服务映射该目录，或修改 API 直接返回图片流。

---

## Error Codes

*   **200**: 成功
*   **404**: 数据集未找到或资源缺失
*   **440**: 自定义状态码 - 基因未找到 (Gene Not Found)
*   **500**: 服务器内部错误
