package jp.nogut.ytdlp_flutter

import android.content.ContentValues
import android.content.Context
import android.provider.MediaStore
import java.io.File

object MediaStoreWriter {
    fun publish(context: Context, file: File, token: CancelToken): String {
        val resolver = context.contentResolver
        val mime = when (file.extension.lowercase()) {
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            else -> error("保存形式を確認できません。")
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/Android movie Download")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("保存先を作成できません。")
        try {
            val destination = resolver.openOutputStream(uri) ?: error("保存先を開けません。")
            destination.use { output -> file.inputStream().use { input ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    token.check()
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                }
            } }
            token.check()
            val completed = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            require(resolver.update(uri, completed, null, null) == 1) { "保存を確定できません。" }
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }
}
