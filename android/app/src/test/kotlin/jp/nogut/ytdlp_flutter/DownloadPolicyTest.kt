package jp.nogut.ytdlp_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.json.JSONObject

class DownloadPolicyTest {
    @Test fun capsResolutionAndFramerateIncludingPortrait() {
        val info = JSONObject("""{"formats":[
            {"format_id":"8k","vcodec":"av1","acodec":"none","width":7680,"height":4320,"fps":60},
            {"format_id":"120fps","vcodec":"vp9","acodec":"none","width":3840,"height":2160,"fps":120},
            {"format_id":"portrait4k","vcodec":"vp9","acodec":"none","width":2160,"height":3840,"fps":60},
            {"format_id":"hd","vcodec":"avc","acodec":"aac","width":1920,"height":1080,"fps":30},
            {"format_id":"audio","vcodec":"none","acodec":"opus","abr":160}
        ]}""")
        assertEquals("portrait4k+audio", DownloadPolicy.chooseFormat(info, 2160, 60, false))
        assertEquals("hd", DownloadPolicy.chooseFormat(info, 1080, 30, false))
        assertEquals("audio", DownloadPolicy.chooseFormat(info, 2160, 60, true))
    }
    @Test fun refusesVideosAboveConfiguredLimit() {
        val info = JSONObject("""{"formats":[{"format_id":"8k","vcodec":"av1","acodec":"aac","width":7680,"height":4320,"fps":60}]}""")
        assertThrows(IllegalStateException::class.java) { DownloadPolicy.chooseFormat(info, 2160, 60, false) }
    }
}
