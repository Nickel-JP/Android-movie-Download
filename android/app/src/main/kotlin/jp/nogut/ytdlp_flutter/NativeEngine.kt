package jp.nogut.ytdlp_flutter

import android.content.Context
import android.app.Application
import android.os.StatFs
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

class NativeEngine private constructor(private val context: Application) {
    val lock = ReentrantLock()
    val runtime = NativeRuntime(context)
    private var initialized = false
    private val tokens = ConcurrentHashMap<String, CancelToken>()
    @Volatile var version = "同梱版"
    val cookieFile = File(context.noBackupFilesDir, "cookies.txt")

    fun initialize() = lock.withLock {
        if (!initialized) {
            runtime.initialize()
            version = runtime.execute(listOf("--version")).trim()
            initialized = true
        }
    }
    private fun common(url: String): List<String> = buildList {
        addAll(listOf("--no-playlist", "--socket-timeout", "30", "--retries", "3", "--fragment-retries", "3"))
        if (cookieFile.isFile) addAll(listOf("--cookies", cookieFile.absolutePath))
        addAll(listOf("--", url))
    }
    private fun metadata(url: String, token: CancelToken): JSONObject {
        val output = runtime.execute(listOf("--dump-single-json", "--skip-download") + common(url), token)
        val jsonLine = output.lineSequence().lastOrNull { it.startsWith("{") } ?: error("動画情報を取得できません。")
        val info = JSONObject(jsonLine)
        require(!info.optBoolean("is_live")) { "現在配信中のライブ動画には対応していません。" }
        require(!info.optBoolean("has_drm")) { "この動画の保存形式には対応していません。" }
        return info
    }
    fun inspect(url: String): Map<String, Any?> = lock.withLock {
        initialize()
        val info = metadata(url, CancelToken())
        val formats = info.optJSONArray("formats")
        var height = 0
        var fps = 0.0
        if (formats != null) for (index in 0 until formats.length()) {
            val f = formats.getJSONObject(index)
            val w = f.optInt("width")
            val h = f.optInt("height")
            height = maxOf(height, if (w > 0 && h > 0) minOf(w, h) else h)
            fps = maxOf(fps, f.optDouble("fps", 0.0))
        }
        val quality = if (height > 0) "配信上限：${height}p" + if (fps > 0) " / ${fps.toInt()}fps" else ""
            else "画質情報は保存後に確認します"
        mapOf("title" to info.optString("title"), "quality" to quality)
    }
    fun cancel(id: String) {
        val token = tokens[id] ?: return
        token.cancelled = true
        Thread({ token.cancel() }, "download-cancel").start()
    }

    fun download(task: JSONObject, report: (Map<String, Any?>) -> Unit,
        publish: (File, CancelToken) -> String): Map<String, Any?> = lock.withLock {
        initialize()
        val id = task.getString("id")
        val token = CancelToken()
        tokens[id] = token
        val workRoot = File(context.getExternalFilesDir(null) ?: context.filesDir, "downloads")
        val job = File(workRoot, id)
        check(job.mkdirs() || job.isDirectory) { "作業フォルダーを作成できません。" }
        try {
            val current = TaskStore.get(context).get(id)
            if (current?.optString("status") == "cancelled") token.cancelled = true
            token.check()
            require(StatFs(workRoot.absolutePath).availableBytes > 256L * 1024 * 1024) { "保存先の空き容量が不足しています。" }
            report(mapOf("status" to "running", "message" to "動画情報を取得しています"))
            val info = metadata(task.getString("url"), token)
            val title = info.optString("title", "動画")
            report(mapOf("title" to title, "message" to "ダウンロード中"))
            val mode = task.getString("mode")
            val format = DownloadPolicy.chooseFormat(info, task.getInt("height"), task.getInt("fps"), mode != "video")
            val args = mutableListOf("--newline", "--no-colors", "--progress", "--progress-delta", "0.5",
                "--progress-template", "download:__PROGRESS__%(progress._percent_str)s",
                "-f", format, "-o", File(job, "%(title).100B [%(id)s].%(ext)s").absolutePath,
                "--print", "after_move:__FILE__%(filepath)s", "--no-simulate")
            if (mode == "video") {
                args.addAll(listOf("--merge-output-format", task.getString("container"), "--remux-video", task.getString("container")))
            } else {
                args.addAll(listOf("-x", "--audio-format", mode))
                if (mode == "mp3") args.addAll(listOf("--audio-quality", "${task.getInt("bitrate")}K"))
                if (mode == "wav") args.addAll(listOf("--postprocessor-args", "ExtractAudio+ffmpeg_o:-c:a pcm_s24le"))
            }
            var outputFile: File? = null
            runtime.execute(args + common(task.getString("url")), token) { line ->
                when {
                    line.startsWith("__PROGRESS__") -> {
                        val percent = Regex("([0-9.]+)%").find(line)?.groupValues?.get(1)?.toDoubleOrNull()
                        if (percent != null) report(mapOf("progress" to percent.coerceIn(0.0, 100.0), "status" to "running"))
                    }
                    line.startsWith("__FILE__") -> outputFile = File(line.removePrefix("__FILE__"))
                    line.startsWith("[Merger]") || line.startsWith("[ExtractAudio]") || line.startsWith("[VideoRemuxer]") ->
                        report(mapOf("status" to "processing", "message" to "映像・音声の結合または変換中"))
                }
            }
            token.check()
            val file = outputFile ?: error("保存対象のファイルが見つかりません。")
            require(file.canonicalPath.startsWith(job.canonicalPath + File.separator) && file.isFile && file.length() > 0) {
                "出力ファイルを確認できません。"
            }
            if (mode == "video" && DownloadPolicy.needsVideoProbe(info, format)) {
                report(mapOf("status" to "processing", "message" to "映像の画質・fpsを確認中"))
                VideoProbe.verify(runtime, file, task.getInt("height"), task.getInt("fps"), token)
            }
            report(mapOf("status" to "saving", "message" to "ダウンロードフォルダーへ保存中"))
            val uri = publish(file, token)
            mapOf("status" to "completed", "progress" to 100.0, "message" to file.name, "outputUri" to uri)
        } finally {
            tokens.remove(id)
            // UUIDで作ったこのジョブの一時ファイルだけを削除する。
            if (job.canonicalPath.startsWith(workRoot.canonicalPath + File.separator) && !job.deleteRecursively()) {
                android.util.Log.w("NativeEngine", "一時ファイルを削除できませんでした")
            }
        }
    }
    companion object {
        @Volatile private var instance: NativeEngine? = null
        fun get(context: Context): NativeEngine = instance ?: synchronized(this) {
            instance ?: NativeEngine(context.applicationContext as Application).also { instance = it }
        }
    }
}
