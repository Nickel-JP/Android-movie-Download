package jp.nogut.ytdlp_flutter

import org.json.JSONObject
import java.net.URI

object DownloadPolicy {
    fun validate(options: Map<String, Any?>): Map<String, Any?> {
        val raw = options["url"] as? String ?: error("動画URLを指定してください。")
        val uri = URI(raw)
        require(!uri.host.isNullOrBlank() && uri.scheme?.lowercase() in listOf("http", "https") &&
            uri.userInfo == null && (uri.port == -1 || uri.port in 1..65535)) {
            "HTTPまたはHTTPSのメディアURLを入力してください。"
        }
        require(options["mode"] in listOf("video", "mp3", "wav")) { "保存形式が不正です。" }
        require((options["height"] as? Number)?.toInt() in listOf(480, 720, 1080, 1440, 2160)) { "画質設定が不正です。" }
        require((options["fps"] as? Number)?.toInt() in listOf(30, 60)) { "fps設定が不正です。" }
        require((options["bitrate"] as? Number)?.toInt() in listOf(128, 192, 256, 320)) { "音質設定が不正です。" }
        require(options["container"] in listOf("mp4", "mkv")) { "動画形式が不正です。" }
        return options
    }

    fun chooseFormat(info: JSONObject, height: Int, fps: Int, audioOnly: Boolean): String {
        val formats = formats(info).filter { !it.optBoolean("has_drm") }
        require(formats.isNotEmpty()) { "取得できるメディア形式が見つかりません。" }
        val audioExtensions = setOf("mp3", "m4a", "aac", "wav", "flac", "opus", "ogg", "oga", "aiff", "alac")
        fun hasVideo(f: JSONObject): Boolean {
            val codec = f.optString("vcodec")
            return if (codec.isNotEmpty()) codec != "none" else f.optString("ext") !in audioExtensions
        }
        fun hasAudio(f: JSONObject): Boolean {
            val codec = f.optString("acodec")
            return codec.isEmpty() || codec != "none"
        }
        fun id(f: JSONObject) = f.optString("format_id").ifEmpty { "best" }
        fun resolution(f: JSONObject): Int {
            val w = f.optInt("width", 0)
            val h = f.optInt("height", 0)
            return if (w > 0 && h > 0) minOf(w, h) else h
        }
        val audio = formats.filter { hasAudio(it) && !hasVideo(it) }
            .maxWithOrNull(compareBy<JSONObject> { it.optDouble("abr", 0.0) }
                .thenBy { it.optDouble("tbr", 0.0) }.thenBy { it.optDouble("asr", 0.0) })
        if (audioOnly) return audio?.let { id(it) } ?: formats.filter { hasAudio(it) }
            .maxByOrNull { it.optDouble("abr", 0.0) }?.let { id(it) } ?: error("音声が見つかりません。")
        val video = formats.filter { hasVideo(it) && resolution(it) in 0..height &&
            (it.isNull("fps") || it.optDouble("fps", 0.0) <= fps) }
            .maxWithOrNull(compareBy<JSONObject> { resolution(it) }.thenBy { it.optDouble("fps", 0.0) }
                .thenBy { it.optDouble("tbr", 0.0) }) ?: error("指定した上限内の動画がありません。画質設定を変更してください。")
        val videoId = id(video)
        return if (hasAudio(video)) videoId else "$videoId+${audio?.let { id(it) } ?: error("音声が見つかりません。") }"
    }

    fun formats(info: JSONObject): List<JSONObject> {
        val array = info.optJSONArray("formats")
        return if (array != null && array.length() > 0) (0 until array.length()).map { array.getJSONObject(it) }
        else if (info.optString("url").isNotBlank()) listOf(info) else emptyList()
    }

    fun needsVideoProbe(info: JSONObject, selected: String): Boolean {
        val id = selected.substringBefore('+')
        val format = formats(info).firstOrNull { it.optString("format_id").ifEmpty { "best" } == id }
            ?: return true
        return format.optInt("width") <= 0 || format.optInt("height") <= 0 || format.optDouble("fps", 0.0) <= 0
    }
}
