package jp.nogut.ytdlp_flutter

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.MediaStore
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Test
import org.junit.runner.RunWith
import java.io.Closeable
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.net.SocketException
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 35)
class DownloadServiceRegressionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun foregroundServiceKeepsItsTypesAndCompletesVideoAndMp3QueueInBackground() {
        val store = TaskStore.get(context)
        // 実行中の既存ジョブがある環境では、そのジョブへ干渉せずテストを省略する。
        assumeFalse("ほかのダウンロードが実行中です。", store.hasActive())
        val notifications = context.getSystemService(NotificationManager::class.java)
        assertTrue("専用検証端末では事前にアプリの通知を許可してください。", notifications.areNotificationsEnabled())
        val engine = NativeEngine.get(context)
        engine.initialize()
        val runId = UUID.randomUUID().toString()
        val video = File(context.cacheDir, "service-$runId.mp4")
        val audio = File(context.cacheDir, "service-$runId.wav")
        val ownedIds = mutableListOf<String>()
        try {
            engine.runtime.executeFfmpeg(listOf("-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30", "-f", "lavfi", "-i",
                "sine=frequency=440:sample_rate=48000", "-t", "1", "-c:v", "libx264", "-preset",
                "ultrafast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart", video.absolutePath))
            engine.runtime.executeFfmpeg(listOf("-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "sine=frequency=660:sample_rate=48000", "-t", "1", "-ac", "2", audio.absolutePath))
            GatedHttpFixture(video.readBytes(), audio.readBytes(), runId).use { fixture ->
                ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                    scenario.onActivity { activity ->
                        ownedIds.add(store.add(options(fixture.videoUrl, "video")))
                        activity.startForegroundService(Intent(activity, DownloadService::class.java))
                    }
                    assertTrue("実サービスからのHTTP要求が到達しませんでした。",
                        fixture.requested.await(20, TimeUnit.SECONDS))
                    assertForegroundTypes()
                    // 最初の処理中に再度 startForegroundService し、連続キューの開始要求も通す。
                    scenario.onActivity { activity ->
                        ownedIds.add(store.add(options(fixture.audioUrl, "mp3")))
                        activity.startForegroundService(Intent(activity, DownloadService::class.java))
                    }
                    instrumentation.waitForIdleSync()
                    scenario.moveToState(Lifecycle.State.CREATED)
                    assertForegroundTypes()
                    assertTrue("実行中の通知がありません。", downloadNotificationExists())
                    fixture.release.countDown()
                    waitUntil("バックグラウンドの動画・MP3キューが完了しませんでした。", 180_000) {
                        ownedIds.forEach { id ->
                            val task = store.get(id) ?: error("テスト用ジョブがありません: $id")
                            assertFalse("保存に失敗しました: ${task.optString("message")}",
                                task.optString("status") in setOf("failed", "cancelled", "interrupted"))
                        }
                        ownedIds.all { store.get(it)?.optString("status") == "completed" }
                    }
                    ownedIds.forEachIndexed { index, id ->
                        val task = store.get(id)!!
                        assertEquals(100.0, task.getDouble("progress"), 0.0)
                        val uri = Uri.parse(task.getString("outputUri"))
                        assertEquals(if (index == 0) "video/mp4" else "audio/mpeg", context.contentResolver.getType(uri))
                        assertTrue("保存ファイルが空です。",
                            context.contentResolver.openInputStream(uri)!!.use { it.readBytes().size } > 1000)
                    }
                    waitUntil("完了後もダウンロードサービスまたは通知が残っています。", 10_000) {
                        !serviceExists() && !downloadNotificationExists()
                    }
                }
            }
        } finally {
            // 中断時も今回作成したジョブだけをキャンセルし、保存したMediaStore行だけを削除する。
            ownedIds.forEach { id ->
                if (store.get(id)?.optString("status") in TaskStore.activeStates) {
                    store.update(id, mapOf("status" to "cancelled", "message" to "検証の後片付け"))
                    engine.cancel(id)
                }
            }
            if (ownedIds.isNotEmpty()) {
                context.stopService(Intent(context, DownloadService::class.java))
                // NativeEngine のロック解放後なら、保存完了と後片付けが競合しない。
                engine.lock.lock()
                try {
                    ownedIds.forEach { id ->
                        store.get(id)?.optString("outputUri")?.takeIf { it.isNotBlank() }?.let {
                            context.contentResolver.delete(Uri.parse(it), null, null)
                        }
                    }
                    // 結果の履歴反映直前に中断されても、今回固有の名前の出力だけを片付ける。
                    context.contentResolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        arrayOf(MediaStore.MediaColumns._ID), "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
                        arrayOf("service-$runId%"), null)?.use { cursor ->
                        while (cursor.moveToNext()) {
                            context.contentResolver.delete(ContentUris.withAppendedId(
                                MediaStore.Downloads.EXTERNAL_CONTENT_URI, cursor.getLong(0)), null, null)
                        }
                    }
                } finally { engine.lock.unlock() }
            }
            video.delete()
            audio.delete()
        }
    }

    private fun options(url: String, mode: String): Map<String, Any?> = mapOf(
        "url" to url, "mode" to mode, "height" to 480, "fps" to 60, "bitrate" to 320, "container" to "mp4")

    private fun assertForegroundTypes() {
        val descriptor = instrumentation.uiAutomation.executeShellCommand(
            "dumpsys activity services ${context.packageName}/.DownloadService")
        val dump = ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText() }
        assertTrue("DownloadService が dataSync と mediaProcessing の両タイプで実行されていません。\n$dump",
            Regex("isForeground=true[^\\r\\n]*(?:types|foregroundServiceType)=0x0*2001\\b",
                RegexOption.IGNORE_CASE).containsMatchIn(dump))
    }

    private fun downloadNotificationExists(): Boolean =
        context.getSystemService(NotificationManager::class.java).activeNotifications.any {
            it.id == 100 && it.notification.channelId == "downloads"
        }

    @Suppress("DEPRECATION")
    private fun serviceExists(): Boolean = context.getSystemService(ActivityManager::class.java)
        .getRunningServices(Int.MAX_VALUE).any { it.service.className == DownloadService::class.java.name }

    private fun waitUntil(message: String, timeoutMillis: Long, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeoutMillis
        while (!condition()) {
            assertTrue(message, SystemClock.elapsedRealtime() < deadline)
            Thread.sleep(100)
        }
    }

    // 自前生成した素材だけをlocalhostで提供し、初回要求をFGS状態の確認まで待機させる。
    private class GatedHttpFixture(video: ByteArray, audio: ByteArray, runId: String) : Closeable {
        private val files = mapOf("/service-$runId.mp4" to (video to "video/mp4"),
            "/service-$runId.wav" to (audio to "audio/wav"))
        private val server = ServerSocket(0, 20, InetAddress.getByName("127.0.0.1"))
        private val workers = Executors.newCachedThreadPool()
        @Volatile private var closed = false
        val requested = CountDownLatch(1)
        val release = CountDownLatch(1)
        val videoUrl = "http://127.0.0.1:${server.localPort}/service-$runId.mp4"
        val audioUrl = "http://127.0.0.1:${server.localPort}/service-$runId.wav"

        init {
            workers.submit {
                while (!closed) {
                    val socket = try { server.accept() } catch (e: SocketException) {
                        if (closed) break else throw e
                    }
                    workers.submit request@ {
                        socket.use {
                            socket.soTimeout = 10_000
                            val input = socket.getInputStream().bufferedReader()
                            val request = input.readLine() ?: return@request
                            while (!input.readLine().isNullOrEmpty()) { }
                            val path = request.split(' ').getOrNull(1)?.substringBefore('?')
                            val file = files[path]
                            if (file == null) {
                                socket.getOutputStream().write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                                    .toByteArray(Charsets.US_ASCII))
                                return@request
                            }
                            requested.countDown()
                            if (!release.await(25, TimeUnit.SECONDS)) return@request
                            val (data, type) = file
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

        override fun close() {
            closed = true
            release.countDown()
            server.close()
            workers.shutdownNow()
        }
    }
}
