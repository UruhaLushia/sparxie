// Package tun attaches a platform-provided file descriptor to mihomo's
// sing-tun listener. The fd comes from Android's VpnService (or a platform
// equivalent on desktop); the kernel never creates its own device.
package tun

import (
	"encoding/json"
	"io"
	"net"
	"net/netip"
	"strings"

	C "github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"golang.org/x/sys/unix"
)

func Start(fd int, stack, gateway, dns string, mtu int) (io.Closer, error) {
	log.Debugln("TUN: fd = %d, stack = %s, gateway = %s, dns = %s", fd, stack, gateway, dns)

	tunStack, ok := C.StackTypeMapping[strings.ToLower(stack)]
	if !ok {
		tunStack = C.TunSystem
	}

	var prefix4 []netip.Prefix
	var prefix6 []netip.Prefix
	for _, gatewayStr := range strings.Split(gateway, ",") {
		gatewayStr = strings.TrimSpace(gatewayStr)
		if len(gatewayStr) == 0 {
			continue
		}
		prefix, err := netip.ParsePrefix(gatewayStr)
		if err != nil {
			log.Errorln("TUN: %v", err)
			return nil, err
		}
		if prefix.Addr().Is4() {
			prefix4 = append(prefix4, prefix)
		} else {
			prefix6 = append(prefix6, prefix)
		}
	}

	var dnsHijack []string
	for _, dnsStr := range strings.Split(dns, ",") {
		dnsStr = strings.TrimSpace(dnsStr)
		if len(dnsStr) == 0 {
			continue
		}
		dnsHijack = append(dnsHijack, net.JoinHostPort(dnsStr, "53"))
	}

	listener, err := newTun(fd, tunStack, prefix4, prefix6, dnsHijack, mtu)
	if err != nil {
		log.Errorln("TUN: %v", err)
		return nil, err
	}
	return listener, nil
}

func newTun(fd int, tunStack C.TUNStack, prefix4, prefix6 []netip.Prefix, dnsHijack []string, mtu int) (io.Closer, error) {
	// Java owns the original fd; the kernel closes only its duplicate.
	dupFd, err := unix.Dup(fd)
	if err != nil {
		return nil, err
	}

	options := LC.Tun{
		Enable:              true,
		Device:              sing_tun.InterfaceName,
		Stack:               tunStack,
		DNSHijack:           dnsHijack,
		AutoRoute:           false,
		AutoDetectInterface: false,
		Inet4Address:        prefix4,
		Inet6Address:        prefix6,
		MTU:                 uint32(mtu),
		FileDescriptor:      dupFd,
	}

	tunOptions, _ := json.Marshal(options)
	log.Debugln(string(tunOptions))

	closer, err := sing_tun.New(options, tunnel.Tunnel)
	return closer, err
}
