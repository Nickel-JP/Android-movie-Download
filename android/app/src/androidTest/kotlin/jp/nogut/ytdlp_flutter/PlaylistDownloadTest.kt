package jp.nogut.ytdlp_flutter

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.net.Uri
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.Closeable
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.util.UUID
import java.util.concurrent.Executors

@RunWith(AndroidJUnit4::class)
class PlaylistDownloadTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun options(url: String): Map<String, Any?> = mapOf("url" to url, "mode" to "video",
        "height" to 480, "fps" to 60, "bitrate" to 320, "container" to "mp4")

    @Test fun listsEmbeddedVideosAndDownloadsTheSelectedUrl() {
        val engine = NativeEngine.get(context)
        engine.initialize()
        val source = File(context.cacheDir, "list-fixture-${UUID.randomUUID()}.mp4")
        try {
            engine.runtime.executeFfmpeg(listOf("-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30", "-f", "lavfi", "-i", "sine=frequency=440",
                "-t", "1", "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac",
                "-movflags", "+faststart", source.absolutePath))
            ListFixture(source.readBytes()).use { server ->
                val page = engine.inspectCollection(server.url, 0)
                assertEquals("playlist", page["kind"])
                val entries = page["entries"] as List<Map<String, Any?>>
                assertEquals(2, entries.size)
                assertTrue(entries.all { it["available"] == true })
                val task = JSONObject(options(entries[1]["url"] as String)).put("id", UUID.randomUUID().toString())
                val result = engine.download(task, {}) { file, token -> MediaStoreWriter.publish(context, file, token) }
                assertEquals("completed", result["status"])
                val uri = Uri.parse(result["outputUri"] as String)
                try { assertTrue(context.contentResolver.openInputStream(uri)!!.use { it.readBytes().size } > 1000) }
                finally { context.contentResolver.delete(uri, null, null) }
            }
        } finally { source.delete() }
    }

    @Test fun batchRegistrationSupportsMoreThanTwentyAndIsAtomicOnFailure() {
        val store = TaskStore.get(context)
        val items = (1..25).map { options("https://example.org/$it.mp4") + ("title" to "動画$it") }
        val ids = store.addBatch(items)
        try {
            assertEquals(25, ids.size)
            assertTrue(ids.all { store.get(it)?.optString("status") == "queued" })
            val size = store.all().size
            assertThrows(IllegalArgumentException::class.java) {
                store.addBatch(listOf(options("https://example.org/ok.mp4"), options("file:///invalid.mp4")))
            }
            assertEquals(size, store.all().size)
        } finally { ids.forEach { store.update(it, mapOf("status" to "cancelled")) } }
    }

    private class ListFixture(private val clip: ByteArray) : Closeable {
        private val server = ServerSocket(0, 20, InetAddress.getByName("127.0.0.1"))
        private val workers = Executors.newCachedThreadPool()
        @Volatile private var closed = false
        val base = "http://127.0.0.1:${server.localPort}"
        val url = "$base/list.html"
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
                            val page = request.split(' ').getOrNull(1)?.startsWith("/list.html") == true
                            val bytes = if (page) "<html><title>Local playlist</title><body><video src='$base/a.mp4'></video><video src='$base/b.mp4'></video></body></html>".toByteArray() else clip
                            val type = if (page) "text/html; charset=utf-8" else "video/mp4"
                            val header = "HTTP/1.1 200 OK\r\nContent-Type: $type\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
                            socket.getOutputStream().apply {
                                write(header.toByteArray(Charsets.US_ASCII))
                                if (!request.startsWith("HEAD ")) write(bytes)
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
