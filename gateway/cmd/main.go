package main

import (
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"

	"gateway/internal/config"
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

			// Remove /api/v1 prefix
			path := c.Param("path")
			req.URL.Path = path
			req.URL.RawQuery = c.Request.URL.RawQuery

			log.Printf("[Gateway] Proxying: %s %s -> %s%s",
				c.Request.Method,
				c.Request.URL.Path,
				target.Host,
				path,
			)
		}

		// Modify response for path conversion
		proxy.ModifyResponse = func(resp *http.Response) error {
			// Only modify /plots/all responses
			if strings.Contains(c.Request.URL.Path, "/plots/all") {
				// TODO: Implement path conversion from absolute paths to /static URLs
				// This will be done in the next iteration
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
