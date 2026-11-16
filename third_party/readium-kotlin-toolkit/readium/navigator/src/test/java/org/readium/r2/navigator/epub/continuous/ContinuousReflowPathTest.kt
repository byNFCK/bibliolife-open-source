package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.*
import org.junit.Test

class ContinuousReflowPathTest {
    @Test fun `same height and exact stable anchor uses no op within unchanged tolerance`() {
        for (delta in listOf(0.0, -0.15, 0.5, 3.9, -4.0)) {
            assertEquals(ContinuousReflowPath.NO_OP, continuousReflowPath(true, true, true, delta))
        }
    }
    @Test fun `same height and moved exact anchor uses only anchor correction`() {
        assertEquals(ContinuousReflowPath.ANCHOR_ONLY, continuousReflowPath(true, true, true, 12.0))
    }
    @Test fun `changed current or predecessor geometry cannot use fast paths even if net delta cancels`() {
        assertEquals(ContinuousReflowPath.FULL_REFLOW, continuousReflowPath(true, true, false, 0.0))
    }
    @Test fun `unknown exact identity and invalid or stale measurement use existing full path`() {
        assertEquals(ContinuousReflowPath.FULL_REFLOW, continuousReflowPath(true, false, true, 0.0))
        assertEquals(ContinuousReflowPath.FULL_REFLOW, continuousReflowPath(false, true, true, 0.0))
        assertEquals(ContinuousReflowPath.FULL_REFLOW, continuousReflowPath(true, true, true, Double.NaN))
    }
    @Test fun `mechanical zero epsilon is separate from semantic anchor tolerance`() {
        for (delta in listOf(0.0, 0.49, -0.49, 0.5, -0.5)) assertFalse(continuousAnchorScrollRequired(delta))
        assertTrue(continuousAnchorScrollRequired(0.6))
        assertTrue(continuousAnchorScrollRequired(-12.0))
        assertTrue(continuousAnchorViewportMatches(3.9))
        assertTrue(continuousAnchorScrollRequired(3.9))
    }

    @Test fun `logical same height batch acknowledgement is committed without full apply admission`() {
        val target = ContinuousReflowTarget(0, 2, 3)
        val batch = ContinuousGeometryMeasurementBatch(ContinuousGeometryBatchOwner(4, 5, 2), target, mapOf(0 to 3L))
        assertFalse(batch.acknowledgeUnchangedGeometry())
        batch.collect(ResourceLayoutMeasurement(0, 1200, 2, 3, 6, 7, 8))
        assertFalse(batch.markApplied())
        assertTrue(batch.acknowledgeUnchangedGeometry())
        assertTrue(batch.markCommitted())
        assertFalse(batch.acknowledgeUnchangedGeometry())
    }

    @Test fun `unchanged layout acknowledgement does not relax normal changed-height barrier`() {
        val target = ContinuousReflowTarget(0, 2, 3)
        val barrier = ContinuousReflowTargetBarrier()
        assertFalse(barrier.markUnchangedGeometry(target, 5) { true })
        barrier.markReady(target)
        assertFalse(barrier.markUnchangedGeometry(target.copy(resourceGeneration = 4), 5) { true })
        assertFalse(barrier.markUnchangedGeometry(target, 5) { false })
        assertTrue(barrier.markUnchangedGeometry(target, 5) { true })
        assertTrue(barrier.isReady(target))
        barrier.markMeasured(target, 5)
        barrier.markAttachedLayouts(5) { true }
        assertFalse(barrier.isReady(target))
        barrier.markAttachedLayouts(6) { true }
        assertTrue(barrier.isReady(target))
    }
}
