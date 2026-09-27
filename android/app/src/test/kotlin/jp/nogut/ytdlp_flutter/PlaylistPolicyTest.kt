package jp.nogut.ytdlp_flutter

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PlaylistPolicyTest {
    @Test fun resolvesYoutubeEntriesAndMarksMissingOrLiveUrls() {
        val info = JSONObject("""{"title":"mix","entries":[
            {"id":"abcdefghijk","ie_key":"Youtube","title":"first","url":"abcdefghijk"},
            {"id":"missing","title":"missing"},
            {"url":"https://example.org/live","is_live":true}
        ]}""")
        val result = PlaylistPolicy.page(info, 0)
        val entries = result["entries"] as List<Map<String, Any?>>
        assertEquals("https://www.youtube.com/watch?v=abcdefghijk", entries[0]["url"])
        assertEquals(true, entries[0]["available"])
        assertEquals(false, entries[1]["available"])
        assertEquals(false, entries[2]["available"])
    }
    @Test fun pagingUsesPeekEntryAndStopsAtMaximum() {
        val data = JSONArray()
        repeat(51) { data.put(JSONObject().put("url", "https://example.org/$it.mp4")) }
        val info = JSONObject().put("entries", data)
        val first = PlaylistPolicy.page(info, 0)
        assertEquals(50, (first["entries"] as List<*>).size)
        assertEquals(50, first["nextOffset"])
        assertEquals(true, first["hasMore"])
        assertEquals(false, PlaylistPolicy.page(info, 950)["hasMore"])
    }
    @Test fun resolvesGenericEmbeddedMediaInsteadOfCollectionPage() {
        val info = JSONObject("""{"entries":[{"title":"clip","extractor":"generic","webpage_url":"https://example.org/list",
            "formats":[{"url":"https://example.org/clip.mp4"}]}]}""")
        val entries = PlaylistPolicy.page(info, 0)["entries"] as List<Map<String, Any?>>
        assertEquals("https://example.org/clip.mp4", entries[0]["url"])
    }
}
