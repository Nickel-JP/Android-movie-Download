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
        val result = VideoProbe.parse("""{"streams":[{"width":3840,"height":2160,"avg_frame_rate":"60000/1001","r_frame_rate":"60/1"}]}""")
        assertEquals(3840, result.width)
        assertEquals(2160, result.height)
        assertEquals(59.94, result.fps!!, 0.001)
    }
}
