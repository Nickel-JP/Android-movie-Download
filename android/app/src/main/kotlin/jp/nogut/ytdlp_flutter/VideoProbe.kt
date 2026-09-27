package jp.nogut.ytdlp_flutter

import java.io.File

object VideoProbe {
    data class Geometry(val width: Int, val height: Int, val fps: Double?)

    fun parse(output: String): Geometry {
        val line = output.lineSequence().firstOrNull { "Video:" in it && "Stream #" in it }
            ?: error("映像を確認できません。音声URLの場合はMP3またはWAVを選択してください。")
        val size = Regex("\\b(\\d{2,6})x(\\d{2,6})\\b").find(line)
            ?: error("保存した映像の画質を確認できません。")
        val fps = Regex("\\b(\\d+(?:\\.\\d+)?) fps\\b").find(line)?.groupValues?.get(1)?.toDoubleOrNull()
        return Geometry(size.groupValues[1].toInt(), size.groupValues[2].toInt(), fps)
    }

    fun verify(runtime: NativeRuntime, file: File, height: Int, fps: Int, token: CancelToken) {
        val output = runtime.executeFfmpeg(listOf("-hide_banner", "-i", file.absolutePath,
            "-map", "0:v:0", "-frames:v", "1", "-an", "-sn", "-dn", "-f", "null", "-"), token)
        val geometry = parse(output)
        require(minOf(geometry.width, geometry.height) <= height && (geometry.fps == null || geometry.fps <= fps + 0.01)) {
            "この映像は指定した画質・fpsの上限を超えています。元の配信形式に上限内の映像がありません。"
        }
    }
}
