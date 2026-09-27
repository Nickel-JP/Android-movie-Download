package jp.nogut.ytdlp_flutter

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.net.Uri
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import java.io.Closeable
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.util.UUID
import java.util.concurrent.Executors

@RunWith(AndroidJUnit4::class)
class HttpDirectDownloadTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun downloadsGenericHttpVideoWithUnknownQualityAndSavesIt() {
        val engine = NativeEngine.get(context)
        engine.initialize()
        val source = File(context.cacheDir, "fixture-${UUID.randomUUID()}.mp4")
        try {
            engine.runtime.executeFfmpeg(listOf("-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
                "-t", "1", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-movflags", "+faststart", source.absolutePath))
            assertThrows(IllegalArgumentException::class.java) {
                VideoProbe.verify(engine.runtime, source, 100, 60, CancelToken())
            }
            assertThrows(IllegalArgumentException::class.java) {
                VideoProbe.verify(engine.runtime, source, 480, 15, CancelToken())
            }
            HttpFixture(source.readBytes(), "video/mp4").use { server ->
                val options = options(server.url, "video")
                DownloadPolicy.validate(options)
                val preview = engine.inspect(server.url)
                assertTrue(preview["title"].toString().isNotBlank())
                val task = JSONObject(options).put("id", UUID.randomUUID().toString())
                val result = engine.download(task, {}) { file, token -> MediaStoreWriter.publish(context, file, token) }
                assertEquals("completed", result["status"])
                val uri = Uri.parse(result["outputUri"] as String)
                try {
                    val bytes = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                    assertTrue(bytes.size > 1000)
                } finally { context.contentResolver.delete(uri, null, null) }
            }
        } finally { source.delete() }
    }

    @Test fun downloadsGenericHttpAudioAndConvertsToMp3() {
        val engine = NativeEngine.get(context)
        engine.initialize()
        val source = File(context.cacheDir, "fixture-${UUID.randomUUID()}.wav")
        try {
            engine.runtime.executeFfmpeg(listOf("-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
                "-i", "sine=frequency=440:sample_rate=48000", "-t", "1", "-ac", "2", source.absolutePath))
            HttpFixture(source.readBytes(), "audio/wav").use { server ->
                val task = JSONObject(options(server.url, "mp3")).put("id", UUID.randomUUID().toString())
                val result = engine.download(task, {}) { file, token -> MediaStoreWriter.publish(context, file, token) }
                assertEquals("completed", result["status"])
                val uri = Uri.parse(result["outputUri"] as String)
                try {
                    assertEquals("audio/mpeg", context.contentResolver.getType(uri))
                    assertTrue(context.contentResolver.openInputStream(uri)!!.use { it.readBytes().size } > 1000)
                } finally { context.contentResolver.delete(uri, null, null) }
            }
        } finally { source.delete() }
    }

    private fun options(url: String, mode: String): Map<String, Any?> = mapOf("url" to url, "mode" to mode,
        "height" to 480, "fps" to 60, "bitrate" to 320, "container" to "mp4")

    // 外部サイトに接続せず、自分で生成した素材だけをHTTP経由で提供する。
    private class HttpFixture(private val data: ByteArray, private val type: String) : Closeable {
        private val server = ServerSocket(0, 20, InetAddress.getByName("127.0.0.1"))
        private val workers = Executors.newCachedThreadPool()
        @Volatile private var closed = false
        val url = "http://127.0.0.1:${server.localPort}/fixture?token=local"
        init {
            workers.submit {
                while (!closed) {
                    val socket = try { server.accept() } catch (e: java.net.SocketException) {
                        if (closed) break else throw e
                    }
                    workers.submit {
                        socket.use {
                            socket.soTimeout = 10_000
                            val input = socket.getInputStream().bufferedReader()
                            val request = input.readLine() ?: return@submit
                            while (!input.readLine().isNullOrEmpty()) { }
                            val header = "HTTP/1.1 200 OK\r\nContent-Type: $type\r\nContent-Length: ${data.size}\r\nConnection: close\r\n\r\n"
                            socket.getOutputStream().apply {
                                write(header.toByteArray(Charsets.US_ASCII))
                                if (!request.startsWith("HEAD ")) write(data)
                                flush()
                            }
                        }
                    }
                }
            }
        }
        override fun close() { closed = true; server.close(); workers.shutdownNow() }
    }
}
