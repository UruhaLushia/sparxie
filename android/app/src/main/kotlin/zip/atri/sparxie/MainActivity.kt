package zip.atri.sparxie

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.hardware.input.InputManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.provider.Settings
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity(), GamepadsCompatibleActivity {
    private val channel = "zip.atri.sparxie/process_icons"
    private val systemColorsChannel = "zip.atri.sparxie/system_colors"
    private val updateInstallerChannel = "zip.atri.sparxie/update_installer"
    private val iconSize = 256
    private val installPermissionRequestCode = 2101
    private val updateDirectory = "sparxie_updates"
    private var installPermissionResult: MethodChannel.Result? = null
    private var cleanupUpdatePackageOnResume = false
    private var gamepadKeyListener: ((KeyEvent) -> Boolean)? = null
    private var gamepadMotionListener: ((MotionEvent) -> Boolean)? = null

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (gamepadKeyListener?.invoke(event) == true) return true
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (gamepadMotionListener?.invoke(event) == true) return true
        return super.dispatchGenericMotionEvent(event)
    }

    override fun registerInputDeviceListener(
        listener: InputManager.InputDeviceListener,
        handler: Handler?,
    ) {
        val inputManager = getSystemService(INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(listener, handler)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        gamepadKeyListener = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        gamepadMotionListener = handler
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cleanupUpdatePackage()
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Concurrent background pool: icon decode + PNG compression are
        // CPU-heavy and must stay off the UI thread, and the PackageManager
        // lookups are independent + thread-safe, so parallelism is a win.
        val taskQueue = messenger.makeBackgroundTaskQueue(
            BinaryMessenger.TaskQueueOptions().setIsSerial(false)
        )
        MethodChannel(messenger, channel, StandardMethodCodec.INSTANCE, taskQueue)
            .setMethodCallHandler { call, result ->
                val pkg = call.argument<String>("package")
                when (call.method) {
                    "getIcon" ->
                        result.success(if (pkg.isNullOrEmpty()) null else iconPng(pkg))
                    "getName" ->
                        result.success(if (pkg.isNullOrEmpty()) null else appLabel(pkg))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, systemColorsChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAccentColor" -> result.success(systemAccentColor())
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, updateInstallerChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestInstallPermission" -> requestInstallPermission(result)
                "installUpdatePackage" ->
                    installUpdatePackage(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (!cleanupUpdatePackageOnResume) return
        cleanupUpdatePackageOnResume = false
        cleanupUpdatePackage()
    }

    private fun cleanupUpdatePackage() {
        runCatching { File(cacheDir, updateDirectory).deleteRecursively() }
        // Remove packages left by ota_update versions used before the native installer.
        runCatching { File(filesDir, "ota_update").deleteRecursively() }
    }

    private fun installUpdatePackage(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("invalid_path", "安装包路径为空", null)
            return
        }
        try {
            val root = File(cacheDir, updateDirectory).canonicalFile
            val apk = File(path).canonicalFile
            val rootPrefix = root.path + File.separator
            if (!apk.isFile ||
                !apk.path.startsWith(rootPrefix) ||
                !apk.name.endsWith(".apk", ignoreCase = true)
            ) {
                result.error("invalid_path", "安装包路径无效", null)
                return
            }

            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.update_provider",
                apk
            )
            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            cleanupUpdatePackageOnResume = true
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            cleanupUpdatePackageOnResume = false
            result.error("installer_unavailable", error.message, null)
        }
    }

    private fun requestInstallPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
        ) {
            result.success(true)
            return
        }
        if (installPermissionResult != null) {
            result.error("already_pending", "Install permission request is already open", null)
            return
        }
        installPermissionResult = result
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName")
        )
        try {
            startActivityForResult(intent, installPermissionRequestCode)
        } catch (error: Exception) {
            installPermissionResult = null
            result.error("settings_unavailable", error.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != installPermissionRequestCode) return
        installPermissionResult?.success(
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                packageManager.canRequestPackageInstalls()
        )
        installPermissionResult = null
    }

    private fun systemAccentColor(): Long? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return resources.getColor(android.R.color.system_accent1_500, theme)
            .toLong() and 0xffffffffL
    }

    private fun iconPng(pkg: String): ByteArray? {
        return try {
            drawableToPng(packageManager.getApplicationIcon(pkg))
        } catch (_: PackageManager.NameNotFoundException) {
            null
        } catch (_: Throwable) {
            null
        }
    }

    private fun appLabel(pkg: String): String? {
        return try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info).toString().ifEmpty { null }
        } catch (_: PackageManager.NameNotFoundException) {
            null
        } catch (_: Throwable) {
            null
        }
    }

    private fun drawableToPng(drawable: Drawable): ByteArray? {
        var ownsBitmap = false
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            val source = drawable.bitmap
            Bitmap.createScaledBitmap(source, iconSize, iconSize, true).also {
                ownsBitmap = it !== source
            }
        } else {
            ownsBitmap = true
            val bmp = Bitmap.createBitmap(iconSize, iconSize, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        }
        return try {
            ByteArrayOutputStream().use { stream ->
                if (bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                    stream.toByteArray()
                } else {
                    null
                }
            }
        } finally {
            if (ownsBitmap) bitmap.recycle()
        }
    }
}
