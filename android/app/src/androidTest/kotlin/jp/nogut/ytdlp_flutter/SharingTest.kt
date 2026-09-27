package jp.nogut.ytdlp_flutter

import android.content.ClipData
import android.content.Intent
import android.text.SpannableString
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class SharingTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val shorts = "https://youtube.com/shorts/-WcGAdKTQGo?si=W9Kfp7wGwafNow9f"
    private fun pythonString(value: String): String = JSONObject.quote(value).replace("\\/", "/")

    @Test fun appIsAnAndroidTextShareTarget() {
        for (mime in listOf("text/plain", "text/html")) {
            val share = Intent(Intent.ACTION_SEND).setType(mime).setPackage(context.packageName)
            val targets = context.packageManager.queryIntentActivities(share, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
            assertTrue(targets.any { it.activityInfo.name == MainActivity::class.java.name && it.activityInfo.exported })
        }
    }

    @Test fun readsTextAndClipDataAndRejectsOtherContent() {
        val inbox = ShareInbox()
        assertTrue(inbox.receive(Intent(Intent.ACTION_SEND).setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, SpannableString("ショート動画\n$shorts"))))
        assertEquals("ショート動画\n$shorts", inbox.snapshot()["sharedUrl"])
        assertTrue(inbox.receive(Intent(Intent.ACTION_SEND).setType("text/html").apply {
            clipData = ClipData.newPlainText("動画", shorts)
        }))
        assertEquals(shorts, inbox.snapshot()["sharedUrl"])
        assertFalse(inbox.receive(Intent(Intent.ACTION_SEND).setType("text/plain")))
        assertFalse(inbox.receive(Intent(Intent.ACTION_VIEW).setType("text/plain").putExtra(Intent.EXTRA_TEXT, shorts)))
        assertFalse(inbox.receive(Intent(Intent.ACTION_SEND).setType("image/jpeg").putExtra(Intent.EXTRA_TEXT, shorts)))
    }

    @Test fun eachShareHasAnIdAndOnlyTheMatchingConfirmationConsumesIt() {
        val inbox = ShareInbox()
        val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, shorts)
        assertTrue(inbox.receive(intent))
        val first = inbox.snapshot()
        assertEquals(first, inbox.snapshot())
        assertTrue(inbox.receive(intent))
        val second = inbox.snapshot()
        assertNotEquals(first["shareId"], second["shareId"])
        assertFalse(inbox.consume(first["shareId"]!!))
        assertEquals(second, inbox.snapshot())
        assertTrue(inbox.consume(second["shareId"]!!))
        assertNull(inbox.snapshot()["sharedUrl"])
    }

    @Test fun bundledYtDlpRecognizesShortsWithoutNetworkAccess() {
        val runtime = NativeRuntime(context)
        runtime.initialize()
        val script = File(context.cacheDir, "shorts-matching-${UUID.randomUUID()}.py")
        try {
            // URLを取得せず、同梱エンジンの形式判定と動画ID抽出だけを確認する。
            script.writeText("import sys\nsys.path.insert(0, ${pythonString(runtime.script.absolutePath)})\n" +
                "from yt_dlp.extractor.youtube import YoutubeIE\n" +
                "url = ${pythonString(shorts)}\n" +
                "assert YoutubeIE.suitable(url)\nassert YoutubeIE._match_id(url) == '-WcGAdKTQGo'\n" +
                "print('__SHORTS_MATCHED__')\n")
            assertTrue(runtime.execute(emptyList(), CancelToken(), script).contains("__SHORTS_MATCHED__"))
        } finally { script.delete() }
    }
}
