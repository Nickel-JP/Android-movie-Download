package jp.nogut.ytdlp_flutter

import android.content.Context
import android.system.Os
import android.system.OsConstants
import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit

class CancelToken {
    @Volatile var cancelled = false
    @Volatile var process: Process? = null
    @Volatile var pid: Int? = null
    fun check() { if (cancelled) throw CancellationException("キャンセルしました。") }
    fun cancel() {
        cancelled = true
        val current = process ?: return
        if (!current.isAlive) return
        val root = pid
        if (root != null) {
            try {
                val ps = ProcessBuilder("/system/bin/ps", "-A", "-o", "PID,PPID").start()
                val rows = ps.inputStream.bufferedReader().use { it.readLines() }
                if (!ps.waitFor(2, TimeUnit.SECONDS)) ps.destroyForcibly()
                val relations = rows.mapNotNull {
                    val parts = it.trim().split(Regex("\\s+"))
                    if (parts.size < 2) null else {
                        val child = parts[0].toIntOrNull()
                        val parent = parts[1].toIntOrNull()
                        if (child == null || parent == null) null else child to parent
                    }
                }
                val descendants = mutableListOf<Int>()
                fun collect(parent: Int) {
                    relations.filter { it.second == parent }.forEach {
                        collect(it.first)
                        descendants.add(it.first)
                    }
                }
                collect(root)
                descendants.forEach { child ->
                    try { Os.kill(child, OsConstants.SIGKILL) }
                    catch (e: android.system.ErrnoException) {
                        if (e.errno != OsConstants.ESRCH) Log.w("NativeRuntime", "子プロセスを終了できません", e)
                    }
                }
            } catch (e: Exception) { Log.w("NativeRuntime", "子プロセスの確認に失敗しました", e) }
        }
        current.destroyForcibly()
    }
}

class NativeRuntime(private val context: Context) {
    val base = File(context.noBackupFilesDir, "youtubedl-android")
    val script = File(base, "yt-dlp/yt-dlp")
    private val nativeDir = File(context.applicationInfo.nativeLibraryDir)
    private val pythonHome = File(base, "packages/python/usr")

    fun initialize() {
        YoutubeDL.getInstance().init(context)
        FFmpeg.getInstance().init(context)
        require(File(nativeDir, "libqjs.so").isFile) { "JavaScriptエンジンが見つかりません。APKを確認してください。" }
    }

    fun execute(args: List<String>, token: CancelToken = CancelToken(),
        targetScript: File = script, onLine: (String) -> Unit = {}): String {
        token.check()
        // 固定スクリプトはPIDだけを出力する。URL等はシェル文字列に埋め込まず、位置引数として渡す。
        val command = mutableListOf("/system/bin/sh", "-c",
            "echo __ANDROID_MOVIE_PID__\$\$; exec \"\$@\"", "ytdlp-runner",
            File(nativeDir, "libpython.so").absolutePath, targetScript.absolutePath,
            "--ignore-config", "--no-plugin-dirs", "--no-cache-dir",
            "--js-runtimes", "quickjs:${File(nativeDir, "libqjs.so").absolutePath}",
            "--ffmpeg-location", File(nativeDir, "libffmpeg.so").absolutePath)
        command.addAll(args)
        return run(command, token, onLine = onLine)
    }

    fun executeFfmpeg(args: List<String>, token: CancelToken = CancelToken()): String {
        val command = mutableListOf("/system/bin/sh", "-c",
            "echo __ANDROID_MOVIE_PID__\$\$; exec \"\$@\"", "ffmpeg-runner",
            File(nativeDir, "libffmpeg.so").absolutePath)
        command.addAll(args)
        return run(command, token) {}
    }

    fun executeFfprobe(args: List<String>, token: CancelToken = CancelToken()): String {
        val command = mutableListOf("/system/bin/sh", "-c",
            "echo __ANDROID_MOVIE_PID__\$\$; exec \"\$@\"", "ffprobe-runner",
            File(nativeDir, "libffprobe.so").absolutePath)
        command.addAll(args)
        try {
            return run(command, token, "動画情報の確認に失敗しました") {}
        } catch (e: java.io.IOException) {
            token.check()
            throw IllegalStateException("動画情報の確認中に入出力エラーが発生しました。${e.message.orEmpty()}", e)
        }
    }

    private fun run(command: List<String>, token: CancelToken,
        failureContext: String? = null, onLine: (String) -> Unit): String {
        token.check()
        val builder = ProcessBuilder(command).redirectErrorStream(true)
        builder.environment().apply {
            put("LD_LIBRARY_PATH", "${pythonHome.absolutePath}/lib:${File(base, "packages/ffmpeg/usr/lib").absolutePath}")
            put("SSL_CERT_FILE", "${pythonHome.absolutePath}/etc/tls/cert.pem")
            put("PYTHONHOME", pythonHome.absolutePath)
            put("HOME", context.noBackupFilesDir.absolutePath)
            put("TMPDIR", context.cacheDir.absolutePath)
            put("PATH", "${System.getenv("PATH")}:${nativeDir.absolutePath}")
        }
        val process = builder.start()
        token.process = process
        val output = StringBuilder()
        try {
            process.inputStream.bufferedReader().use { reader ->
                reader.forEachLine { line ->
                    if (line.startsWith("__ANDROID_MOVIE_PID__")) {
                        token.pid = line.removePrefix("__ANDROID_MOVIE_PID__").trim().toInt()
                        if (token.cancelled) token.cancel()
                    } else {
                        token.check()
                        if (output.length + line.length > 8 * 1024 * 1024) error("出力が大きすぎます。")
                        output.appendLine(line)
                        onLine(line)
                    }
                }
            }
            val exitCode = process.waitFor()
            token.check()
            if (exitCode != 0) {
                val detail = output.toString().takeLast(2500).replace(Regex("https?://[^\\s]+"), "[URL]")
                error(if (failureContext == null) detail.ifBlank { "ダウンロードに失敗しました（$exitCode）。" }
                    else "$failureContext（終了コード $exitCode）。\n$detail".trimEnd())
            }
            return output.toString()
        } catch (e: java.io.IOException) {
            // プロセス終了によるストリーム切断も、ユーザーが指示したキャンセルとして扱う。
            if (token.cancelled) throw CancellationException("キャンセルしました。").apply { initCause(e) }
            throw e
        } finally {
            if (process.isAlive) token.cancel()
            listOf(process.inputStream, process.errorStream, process.outputStream).forEach { stream ->
                try { stream.close() }
                catch (e: java.io.IOException) { Log.w("NativeRuntime", "終了済みストリームを閉じられません", e) }
            }
            token.process = null
            token.pid = null
        }
    }
}
