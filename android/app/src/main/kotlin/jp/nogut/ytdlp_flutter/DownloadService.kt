package jp.nogut.ytdlp_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class DownloadService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val pumping = AtomicBoolean(false)
    private lateinit var store: TaskStore
    private lateinit var engine: NativeEngine
    private var wakeLock: PowerManager.WakeLock? = null
    @Volatile private var activeId: String? = null
    @Volatile private var lastStartId = 0
    @Volatile private var closing = false
    private var lastNotifyAt = 0L

    override fun onCreate() {
        super.onCreate()
        store = TaskStore.get(this)
        engine = NativeEngine.get(this)
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "ダウンロード", NotificationManager.IMPORTANCE_LOW))
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        if (intent?.action == CANCEL) {
            val id = intent.getStringExtra("id")
            if (id != null) {
                store.update(id, mapOf("status" to "cancelled", "message" to "キャンセルしました"))
                engine.cancel(id)
            }
        }
        ServiceCompat.startForeground(this, NOTIFICATION, notification("保存の準備中", 0, null),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        if (!pumping.get()) pump()
        return START_NOT_STICKY
    }
    private fun pump() {
        if (closing || !pumping.compareAndSet(false, true)) return
        executor.submit {
            val power = getSystemService(PowerManager::class.java)
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:download").apply {
                acquire(6 * 60 * 60 * 1000L)
            }
            try {
                while (!closing) {
                    val task = store.next() ?: break
                    val id = task.getString("id")
                    activeId = id
                    store.update(id, mapOf("status" to "running"))
                    try {
                        val result = engine.download(task, { changes ->
                            if (store.get(id)?.optString("status") != "cancelled") store.update(id, changes)
                            val now = System.currentTimeMillis()
                            if (now - lastNotifyAt > 500) {
                                lastNotifyAt = now
                                val current = store.get(id)
                                val status = current?.optString("status")
                                val type = if (Build.VERSION.SDK_INT >= 35 && status in listOf("processing", "saving"))
                                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING else ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                                ServiceCompat.startForeground(this, NOTIFICATION,
                                    notification(current?.optString("title") ?: "ダウンロード中",
                                        current?.optDouble("progress")?.toInt() ?: 0, id), type)
                            }
                        }) { file, token -> MediaStoreWriter.publish(this, file, token) }
                        store.update(id, result)
                    } catch (e: CancellationException) {
                        store.update(id, mapOf("status" to "cancelled", "message" to "キャンセルしました"))
                    } catch (e: Exception) {
                        store.update(id, mapOf("status" to "failed", "message" to (e.message ?: "保存に失敗しました。")))
                        android.util.Log.e("DownloadService", "保存処理に失敗しました", e)
                    } finally { activeId = null }
                }
            } finally {
                wakeLock?.let { if (it.isHeld) it.release() }
                wakeLock = null
                pumping.set(false)
                android.os.Handler(mainLooper).post {
                    if (!closing && store.next() != null) pump()
                    else { stopForeground(STOP_FOREGROUND_REMOVE); stopSelfResult(lastStartId) }
                }
            }
        }
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
        closing = true
        activeId?.let { engine.cancel(it) }
        store.interruptQueued()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    override fun onDestroy() {
        closing = true
        activeId?.let { engine.cancel(it) }
        executor.shutdownNow()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
    companion object {
        const val CANCEL = "jp.nogut.ytdlp.CANCEL"
        private const val CHANNEL = "downloads"
        private const val NOTIFICATION = 100
    }
}
