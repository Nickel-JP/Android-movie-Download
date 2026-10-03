package jp.nogut.ytdlp_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class DownloadService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val pumping = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())
    private val wakeLockGuard = Any()
    private lateinit var store: TaskStore
    private lateinit var engine: NativeEngine
    private lateinit var notifications: NotificationManager
    private var foregroundStarted = false
    private var wakeLock: PowerManager.WakeLock? = null
    @Volatile private var activeId: String? = null
    @Volatile private var lastStartId = 0
    @Volatile private var closing = false
    @Volatile private var interruptionMessage = "Androidが保存処理を終了しました。アプリを開いて再試行してください。"
    private var lastNotifyAt = 0L

    override fun onCreate() {
        super.onCreate()
        store = TaskStore.get(this)
        engine = NativeEngine.get(this)
        notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL, "ダウンロード", NotificationManager.IMPORTANCE_LOW))
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        if (closing) { stopSelfResult(startId); return START_NOT_STICKY }
        if (intent?.action == CANCEL) {
            val id = intent.getStringExtra("id")
            if (id != null && store.get(id)?.optString("status") in TaskStore.activeStates) {
                store.update(id, mapOf("status" to "cancelled", "message" to "キャンセルしました"))
                engine.cancel(id)
            }
        }
        if (!foregroundStarted) {
            if (store.next() == null) { stopSelfResult(startId); return START_NOT_STICKY }
            try {
                // minSdk29のAPIを直接使い、互換ライブラリが新しい種別を消すことを避ける。
                // 保存中の種別追加を不要にするため、開始時に取得と変換の両方を登録する。
                startForeground(NOTIFICATION, notification("保存の準備中", 0, null),
                    DownloadForegroundPolicy.types(Build.VERSION.SDK_INT))
                foregroundStarted = true
            } catch (e: Exception) {
                closing = true
                store.interruptQueued("Androidが保存処理の開始を許可しませんでした。アプリを開いて再試行してください。\n\n${e.message.orEmpty()}")
                android.util.Log.e("DownloadService", "保存サービスを開始できませんでした", e)
                stopSelfResult(startId)
                return START_NOT_STICKY
            }
        }
        if (!pumping.get()) pump()
        return START_NOT_STICKY
    }
    private fun pump() {
        if (closing || !pumping.compareAndSet(false, true)) return
        executor.submit {
            try {
                synchronized(wakeLockGuard) {
                    if (!closing) {
                        wakeLock = getSystemService(PowerManager::class.java)
                            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:download").apply {
                                acquire(6 * 60 * 60 * 1000L)
                            }
                    }
                }
                while (!closing) {
                    val task = store.claimNext() ?: break
                    val id = task.getString("id")
                    activeId = id
                    lastNotifyAt = 0L
                    try {
                        val result = engine.download(task, { changes ->
                            // エンジンのトークン登録前に停止された場合も、最初の報告で中断する。
                            if (closing) throw CancellationException(interruptionMessage)
                            val cancelled = store.get(id)?.optString("status") == "cancelled"
                            if (!closing && !cancelled) store.update(id, changes)
                            val now = SystemClock.elapsedRealtime()
                            if (!closing && !cancelled && now - lastNotifyAt > 500) {
                                lastNotifyAt = now
                                val current = store.get(id)
                                val updated = notification(current?.optString("title") ?: "ダウンロード中",
                                    current?.optDouble("progress")?.toInt() ?: 0, id)
                                main.post {
                                    // 完了・停止後の遅れて届いた進捗通知は再表示しない。
                                    if (!closing && foregroundStarted && activeId == id) {
                                        try { notifications.notify(NOTIFICATION, updated) }
                                        catch (e: RuntimeException) {
                                            android.util.Log.w("DownloadService", "進捗通知を更新できませんでした", e)
                                        }
                                    }
                                }
                            }
                        }) { file, token -> MediaStoreWriter.publish(this, file, token) }
                        store.update(id, result)
                    } catch (e: CancellationException) {
                        if (closing && store.get(id)?.optString("status") != "cancelled") {
                            store.update(id, mapOf("status" to "interrupted", "message" to interruptionMessage))
                        } else {
                            store.update(id, mapOf("status" to "cancelled", "message" to "キャンセルしました"))
                        }
                    } catch (e: Exception) {
                        store.update(id, mapOf("status" to if (closing) "interrupted" else "failed",
                            "message" to if (closing) interruptionMessage else (e.message ?: "保存に失敗しました。")))
                        android.util.Log.e("DownloadService", "保存処理に失敗しました", e)
                    } finally { activeId = null }
                }
            } finally {
                releaseWakeLock()
                main.post {
                    // onStartCommandと同じスレッドで稼働状態と次のキューを確定する。
                    // 古い完了処理が、新しく始まった処理を停止する競合を防ぐ。
                    pumping.set(false)
                    if (!closing && store.next() != null) pump()
                    else { finishForeground(); stopSelfResult(lastStartId) }
                }
            }
        }
    }
    private fun releaseWakeLock() = synchronized(wakeLockGuard) {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
    private fun finishForeground() {
        foregroundStarted = false
        stopForeground(STOP_FOREGROUND_REMOVE)
    }
    private fun notification(title: String, progress: Int, id: String?): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = NotificationCompat.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_download)
            .setContentTitle("Android movie Download").setContentText(title)
            .setContentIntent(open).setOnlyAlertOnce(true).setOngoing(true)
            .setProgress(100, progress, progress == 0)
        if (id != null) {
            val cancel = Intent(this, DownloadService::class.java).setAction(CANCEL).putExtra("id", id)
            val pending = PendingIntent.getService(this, id.hashCode(), cancel,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            builder.addAction(0, "キャンセル", pending)
        }
        return builder.build()
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        interruptionMessage = "Androidのバックグラウンド実行時間の上限に達しました。アプリを開いて再試行してください。"
        closing = true
        activeId?.let { engine.cancel(it) }
        store.interruptQueued()
        finishForeground()
        stopSelf()
    }
    override fun onDestroy() {
        closing = true
        foregroundStarted = false
        activeId?.let { engine.cancel(it) }
        executor.shutdownNow()
        releaseWakeLock()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
    companion object {
        const val CANCEL = "jp.nogut.ytdlp.CANCEL"
        private const val CHANNEL = "downloads"
        private const val NOTIFICATION = 100
    }
}
