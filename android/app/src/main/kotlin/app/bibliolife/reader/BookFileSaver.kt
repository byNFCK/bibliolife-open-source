package app.bibliolife.reader

import android.content.Context
import android.net.Uri
import java.io.File

internal object BookFileSaver {
    data class CopyResult(val success: Boolean, val error: String? = null)

    fun copy(context: Context, sourcePath: String, expectedSize: Long, destination: Uri): CopyResult {
        var completed = false
        return try {
            val source = File(sourcePath)
            if (!source.isFile || source.length() <= 0L || source.length() != expectedSize) {
                return CopyResult(false, "Source file changed or is unavailable")
            }
            val resolver = context.contentResolver
            source.inputStream().buffered().use { input ->
                val output = resolver.openOutputStream(destination, "w")
                    ?: return CopyResult(false, "Could not open destination")
                output.buffered().use { target ->
                    if (input.copyTo(target, 64 * 1024) != expectedSize) {
                        return CopyResult(false, "Source file changed during copy")
                    }
                }
            }
            completed = true
            CopyResult(true)
        } catch (error: Exception) {
            CopyResult(false, error.message ?: "Copy failed")
        } finally {
            if (!completed) removePartial(context, destination)
        }
    }

    fun removePartial(context: Context, destination: Uri) {
        try {
            context.contentResolver.delete(destination, null, null)
        } catch (_: Exception) {
            // Some document providers do not support deletion; never touch source files.
        }
    }
}
