package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.*
import org.junit.Test

class ContinuousAppliedLayoutStateTest {
    private fun owner(g: Long) = ContinuousCssMutationOwner(g, g, g, g.toInt(), 1, g)
    private fun measurement(o: ContinuousCssMutationOwner, h: Long) = ResourceLayoutMeasurement(0, h, o.layoutGeneration, 1, o.token, o.measurementEpoch, o.token)

    @Test fun `changed and same height both require current CSS acknowledgement before commit`() {
        val state = ContinuousAppliedLayoutState()
        for ((g, height) in listOf(1L to 700L, 2L to 900L, 3L to 900L)) {
            val current = owner(g)
            assertNull(state.applied(current))
            assertTrue(state.snapshot().pending)
            assertFalse(state.commit(measurement(current, height)))
            assertTrue(state.measured(current.layoutGeneration, 1, current.measurementEpoch, height))
            assertTrue(state.commit(measurement(current, height)))
            assertFalse(state.snapshot().pending)
            assertEquals(current, state.snapshot().committed)
        }
    }

    @Test fun `logical supersession cannot erase applied CSS obligation`() {
        val state = ContinuousAppliedLayoutState()
        val first = owner(1)
        state.applied(first)
        assertTrue(state.snapshot().pending)
        assertEquals(first, state.snapshot().applied)
        val second = owner(2)
        assertEquals(first, state.applied(second))
        assertTrue(state.snapshot().pending)
        assertFalse(state.measured(first.layoutGeneration, 1, first.measurementEpoch, 700))
        assertFalse(state.commit(measurement(first, 700)))
        state.measured(second.layoutGeneration, 1, second.measurementEpoch, 900)
        assertTrue(state.commit(measurement(second, 900)))
        assertFalse(state.snapshot().pending)
    }

    @Test fun `same epoch and same height cannot disguise a superseded CSS token`() {
        val state = ContinuousAppliedLayoutState()
        val first = owner(1)
        val replacement = first.copy(token = 2, preferenceGeneration = 2)
        state.applied(first)
        state.measured(1, 1, 1, 700)
        state.applied(replacement)
        state.measured(1, 1, 1, 700)
        assertFalse(state.commit(measurement(first, 700)))
        assertTrue(state.commit(measurement(replacement, 700)))
    }
}
