package jp.nogut.ytdlp_flutter

import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

object GithubHttp {
    private val hosts = setOf("api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")
    private fun connection(raw: String): HttpURLConnection {
        var url = URL(raw)
        repeat(6) {
            require(url.protocol == "https" && url.host in hosts && url.userInfo == null && url.port == -1) { "更新先が不正です。" }
            val connection = url.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 30_000
            connection.readTimeout = 60_000
            connection.setRequestProperty("User-Agent", "Android-movie-Download")
            val status = connection.responseCode
            if (status in listOf(301, 302, 303, 307, 308)) {
                val location = connection.getHeaderField("Location") ?: error("更新先の転送情報がありません。")
                connection.disconnect()
                url = URL(url, location)
            } else {
                if (status != 200) { connection.disconnect(); error("更新を確認できませんでした（HTTP $status）。") }
                return connection
            }
        }
        error("更新先の転送回数が多すぎます。")
    }
    fun text(url: String): String {
        val connection = connection(url)
        try {
            return connection.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(output.size() + count <= 1024 * 1024) { "更新情報が大きすぎます。" }
                    output.write(buffer, 0, count)
                }
                output.toString("UTF-8")
            }
        } finally { connection.disconnect() }
    }
    fun download(url: String, file: File, limit: Long = 40L * 1024 * 1024): String {
        val connection = connection(url)
        val digest = MessageDigest.getInstance("SHA-256")
        var size = 0L
        try {
            connection.inputStream.use { input -> file.outputStream().use { output ->
                val buffer = ByteArray(256 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    size += read
                    require(size <= limit) { "更新ファイルが大きすぎます。" }
                    digest.update(buffer, 0, read)
                    output.write(buffer, 0, read)
                }
            } }
            require(size > 0) { "更新ファイルが空です。" }
            return digest.digest().joinToString("") { "%02x".format(it) }
        } finally { connection.disconnect() }
    }
}
