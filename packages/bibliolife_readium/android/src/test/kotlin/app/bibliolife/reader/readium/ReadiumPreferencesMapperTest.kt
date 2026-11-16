package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.readium.r2.navigator.preferences.ColumnCount
import org.readium.r2.navigator.preferences.Theme
import org.readium.r2.navigator.preferences.TextAlign

class ReadiumPreferencesMapperTest {
    @Test fun `maps all semantic themes defensively`() {
        assertEquals(MappedReaderTheme.SYSTEM, ReaderPreferencesPayload().toMappedReaderPreferences().theme)
        assertEquals(MappedReaderTheme.LIGHT, ReaderPreferencesPayload(theme = "light").toMappedReaderPreferences().theme)
        assertEquals(MappedReaderTheme.DARK, ReaderPreferencesPayload(theme = "dark").toMappedReaderPreferences().theme)
        assertEquals(MappedReaderTheme.SEPIA, ReaderPreferencesPayload(theme = "sepia").toMappedReaderPreferences().theme)
        assertEquals(MappedReaderTheme.SYSTEM, ReaderPreferencesPayload(theme = "unexpected").toMappedReaderPreferences().theme)
    }

    @Test fun `normalizes numeric values at native boundary`() {
        val low = ReaderPreferencesPayload(fontSize = 0.0, lineHeight = 0.0, pageMargins = -1.0).toMappedReaderPreferences()
        assertEquals(0.5, low.fontSize, 0.0); assertEquals(1.0, low.lineHeight, 0.0); assertEquals(0.0, low.pageMargins, 0.0)
        val high = ReaderPreferencesPayload(fontSize = 4.0, lineHeight = 3.0, pageMargins = 5.0).toMappedReaderPreferences()
        assertEquals(3.0, high.fontSize, 0.0); assertEquals(2.5, high.lineHeight, 0.0); assertEquals(4.0, high.pageMargins, 0.0)
    }

    @Test fun `preserves publisher styles semantics`() {
        assertTrue(ReaderPreferencesPayload(publisherStyles = true).toMappedReaderPreferences().publisherStyles)
        assertFalse(ReaderPreferencesPayload(publisherStyles = false).toMappedReaderPreferences().publisherStyles)
    }

    @Test fun `maps expanded reflowable controls`() {
        val mapped = ReaderPreferencesPayload(
            fontFamily = "sansSerif",
            fontWeight = 1.3,
            textAlignment = "justify",
            scroll = true,
            columns = "two",
        ).toMappedReaderPreferences()
        assertEquals("sans-serif", mapped.fontFamily)
        assertEquals(1.3, mapped.fontWeight, 0.0)
        assertEquals(TextAlign.JUSTIFY, mapped.textAlignment)
        assertTrue(mapped.scroll)
        assertEquals(ColumnCount.TWO, mapped.columns)
        assertNull(ReaderPreferencesPayload().toMappedReaderPreferences().fontFamily)
    }

    @Test fun `generated-source text overrides enable Readium advanced CSS`() {
        val preferences = ReaderPreferencesPayload(
            lineHeight = 1.9,
            textAlignment = "justify",
            columns = "two",
            publisherStyles = false,
        ).toEpubPreferences()
        assertEquals(1.9, preferences.lineHeight!!, 0.0)
        assertEquals(TextAlign.JUSTIFY, preferences.textAlign)
        assertEquals(ColumnCount.TWO, preferences.columnCount)
        assertFalse(preferences.publisherStyles!!)
    }

    @Test fun `complete exposed reflowable matrix reaches EpubPreferences`() {
        val dark = ReaderPreferencesPayload(
            theme = "dark",
            fontFamily = "serif",
            fontSize = 1.25,
            fontWeight = 1.4,
            lineHeight = 1.8,
            pageMargins = 1.6,
            textAlignment = "justify",
            scroll = true,
            columns = "one",
            publisherStyles = false,
        ).toEpubPreferences()

        assertEquals(Theme.DARK, dark.theme)
        assertEquals("serif", dark.fontFamily?.name)
        assertEquals(1.25, dark.fontSize!!, 0.0)
        assertEquals(1.4, dark.fontWeight!!, 0.0)
        assertEquals(1.8, dark.lineHeight!!, 0.0)
        assertEquals(1.6, dark.pageMargins!!, 0.0)
        assertEquals(TextAlign.JUSTIFY, dark.textAlign)
        assertTrue(dark.scroll!!)
        assertEquals(ColumnCount.ONE, dark.columnCount)
        assertFalse(dark.publisherStyles!!)

        assertEquals(Theme.LIGHT, ReaderPreferencesPayload(theme = "light").toEpubPreferences().theme)
        assertEquals(Theme.SEPIA, ReaderPreferencesPayload(theme = "sepia").toEpubPreferences().theme)
        assertEquals(Theme.LIGHT, ReaderPreferencesPayload(theme = "system").toEpubPreferences(false).theme)
        assertEquals(Theme.DARK, ReaderPreferencesPayload(theme = "system").toEpubPreferences(true).theme)
        assertEquals(ColumnCount.AUTO, ReaderPreferencesPayload(columns = "auto").toEpubPreferences().columnCount)
        assertEquals(ColumnCount.TWO, ReaderPreferencesPayload(columns = "two").toEpubPreferences().columnCount)
    }
}
