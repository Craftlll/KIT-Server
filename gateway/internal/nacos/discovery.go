package nacos

import (
	"fmt"
	"log"

	"gateway/internal/lb"

	"github.com/nacos-group/nacos-sdk-go/v2/clients"
	"github.com/nacos-group/nacos-sdk-go/v2/clients/naming_client"
	"github.com/nacos-group/nacos-sdk-go/v2/common/constant"
	"github.com/nacos-group/nacos-sdk-go/v2/model"
	"github.com/nacos-group/nacos-sdk-go/v2/vo"
)

// Discovery handles Nacos service discovery
type Discovery struct {
	client      naming_client.INamingClient
	serviceName string
	group       string
	lb          *lb.RoundRobin
}

// NewDiscovery creates a new Nacos discovery client
func NewDiscovery(serverAddr string, serverPort uint64, serviceName, group string) (*Discovery, error) {
	// Create Nacos server config
	sc := []constant.ServerConfig{
		*constant.NewServerConfig(serverAddr, serverPort),
	}

	// Create Nacos client config
	cc := constant.ClientConfig{
		NamespaceId:         "",
		TimeoutMs:           10000,
		NotLoadCacheAtStart: true,
		LogDir:              "/tmp/nacos/log",
		CacheDir:            "/tmp/nacos/cache",
		LogLevel:            "info",
	}

	// Create naming client
	client, err := clients.NewNamingClient(
		vo.NacosClientParam{
			ClientConfig:  &cc,
			ServerConfigs: sc,
		},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create Nacos client: %w", err)
	}

	d := &Discovery{
		client:      client,
		serviceName: serviceName,
		group:       group,
		lb:          lb.NewRoundRobin(),
	}

	// Initial instance refresh
	if err := d.refreshInstances(); err != nil {
		log.Printf("[Nacos] Warning: Failed to refresh instances on startup: %v", err)
	}

	// Subscribe to service changes
	if err := d.subscribe(); err != nil {
		return nil, fmt.Errorf("failed to subscribe to service: %w", err)
	}

	log.Printf("[Nacos] Service discovery initialized for: %s", serviceName)
	return d, nil
}

// refreshInstances fetches and updates the instance list
func (d *Discovery) refreshInstances() error {
	instances, err := d.client.SelectInstances(vo.SelectInstancesParam{
		ServiceName: d.serviceName,
		GroupName:   d.group,
		HealthyOnly: true,
	})

	if err != nil {
		return fmt.Errorf("failed to select instances: %w", err)
	}

	d.lb.UpdateInstances(instances)
	log.Printf("[Nacos] Instance list updated: %d instances available", len(instances))
	return nil
}

// subscribe listens for service instance changes
func (d *Discovery) subscribe() error {
	return d.client.Subscribe(&vo.SubscribeParam{
		ServiceName: d.serviceName,
		GroupName:   d.group,
		SubscribeCallback: func(services []model.Instance, err error) {
			if err != nil {
				log.Printf("[Nacos] Subscribe callback error: %v", err)
				return
			}

			d.lb.UpdateInstances(services)
			log.Printf("[Nacos] Service instances changed: %d instances", len(services))
		},
	})
}

// GetInstance returns the next available instance using load balancing
func (d *Discovery) GetInstance() (*model.Instance, error) {
	return d.lb.Next()
}

// GetInstances returns all current instances
func (d *Discovery) GetInstances() []model.Instance {
	return d.lb.GetInstances()
}

// GetInstanceURL constructs the URL for an instance
func (d *Discovery) GetInstanceURL(instance *model.Instance) string {
	return fmt.Sprintf("http://%s:%d", instance.Ip, instance.Port)
}

// InstanceCount returns the number of available instances
func (d *Discovery) InstanceCount() int {
	return d.lb.Count()
}
