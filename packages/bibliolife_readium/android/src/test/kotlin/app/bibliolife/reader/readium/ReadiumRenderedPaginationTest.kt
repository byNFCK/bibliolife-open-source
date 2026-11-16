package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadiumRenderedPaginationTest {
    @Test fun `rendered page state is zero based finite and clamped by construction`() {
        val state = ReadiumRenderedPageState.create(3, 7, 4, publicationScoped = true)
        assertEquals(3, state?.index)
        assertEquals(7, state?.count)
        assertEquals(0.5, state?.progression ?: -1.0, 0.0)
        assertTrue(state?.publicationScoped == true)
        assertNull(ReadiumRenderedPageState.create(-1, 7, 4, true))
        assertNull(ReadiumRenderedPageState.create(7, 7, 4, true))
        assertNull(ReadiumRenderedPageState.create(0, 0, 4, true))
    }

    @Test fun `single resource progression preserves every requested slider value`() {
        val values = listOf(0.0, 0.1, 0.25, 0.5, 0.76, 0.9, 1.0)
        val actual = values.map(::continuousProgressionLocations)
        assertEquals(values, actual.map { it?.progression })
        assertEquals(values, actual.map { it?.totalProgression })
        assertNull(continuousProgressionLocations(Double.NaN))
        assertNull(continuousProgressionLocations(1.01))
    }

    @Test fun `twenty rendered pages expose the full continuous range`() {
        val pages = listOf(0, 4, 9, 10, 15, 19)
        val progressions = pages.map {
            ReadiumRenderedPageState.create(it, 20, 0, true)!!.progression
        }
        assertEquals(listOf(0.0, 4.0 / 19, 9.0 / 19, 10.0 / 19, 15.0 / 19, 1.0), progressions)
        assertTrue(progressions.distinct().size > 3)
    }

    @Test fun `rendered target maps requested progression through page intervals`() {
        val target = renderedPageTarget(0.76, 20)
        assertEquals(0.76, target?.requestedProgression ?: -1.0, 0.0)
        assertEquals(14, target?.pageIndex)
        assertEquals(20, target?.pageCount)
    }
}
