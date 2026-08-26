package state

import (
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type EmitEvent func(typ string, payload any)

type trafficSample struct {
	Up        int64 `json:"up"`
	Down      int64 `json:"down"`
	UpTotal   int64 `json:"upTotal"`
	DownTotal int64 `json:"downTotal"`
}

type memorySample struct {
	Inuse   uint64 `json:"inuse"`
	OSLimit uint64 `json:"oslimit"`
}

var (
	telemetryMu   sync.Mutex
	telemetryStop chan struct{}
)

func StartTelemetry(emit EmitEvent) {
	telemetryMu.Lock()
	if telemetryStop != nil {
		close(telemetryStop)
	}
	stop := make(chan struct{})
	telemetryStop = stop
	telemetryMu.Unlock()

	go func() {
		tick := time.NewTicker(time.Second)
		defer tick.Stop()
		for {
			select {
			case <-stop:
				return
			case <-tick.C:
				up, down := statistic.DefaultManager.Now()
				upTotal, downTotal := statistic.DefaultManager.Total()
				emit("traffic", trafficSample{Up: up, Down: down, UpTotal: upTotal, DownTotal: downTotal})
				emit("memory", memorySample{Inuse: statistic.DefaultManager.Memory()})
			}
		}
	}()

	go func() {
		subscription := log.Subscribe()
		defer log.UnSubscribe(subscription)
		for {
			select {
			case <-stop:
				return
			case event := <-subscription:
				payload := strings.TrimSpace(event.Payload)
				if payload == "" {
					continue
				}
				emit("logs", map[string]any{
					"level":   event.LogLevel.String(),
					"payload": payload,
					"time":    time.Now().UnixMilli(),
				})
			}
		}
	}()
}

func StopTelemetry() {
	telemetryMu.Lock()
	defer telemetryMu.Unlock()
	if telemetryStop != nil {
		close(telemetryStop)
		telemetryStop = nil
	}
}
