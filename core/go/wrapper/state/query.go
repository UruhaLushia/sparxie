package state

import (
	"encoding/json"
	"net"
	"syscall"
	"time"

	MC "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type ProcessLookup func(protocol int, source, target string) string

type ruleItem struct {
	Index   int        `json:"index"`
	Type    string     `json:"type"`
	Payload string     `json:"payload"`
	Proxy   string     `json:"proxy"`
	Size    int        `json:"size"`
	Extra   *ruleExtra `json:"extra,omitempty"`
}

type ruleExtra struct {
	Disabled  bool      `json:"disabled"`
	HitCount  uint64    `json:"hitCount"`
	HitAt     time.Time `json:"hitAt,omitempty"`
	MissCount uint64    `json:"missCount"`
	MissAt    time.Time `json:"missAt,omitempty"`
}

func Query(method string, lookup ProcessLookup) string {
	var result any
	switch method {
	case "connections":
		result = snapshotWithProcessRefresh(lookup)
	case "proxies":
		result = map[string]any{"proxies": proxiesWithProviders()}
	case "configs":
		result = executor.GetGeneral()
	case "rules":
		result = map[string]any{"rules": ruleList()}
	case "version":
		result = map[string]any{"meta": MC.Meta, "version": MC.Version}
	case "providers":
		result = map[string]any{"providers": tunnel.Providers()}
	case "ruleProviders":
		result = map[string]any{"providers": tunnel.RuleProviders()}
	default:
		result = map[string]any{"error": "unknown method: " + method}
	}

	body, err := json.Marshal(result)
	if err != nil {
		return `{"error":"marshal failed"}`
	}
	return string(body)
}

func snapshotWithProcessRefresh(lookup ProcessLookup) json.RawMessage {
	snapshot := statistic.DefaultManager.Snapshot()
	body, err := json.Marshal(snapshot)
	if err != nil {
		return json.RawMessage(`{"connections":[]}`)
	}
	var response map[string]any
	if json.Unmarshal(body, &response) != nil {
		return body
	}
	connections, _ := response["connections"].([]any)
	for index, info := range snapshot.Connections {
		metadata := info.Metadata
		if metadata == nil || metadata.Process != "" || index >= len(connections) {
			continue
		}
		src, dst := metadata.RawSrcAddr, metadata.RawDstAddr
		if src == nil && metadata.SrcIP.IsValid() && metadata.SrcPort > 0 {
			src = &net.TCPAddr{IP: metadata.SrcIP.AsSlice(), Port: int(metadata.SrcPort)}
		}
		if dst == nil && metadata.InIP.IsValid() && metadata.InPort > 0 {
			dst = &net.TCPAddr{IP: metadata.InIP.AsSlice(), Port: int(metadata.InPort)}
		}
		if src == nil || dst == nil || lookup == nil {
			continue
		}
		if process := lookup(protocolOf(src), src.String(), dst.String()); process != "" {
			if connection, ok := connections[index].(map[string]any); ok {
				if value, ok := connection["metadata"].(map[string]any); ok {
					value["process"] = process
				}
			}
		}
	}
	body, err = json.Marshal(response)
	if err != nil {
		return json.RawMessage(`{"connections":[]}`)
	}
	return body
}

func protocolOf(addr net.Addr) int {
	switch addr.Network() {
	case "udp", "udp4", "udp6":
		return syscall.IPPROTO_UDP
	default:
		return syscall.IPPROTO_TCP
	}
}

func proxiesWithProviders() map[string]MC.Proxy {
	allProxies := make(map[string]MC.Proxy)
	for name, proxy := range tunnel.Proxies() {
		allProxies[name] = proxy
	}
	for _, provider := range tunnel.Providers() {
		for _, proxy := range provider.Proxies() {
			allProxies[proxy.Name()] = proxy
		}
	}
	return allProxies
}

func ruleList() []ruleItem {
	rawRules := tunnel.Rules()
	rules := make([]ruleItem, 0, len(rawRules))
	for index, rule := range rawRules {
		item := ruleItem{
			Index:   index,
			Type:    rule.RuleType().String(),
			Payload: rule.Payload(),
			Proxy:   rule.Adapter(),
			Size:    -1,
		}
		if wrapper, ok := rule.(MC.RuleWrapper); ok {
			item.Extra = &ruleExtra{
				Disabled:  wrapper.IsDisabled(),
				HitCount:  wrapper.HitCount(),
				HitAt:     wrapper.HitAt(),
				MissCount: wrapper.MissCount(),
				MissAt:    wrapper.MissAt(),
			}
			rule = wrapper.Unwrap()
		}
		if rule.RuleType() == MC.GEOIP || rule.RuleType() == MC.GEOSITE {
			if group, ok := rule.(MC.RuleGroup); ok {
				item.Size = group.GetRecodeSize()
			}
		}
		rules = append(rules, item)
	}
	return rules
}
