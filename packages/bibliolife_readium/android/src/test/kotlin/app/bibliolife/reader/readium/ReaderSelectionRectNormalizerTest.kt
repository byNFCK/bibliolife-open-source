package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReaderSelectionRectNormalizerTest {
    private val viewport = ReadiumSelectionRect(0f, 0f, 400f, 800f)

    @Test
    fun `normalizes reversed and partially offscreen geometry after conversion`() {
        val normalized = ReaderSelectionRectNormalizer.normalize(
            ReadiumSelectionRect(450f, 60f, -20f, 20f),
            viewport,
        )
        assertEquals(0f, normalized?.left)
        assertEquals(20f, normalized?.top)
        assertEquals(400f, normalized?.right)
        assertEquals(60f, normalized?.bottom)
    }

    @Test
    fun `rejects nonfinite and empty geometry`() {
        assertNull(ReaderSelectionRectNormalizer.normalize(ReadiumSelectionRect(Float.NaN, 0f, 10f, 10f), viewport))
        assertNull(ReaderSelectionRectNormalizer.normalize(ReadiumSelectionRect(10f, 10f, 10f, 20f), viewport))
    }
}
