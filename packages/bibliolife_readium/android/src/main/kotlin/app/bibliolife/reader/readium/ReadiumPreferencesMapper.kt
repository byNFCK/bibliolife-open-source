package app.bibliolife.reader.readium

import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.ColumnCount
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.navigator.preferences.Theme

internal enum class MappedReaderTheme { SYSTEM, LIGHT, DARK, SEPIA }

internal data class MappedReaderPreferences(
    val theme: MappedReaderTheme,
    val fontFamily: String?,
    val fontSize: Double,
    val fontWeight: Double,
    val lineHeight: Double,
    val pageMargins: Double,
    val textAlignment: TextAlign,
    val scroll: Boolean,
    val columns: ColumnCount,
    val publisherStyles: Boolean,
)

internal fun ReaderPreferencesPayload.toMappedReaderPreferences() =
    MappedReaderPreferences(
        theme = when (theme) {
            "light" -> MappedReaderTheme.LIGHT
            "dark" -> MappedReaderTheme.DARK
            "sepia" -> MappedReaderTheme.SEPIA
            "system" -> MappedReaderTheme.SYSTEM
            else -> MappedReaderTheme.SYSTEM
        },
        fontFamily = when (fontFamily) {
            "serif" -> "serif"
            "sansSerif" -> "sans-serif"
            "dyslexic" -> "OpenDyslexic"
            "monospace" -> "monospace"
            else -> null
        },
        fontSize = fontSize.coerceIn(0.5, 3.0),
        fontWeight = fontWeight.coerceIn(0.0, 2.5),
        lineHeight = lineHeight.coerceIn(1.0, 2.5),
        pageMargins = pageMargins.coerceIn(0.0, 4.0),
        textAlignment = if (textAlignment == "justify") TextAlign.JUSTIFY else TextAlign.START,
        scroll = scroll,
        columns = when (columns) {
            "one" -> ColumnCount.ONE
            "two" -> ColumnCount.TWO
            else -> ColumnCount.AUTO
        },
        publisherStyles = publisherStyles,
    )

fun ReaderPreferencesPayload.toEpubPreferences(isNightMode: Boolean = false): EpubPreferences =
    toMappedReaderPreferences().toEpubPreferences(isNightMode)

internal fun MappedReaderPreferences.toEpubPreferences(isNightMode: Boolean) = EpubPreferences(
    theme = when (theme) {
        MappedReaderTheme.SYSTEM -> if (isNightMode) Theme.DARK else Theme.LIGHT
        MappedReaderTheme.LIGHT -> Theme.LIGHT
        MappedReaderTheme.DARK -> Theme.DARK
        MappedReaderTheme.SEPIA -> Theme.SEPIA
    },
    fontFamily = fontFamily?.let(::FontFamily),
    fontSize = fontSize,
    fontWeight = fontWeight,
    lineHeight = lineHeight,
    pageMargins = pageMargins,
    textAlign = textAlignment,
    scroll = scroll,
    columnCount = columns,
    publisherStyles = publisherStyles,
)
