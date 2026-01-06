package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server ServerConfig `yaml:"server"`
	Nacos  NacosConfig  `yaml:"nacos"`
	Proxy  ProxyConfig  `yaml:"proxy"`
	Static StaticConfig `yaml:"static"`
	Log    LogConfig    `yaml:"log"`
}

type ServerConfig struct {
	Port string `yaml:"port"`
	Mode string `yaml:"mode"`
}

type NacosConfig struct {
	ServerAddr  string `yaml:"server_addr"`
	ServerPort  uint64 `yaml:"server_port"`
	NamespaceID string `yaml:"namespace_id"`
	Group       string `yaml:"group"`
	ServiceName string `yaml:"service_name"`
	TimeoutMs   uint64 `yaml:"timeout_ms"`
}

type ProxyConfig struct {
	TimeoutSeconds int `yaml:"timeout_seconds"`
	MaxIdleConns   int `yaml:"max_idle_conns"`
}

type StaticConfig struct {
	RootPath  string `yaml:"root_path"`
	URLPrefix string `yaml:"url_prefix"`
}

type LogConfig struct {
	Level  string `yaml:"level"`
	Format string `yaml:"format"`
}

// LoadConfig loads configuration from file with environment variable override
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	// Environment variable overrides
	if port := os.Getenv("SERVER_PORT"); port != "" {
		cfg.Server.Port = port
	}
	if nacosAddr := os.Getenv("NACOS_SERVER_ADDR"); nacosAddr != "" {
		cfg.Nacos.ServerAddr = nacosAddr
	}
	if dataPath := os.Getenv("DATA_PATH"); dataPath != "" {
		cfg.Static.RootPath = dataPath
	}

	return &cfg, nil
}
