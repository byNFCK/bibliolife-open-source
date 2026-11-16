package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.*
import org.junit.Test

class ContinuousGestureReflowBaselineTest {
    private data class Anchor(val id: String, val offset: Int, val targetY: Double, val pointOffset: Double = 17.0)
    private val original = Anchor("dom-7", 42, 556.551)

    @Test fun `start captures once and repeated applies cannot rebase to previous actual`() {
        val baseline = ContinuousGestureReflowBaseline<Anchor>()
        val owner = baseline.begin(1, "fontSize")
        assertTrue(baseline.install(owner, original))
        assertFalse(baseline.install(owner, original.copy(targetY = 556.140)))
        assertSame(original, baseline.anchor)
        assertEquals(owner, baseline.begin(1, "fontSize"))
        assertSame(original, baseline.anchor)
    }

    @Test fun `twenty previews measure independent errors against original gesture target`() {
        val baseline = ContinuousGestureReflowBaseline<Anchor>()
        val owner = baseline.begin(42, "fontSize")
        baseline.install(owner, original)
        val errors = List(20) { if (it % 2 == 0) -0.5 else 0.4 }
        val actuals = errors.map { error ->
            val anchor = requireNotNull(baseline.anchor)
            assertEquals(556.551, anchor.targetY, 0.0)
            assertEquals("dom-7", anchor.id)
            assertEquals(42, anchor.offset)
            val actual = anchor.targetY + error
            assertFalse(baseline.install(owner, anchor.copy(targetY = actual)))
            actual
        }
        actuals.zip(errors).forEach { (actual, error) ->
            assertEquals(error, actual - original.targetY, 0.000001)
            assertTrue(kotlin.math.abs(actual - original.targetY) <= 0.500001)
        }
        assertEquals(0.4, actuals.last() - original.targetY, 0.000001)
    }

    @Test fun `superseded preview and commit lock completion do not release gesture anchor`() {
        val baseline = ContinuousGestureReflowBaseline<Anchor>()
        val owner = baseline.begin(1, "fontSize")
        baseline.install(owner, original)
        // Transaction owners are distinct from this gesture owner. A late end
        // from another gesture cannot release it, regardless of commit status.
        assertFalse(baseline.release(99))
        assertSame(original, baseline.anchor)
        assertTrue(baseline.matches(1, "fontSize"))
    }

    @Test fun `final value uses original anchor until terminal release`() {
        val baseline = ContinuousGestureReflowBaseline<Anchor>()
        baseline.install(baseline.begin(1, "fontSize"), original)
        val finalValueAnchor = baseline.anchor
        assertSame(original, finalValueAnchor)
        assertTrue(baseline.release(1))
        assertNull(baseline.anchor)
        assertNull(baseline.owner)
    }

    @Test fun `new physical gesture and different slider get new capture owners`() {
        val baseline = ContinuousGestureReflowBaseline<Anchor>()
        val old = baseline.begin(1, "fontSize")
        baseline.install(old, original)
        baseline.release(1)
        val next = baseline.begin(2, "fontWeight")
        assertNull(baseline.anchor)
        assertFalse(baseline.install(old, original))
        assertTrue(baseline.install(next, original.copy(id = "dom-8", targetY = 555.9)))
        assertFalse(baseline.release(1))
        assertEquals("dom-8", baseline.anchor?.id)
    }

    @Test fun `manual or unavailable resource invalidation fences a late capture`() {
        val baseline = ContinuousGestureReflowBaseline<Anchor>()
        val oldCapture = baseline.begin(1, "fontSize")
        baseline.invalidate()
        assertNull(baseline.anchor)
        assertFalse(baseline.install(oldCapture, original))
        val freshCapture = requireNotNull(baseline.owner)
        assertTrue(baseline.install(freshCapture, original.copy(targetY = 600.0)))
        assertEquals(600.0, baseline.anchor!!.targetY, 0.0)
    }

    @Test fun `session close and cancellation prevent late capture resurrection`() {
        val baseline = ContinuousGestureReflowBaseline<Anchor>()
        val old = baseline.begin(1, "fontSize")
        baseline.release(1)
        assertFalse(baseline.install(old, original))
        assertNull(baseline.owner)
    }

    @Test fun `delayed begin cannot replace newer gesture or reopen released gesture`() {
        val baseline = ContinuousGestureReflowBaseline<Anchor>()
        val active = baseline.begin(2, "fontSize")
        baseline.install(active, original)
        val stale = baseline.begin(1, "fontWeight")
        assertFalse(baseline.install(stale, original.copy(targetY = 100.0)))
        assertEquals(active, baseline.owner)
        assertSame(original, baseline.anchor)
        assertTrue(baseline.isStale(1, "fontWeight"))
        assertFalse(baseline.isStale(2, "fontSize"))
        baseline.release(2)
        assertFalse(baseline.install(baseline.begin(2, "fontSize"), original))
        assertNull(baseline.owner)
        assertTrue(baseline.isStale(2, "fontSize"))
    }
}
