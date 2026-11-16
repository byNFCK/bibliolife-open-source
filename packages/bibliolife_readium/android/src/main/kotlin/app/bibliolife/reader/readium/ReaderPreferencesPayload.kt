package app.bibliolife.reader.readium

data class ReaderPreferencesPayload(
    val theme: String = "system",
    val fontFamily: String = "original",
    val fontSize: Double = 1.0,
    val fontWeight: Double = 1.0,
    val lineHeight: Double = 1.5,
    val pageMargins: Double = 1.0,
    val textAlignment: String = "start",
    val scroll: Boolean = false,
    val columns: String = "auto",
    val publisherStyles: Boolean = true,
) {
    fun toChannelMap(): Map<String, Any> = mapOf(
        "theme" to theme,
        "fontFamily" to fontFamily,
        "fontSize" to fontSize,
        "fontWeight" to fontWeight,
        "lineHeight" to lineHeight,
        "pageMargins" to pageMargins,
        "textAlignment" to textAlignment,
        "scroll" to scroll,
        "columns" to columns,
        "publisherStyles" to publisherStyles,
    )

    companion object {
        private val themes = setOf("system", "light", "dark", "sepia")
        private val fontFamilies = setOf("original", "serif", "sansSerif", "dyslexic", "monospace")
        private val alignments = setOf("start", "justify")
        private val columnCounts = setOf("auto", "one", "two")

        fun fromChannelValue(value: Any?): ReaderPreferencesPayload? =
            (value as? Map<*, *>)?.let(::fromMap)

        fun fromMap(map: Map<*, *>): ReaderPreferencesPayload = ReaderPreferencesPayload(
            theme = (map["theme"] as? String)?.takeIf { it in themes } ?: "system",
            fontFamily = (map["fontFamily"] as? String)?.takeIf { it in fontFamilies } ?: "original",
            fontSize = number(map["fontSize"], 1.0, .5, 3.0),
            fontWeight = number(map["fontWeight"], 1.0, 0.0, 2.5),
            lineHeight = number(map["lineHeight"], 1.5, 1.0, 2.5),
            pageMargins = number(map["pageMargins"], 1.0, 0.0, 4.0),
            textAlignment = (map["textAlignment"] as? String)?.takeIf { it in alignments } ?: "start",
            scroll = map["scroll"] as? Boolean ?: false,
            columns = (map["columns"] as? String)?.takeIf { it in columnCounts } ?: "auto",
            publisherStyles = map["publisherStyles"] as? Boolean ?: true,
        )

        private fun number(value: Any?, fallback: Double, low: Double, high: Double): Double {
            val number = (value as? Number)?.toDouble() ?: return fallback
            return if (number.isFinite()) number.coerceIn(low, high) else fallback
        }
    }
}
