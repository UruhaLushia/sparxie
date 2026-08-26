package state

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"strconv"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	MC "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"go4.org/netipx"
)

type OverrideConfig struct {
	MixedPort  int32
	Port       int32
	SocksPort  int32
	AllowLAN   bool
	Controller string
	Secret     string
	LogLevel   string
}

var overrideConfig OverrideConfig

type configSchema struct {
	Mode *tunnel.TunnelMode `json:"mode"`
}

func ChangeProxy(group, name string) error {
	proxy, ok := proxiesWithProviders()[group]
	if !ok {
		return errors.New("proxy group not found")
	}
	selector, ok := proxy.Adapter().(outboundgroup.SelectAble)
	if !ok {
		return errors.New("proxy group is not selectable")
	}
	if err := selector.Set(name); err != nil {
		return err
	}
	cachefile.Cache().SetSelected(proxy.Name(), name)
	return nil
}

func CloseConnection(id string) {
	if connection := statistic.DefaultManager.Get(id); connection != nil {
		_ = connection.Close()
	}
}

func CloseAllConnections() {
	statistic.DefaultManager.Range(func(connection statistic.Tracker) bool {
		_ = connection.Close()
		return true
	})
}

func PatchConfig(params string) error {
	var general configSchema
	if err := json.Unmarshal([]byte(params), &general); err != nil {
		return err
	}
	if general.Mode != nil {
		tunnel.SetMode(*general.Mode)
	}
	return nil
}

func SetOverrideConfig(config OverrideConfig) {
	overrideConfig = config
}

func ApplyInitialConfig(path string) error {
	bytes, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read config: %w", err)
	}
	cfg, err := executor.ParseWithBytes(bytes)
	if err != nil {
		return fmt.Errorf("parse config: %w", err)
	}
	applyOverride(cfg)
	hub.ApplyConfig(cfg)
	return nil
}

func ReloadConfig(path string) error {
	cfg, err := executor.ParseWithPath(path)
	if err != nil {
		return err
	}
	applyOverride(cfg)
	executor.ApplyConfig(cfg, true)
	return nil
}

func applyOverride(cfg *config.Config) {
	cfg.General.Tun.Enable = false
	cfg.Controller.ExternalController = overrideConfig.Controller
	cfg.Controller.Secret = overrideConfig.Secret
	cfg.General.MixedPort = int(overrideConfig.MixedPort)
	cfg.General.Port = int(overrideConfig.Port)
	cfg.General.SocksPort = int(overrideConfig.SocksPort)
	cfg.General.AllowLan = overrideConfig.AllowLAN
	cfg.General.LogLevel = log.LogLevelMapping[overrideConfig.LogLevel]
}

func TestDelay(name, url string, timeoutMs int, expected string) string {
	proxy, ok := proxiesWithProviders()[name]
	if !ok {
		return `{"error":"proxy not found"}`
	}
	expectedStatus, _ := utils.NewUnsignedRanges[uint16](expected)
	ctx, cancel := context.WithTimeout(context.Background(), time.Millisecond*time.Duration(timeoutMs))
	defer cancel()

	delay, err := proxy.URLTest(ctx, url, expectedStatus)
	if ctx.Err() != nil {
		return `{"error":"timeout"}`
	}
	if err != nil || delay == 0 {
		message := "no delay"
		if err != nil {
			message = err.Error()
		}
		return `{"error":` + strconv.Quote(message) + `}`
	}
	return `{"delay":` + strconv.FormatUint(uint64(delay), 10) + `}`
}

func ValidateConfig(text string) error {
	_, err := executor.ParseWithBytes([]byte(text))
	return err
}

func UpdateProvider(name string) error {
	provider, ok := tunnel.Providers()[name]
	if !ok {
		return errors.New("provider not found")
	}
	return provider.Update()
}

func UpdateRuleProvider(name string) error {
	provider, ok := tunnel.RuleProviders()[name]
	if !ok {
		return errors.New("rule provider not found")
	}
	return provider.Update()
}

func UnfixProxy(name string) error {
	proxy, ok := proxiesWithProviders()[name]
	if !ok {
		return errors.New("proxy not found")
	}
	selectable, ok := proxy.Adapter().(outboundgroup.SelectAble)
	if ok && proxy.Type() != MC.Selector {
		selectable.ForceSet("")
		cachefile.Cache().SetSelected(proxy.Name(), "")
	}
	return nil
}

func FlushFakeIP() error {
	return resolver.FlushFakeIP()
}

func FlushDNS() {
	resolver.ClearCache()
}

func SetDefaultInterface(name string) {
	dialer.DefaultInterface.Store(name)
	if name != "" {
		iface.FlushCache()
		resolver.ResetConnection()
	}
}

func ComputeRouteRanges(excludeJSON string) (string, error) {
	var excludes []string
	if err := json.Unmarshal([]byte(excludeJSON), &excludes); err != nil {
		return "", err
	}
	var builder netipx.IPSetBuilder
	builder.AddPrefix(netip.PrefixFrom(netip.IPv4Unspecified(), 0))
	builder.AddPrefix(netip.PrefixFrom(netip.IPv6Unspecified(), 0))
	for _, exclude := range excludes {
		if prefix, err := netip.ParsePrefix(exclude); err == nil {
			builder.RemovePrefix(prefix)
		}
	}
	set, err := builder.IPSet()
	if err != nil {
		return "", err
	}
	out, err := json.Marshal(set.Prefixes())
	if err != nil {
		return "", err
	}
	return string(out), nil
}
