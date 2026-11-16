package app.bibliolife.reader

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.StatFs
import android.content.res.Configuration
import android.content.Intent
import android.view.Window
import android.net.Uri
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterFragmentActivity() {
    private data class PendingBookSave(
        val result: MethodChannel.Result,
        val sourcePath: String,
        val expectedSize: Long,
    )

    private var pendingBookSave: PendingBookSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bibliolife/cache-storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "availableBytes") {
                    result.success(StatFs(cacheDir.path).availableBytes)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bibliolife/book-file-save")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingBookSave != null) {
                    result.success(mapOf("status" to "busy"))
                    return@setMethodCallHandler
                }
                val sourcePath = call.argument<String>("sourcePath")
                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType")
                val expectedSize = call.argument<Number>("sizeBytes")?.toLong()
                val source = sourcePath?.let(::File)
                if (source == null || fileName.isNullOrBlank() || mimeType.isNullOrBlank() ||
                    expectedSize == null || expectedSize <= 0L ||
                    !source.isFile || source.length() != expectedSize
                ) {
                    result.success(mapOf("status" to "failed"))
                    return@setMethodCallHandler
                }
                pendingBookSave = PendingBookSave(result, source.path, expectedSize)
                try {
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mimeType
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, BOOK_FILE_SAVE_REQUEST)
                } catch (_: Exception) {
                    pendingBookSave = null
                    result.success(mapOf("status" to "failed"))
                }
            }
    }

    @Deprecated("The SAF create-document result is delivered here.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != BOOK_FILE_SAVE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingBookSave ?: return
        val destination: Uri? = data?.data
        if (resultCode != RESULT_OK || destination == null) {
            pendingBookSave = null
            pending.result.success(mapOf("status" to "cancelled"))
            return
        }
        thread(name = "bibliolife-book-file-save") {
            val copied = BookFileSaver.copy(
                applicationContext,
                pending.sourcePath,
                pending.expectedSize,
                destination,
            )
            runOnUiThread {
                if (pendingBookSave === pending) {
                    pendingBookSave = null
                    pending.result.success(
                        mapOf("status" to if (copied.success) "saved" else "failed"),
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        val pending = pendingBookSave
        pendingBookSave = null
        pending?.result?.success(mapOf("status" to "failed"))
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        val isDark = resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        WindowInsetsControllerCompat(window, window.decorView)
            .isAppearanceLightNavigationBars = !isDark
    }

    private companion object {
        const val BOOK_FILE_SAVE_REQUEST = 4782
    }

}
