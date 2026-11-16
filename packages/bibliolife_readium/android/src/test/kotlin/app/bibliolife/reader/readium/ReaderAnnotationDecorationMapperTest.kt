package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Test

class ReaderAnnotationDecorationMapperTest {
    @Test
    fun `maps stable IDs every supported style and color`() {
        val styles = listOf("highlight", "underline")
        val colors = listOf("yellow", "green", "blue", "pink", "purple")
        for (style in styles) for (color in colors) {
            val decorationStyle = requireNotNull(ReaderAnnotationDecorationMapper.styleFor(style, color))
            assertEquals("annotation:id", ReaderAnnotationDecorationMapper.decorationId("id"))
            assertEquals(
                if (style == "highlight") ReadiumDecorationStyle.Highlight::class else ReadiumDecorationStyle.Underline::class,
                decorationStyle::class,
            )
        }
    }

    @Test
    fun `rejects unknown styles and colors safely`() {
        assertEquals(null, ReaderAnnotationDecorationMapper.styleFor("unknown", "yellow"))
        assertEquals(null, ReaderAnnotationDecorationMapper.styleFor("highlight", "unknown"))
    }
}
