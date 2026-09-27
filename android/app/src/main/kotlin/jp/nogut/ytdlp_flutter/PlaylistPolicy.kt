package jp.nogut.ytdlp_flutter

import org.json.JSONObject
import java.net.URI

object PlaylistPolicy {
    const val PAGE_SIZE = 50
    const val MAX_ENTRIES = 1000

    fun page(info: JSONObject, offset: Int): Map<String, Any?> {
        require(offset in 0 until MAX_ENTRIES) { "リストの取得位置が不正です。" }
        val array = info.optJSONArray("entries") ?: return mapOf("kind" to "single", "title" to info.optString("title"))
        val count = minOf(array.length(), PAGE_SIZE, MAX_ENTRIES - offset)
        val entries = (0 until count).map { position ->
            val entry = array.optJSONObject(position) ?: JSONObject()
            val index = entry.optInt("playlist_index", offset + position + 1)
            val candidates = mutableListOf(entry.optString("url"))
            // Genericの埋め込み動画では、各動画の実URLを優先して一覧ページの再取得を避ける。
            if (entry.optString("extractor") == "generic" || entry.optString("_type", "video") == "video") {
                val formats = entry.optJSONArray("formats")
                if (formats != null) for (i in 0 until formats.length()) candidates.add(formats.optJSONObject(i)?.optString("url") ?: "")
            }
            candidates.add(entry.optString("webpage_url"))
            val id = entry.optString("id")
            if (entry.optString("ie_key").startsWith("Youtube") && Regex("[A-Za-z0-9_-]{11}").matches(id)) {
                candidates.add("https://www.youtube.com/watch?v=$id")
            }
            val url = candidates.firstOrNull { validUrl(it) } ?: ""
            val nested = entry.optString("_type") in setOf("playlist", "multi_video")
            val live = entry.optBoolean("is_live") || entry.optString("live_status") == "is_live"
            val available = url.isNotBlank() && !nested && !live
            val reason = when {
                live -> "ライブ配信中"
                nested -> "動画URLを直接指定してください"
                url.isBlank() -> "URLを取得できません"
                else -> ""
            }
            mapOf("key" to "$index:${id.ifBlank { url }}", "index" to index,
                "title" to entry.optString("title").ifBlank { "動画 $index" }, "url" to url,
                "duration" to if (entry.isNull("duration")) null else entry.optDouble("duration"),
                "available" to available, "reason" to reason)
        }
        val next = offset + count
        val more = array.length() > count && next < MAX_ENTRIES
        val total = info.optInt("playlist_count", 0).takeIf { it > 0 }
        return mapOf("kind" to "playlist", "title" to info.optString("title").ifBlank { "動画リスト" },
            "entries" to entries, "nextOffset" to next, "hasMore" to more, "total" to total,
            "maximum" to MAX_ENTRIES)
    }

    private fun validUrl(value: String): Boolean = try {
        val uri = URI(value)
        uri.scheme?.lowercase() in setOf("http", "https") && !uri.host.isNullOrBlank() &&
            uri.userInfo == null && (uri.port == -1 || uri.port in 1..65535)
    } catch (_: java.net.URISyntaxException) { false }
}
