package jp.nogut.ytdlp_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CookieAndProbeTest {
    @Test fun retainsCookiesFromOtherSitesAndHttpOnlyEntries() {
        val entries = listOf(".vimeo.com\tTRUE\t/\tTRUE\t0\tsession\ttest",
            "#HttpOnly_.example.org\tTRUE\t/\tTRUE\t0\tauth\ttest")
        assertEquals(entries, CookiePolicy.parse("# Netscape HTTP Cookie File\n" + entries.joinToString("\n")))
    }
    @Test fun rejectsInvalidCookieRecords() {
        assertThrows(IllegalArgumentException::class.java) {
            CookiePolicy.parse("# Netscape HTTP Cookie File\n.example.org\tTRUE\t/\tTRUE\tinvalid\tx\ttest")
        }
    }
    @Test fun parsesVideoDimensionsAndFrameRate() {
        val result = VideoProbe.parse("Stream #0:0: Video: h264 (High), yuv420p, 3840x2160 [SAR 1:1 DAR 16:9], 59.94 fps, 60 tbr")
        assertEquals(3840, result.width)
        assertEquals(2160, result.height)
        assertEquals(59.94, result.fps!!, 0.001)
    }
}
