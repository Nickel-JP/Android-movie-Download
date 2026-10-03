package jp.nogut.ytdlp_flutter

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID
import java.util.concurrent.CancellationException

@RunWith(AndroidJUnit4::class)
class VideoProbeIntegrationTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun runtime() = NativeRuntime(context).apply { initialize() }

    @Test fun probesLandscapeAndPortraitFractionalVideoAndChecksLimits() {
        val runtime = runtime()
        listOf("320x240", "240x320").forEach { dimensions ->
            withFixture("mp4") { file ->
                // 外部サイトへ接続せず、通常動画と縦動画を同じ分数fpsで生成する。
                runtime.executeFfmpeg(listOf("-hide_banner", "-loglevel", "error", "-y",
                    "-f", "lavfi", "-i", "testsrc2=size=$dimensions:rate=30000/1001", "-t", "0.2",
                    "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", file.absolutePath))
                VideoProbe.verify(runtime, file, 240, 30, CancelToken())
                assertThrows(IllegalArgumentException::class.java) {
                    VideoProbe.verify(runtime, file, 200, 30, CancelToken())
                }
                assertThrows(IllegalArgumentException::class.java) {
                    VideoProbe.verify(runtime, file, 240, 24, CancelToken())
                }
            }
        }
    }

    @Test fun reportsAudioOnlyAsAudioInsteadOfVideo() {
        val runtime = runtime()
        withFixture("wav") { file ->
            runtime.executeFfmpeg(listOf("-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
                "-i", "sine=frequency=440:sample_rate=8000", "-t", "0.1", file.absolutePath))
            val failure = assertThrows(IllegalStateException::class.java) {
                VideoProbe.verify(runtime, file, 2160, 60, CancelToken())
            }
            assertTrue(failure.message!!.contains("MP3またはWAV"))
        }
    }

    @Test fun doesNotTreatAttachedCoverArtAsVideo() {
        val runtime = runtime()
        withFixture("jpg") { cover ->
            val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
            try { cover.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) } }
            finally { bitmap.recycle() }
            withFixture("mp3") { file ->
                runtime.executeFfmpeg(listOf("-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
                    "-i", "sine=frequency=440:sample_rate=44100", "-i", cover.absolutePath,
                    "-map", "0:a", "-map", "1:v", "-t", "0.2", "-c:a", "libmp3lame",
                    "-c:v", "copy", "-disposition:v", "attached_pic", file.absolutePath))
                val failure = assertThrows(IllegalStateException::class.java) {
                    VideoProbe.verify(runtime, file, 2160, 60, CancelToken())
                }
                assertTrue(failure.message!!.contains("MP3またはWAV"))
            }
        }
    }

    @Test fun reportsCorruptFileWithProbeDiagnostic() {
        val runtime = runtime()
        withFixture("mp4") { file ->
            file.writeText("This is a deliberately corrupt local test fixture.")
            val token = CancelToken()
            val failure = assertThrows(IllegalStateException::class.java) {
                VideoProbe.verify(runtime, file, 2160, 60, token)
            }
            assertTrue(failure.message!!.contains("動画情報の確認に失敗"))
            assertTrue(failure.message!!.contains("終了コード"))
            assertTrue(failure.message!!.contains("Invalid data"))
            assertNull(token.process)
            assertNull(token.pid)
        }
    }

    @Test fun preCancelledProbeKeepsCancellation() {
        val token = CancelToken().apply { cancel() }
        assertThrows(CancellationException::class.java) {
            VideoProbe.verify(NativeRuntime(context), File(context.cacheDir, "unused-probe.mp4"), 2160, 60, token)
        }
        assertNull(token.process)
    }

    private fun withFixture(extension: String, test: (File) -> Unit) {
        val file = File(context.cacheDir, "probe-fixture-${UUID.randomUUID()}.$extension")
        try { test(file) } finally { file.delete() }
    }
}
