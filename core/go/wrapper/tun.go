package main

import (
	"io"
	"sync"

	"sparxie-core/wrapper/tun"
)

var (
	rTunLock sync.Mutex
	rTun     *remoteTun
)

type remoteTun struct {
	closer io.Closer
}

func (t *remoteTun) close() {
	if t.closer != nil {
		_ = t.closer.Close()
	}
}

func tunStart(fd int, stack, gateway, dns string, mtu int) error {
	rTunLock.Lock()
	defer rTunLock.Unlock()

	if rTun != nil {
		rTun.close()
		rTun = nil
	}

	closer, err := tun.Start(fd, stack, gateway, dns, mtu)
	if err != nil {
		return err
	}

	rTun = &remoteTun{closer: closer}
	return nil
}

func tunStop() {
	rTunLock.Lock()
	defer rTunLock.Unlock()

	if rTun != nil {
		rTun.close()
		rTun = nil
	}
}
