package app.bibliolife.reader.readium

/** Stable highlight palette identifiers shared by the native menu and typed bridge. */
internal enum class ReaderHighlightColor(val storageValue: String) {
    Yellow("yellow"),
    Green("green"),
    Blue("blue"),
    Pink("pink");

    companion object {
        fun fromStorageValue(value: String): ReaderHighlightColor? =
            entries.firstOrNull { it.storageValue == value }
    }
}
