package zip.atri.sparxie

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap

/**
 * Kotlin executes Rust commands and reports platform events back to Rust.
 * Flutter never accesses this bridge directly.
 */
object EngineBridge {

    const val REQUEST_VPN_CONSENT = 4101

    init {
        System.loadLibrary("sparxie")
    }

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var activityRef: java.lang.ref.WeakReference<Activity>? = null

    private val vpnLock = Any()

    @Volatile
    private var vpnService: SparxieVpnService? = null

    private var activeRunId = 0L
    private var pendingVpn: Pair<Long, String>? = null

    private const val ACTION_VPN = "zip.atri.sparxie.action.START_VPN"
    private const val EXTRA_TUN = "tun"

    external fun nativeEngineInit(context: Context)

    external fun nativeOnVpnFd(runId: Long, fd: Int, ipv6: Boolean)

    external fun nativeOnVpnError(runId: Long, message: String)

    external fun nativeOnVpnStopped(runId: Long)

    external fun nativeOnNetworkChanged(runId: Long, interfaceName: String)

    @JvmStatic
    fun startVpn(tunJson: String): Boolean {
        val runId = runCatching { JSONObject(tunJson).getLong("run_id") }.getOrNull()
            ?.takeIf { it > 0 } ?: return false
        val context = appContext ?: return false
        val previous = synchronized(vpnLock) {
            activeRunId = runId
            pendingVpn = null
            vpnService
        }
        previous?.stop()
        val intent = VpnService.prepare(context)
        if (intent != null) {
            synchronized(vpnLock) {
                if (activeRunId != runId) return false
                pendingVpn = runId to tunJson
            }
            postToMain {
                if (!isCurrentRun(runId)) return@postToMain
                val activity = activityRef?.get()
                if (activity != null && !activity.isFinishing) {
                    runCatching {
                        activity.startActivityForResult(intent, REQUEST_VPN_CONSENT)
                    }.onFailure {
                        synchronized(vpnLock) { pendingVpn = null }
                        nativeOnVpnError(runId, "无法打开 VPN 授权界面:${it.message}")
                    }
                } else {
                    synchronized(vpnLock) { pendingVpn = null }
                    nativeOnVpnError(runId, "无可用界面进行 VPN 授权")
                }
            }
            return true
        } else {
            return startVpnService(runId, tunJson)
        }
    }

    @JvmStatic
    fun stopVpn() {
        val service = synchronized(vpnLock) {
            activeRunId = 0
            pendingVpn = null
            vpnService.also { vpnService = null }
        }
        service?.stop()
    }

    @JvmStatic
    fun protect(fd: Int): Boolean {
        val svc = vpnService
        val result = if (svc != null) {
            svc.protect(fd)
        } else {
            android.util.Log.w("SparxieProtect", "vpnService null, fd=$fd NOT protected")
            false
        }
        if (!result) {
            android.util.Log.w("SparxieProtect", "protect failed fd=$fd")
        }
        return result
    }

    private val packageCache = ConcurrentHashMap<Int, String>()

    private val systemUidNames = mapOf(
        0 to "root",
        1000 to "android",
        1001 to "电话",
        1002 to "蓝牙",
        1003 to "图形",
        1004 to "输入",
        1005 to "音频",
        1006 to "相机",
        1009 to "存储",
        1010 to "Wi-Fi",
        1013 to "媒体",
        1015 to "SD 卡",
        1016 to "VPN",
        1017 to "密钥库",
        1019 to "DRM",
        1020 to "mDNS",
        1021 to "GPS",
        1022 to "NFC",
        1024 to "MTP",
    )

    @JvmStatic
    fun queryPackage(uid: Int): String {
        if (uid < 0) return ""
        packageCache[uid]?.let { return it }
        val context = appContext ?: return ""
        val name = runCatching {
            val packages = context.packageManager.getPackagesForUid(uid)
            packages?.firstOrNull { it.isNotBlank() }
                ?: context.packageManager.getNameForUid(uid)
                ?: systemUidNames[uid]
                ?: ""
        }.getOrDefault("")
        if (name.isNotEmpty()) {
            packageCache[uid] = name
        }
        return name
    }

    @JvmStatic
    fun listApps(): String {
        val context = appContext ?: return "[]"
        return runCatching {
            val pm = context.packageManager
            val apps = pm.getInstalledApplications(0)
                .filter { it.enabled && it.packageName.isNotBlank() }
                .map {
                    val label = runCatching { pm.getApplicationLabel(it).toString() }
                        .getOrDefault(it.packageName)
                    it.packageName to label
                }
                .sortedBy { it.second.lowercase() }
            JSONArray().apply {
                apps.forEach { (packageName, label) ->
                    put(JSONObject().put("package", packageName).put("label", label))
                }
            }.toString()
        }.getOrDefault("[]")
    }

    @JvmStatic
    fun queryUid(protocol: Int, source: String, target: String): Int {
        val context = appContext ?: return -1
        if (Build.VERSION.SDK_INT < 29) return -1
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val src4 = parseSocketAddress(source) ?: return -1
        val dst4 = parseSocketAddress(target) ?: return -1

        val variants = mutableListOf(
            src4 to dst4,
            toMappedV6(src4) to toMappedV6(dst4),
        )
        if (!src4.address.isLoopbackAddress && src4.address.address?.size == 4) {
            val loop = java.net.InetSocketAddress(
                java.net.InetAddress.getByName("127.0.0.1"),
                src4.port,
            )
            variants += loop to dst4
            variants += toMappedV6(loop) to toMappedV6(dst4)
        }

        for ((sourceAddress, targetAddress) in variants) {
            val uid = runCatching {
                cm.getConnectionOwnerUid(protocol, sourceAddress, targetAddress)
            }.getOrElse { -1 }
            if (uid >= 0) return uid
        }
        return -1
    }

    private fun toMappedV6(addr: java.net.InetSocketAddress): java.net.InetSocketAddress {
        val bytes = addr.address.address
        if (bytes.size != 4) return addr
        val mapped = byteArrayOf(
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff.toByte(), 0xff.toByte(),
            bytes[0], bytes[1], bytes[2], bytes[3],
        )
        return java.net.InetSocketAddress(
            java.net.InetAddress.getByAddress(mapped),
            addr.port,
        )
    }

    fun attach(context: Context, activity: Activity?) {
        if (appContext == null) {
            appContext = context.applicationContext
        }
        if (activity != null) {
            activityRef = java.lang.ref.WeakReference(activity)
        }
        nativeEngineInit(context)
    }

    private fun postToMain(block: () -> Unit) {
        val context = appContext ?: return
        val handler = android.os.Handler(context.mainLooper)
        handler.post(block)
    }

    fun onVpnConsentResult(granted: Boolean) {
        val pending = synchronized(vpnLock) {
            pendingVpn.also { pendingVpn = null }
        } ?: return
        val (runId, json) = pending
        if (!isCurrentRun(runId)) return
        if (granted) {
            if (!startVpnService(runId, json)) {
                nativeOnVpnError(runId, "VPN 服务启动失败")
            }
        } else {
            nativeOnVpnError(runId, "VPN 授权被拒绝")
        }
    }

    private fun startVpnService(runId: Long, tunJson: String): Boolean {
        if (!isCurrentRun(runId)) return false
        val context = appContext ?: return false
        val intent = Intent(context, SparxieVpnService::class.java)
            .setAction(ACTION_VPN)
            .putExtra(EXTRA_TUN, tunJson)
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }.isSuccess
    }

    internal fun isCurrentRun(runId: Long): Boolean =
        synchronized(vpnLock) { activeRunId == runId }

    internal fun registerVpnService(runId: Long, service: SparxieVpnService): Boolean =
        synchronized(vpnLock) {
            if (activeRunId != runId) return@synchronized false
            vpnService = service
            true
        }

    internal fun unregisterVpnService(runId: Long, service: SparxieVpnService) {
        synchronized(vpnLock) {
            if (activeRunId == runId && vpnService === service) {
                vpnService = null
            }
        }
    }

    internal fun parseSocketAddress(text: String): InetSocketAddress? {
        return runCatching {
            val value = text.trim()
            if (value.startsWith("[")) {
                val close = value.indexOf(']')
                val host = value.substring(1, close)
                val port = value.substring(close + 2).toInt()
                InetSocketAddress(host, port)
            } else {
                val lastColon = value.lastIndexOf(':')
                if (lastColon < 0) return@runCatching null
                val host = value.substring(0, lastColon)
                val port = value.substring(lastColon + 1).toInt()
                InetSocketAddress(host, port)
            }
        }.getOrNull()
    }
}
