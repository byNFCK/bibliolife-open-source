package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProgressNavigationModelTest {
    private fun target(index: Int, total: Int, position: Int, progression: Double? = null) =
        ProgressNavigationTarget(index, total, null, "chapter-$index.xhtml", position, progression, progression)

    @Test fun `empty positions are unavailable`() {
        assertNull(ProgressNavigationModel.targetAtSliderValue(emptyList(), 0f))
        assertEquals(0, ProgressNavigationModel.currentIndex(emptyList(), ProgressLocationSnapshot(null, null, null, null)))
    }

    @Test fun `slider maps first last and middle canonical items`() {
        val targets = listOf(target(0, 3, 1), target(1, 3, 203), target(2, 3, 204))
        assertEquals(1, ProgressNavigationModel.targetAtSliderValue(targets, 0f)?.logicalPosition)
        assertEquals(203, ProgressNavigationModel.targetAtSliderValue(targets, 1f)?.logicalPosition)
        assertEquals(204, ProgressNavigationModel.targetAtSliderValue(targets, 2f)?.logicalPosition)
    }

    @Test fun `display position is never the zero based slider index`() {
        val targets = (1..230).map { position -> target(position - 1, 230, position) }
        assertEquals(1, ProgressNavigationModel.displayPosition(targets[0]))
        assertEquals(2, ProgressNavigationModel.displayPosition(targets[1]))
        assertEquals(228, ProgressNavigationModel.displayPosition(targets[227]))
        assertEquals(229, ProgressNavigationModel.displayPosition(targets[228]))
        assertEquals(228, targets[227].logicalPosition)
        assertEquals(229, targets[228].logicalPosition)
    }

    @Test fun `slider conversion rounds drift once and clamps`() {
        assertEquals(203, ProgressNavigationModel.sliderValueToIndex(202.999f, 300))
        assertEquals(0, ProgressNavigationModel.sliderValueToIndex(-4f, 3))
        assertEquals(2, ProgressNavigationModel.sliderValueToIndex(99f, 3))
    }

    @Test fun `current index prefers exact synthetic position then href progression`() {
        val targets = listOf(target(0, 3, 1, 0.0), target(1, 3, 203, 0.5), target(2, 3, 204, 1.0))
        assertEquals(1, ProgressNavigationModel.currentIndex(targets, ProgressLocationSnapshot(null, 203, null, null)))
        assertEquals(2, ProgressNavigationModel.currentIndex(targets, ProgressLocationSnapshot("chapter-2.xhtml", null, 1.0, null)))
    }

    @Test fun `confirmation detects exact and nearest positions without index offset`() {
        val selected = target(1, 3, 203)
        assertEquals(ProgressNavigationConfirmation.Exact, ProgressNavigationModel.confirmation(selected, ProgressLocationSnapshot(null, 203, null, null)))
        assertEquals(ProgressNavigationConfirmation.NearestAvailable, ProgressNavigationModel.confirmation(selected, ProgressLocationSnapshot(null, 204, null, null)))
    }

    @Test fun `canonical grouping preserves first publication group and lowest progression locator`() {
        val canonical = ProgressNavigationModel.canonicalTargets(
            listOf(
                ProgressPositionCandidate(null, "one-late", 1, 0.8, 0.1),
                ProgressPositionCandidate(null, "one-early", 1, 0.1, 0.1),
                ProgressPositionCandidate(null, "missing", null, null, null),
                ProgressPositionCandidate(null, "two", 2, 0.0, 0.2),
                ProgressPositionCandidate(null, "invalid", 0, 0.0, 0.0),
            ),
        )
        assertEquals(2, canonical.size)
        assertEquals("one-early", canonical[0].href)
        assertEquals(1, canonical[0].logicalPosition)
        assertEquals("two", canonical[1].href)
        assertEquals(2, canonical[1].logicalPosition)
    }

    @Test fun `material locator equality ignores insignificant progression jitter`() {
        val first = ProgressLocationSnapshot("chapter", 203, 0.2, 0.4)
        val jitter = ProgressLocationSnapshot("chapter", 203, 0.20001, 0.40001)
        val next = ProgressLocationSnapshot("chapter", 204, 0.0, 0.41)
        assertEquals(true, ProgressNavigationModel.materiallySame(first, jitter))
        assertEquals(false, ProgressNavigationModel.materiallySame(first, next))
    }

    @Test fun `pre navigation replay is ignored but changed locator is retained`() {
        val pre = ProgressLocationSnapshot("chapter", 203, 0.2, 0.4)
        assertEquals(true, ProgressNavigationModel.isPreNavigationReplay(pre, ProgressLocationSnapshot("chapter", 203, 0.2, 0.4)))
        assertEquals(false, ProgressNavigationModel.isPreNavigationReplay(pre, ProgressLocationSnapshot("chapter", 204, 0.0, 0.41)))
    }
}
