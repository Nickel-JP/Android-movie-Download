package jp.nogut.ytdlp_flutter

import org.json.JSONObject
import java.net.URI

object DownloadPolicy {
    fun validate(options: Map<String, Any?>): Map<String, Any?> {
        val raw = options["url"] as? String ?: error("動画URLを指定してください。")
        val uri = URI(raw)
        val host = uri.host?.lowercase() ?: error("動画URLを確認してください。")
        val roots = listOf("youtube.com", "youtu.be", "nicovideo.jp", "nico.ms")
        require(uri.scheme == "https" && uri.userInfo == null && uri.port in listOf(-1, 443)) { "HTTPSの動画URLを入力してください。" }
        require(roots.any { host == it || host.endsWith(".$it") }) { "対応サイトはYouTubeとニコニコ動画です。" }
        require(options["mode"] in listOf("video", "mp3", "wav")) { "保存形式が不正です。" }
        require((options["height"] as? Number)?.toInt() in listOf(480, 720, 1080, 1440, 2160)) { "画質設定が不正です。" }
        require((options["fps"] as? Number)?.toInt() in listOf(30, 60)) { "fps設定が不正です。" }
        require((options["bitrate"] as? Number)?.toInt() in listOf(128, 192, 256, 320)) { "音質設定が不正です。" }
        require(options["container"] in listOf("mp4", "mkv")) { "動画形式が不正です。" }
        return options
    }

    fun chooseFormat(info: JSONObject, height: Int, fps: Int, audioOnly: Boolean): String {
        val array = info.optJSONArray("formats") ?: error("配信形式が見つかりません。")
        val formats = (0 until array.length()).map { array.getJSONObject(it) }
            .filter { !it.optBoolean("has_drm") && it.optString("format_id").isNotEmpty() }
        fun hasVideo(f: JSONObject) = f.optString("vcodec", "none") != "none"
        fun hasAudio(f: JSONObject) = f.optString("acodec", "none") != "none"
        fun resolution(f: JSONObject): Int {
            val w = f.optInt("width", 0)
            val h = f.optInt("height", 0)
            return if (w > 0 && h > 0) minOf(w, h) else h
        }
        val audio = formats.filter { hasAudio(it) && !hasVideo(it) }
            .maxWithOrNull(compareBy<JSONObject> { it.optDouble("abr", 0.0) }
                .thenBy { it.optDouble("tbr", 0.0) }.thenBy { it.optDouble("asr", 0.0) })
        if (audioOnly) return audio?.getString("format_id") ?: formats.filter { hasAudio(it) }
            .maxByOrNull { it.optDouble("abr", 0.0) }?.getString("format_id") ?: error("音声が見つかりません。")
        val video = formats.filter { hasVideo(it) && resolution(it) in 1..height &&
            (it.isNull("fps") || it.optDouble("fps", 0.0) <= fps) }
            .maxWithOrNull(compareBy<JSONObject> { resolution(it) }.thenBy { it.optDouble("fps", 0.0) }
                .thenBy { it.optDouble("tbr", 0.0) }) ?: error("指定した上限内の動画がありません。画質設定を変更してください。")
        val videoId = video.getString("format_id")
        return if (hasAudio(video)) videoId else "$videoId+${audio?.getString("format_id") ?: error("音声が見つかりません。") }"
    }
}
