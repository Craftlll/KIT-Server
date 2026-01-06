package handlers

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strings"
)

// PlotsResponse 表示 /plots/all 的响应结构
type PlotsResponse struct {
	Gene      string                 `json:"gene"`
	GenePlots map[string]interface{} `json:"gene_plots"`
	BasePlots map[string]interface{} `json:"base_plots"`
}

// FilteredPlotsResponse 表示过滤后的响应结构
type FilteredPlotsResponse struct {
	Gene        string                 `json:"gene"`
	GenePlots   map[string]interface{} `json:"gene_plots"`
	BasePlots   map[string]interface{} `json:"base_plots"`
	FilterType  string                 `json:"filter_type"`
	Description string                 `json:"description"`
}

// FilterPlotsAnno 过滤出带 anno 的图像
func FilterPlotsAnno(resp *http.Response) error {
	// 读取原始响应体
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	resp.Body.Close()

	// 解析 JSON
	var plotsResp PlotsResponse
	if err := json.Unmarshal(body, &plotsResp); err != nil {
		log.Printf("[Gateway] Failed to parse plots response: %v", err)
		// 如果解析失败，返回原始响应
		resp.Body = io.NopCloser(bytes.NewReader(body))
		return nil
	}

	// 过滤 gene_plots：只保留带 anno 的
	filteredGenePlots := make(map[string]interface{})
	for key, value := range plotsResp.GenePlots {
		if strings.Contains(key, "withanno") {
			filteredGenePlots[key] = value
		}
	}

	// 过滤 base_plots：只保留 ucta_withanno
	filteredBasePlots := make(map[string]interface{})
	for key, value := range plotsResp.BasePlots {
		if key == "ucta_withanno" {
			filteredBasePlots[key] = value
		}
	}

	// 构建新的响应
	filteredResp := FilteredPlotsResponse{
		Gene:        plotsResp.Gene,
		GenePlots:   filteredGenePlots,
		BasePlots:   filteredBasePlots,
		FilterType:  "anno",
		Description: "仅包含带注释(anno)的图像",
	}

	// 序列化为 JSON
	newBody, err := json.Marshal(filteredResp)
	if err != nil {
		log.Printf("[Gateway] Failed to marshal filtered response: %v", err)
		resp.Body = io.NopCloser(bytes.NewReader(body))
		return nil
	}

	// 更新响应体
	resp.Body = io.NopCloser(bytes.NewReader(newBody))
	resp.ContentLength = int64(len(newBody))
	resp.Header.Set("Content-Length", string(rune(len(newBody))))

	log.Printf("[Gateway] Filtered anno plots for gene: %s", plotsResp.Gene)
	return nil
}

// FilterPlotsNoAnno 过滤出不带 anno 的图像
func FilterPlotsNoAnno(resp *http.Response) error {
	// 读取原始响应体
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	resp.Body.Close()

	// 解析 JSON
	var plotsResp PlotsResponse
	if err := json.Unmarshal(body, &plotsResp); err != nil {
		log.Printf("[Gateway] Failed to parse plots response: %v", err)
		// 如果解析失败，返回原始响应
		resp.Body = io.NopCloser(bytes.NewReader(body))
		return nil
	}

	// 过滤 gene_plots：排除带 anno 的
	filteredGenePlots := make(map[string]interface{})
	for key, value := range plotsResp.GenePlots {
		if !strings.Contains(key, "withanno") {
			filteredGenePlots[key] = value
		}
	}

	// 过滤 base_plots：排除 ucta_withanno
	filteredBasePlots := make(map[string]interface{})
	for key, value := range plotsResp.BasePlots {
		if key != "ucta_withanno" {
			filteredBasePlots[key] = value
		}
	}

	// 构建新的响应
	filteredResp := FilteredPlotsResponse{
		Gene:        plotsResp.Gene,
		GenePlots:   filteredGenePlots,
		BasePlots:   filteredBasePlots,
		FilterType:  "noanno",
		Description: "仅包含不带注释(noanno)的图像",
	}

	// 序列化为 JSON
	newBody, err := json.Marshal(filteredResp)
	if err != nil {
		log.Printf("[Gateway] Failed to marshal filtered response: %v", err)
		resp.Body = io.NopCloser(bytes.NewReader(body))
		return nil
	}

	// 更新响应体
	resp.Body = io.NopCloser(bytes.NewReader(newBody))
	resp.ContentLength = int64(len(newBody))
	resp.Header.Set("Content-Length", string(rune(len(newBody))))

	log.Printf("[Gateway] Filtered noanno plots for gene: %s", plotsResp.Gene)
	return nil
}
