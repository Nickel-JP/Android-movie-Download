package jp.nogut.ytdlp_flutter

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.provider.MediaStore
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

@RunWith(AndroidJUnit4::class)
class StorageAndCancellationTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun wave(): File {
        val data = ByteArray(16000)
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray()).putInt(36 + data.size).put("WAVEfmt ".toByteArray())
            .putInt(16).putShort(1).putShort(1).putInt(8000).putInt(16000)
            .putShort(2).putShort(16).put("data".toByteArray()).putInt(data.size)
        return File(context.cacheDir, "AndroidMovieDownload-test-${UUID.randomUUID()}.wav").apply {
            writeBytes(header.array() + data)
        }
    }
    @Test fun mediaStoreSavePreservesContent() {
        val file = wave()
        var uri: android.net.Uri? = null
        try {
            uri = android.net.Uri.parse(MediaStoreWriter.publish(context, file, CancelToken()))
            val saved = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
            assertArrayEquals(file.readBytes(), saved)
        } finally {
            if (uri != null) context.contentResolver.delete(uri, null, null)
            file.delete()
        }
    }
    @Test fun cancelledSaveRemovesPendingEntry() {
        val file = wave()
        val token = CancelToken().apply { cancelled = true }
        try {
            var cancelled = false
            try { MediaStoreWriter.publish(context, file, token) }
            catch (_: CancellationException) { cancelled = true }
            assertTrue(cancelled)
            context.contentResolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID), "${MediaStore.MediaColumns.DISPLAY_NAME}=?",
                arrayOf(file.name), null)!!.use { assertFalse(it.moveToFirst()) }
        } finally { file.delete() }
    }
    @Test fun cancellationStopsRunnerAndChild() {
        val runtime = NativeRuntime(context)
        runtime.initialize()
        val script = File(context.cacheDir, "qa-wait.py")
        script.writeText("import subprocess, time\np = subprocess.Popen(['/system/bin/sleep', '30'])\nprint('__CHILD__' + str(p.pid), flush=True)\ntime.sleep(30)\n")
        val token = CancelToken()
        val started = CountDownLatch(1)
        val cancelled = AtomicBoolean(false)
        var child = 0
        val thread = Thread {
            try {
                runtime.execute(emptyList(), token, script) { line ->
                    if (line.startsWith("__CHILD__")) {
                        child = line.removePrefix("__CHILD__").toInt()
                        started.countDown()
                    }
                }
            } catch (_: CancellationException) { cancelled.set(true) }
        }
        try {
            thread.start()
            assertTrue(started.await(10, TimeUnit.SECONDS))
            token.cancel()
            thread.join(5000)
            assertFalse(thread.isAlive)
            assertTrue(cancelled.get())
            val status = File("/proc/$child/status")
            assertTrue(!status.exists() || status.readText().contains(Regex("State:\\s+Z")))
        } finally { token.cancel(); script.delete() }
    }
}
