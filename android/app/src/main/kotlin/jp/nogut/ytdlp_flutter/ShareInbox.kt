package jp.nogut.ytdlp_flutter

import android.content.Intent
import java.util.UUID

class ShareInbox {
    private var pendingText: String? = null
    private var pendingId: String? = null

    fun receive(intent: Intent?): Boolean {
        if (intent?.action != Intent.ACTION_SEND || intent.type !in setOf("text/plain", "text/html")) return false
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString()
        if (text.isNullOrBlank()) return false
        pendingText = text
        pendingId = UUID.randomUUID().toString()
        return true
    }

    fun snapshot(): Map<String, String?> = mapOf("sharedUrl" to pendingText, "shareId" to pendingId)

    fun consume(id: String): Boolean {
        // 新しい共有が届いた場合、前の画面からの確認では消さない。
        if (id != pendingId) return false
        pendingText = null
        pendingId = null
        return true
    }
}
