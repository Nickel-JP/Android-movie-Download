package jp.nogut.ytdlp_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class VideoProbeTest {
    @Test fun keepsPortraitGeometryAndUsesShortEdgeForQuality() {
        val geometry = VideoProbe.parse(video(1080, 1920, "30000/1001", "30/1"))
        assertEquals(1080, geometry.width)
        assertEquals(1920, geometry.height)
        assertEquals(30000.0 / 1001, geometry.fps!!, 0.0001)
        VideoProbe.checkLimits(geometry, 1080, 30)
        assertThrows(IllegalArgumentException::class.java) { VideoProbe.checkLimits(geometry, 720, 30) }
    }

    @Test fun rejectsQualityAndFrameRateAboveRequestedLimit() {
        val geometry = VideoProbe.parse(video(3840, 2160, "60000/1001", "60/1"))
        VideoProbe.checkLimits(geometry, 2160, 60)
        assertThrows(IllegalArgumentException::class.java) { VideoProbe.checkLimits(geometry, 1080, 60) }
        assertThrows(IllegalArgumentException::class.java) { VideoProbe.checkLimits(geometry, 2160, 30) }
    }

    @Test fun fallsBackToNominalRateWhenAverageRateIsUnavailable() {
        listOf("0/0", "N/A", "0", "-30/1", "30/0", "NaN", "Infinity", "1/2/3").forEach {
            val geometry = VideoProbe.parse(video(320, 240, it, "24000/1001"))
            assertEquals(24000.0 / 1001, geometry.fps!!, 0.0001)
        }
    }

    @Test fun acceptsUnknownRateWithoutTreatingItAsZeroOrInfinity() {
        val geometry = VideoProbe.parse(video(320, 240, "0/0", "N/A"))
        assertNull(geometry.fps)
        VideoProbe.checkLimits(geometry, 240, 30)
    }

    @Test fun acceptsDecimalRateAndPrefersAverageRate() {
        assertEquals(29.97, VideoProbe.parse(video(320, 240, "29.97", "60/1")).fps!!, 0.001)
    }

    @Test fun explainsAudioOnlyAndRejectsInvalidDimensions() {
        val audio = assertThrows(IllegalStateException::class.java) { VideoProbe.parse("""{"streams":[]}""") }
        assertTrue(audio.message!!.contains("MP3またはWAV"))
        assertThrows(IllegalStateException::class.java) { VideoProbe.parse(video(0, 240, "30/1", "30/1")) }
        assertThrows(IllegalStateException::class.java) { VideoProbe.parse(video(320, -1, "30/1", "30/1")) }
    }

    @Test fun invalidOutputHasProbeSpecificMessage() {
        listOf("not json", "{}", "[]").forEach {
            val failure = assertThrows(IllegalStateException::class.java) { VideoProbe.parse(it) }
            assertTrue(failure.message!!.contains("動画情報の確認に失敗"))
        }
    }

    @Test fun retainsProbeErrorAndRedactsUrl() {
        val failure = assertThrows(IllegalStateException::class.java) {
            VideoProbe.parse("""{"error":{"code":-1,"string":"Invalid data https://example.org/private?token=secret"}}""")
        }
        assertTrue(failure.message!!.contains("Invalid data"))
        assertTrue(failure.message!!.contains("[URL]"))
        assertTrue(!failure.message!!.contains("secret"))
    }

    private fun video(width: Int, height: Int, average: String, nominal: String) =
        """{"streams":[{"width":$width,"height":$height,"avg_frame_rate":"$average","r_frame_rate":"$nominal"}]}"""
}
