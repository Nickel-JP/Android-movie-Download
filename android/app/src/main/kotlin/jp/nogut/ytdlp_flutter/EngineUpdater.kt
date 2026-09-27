package jp.nogut.ytdlp_flutter

import android.content.Context
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.withLock

object EngineUpdater {
    fun update(context: Context): String {
        val engine = NativeEngine.get(context)
        return engine.lock.withLock {
            require(!TaskStore.get(context).hasActive()) { "ダウンロード完了後に更新してください。" }
            engine.initialize()
            val release = JSONObject(GithubHttp.text("https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"))
            val tag = release.getString("tag_name")
            require(Regex("[A-Za-z0-9._-]+").matches(tag)) { "更新バージョンが不正です。" }
            if (tag == engine.version) return@withLock "yt-dlpは最新版です（$tag）"
            val root = "https://github.com/yt-dlp/yt-dlp/releases/download/$tag/"
            val sums = GithubHttp.text(root + "SHA2-256SUMS")
            val expected = sums.lineSequence().map { it.trim().split(Regex("\\s+")) }
                .firstOrNull { it.size == 2 && it[1].removePrefix("*") == "yt-dlp" }?.first()
                ?: error("yt-dlpの検証情報が見つかりません。")
            require(Regex("[a-fA-F0-9]{64}").matches(expected)) { "検証情報が不正です。" }
            val candidate = File(engine.runtime.script.parentFile, "yt-dlp.new")
            val backup = File(engine.runtime.script.parentFile, "yt-dlp.previous")
            try {
                val actual = GithubHttp.download(root + "yt-dlp", candidate)
                require(actual.equals(expected, true)) { "yt-dlp更新ファイルの検証に失敗しました。" }
                val version = engine.runtime.execute(listOf("--version"), targetScript = candidate).trim()
                require(version == tag) { "更新バージョンが一致しません。" }
                require(!backup.exists() || backup.delete()) { "更新用バックアップを準備できません。" }
                require(engine.runtime.script.renameTo(backup)) { "現在のエンジンを退避できません。" }
                if (!candidate.renameTo(engine.runtime.script)) {
                    check(backup.renameTo(engine.runtime.script)) { "エンジンの復元に失敗しました。アプリを再起動してください。" }
                    error("エンジンを更新できません。")
                }
                if (!backup.delete()) android.util.Log.w("EngineUpdater", "旧エンジンの削除を次回更新時に再試行します")
                engine.version = version
                "yt-dlpを $version に更新しました"
            } finally { if (candidate.exists() && !candidate.delete()) android.util.Log.w("EngineUpdater", "更新用一時ファイルを削除できません") }
        }
    }
}
