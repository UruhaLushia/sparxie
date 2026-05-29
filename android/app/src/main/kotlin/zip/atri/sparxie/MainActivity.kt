package zip.atri.sparxie

import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val channel = "zip.atri.sparxie/process_icons"
    private val iconSize = 128

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, iconSize, iconSize, true)
        } else {
            val bmp = Bitmap.createBitmap(iconSize, iconSize, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        }
        val stream = ByteArrayOutputStream()
        return if (bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
            stream.toByteArray()
        } else {
            null
        }
    }
}
