package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.readium.r2.shared.publication.Locator

class ContinuousInitialRestoreStartBoundaryTest {
    private val anchor = EpubContinuousLocatorAnchor(
        readingOrderIndex = 0,
        resourceGeneration = 1,
        layoutGeneration = 0,
        x = 540.0,
        y = 555.5,
    )

    @Test fun `first resource at scroll origin verifies the requested zero offset`() {
        val target = ContinuousReflowTarget(0, 0, 1)
        val rangeY = rangeY(offset = 0.0)
        assertEquals(0.0, rangeY)
        assertTrue(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor, true, rangeY == 0.0))
        assertFalse(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor, true, rangeY == 32.0))
    }

    @Test fun `a nearby target stays at its own offset including with viewport padding`() {
        assertEquals(37.5, rangeY(offset = 37.5, top = 24, paddingTop = 24))
        assertNull(rangeY(offset = 555.5, top = 24, paddingTop = 24))
        assertNull(rangeY(offset = 600.0, top = 24, paddingTop = 24))
    }

    @Test fun `short first resource can verify its visible range without a reading anchor inside it`() {
        assertEquals(0.0, rangeY(offset = 0.0, visibleHeight = 350))
        assertNull(rangeY(offset = 350.0, visibleHeight = 350))
        assertNull(rangeY(offset = 0.0, visibleHeight = 0))
    }

    @Test fun `publication start accepts legacy position metadata but preserves stronger locator targets`() {
        val locations = Locator.Locations(progression = 0.0, position = 1, totalProgression = 0.0)
        val text = Locator.Text()
        assertTrue(isInitialRestorePublicationStartLocator(locations, text))
        assertFalse(isInitialRestorePublicationStartLocator(locations.copy(progression = 0.01), text))
        assertFalse(isInitialRestorePublicationStartLocator(locations.copy(fragments = listOf("chapter")), text))
        assertFalse(isInitialRestorePublicationStartLocator(locations, Locator.Text(highlight = "quote")))
        for (key in listOf("cssSelector", "cfi", "partialCfi", "continuousDomAnchor")) {
            assertFalse(isInitialRestorePublicationStartLocator(
                locations.copy(otherLocations = mapOf(key to "target")),
                text,
            ))
        }
    }

    @Test fun `other resources or a viewport away from its start keep normal verification`() {
        assertNull(rangeY(index = 1))
        assertNull(rangeY(top = -40))
        assertNull(rangeY(canScrollTowardStart = true))
        assertNull(rangeY(offset = -1.0))
        assertNull(rangeY(offset = Double.NaN))
    }

    @Test fun `an exact range still requires a current anchor and ready geometry`() {
        val target = ContinuousReflowTarget(0, 0, 1)
        assertFalse(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor, false, true))
        assertFalse(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor.copy(y = 580.0), true, true))
        assertFalse(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor.copy(resourceGeneration = 2), true, true))
    }

    @Test fun `nonzero physical TXT target has a proven upper clamp without replacing its Locator`() {
        val locations = Locator.Locations(progression = 0.033527696793002916, position = 1, totalProgression = 0.01)
        assertTrue(isInitialRestoreTopBoundaryLocator(locations, Locator.Text()))
        assertEquals(231.56250286102295, rangeY(offset = 231.56250286102295))
        assertFalse(isInitialRestoreTopBoundaryLocator(locations.copy(progression = Double.NaN), Locator.Text()))
        assertFalse(isInitialRestoreTopBoundaryLocator(locations.copy(progression = -0.1), Locator.Text()))
        assertFalse(isInitialRestoreTopBoundaryLocator(locations.copy(progression = null), Locator.Text()))
        assertFalse(isInitialRestoreTopBoundaryLocator(locations.copy(otherLocations = mapOf("cssSelector" to "p.other")), Locator.Text()))
        assertFalse(isInitialRestoreTopBoundaryLocator(locations, Locator.Text(highlight = "another point")))
    }

    @Test fun `visibility alone cannot prove top clamp for wrong resource scrolling range or lower boundary`() {
        assertNull(rangeY(index = 1, offset = 231.56)) // wrong resource
        assertNull(rangeY(offset = 231.56, canScrollTowardStart = true)) // visible, but not clamped
        assertNull(rangeY(top = -6501, offset = 231.56, canScrollTowardStart = true)) // lower boundary
        assertNull(rangeY(offset = 3000.0)) // outside viewport
        assertNull(rangeY(offset = 555.5)) // ordinary anchor is attainable
        assertNull(rangeY(offset = Double.NaN)) // unresolved geometry
        assertNull(rangeY(top = 323, offset = 231.56)) // request not consumed/clamped
    }

    private fun rangeY(
        index: Int = 0,
        offset: Double = 0.0,
        top: Int = 0,
        paddingTop: Int = 0,
        visibleHeight: Int = 2222,
        canScrollTowardStart: Boolean = false,
    ): Double? = initialRestoreStartBoundaryRangeY(
        targetIndex = index,
        targetDocumentOffset = offset,
        resourceTopPx = top,
        viewportPaddingTopPx = paddingTop,
        visibleHeightPx = visibleHeight,
        viewportAnchorYPx = anchor.y,
        canScrollTowardStart = canScrollTowardStart,
    )
}
