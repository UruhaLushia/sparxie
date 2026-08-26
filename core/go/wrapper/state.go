package main

/*
#include <stdlib.h>
*/
import "C"

import corestate "sparxie-core/wrapper/state"

func cstr(s string) *C.char {
	if s == "" {
		return nil
	}
	return C.CString(s)
}

func queryProcess(protocol int, source, target string) string {
	uid := querySocketUid(protocol, source, target)
	if uid < 0 {
		return ""
	}
	return queryPackageName(uid)
}

//export queryState
func queryState(method *C.char) *C.char {
	m := ""
	if method != nil {
		m = C.GoString(method)
	}
	return cstr(corestate.Query(m, queryProcess))
}

//export changeProxy
func changeProxy(group, name *C.char) C.int {
	if group == nil || name == nil {
		return 1
	}
	if corestate.ChangeProxy(C.GoString(group), C.GoString(name)) != nil {
		return 1
	}
	return 0
}

//export closeConnection
func closeConnection(id *C.char) C.int {
	if id == nil {
		return 1
	}
	corestate.CloseConnection(C.GoString(id))
	return 0
}

//export closeAllConnections
func closeAllConnections() C.int {
	corestate.CloseAllConnections()
	return 0
}

//export patchConfig
func patchConfig(params *C.char) C.int {
	if params == nil || corestate.PatchConfig(C.GoString(params)) != nil {
		return 1
	}
	return 0
}

//export reloadConfig
func reloadConfig(path *C.char) *C.char {
	if path == nil {
		return cstr("missing config path")
	}
	lifeMu.Lock()
	defer lifeMu.Unlock()
	if err := corestate.ReloadConfig(C.GoString(path)); err != nil {
		return cstr(err.Error())
	}
	return nil
}

//export testDelay
func testDelay(name, url *C.char, timeoutMs C.int, expected *C.char) *C.char {
	if name == nil || url == nil {
		return cstr(`{"error":"missing args"}`)
	}
	expectedStatus := ""
	if expected != nil {
		expectedStatus = C.GoString(expected)
	}
	return cstr(corestate.TestDelay(
		C.GoString(name),
		C.GoString(url),
		int(timeoutMs),
		expectedStatus,
	))
}

//export validateConfig
func validateConfig(text *C.char) *C.char {
	if text == nil {
		return cstr("缺少配置内容")
	}
	if err := corestate.ValidateConfig(C.GoString(text)); err != nil {
		return cstr(err.Error())
	}
	return nil
}

//export updateProvider
func updateProvider(name *C.char) C.int {
	if name == nil || corestate.UpdateProvider(C.GoString(name)) != nil {
		return 1
	}
	return 0
}

//export updateRuleProvider
func updateRuleProvider(name *C.char) C.int {
	if name == nil || corestate.UpdateRuleProvider(C.GoString(name)) != nil {
		return 1
	}
	return 0
}

func startTelemetry() {
	corestate.StartTelemetry(emitEvent)
}

func stopTelemetry() {
	corestate.StopTelemetry()
}

//export unfixProxy
func unfixProxy(name *C.char) C.int {
	if name == nil || corestate.UnfixProxy(C.GoString(name)) != nil {
		return 1
	}
	return 0
}

//export flushFakeIp
func flushFakeIp() C.int {
	if corestate.FlushFakeIP() != nil {
		return 1
	}
	return 0
}

//export flushDns
func flushDns() C.int {
	corestate.FlushDNS()
	return 0
}

//export setDefaultInterface
func setDefaultInterface(name *C.char) C.int {
	corestate.SetDefaultInterface(C.GoString(name))
	return 0
}

//export setOverrideConfig
func setOverrideConfig(mixed, port, socks C.int, allowLan C.int, controller, secret, logLevel *C.char) C.int {
	lifeMu.Lock()
	defer lifeMu.Unlock()
	corestate.SetOverrideConfig(corestate.OverrideConfig{
		MixedPort:  int32(mixed),
		Port:       int32(port),
		SocksPort:  int32(socks),
		AllowLAN:   allowLan != 0,
		Controller: C.GoString(controller),
		Secret:     C.GoString(secret),
		LogLevel:   C.GoString(logLevel),
	})
	return 0
}

//export computeRouteRanges
func computeRouteRanges(excludeJSON *C.char) *C.char {
	if excludeJSON == nil {
		return nil
	}
	result, err := corestate.ComputeRouteRanges(C.GoString(excludeJSON))
	if err != nil {
		return nil
	}
	return cstr(result)
}
