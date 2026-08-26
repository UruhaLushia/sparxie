package main

/*
#include <stdint.h>
#include <stdlib.h>

// Trampolines for callbacks registered by the Rust host via setCallbacks.
// Kept as a cgo preamble — no separate C sources; the only C surface of this
// library is the cgo ABI itself.

static int invoke_mark_socket(void *fn, int fd) {
    if (!fn) {
        return 0;
    }
    return ((int (*)(void *, int))fn)(0, fd);
}

static int invoke_query_socket_uid(void *fn, int protocol, const char *source, const char *target) {
    if (!fn) {
        return -1;
    }
    return ((int (*)(void *, int, const char *, const char *))fn)(0, protocol, source, target);
}

static void invoke_event(void *fn, const char *json) {
    if (fn) {
        ((void (*)(void *, const char *))fn)(0, json);
    }
}

static void invoke_resolve_package(void *fn, int uid, char *buf, int buf_len) {
    if (fn) {
        ((void (*)(void *, int, char *, int))fn)(0, uid, buf, buf_len);
    }
}
*/
import "C"

import (
	"encoding/json"
	"sync"
	"unsafe"
)

func main() {}

var (
	callbackMu sync.Mutex

	markSocketCb     unsafe.Pointer
	queryUidCb       unsafe.Pointer
	eventCb          unsafe.Pointer
	resolvePackageCb unsafe.Pointer
)

//export setCallbacks
func setCallbacks(mark, uid, event, resolvePackage unsafe.Pointer) {
	callbackMu.Lock()
	defer callbackMu.Unlock()
	markSocketCb = mark
	queryUidCb = uid
	eventCb = event
	resolvePackageCb = resolvePackage
}

func markSocket(fd int) bool {
	callbackMu.Lock()
	fn := markSocketCb
	callbackMu.Unlock()
	if fn != nil {
		return C.invoke_mark_socket(fn, C.int(fd)) != 0
	}
	return false
}

func querySocketUid(protocol int, source, target string) int {
	callbackMu.Lock()
	fn := queryUidCb
	callbackMu.Unlock()
	if fn == nil {
		return -1
	}
	cs := C.CString(source)
	ct := C.CString(target)
	defer C.free(unsafe.Pointer(cs))
	defer C.free(unsafe.Pointer(ct))
	return int(C.invoke_query_socket_uid(fn, C.int(protocol), cs, ct))
}

func queryPackageName(uid int) string {
	callbackMu.Lock()
	fn := resolvePackageCb
	callbackMu.Unlock()
	if fn == nil {
		return ""
	}
	buf := make([]byte, 256)
	C.invoke_resolve_package(fn, C.int(uid), (*C.char)(unsafe.Pointer(&buf[0])), C.int(len(buf)))
	end := 0
	for end < len(buf) && buf[end] != 0 {
		end++
	}
	return string(buf[:end])
}

func emitEvent(typ string, payload any) {
	data, err := json.Marshal(map[string]any{"type": typ, "data": payload})
	if err != nil {
		return
	}
	callbackMu.Lock()
	fn := eventCb
	callbackMu.Unlock()
	if fn == nil {
		return
	}
	ce := C.CString(string(data))
	defer C.free(unsafe.Pointer(ce))
	C.invoke_event(fn, ce)
}

//export coreInit
func coreInit(home *C.char) {
	lifecycleInit(C.GoString(home))
}

//export coreStart
func coreStart(configPath *C.char) *C.char {
	if err := lifecycleStart(C.GoString(configPath)); err != nil {
		return cstr(err.Error())
	}
	return nil
}

//export coreStop
func coreStop() {
	lifecycleStop()
}

//export startTun
func startTun(fd C.int, stack, gateway, dns *C.char, mtu C.int) *C.char {
	if err := tunStart(int(fd), C.GoString(stack), C.GoString(gateway), C.GoString(dns), int(mtu)); err != nil {
		return cstr(err.Error())
	}
	return nil
}

//export stopTun
func stopTun() {
	tunStop()
}
