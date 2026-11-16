package app.bibliolife.reader.readium

internal object ReaderAnnotationDecorationMapper {
    const val GROUP = "bibliolife-reader-annotations"

    fun decorationId(annotationId: String): String = "annotation:$annotationId"

    fun styleFor(style: String, color: String): ReadiumDecorationStyle? {
        val tint = when (color) {
            "yellow" -> 0x66FDD835
            "green" -> 0x6643A047
            "blue" -> 0x6642A5F5
            "pink" -> 0x66EC407A
            "purple" -> 0x667E57C2
            else -> return null
        }
        return when (style) {
            "highlight" -> ReadiumDecorationStyle.Highlight(tint)
            "underline" -> ReadiumDecorationStyle.Underline(tint or 0xFF000000.toInt())
            else -> null
        }
    }
}
