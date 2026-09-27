package jp.nogut.ytdlp_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class TaskStore private constructor(context: Context) {
    private val prefs = context.getSharedPreferences("download_history", Context.MODE_PRIVATE)
    private val tasks = mutableListOf<JSONObject>()
    private val main = Handler(Looper.getMainLooper())
    var listener: (() -> Unit)? = null
    init {
        val saved = prefs.getString("tasks", "[]") ?: "[]"
        try {
            val array = JSONArray(saved)
            for (index in 0 until array.length()) {
                val task = array.getJSONObject(index)
                if (task.optString("status") in activeStates) {
                    task.put("status", "interrupted").put("message", "アプリが終了しました。再試行してください。")
                }
                tasks.add(task)
            }
        } catch (e: org.json.JSONException) {
            android.util.Log.e("TaskStore", "履歴データを読み込めません", e)
        }
    }
    @Synchronized
    fun add(options: Map<String, Any?>): String {
        require(tasks.count { it.optString("status") in activeStates } < 20) { "待機中の上限は20件です。" }
        val id = UUID.randomUUID().toString()
        tasks.add(JSONObject(options).put("id", id).put("title", "動画情報を取得中")
            .put("status", "queued").put("progress", 0.0).put("createdAt", System.currentTimeMillis()))
        while (tasks.size > 200) {
            val index = tasks.indexOfFirst { it.optString("status") !in activeStates }
            if (index < 0) break
            tasks.removeAt(index)
        }
        publish()
        return id
    }
    @Synchronized
    fun get(id: String): JSONObject? = tasks.find { it.optString("id") == id }?.let { JSONObject(it.toString()) }
    @Synchronized
    fun next(): JSONObject? = tasks.find { it.optString("status") == "queued" }?.let { JSONObject(it.toString()) }
    @Synchronized
    fun hasActive(): Boolean = tasks.any { it.optString("status") in activeStates }
    @Synchronized
    fun all(): List<Map<String, Any?>> = tasks.map { jsonToMap(it) }
    @Synchronized
    fun update(id: String, changes: Map<String, Any?>) {
        val task = tasks.find { it.optString("id") == id } ?: return
        changes.forEach { (key, value) -> task.put(key, value ?: JSONObject.NULL) }
        publish()
    }
    @Synchronized
    fun interruptQueued() {
        tasks.filter { it.optString("status") == "queued" }.forEach {
            it.put("status", "interrupted").put("message", "Androidの実行制限に達しました。アプリを開いて再試行してください。")
        }
        publish()
    }
    private fun publish() {
        prefs.edit().putString("tasks", JSONArray(tasks).toString()).apply()
        main.post { listener?.invoke() }
    }
    companion object {
        val activeStates = setOf("queued", "running", "processing", "saving")
        @Volatile private var instance: TaskStore? = null
        fun get(context: Context): TaskStore = instance ?: synchronized(this) {
            instance ?: TaskStore(context.applicationContext).also { instance = it }
        }
        fun jsonToMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith {
            when (val value = json.get(it)) {
                JSONObject.NULL -> null
                is JSONObject -> jsonToMap(value)
                is JSONArray -> (0 until value.length()).map { index -> value.get(index) }
                else -> value
            }
        }
    }
}
