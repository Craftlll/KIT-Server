package main

import (
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"

	"gateway/internal/config"
	"gateway/internal/handlers"
	"gateway/internal/nacos"

	"github.com/gin-gonic/gin"
)

func main() {
	// Load configuration
	cfg, err := config.LoadConfig("config.yaml")
	if err != nil {
		log.Fatalf("[Gateway] Failed to load config: %v", err)
	}

	// Set Gin mode
	gin.SetMode(cfg.Server.Mode)

	// Initialize Nacos service discovery
	discovery, err := nacos.NewDiscovery(
		cfg.Nacos.ServerAddr,
		cfg.Nacos.ServerPort,
		cfg.Nacos.ServiceName,
		cfg.Nacos.Group,
	)
	if err != nil {
		log.Fatalf("[Gateway] Failed to initialize Nacos: %v", err)
	}

	// Create Gin router
	r := gin.Default()

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":    "UP",
			"instances": discovery.InstanceCount(),
		})
	})

	// API proxy routes
	api := r.Group("/api/v1")
	{
		api.Any("/*path", proxyHandler(discovery, cfg))
	}

	// Static file service
	r.Static(cfg.Static.URLPrefix, cfg.Static.RootPath)

	// Start server
	addr := ":" + cfg.Server.Port
	log.Printf("[Gateway] Starting on %s", addr)
	log.Printf("[Gateway] Proxying to service: %s", cfg.Nacos.ServiceName)

	if err := r.Run(addr); err != nil {
		log.Fatalf("[Gateway] Failed to start: %v", err)
	}
}

// proxyHandler creates a reverse proxy handler with load balancing
func proxyHandler(discovery *nacos.Discovery, cfg *config.Config) gin.HandlerFunc {
	// Create HTTP transport with connection pooling
	transport := &http.Transport{
		MaxIdleConns:        cfg.Proxy.MaxIdleConns,
		MaxIdleConnsPerHost: 10,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: 10 * time.Second,
	}

	return func(c *gin.Context) {
		// Get next available instance
		instance, err := discovery.GetInstance()
		if err != nil {
			log.Printf("[Gateway] No available instances: %v", err)
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error": "No available service instances",
			})
			return
		}

		// Build target URL
		targetURL := discovery.GetInstanceURL(instance)
		target, err := url.Parse(targetURL)
		if err != nil {
			log.Printf("[Gateway] Failed to parse target URL: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Internal server error",
			})
			return
		}

		// Create reverse proxy
		proxy := httputil.NewSingleHostReverseProxy(target)
		proxy.Transport = transport

		// Modify request
		director := proxy.Director
		proxy.Director = func(req *http.Request) {
			director(req)
			req.Host = target.Host
			req.URL.Scheme = target.Scheme
			req.URL.Host = target.Host

			// 获取原始路径
			path := c.Param("path")

			// 路由转换：将 /plots/anno 和 /plots/noanno 转换为 /plots/all
			if strings.HasPrefix(path, "/plots/anno") || strings.HasPrefix(path, "/plots/noanno") {
				// 保留查询参数，但将路径改为 /plots/all
				path = "/plots/all"
			}

			req.URL.Path = path
			req.URL.RawQuery = c.Request.URL.RawQuery

			log.Printf("[Gateway] Proxying: %s %s -> %s%s",
				c.Request.Method,
				c.Request.URL.Path,
				target.Host,
				path,
			)
		}

		// Modify response for filtering plots
		originalPath := c.Request.URL.Path
		proxy.ModifyResponse = func(resp *http.Response) error {
			// 根据原始请求路径进行过滤
			if strings.Contains(originalPath, "/plots/anno") {
				log.Printf("[Gateway] Filtering anno plots...")
				return handlers.FilterPlotsAnno(resp)
			} else if strings.Contains(originalPath, "/plots/noanno") {
				log.Printf("[Gateway] Filtering noanno plots...")
				return handlers.FilterPlotsNoAnno(resp)
			}
			return nil
		}

		// Error handler
		proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
			log.Printf("[Gateway] Proxy error: %v", err)
			c.JSON(http.StatusBadGateway, gin.H{
				"error": "Failed to proxy request",
			})
		}

		// Execute proxy
		proxy.ServeHTTP(c.Writer, c.Request)
	}
}
