package dev.benterm.benterm

import android.content.Intent
import android.os.Build
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "benterm/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    "canRequestInstalls" -> result.success(canRequestInstalls())
                    else -> result.notImplemented()
                }
            }
    }

    /// Hands the downloaded APK to the system installer. Android always asks
    /// the user to confirm; an app can never replace itself silently.
    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("no_path", "No APK path was given", null)
            return
        }

        val apk = File(path)
        if (!apk.exists()) {
            result.error("missing", "No APK at $path", null)
            return
        }

        val uri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apk,
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("launch_failed", error.message, null)
        }
    }

    /// Whether the user has allowed this app to install packages. Without it
    /// the installer screen refuses before showing anything.
    ///
    /// The permission only exists from API 26; below that, holding
    /// REQUEST_INSTALL_PACKAGES is enough.
    private fun canRequestInstalls(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
}
