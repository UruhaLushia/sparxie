package main

import (
	"errors"
	"fmt"
	"net"
	"sync"
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/log"
	"golang.org/x/sys/unix"

	"sparxie-core/wrapper/platform"
	corestate "sparxie-core/wrapper/state"
)

var (
	lifeMu  sync.Mutex
	started bool
)

func lifecycleInit(home string) {
	constant.SetHomeDir(home)
	route.SetEmbedMode(true)

	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		if platform.ShouldBlockConnection() {
			return errors.New("blocked by fd exhaustion guard")
		}
		var protectErr error
		controlErr := conn.Control(func(fd uintptr) {
			if name := dialer.DefaultInterface.Load(); name != "" {
				_ = unix.BindToDevice(int(fd), name)
			}
			if !markSocket(int(fd)) {
				protectErr = errors.New("failed to protect socket from VPN")
			}
		})
		if controlErr != nil {
			return controlErr
		}
		return protectErr
	}
	process.DefaultPackageNameResolver = func(metadata *constant.Metadata) (string, error) {
		src, dst := metadata.RawSrcAddr, metadata.RawDstAddr
		if src == nil && metadata.SrcIP.IsValid() && metadata.SrcPort > 0 {
			// SOCKS inbound only fills SrcIP/SrcPort, not RawSrcAddr.
			src = &net.TCPAddr{IP: metadata.SrcIP.AsSlice(), Port: int(metadata.SrcPort)}
		}
		if src == nil {
			return "", process.ErrInvalidNetwork
		}
		if dst == nil && metadata.InIP.IsValid() && metadata.InPort > 0 {
			// SOCKS5 inbound lacks RawDstAddr; InIP/InPort is the real peer.
			dst = &net.TCPAddr{IP: metadata.InIP.AsSlice(), Port: int(metadata.InPort)}
		}
		if dst == nil {
			return "", process.ErrInvalidNetwork
		}
		uid := querySocketUid(protocolOf(src), src.String(), dst.String())
		if uid < 0 {
			return "", process.ErrInvalidNetwork
		}
		if pkg := queryPackageName(uid); pkg != "" {
			return pkg, nil
		}
		return fmt.Sprintf("%d", uid), nil
	}
}

func protocolOf(addr interface{ Network() string }) int {
	switch addr.Network() {
	case "udp", "udp4", "udp6":
		return syscall.IPPROTO_UDP
	default:
		return syscall.IPPROTO_TCP
	}
}

func lifecycleStart(configPath string) error {
	lifeMu.Lock()
	defer lifeMu.Unlock()

	if started {
		return errors.New("core already started")
	}

	if err := corestate.ApplyInitialConfig(configPath); err != nil {
		return err
	}
	started = true
	startTelemetry()

	log.Infoln("core started")
	return nil
}

func lifecycleStop() {
	lifeMu.Lock()
	defer lifeMu.Unlock()

	tunStop()

	if started {
		stopTelemetry()
		executor.Shutdown()
		route.ReCreateServer(&route.Config{})
		started = false
	}
}
