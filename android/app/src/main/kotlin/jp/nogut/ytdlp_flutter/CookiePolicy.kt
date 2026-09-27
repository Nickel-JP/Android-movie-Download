package jp.nogut.ytdlp_flutter

object CookiePolicy {
    fun parse(content: String): List<String> {
        require(content.startsWith("# Netscape HTTP Cookie File") || content.startsWith("# HTTP Cookie File")) {
            "Netscape形式のCookieファイルを選択してください。"
        }
        val entries = content.lineSequence().filter { it.isNotBlank() && (!it.startsWith('#') || it.startsWith("#HttpOnly_")) }
            .map { line ->
                val fields = line.removePrefix("#HttpOnly_").split('\t')
                require(fields.size == 7 && fields[0].trimStart('.').isNotBlank() &&
                    fields[0].none { it.isWhitespace() || it in "/\\:@" } &&
                    fields[1] in setOf("TRUE", "FALSE") && fields[2].startsWith('/') &&
                    fields[3] in setOf("TRUE", "FALSE") && fields[4].toLongOrNull()?.let { it >= 0 } == true &&
                    fields[5].isNotEmpty()) { "Cookieファイルの形式が不正です。" }
                line
            }.toList()
        require(entries.isNotEmpty()) { "Cookieファイルにデータが含まれていません。" }
        return entries
    }
}
