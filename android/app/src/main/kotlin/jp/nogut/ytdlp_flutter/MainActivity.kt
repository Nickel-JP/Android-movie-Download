package jp.nogut.ytdlp_flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import kotlin.concurrent.withLock

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var cookieResult: MethodChannel.Result? = null
    private var sharedUrl: String? = null
    private var pendingUpdate: Pair<String, Int>? = null
    private lateinit var store: TaskStore
    private lateinit var engine: NativeEngine

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        store = TaskStore.get(this)
        engine = NativeEngine.get(this)
        readShare(intent)
        store.listener = { eventSink?.success(state()) }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "jp.nogut.ytdlp/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    events?.success(state())
                }
                override fun onCancel(arguments: Any?) { eventSink = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jp.nogut.ytdlp/methods")
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun state(): Map<String, Any?> {
        val info = packageManager.getPackageInfo(packageName, 0)
        return mapOf("tasks" to store.all(), "engineVersion" to engine.version,
            "appVersion" to info.versionName, "versionCode" to info.longVersionCode.toInt(),
            "hasCookies" to engine.cookieFile.isFile, "sharedUrl" to sharedUrl)
    }
    private fun background(result: MethodChannel.Result, action: () -> Any?) {
        worker.submit {
            try {
                val value = action()
                main.post { result.success(value) }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "要求の処理に失敗しました", e)
                main.post { result.error("OPERATION_FAILED", e.message ?: "処理に失敗しました。", null) }
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "state" -> {
                    val snapshot = state()
                    sharedUrl = null
                    result.success(snapshot)
                }
                "initialize" -> background(result) { engine.initialize(); engine.version }
                "inspect" -> background(result) {
                    val options = mapOf("url" to call.argument<String>("url"), "mode" to "video",
                        "height" to 2160, "fps" to 60, "bitrate" to 320, "container" to "mp4")
                    DownloadPolicy.validate(options)
                    engine.inspect(options["url"] as String)
                }
                "enqueue" -> {
                    val options = DownloadPolicy.validate(call.arguments as Map<String, Any?>)
                    val id = store.add(options)
                    try { startDownloads() } catch (e: Exception) {
                        store.update(id, mapOf("status" to "failed", "message" to "バックグラウンド処理を開始できません。再試行してください。"))
                        throw e
                    }
                    result.success(id)
                }
                "retry" -> {
                    val id = call.argument<String>("id") ?: error("履歴が見つかりません。")
                    val task = store.get(id) ?: error("履歴が見つかりません。")
                    require(task.optString("status") !in TaskStore.activeStates && task.optString("status") != "completed") { "この履歴は再試行できません。" }
                    val options = DownloadPolicy.validate(TaskStore.jsonToMap(task))
                    val newId = store.add(options.filterKeys { it in setOf("url", "mode", "height", "fps", "bitrate", "container") })
                    try { startDownloads() } catch (e: Exception) {
                        store.update(newId, mapOf("status" to "failed", "message" to "保存処理を開始できません。"))
                        throw e
                    }
                    result.success(newId)
                }
                "cancel" -> {
                    val id = call.argument<String>("id") ?: error("履歴が見つかりません。")
                    val task = store.get(id) ?: error("履歴が見つかりません。")
                    if (task.optString("status") in TaskStore.activeStates) {
                        store.update(id, mapOf("status" to "cancelled", "message" to "キャンセルしました"))
                        engine.cancel(id)
                    }
                    result.success(null)
                }
                "openFile" -> {
                    val uri = Uri.parse(call.argument<String>("uri") ?: error("ファイルが見つかりません。"))
                    require(uri.scheme == "content" && uri.authority == "media") { "保存済みのファイルを指定してください。" }
                    val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, contentResolver.getType(uri))
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    startActivity(Intent.createChooser(intent, "ファイルを開く"))
                    result.success(null)
                }
                "updateDirectory" -> {
                    val folder = File(cacheDir, "updates")
                    require(folder.mkdirs() || folder.isDirectory) { "更新用フォルダーを作成できません。" }
                    result.success(folder.absolutePath)
                }
                "installUpdate" -> background(result) {
                    require(!store.hasActive()) { "ダウンロード完了後に更新してください。" }
                    val path = call.argument<String>("path") ?: error("更新ファイルがありません。")
                    val code = call.argument<Int>("versionCode") ?: error("更新情報がありません。")
                    validateUpdate(path, code)
                    main.post {
                        if (packageManager.canRequestPackageInstalls()) openInstaller(path)
                        else {
                            pendingUpdate = path to code
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")))
                        }
                    }
                    if (packageManager.canRequestPackageInstalls()) "インストール確認画面を開きます" else "このアプリからのインストールを許可してください"
                }
                "updateEngine" -> background(result) { EngineUpdater.update(applicationContext) }
                "importCookies" -> {
                    require(!store.hasActive()) { "ダウンロード完了後に設定してください。" }
                    require(cookieResult == null) { "ファイル選択中です。" }
                    cookieResult = result
                    try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }, COOKIE_REQUEST) } catch (e: Exception) { cookieResult = null; throw e }
                }
                "removeCookies" -> background(result) {
                    engine.lock.withLock {
                        require(!store.hasActive()) { "ダウンロード完了後に設定してください。" }
                        require(!engine.cookieFile.exists() || engine.cookieFile.delete()) { "Cookieを削除できません。" }
                    }
                    null
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("INVALID_REQUEST", e.message ?: "要求を確認してください。", null) }
    }

    private fun startDownloads() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 502)
        }
        startForegroundService(Intent(this, DownloadService::class.java))
    }

    private fun validateUpdate(path: String, expectedCode: Int) {
        val file = File(path)
        require(file.canonicalPath.startsWith(File(cacheDir, "updates").canonicalPath + File.separator) && file.isFile) { "更新ファイルの場所が不正です。" }
        val archive = packageManager.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES)
            ?: error("APKを確認できません。")
        val installed = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        require(archive.packageName == packageName && archive.longVersionCode == expectedCode.toLong() &&
            archive.longVersionCode > installed.longVersionCode) { "更新対象のアプリ・バージョンが一致しません。" }
        val current = installed.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet()
        val incoming = archive.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet()
        require(!current.isNullOrEmpty() && current == incoming) { "アプリの署名が一致しません。更新を中止しました。" }
    }
    private fun openInstaller(path: String) {
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.files", File(path))
            startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        } catch (e: Exception) {
            android.widget.Toast.makeText(this, "インストール確認画面を開けません：${e.message}", android.widget.Toast.LENGTH_LONG).show()
        }
    }
    override fun onResume() {
        super.onResume()
        val update = pendingUpdate ?: return
        pendingUpdate = null
        if (packageManager.canRequestPackageInstalls()) {
            try { validateUpdate(update.first, update.second); openInstaller(update.first) }
            catch (e: Exception) { android.widget.Toast.makeText(this, e.message, android.widget.Toast.LENGTH_LONG).show() }
        }
    }
    private fun readShare(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            sharedUrl = intent.getStringExtra(Intent.EXTRA_TEXT)
            eventSink?.success(mapOf("type" to "share", "url" to sharedUrl))
        }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); readShare(intent) }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != COOKIE_REQUEST) return
        val result = cookieResult ?: return
        cookieResult = null
        if (resultCode != RESULT_OK || data?.data == null) { result.success(null); return }
        val uri = data.data!!
        background(result) {
            engine.lock.withLock {
                require(!store.hasActive()) { "ダウンロード完了後に設定してください。" }
                val content = contentResolver.openInputStream(uri)?.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        require(output.size() + read <= 1024 * 1024) { "Cookieファイルの上限は1MBです。" }
                        output.write(buffer, 0, read)
                    }
                    output.toString("UTF-8")
                } ?: error("Cookieファイルを開けません。")
                require(content.startsWith("# Netscape HTTP Cookie File") || content.startsWith("# HTTP Cookie File")) { "Netscape形式のCookieファイルを選択してください。" }
                val allowed = content.lineSequence().filter { line ->
                    if (line.isBlank() || (line.startsWith("#") && !line.startsWith("#HttpOnly_"))) false
                    else {
                        val columns = line.removePrefix("#HttpOnly_").split('\t')
                        val domain = columns.firstOrNull()?.trimStart('.') ?: ""
                        columns.size == 7 && listOf("youtube.com", "google.com", "nicovideo.jp").any {
                            domain == it || domain.endsWith(".$it")
                        }
                    }
                }.toList()
                require(allowed.isNotEmpty()) { "対応サイトのCookieが含まれていません。" }
                val temporary = File(engine.cookieFile.parentFile, "cookies.tmp")
                temporary.writeText("# Netscape HTTP Cookie File\n" + allowed.joinToString("\n") + "\n")
                require(temporary.renameTo(engine.cookieFile)) { "Cookieファイルを保存できません。" }
                "Cookieを取り込みました"
            }
        }
    }
    override fun onDestroy() {
        if (::store.isInitialized) store.listener = null
        eventSink = null
        cookieResult?.error("CANCELLED", "ファイル選択を中止しました。", null)
        cookieResult = null
        worker.shutdown()
        super.onDestroy()
    }
    companion object { private const val COOKIE_REQUEST = 501 }
}
