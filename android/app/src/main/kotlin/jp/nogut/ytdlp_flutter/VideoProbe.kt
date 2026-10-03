package jp.nogut.ytdlp_flutter

import org.json.JSONException
import org.json.JSONObject
import java.io.File

object VideoProbe {
    data class Geometry(val width: Int, val height: Int, val fps: Double?)

    fun parse(output: String): Geometry {
        val info = try { JSONObject(output) }
        catch (e: JSONException) {
            throw IllegalStateException("動画情報の確認に失敗しました。解析結果を読み取れませんでした。", e)
        }
        info.optJSONObject("error")?.let {
            val detail = it.optString("string", "不明なエラー").take(1000)
                .replace(Regex("https?://[^\\s]+"), "[URL]")
            error("動画情報の確認に失敗しました。$detail")
        }
        val streams = info.optJSONArray("streams")
            ?: error("動画情報の確認に失敗しました。映像情報が含まれていません。")
        val stream = streams.optJSONObject(0)
            ?: error("映像を確認できません。音声URLの場合はMP3またはWAVを選択してください。")
        val width = stream.optInt("width")
        val height = stream.optInt("height")
        check(width > 0 && height > 0) { "保存した映像の画質を確認できません。" }
        val fps = parseFrameRate(stream.optString("avg_frame_rate"))
            ?: parseFrameRate(stream.optString("r_frame_rate"))
        return Geometry(width, height, fps)
    }

    fun verify(runtime: NativeRuntime, file: File, height: Int, fps: Int, token: CancelToken) {
        token.check()
        require(file.isFile && file.length() > 0) { "動画情報の確認に失敗しました。保存したファイルがありません。" }
        // 大文字Vはカバー画像を除外する。デコードせず、ローカル映像の寸法とfpsだけを調べる。
        // ランナーは標準出力・標準エラーを結合するため、診断もJSONに限定する。
        val output = runtime.executeFfprobe(listOf("-v", "quiet", "-show_error",
            "-select_streams", "V:0", "-show_entries", "stream=width,height,avg_frame_rate,r_frame_rate",
            "-of", "json", "-i", file.absolutePath), token)
        checkLimits(parse(output), height, fps)
    }

    internal fun checkLimits(geometry: Geometry, height: Int, fps: Int) {
        require(minOf(geometry.width, geometry.height) <= height && (geometry.fps == null || geometry.fps <= fps + 0.01)) {
            "この映像は指定した画質・fpsの上限を超えています。元の配信形式に上限内の映像がありません。"
        }
    }

    private fun parseFrameRate(value: String): Double? {
        val parts = value.trim().split('/')
        val numerator = parts.firstOrNull()?.toDoubleOrNull() ?: return null
        val rate = when (parts.size) {
            1 -> numerator
            2 -> {
                val denominator = parts[1].toDoubleOrNull() ?: return null
                if (denominator <= 0) return null
                numerator / denominator
            }
            else -> return null
        }
        return rate.takeIf { it.isFinite() && it > 0 }
    }
}
