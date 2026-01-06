package lb

import (
	"fmt"
	"sync"
	"sync/atomic"

	"github.com/nacos-group/nacos-sdk-go/v2/model"
)

// RoundRobin implements a thread-safe round-robin load balancer
type RoundRobin struct {
	instances []model.Instance
	current   uint32
	mu        sync.RWMutex
}

// NewRoundRobin creates a new round-robin load balancer
func NewRoundRobin() *RoundRobin {
	return &RoundRobin{
		instances: make([]model.Instance, 0),
		current:   0,
	}
}

// UpdateInstances updates the instance list
func (rr *RoundRobin) UpdateInstances(instances []model.Instance) {
	rr.mu.Lock()
	defer rr.mu.Unlock()

	rr.instances = make([]model.Instance, len(instances))
	copy(rr.instances, instances)
}

// Next returns the next instance using round-robin algorithm
func (rr *RoundRobin) Next() (*model.Instance, error) {
	rr.mu.RLock()
	defer rr.mu.RUnlock()

	if len(rr.instances) == 0 {
		return nil, fmt.Errorf("no available instances")
	}

	// Atomic increment and modulo
	next := atomic.AddUint32(&rr.current, 1)
	idx := int(next-1) % len(rr.instances)

	return &rr.instances[idx], nil
}

// GetInstances returns a copy of current instances
func (rr *RoundRobin) GetInstances() []model.Instance {
	rr.mu.RLock()
	defer rr.mu.RUnlock()

	instances := make([]model.Instance, len(rr.instances))
	copy(instances, rr.instances)
	return instances
}

// Count returns the number of available instances
func (rr *RoundRobin) Count() int {
	rr.mu.RLock()
	defer rr.mu.RUnlock()
	return len(rr.instances)
}
