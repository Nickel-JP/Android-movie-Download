package jp.nogut.ytdlp_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.json.JSONObject

class DownloadPolicyTest {
    @Test fun acceptsShortsWithoutChangingSharedParameters() {
        val url = "https://youtube.com/shorts/-WcGAdKTQGo?si=W9Kfp7wGwafNow9f"
        val options = mapOf("url" to url, "mode" to "video", "height" to 2160,
            "fps" to 60, "bitrate" to 320, "container" to "mp4")
        assertEquals(url, DownloadPolicy.validate(options)["url"])
    }
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
    @Test fun acceptsOtherSitesAndNonDefaultPorts() {
        for (url in listOf("https://vimeo.com/123", "https://www.twitch.tv/videos/123",
            "http://127.0.0.1:8080/video.mp4?token=abc#fragment")) {
            val options = mapOf("url" to url, "mode" to "video", "height" to 2160,
                "fps" to 60, "bitrate" to 320, "container" to "mp4")
            assertEquals(url, DownloadPolicy.validate(options)["url"])
        }
    }
    @Test fun rejectsInvalidUrlSchemesAndCredentials() {
        for (url in listOf("file:///video.mp4", "https:///video", "https://u:p@example.org/video",
            "http://example.org:0/video", "https://example.org:70000/video")) {
            assertThrows(IllegalArgumentException::class.java) { DownloadPolicy.validate(mapOf("url" to url)) }
        }
    }
    @Test fun acceptsDirectVideoAndAudioWithoutCodecOrQualityMetadata() {
        val info = JSONObject("""{"formats":[{"format_id":"mp4","url":"https://example.org/v.mp4","ext":"mp4"}]}""")
        assertEquals("mp4", DownloadPolicy.chooseFormat(info, 2160, 60, false))
        org.junit.Assert.assertTrue(DownloadPolicy.needsVideoProbe(info, "mp4"))
        val audio = JSONObject("""{"formats":[{"format_id":"mp3","url":"https://example.org/a.mp3","vcodec":"none","ext":"mp3"}]}""")
        assertEquals("mp3", DownloadPolicy.chooseFormat(audio, 2160, 60, true))
        val single = JSONObject("""{"url":"https://example.org/v.mp4","ext":"mp4"}""")
        assertEquals("best", DownloadPolicy.chooseFormat(single, 2160, 60, false))
    }
}
