package zip.atri.sparxie

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import org.json.JSONObject

/**
 * Platform TUN provider. It hands the fd to Rust and owns its original copy.
 */
class SparxieVpnService : VpnService() {

    private companion object {
        const val CHANNEL_ID = "sparxie_vpn"
        const val NOTIFICATION_ID = 1
        const val DNS6 = "fdfe:dcba:9876::2"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val raw = runCatching {
            JSONObject(intent?.getStringExtra("tun") ?: return START_NOT_STICKY)
        }.getOrElse {
            stopSelf()
            return START_NOT_STICKY
        }
        runId = raw.getLong("run_id")
        if (runId <= 0 || !EngineBridge.registerVpnService(runId, this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            startForeground(NOTIFICATION_ID, buildNotification())
        } catch (e: Exception) {
            EngineBridge.nativeOnVpnError(runId, "前台服务启动失败:${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }

        val tunnel = try {
            establishTun(raw)
        } catch (e: Exception) {
            EngineBridge.nativeOnVpnError(runId, "VPN 建立失败:${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        if (tunnel == null) {
            EngineBridge.nativeOnVpnError(runId, "VPN 接口建立失败")
            stopSelf()
            return START_NOT_STICKY
        }

        EngineBridge.nativeOnVpnFd(runId, tunnel.fd, tunnel.ipv6)
        startNetworkMonitor()
        return START_NOT_STICKY
    }

    private fun startNetworkMonitor() {
        try {
            val cm = getSystemService(ConnectivityManager::class.java)
            val request =
                NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
                    .build()
            if (Build.VERSION.SDK_INT >= 31) {
                cm.registerBestMatchingNetworkCallback(
                    request,
                    networkCallback,
                    android.os.Handler(android.os.Looper.getMainLooper()),
                )
            } else {
                cm.requestNetwork(request, networkCallback)
            }
        } catch (_: Exception) {}
    }

    private val networkCallback =
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: android.net.Network) = report(network)

            override fun onCapabilitiesChanged(
                network: android.net.Network,
                networkCapabilities: NetworkCapabilities,
            ) = report(network)

            override fun onLost(network: android.net.Network) {
                EngineBridge.nativeOnNetworkChanged(runId, "")
            }

            private fun report(network: android.net.Network) {
                val name =
                    runCatching {
                        getSystemService(ConnectivityManager::class.java)
                            .getLinkProperties(network)
                            ?.interfaceName
                    }.getOrNull()
                EngineBridge.nativeOnNetworkChanged(runId, name ?: "")
            }
        }

    override fun onRevoke() {
        closeTun()
        EngineBridge.nativeOnVpnError(runId, "VPN 已被系统撤销")
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        closeTun()
        EngineBridge.unregisterVpnService(runId, this)
        runCatching {
            getSystemService(ConnectivityManager::class.java)
                .unregisterNetworkCallback(networkCallback)
        }
        if (runId > 0) EngineBridge.nativeOnVpnStopped(runId)
        super.onDestroy()
    }

    fun stop() {
        closeTun()
        stopSelf()
    }

    private var runId = 0L
    private var pfd: ParcelFileDescriptor? = null

    private fun closeTun() {
        val current = pfd ?: return
        pfd = null
        runCatching { current.close() }
    }

    private data class TunResult(val fd: Int, val ipv6: Boolean)

    private fun establishTun(raw: JSONObject): TunResult? {
        val tun = raw.getJSONObject("tun")
        val ipv6 = tun.getBoolean("ipv6")
        val mtu = tun.getInt("mtu")
        val mixedPort = raw.getInt("mixed_port")
        val dnsServers = tun.getString("dns")
            .split(',')
            .map(String::trim)
            .filter(String::isNotEmpty)
        val excludedRoutes = tun.getJSONArray("excluded_routes")
            .let { routes -> (0 until routes.length()).map(routes::getString) }
        val routeRanges = tun.getJSONArray("route_ranges")
            .let { routes -> (0 until routes.length()).map(routes::getString) }

        val builder = Builder()
            .setSession("Sparxie")
            .setMtu(mtu)
            .setBlocking(false)
            .addAddress("172.19.0.1", 30)
        var ipv6Available = ipv6
        if (ipv6) {
            try {
                builder.addAddress("fdfe:dcba:9876::1", 126)
            } catch (e: Exception) {
                ipv6Available = false
                android.util.Log.w("SparxieVpn", "v6 addAddress failed: ${e.message}")
            }
        }
        if (excludedRoutes.isNotEmpty() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Native route exclusion is available on Android 13+.
            builder.addRoute("0.0.0.0", 0)
            excludedRoutes.forEach { cidr ->
                val (ip, prefix) = parseCidr(cidr)
                if (!ip.contains(':') || ipv6Available) {
                    builder.excludeRoute(
                        android.net.IpPrefix(java.net.InetAddress.getByName(ip), prefix),
                    )
                }
            }
            if (ipv6Available) {
                try {
                    builder.addRoute("::", 0)
                } catch (e: Exception) {
                    android.util.Log.w("SparxieVpn", "v6 addRoute failed: ${e.message}")
                }
            }
        } else if (excludedRoutes.isNotEmpty()) {
            // Rust computes the minimal route cover for older Android versions.
            var v6Added = false
            for (range in routeRanges) {
                val (ip, prefix) = parseCidr(range)
                if (ip.contains(':') && !ipv6Available) continue
                try {
                    builder.addRoute(ip, prefix)
                    if (ip.contains(':')) v6Added = true
                } catch (e: Exception) {
                    android.util.Log.w("SparxieVpn", "bypass route failed $range: ${e.message}")
                }
            }
            dnsServers.forEach { address ->
                val prefix = if (address.contains(':')) 128 else 32
                if (!address.contains(':') || ipv6Available && v6Added) {
                    runCatching { builder.addRoute(address, prefix) }
                }
            }
        } else {
            builder.addRoute("0.0.0.0", 0)
            if (ipv6Available) {
                try {
                    builder.addRoute("::", 0)
                } catch (e: Exception) {
                    android.util.Log.w("SparxieVpn", "v6 addRoute failed: ${e.message}")
                }
            }
        }
        dnsServers.forEach { address ->
            if (!address.contains(':') || ipv6Available) {
                builder.addDnsServer(address)
            }
        }
        if (ipv6Available && dnsServers.none { it.contains(':') }) {
            runCatching { builder.addDnsServer(DNS6) }
        }
        if (tun.getBoolean("allow_bypass")) {
            builder.allowBypass()
        }
        applyAccessControl(builder, tun)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
            if (mixedPort > 0 && tun.getBoolean("system_proxy")) {
                builder.setHttpProxy(ProxyInfo.buildDirectProxy("127.0.0.1", mixedPort, listOf()))
            }
        }
        closeTun()
        val p = builder.establish() ?: return null
        pfd = p
        return TunResult(p.fd, ipv6Available)
    }

    private fun parseCidr(value: String): Pair<String, Int> {
        val (ip, prefix) = value.split('/', limit = 2)
        return ip to prefix.toInt()
    }

    private fun applyAccessControl(builder: Builder, tun: JSONObject) {
        val mode = tun.getString("access_mode")
        val packages = tun.getJSONArray("access_packages")
            .let { apps -> (0 until apps.length()).map(apps::getString) }
        when (mode) {
            "accept_selected" ->
                (packages + packageName).distinct().forEach {
                    runCatching { builder.addAllowedApplication(it) }
                }
            "reject_selected" ->
                packages.forEach {
                    runCatching { builder.addDisallowedApplication(it) }
                }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "代理服务",
            NotificationManager.IMPORTANCE_LOW,
        )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Sparxie 代理")
            .setContentText("本地代理已运行")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }
}
