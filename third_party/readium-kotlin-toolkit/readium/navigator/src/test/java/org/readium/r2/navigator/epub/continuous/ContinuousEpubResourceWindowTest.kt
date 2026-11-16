package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ContinuousEpubResourceWindowTest {
    private data class Resource(val index: Int, val generation: Long)

    private class Fixture {
        val created = mutableListOf<Resource>()
        val released = mutableListOf<Resource>()
        val window = ContinuousEpubResourceWindow(
            create = { index, generation -> Resource(index, generation).also(created::add) },
            release = released::add,
        )
        fun reconcile(visible: Set<Int>, candidates: Sequence<Int>) = window.reconcile(visible, candidates)
    }

    @Test fun `preload ownership is strictly capped while every visible resource is retained`() {
        val fixture = Fixture()
        fixture.reconcile((20..39).toSet(), (0..99).asSequence())
        assertEquals((20..39).toSet(), fixture.window.states().filterValues { it == ContinuousEpubResourceWindow.State.LIVE_VISIBLE }.keys)
        assertEquals(8, fixture.window.nonVisibleUnpinnedLiveCount())
        assertEquals(28, fixture.window.liveIndices().size)
    }

    @Test fun `visible resource keeps both adjacent seam resources live before crossing`() {
        val fixture = Fixture()
        fixture.reconcile(setOf(10), sequenceOf(9, 11, 8, 12))
        assertEquals(ContinuousEpubResourceWindow.State.LIVE_VISIBLE, fixture.window.states().getValue(10))
        assertEquals(ContinuousEpubResourceWindow.State.LIVE_PRELOAD, fixture.window.states().getValue(9))
        assertEquals(ContinuousEpubResourceWindow.State.LIVE_PRELOAD, fixture.window.states().getValue(11))
    }

    @Test fun `initial visible target has no offscreen WebView preload work`() {
        val fixture = Fixture()

        // Startup supplies no preload candidates until the first real viewport
        // has been revealed, so only the visible restore target is materialized.
        fixture.reconcile(setOf(10), emptySequence())

        assertEquals(setOf(10), fixture.window.liveIndices())
        assertEquals(0, fixture.window.nonVisibleUnpinnedLiveCount())
    }

    @Test fun `moving through 100 500 and 1000 resources never leaks visited real resources`() {
        listOf(100, 500, 1_000).forEach { count ->
            val fixture = Fixture()
            var peak = 0
            listOf(0, count / 10, count / 2, (count * 7) / 10, count - 1).forEach { target ->
                fixture.reconcile(setOf(target), candidateOrder(target, count))
                peak = maxOf(peak, fixture.window.liveIndices().size)
                assertTrue(fixture.window.nonVisibleUnpinnedLiveCount() <= 8)
            }
            assertTrue(peak <= 9)
            assertTrue(fixture.released.isNotEmpty())
            assertTrue(fixture.window.liveIndices().size <= 9)
        }
    }

    @Test fun `target 700 prepares no prefix resource`() {
        val fixture = Fixture()
        fixture.reconcile(setOf(700), (701 until 1_000).asSequence())
        assertTrue(700 in fixture.window.liveIndices())
        assertFalse((0..699).any { it in fixture.window.liveIndices() })
        assertTrue(fixture.window.nonVisibleUnpinnedLiveCount() <= 8)
    }

    @Test fun `pinned distant resource survives then is explicitly released after unpin`() {
        val fixture = Fixture()
        fixture.reconcile(setOf(0), candidateOrder(0, 100))
        val first = fixture.window.resourceAt(0)!!
        fixture.window.pin(0, ContinuousResourcePinReason.SELECTION)
        fixture.reconcile(setOf(80), candidateOrder(80, 100))
        assertEquals(first, fixture.window.resourceAt(0))
        assertEquals(ContinuousEpubResourceWindow.State.LIVE_PINNED, fixture.window.states().getValue(0))
        fixture.window.unpin(0, ContinuousResourcePinReason.SELECTION)
        fixture.reconcile(setOf(80), candidateOrder(80, 100))
        assertFalse(0 in fixture.window.liveIndices())
        assertTrue(first in fixture.released)
    }

    @Test fun `selection unpin preserves an unrelated resource pin reason`() {
        val fixture = Fixture()
        fixture.reconcile(setOf(0), candidateOrder(0, 100))
        val selected = fixture.window.resourceAt(0)!!
        fixture.window.pin(0, ContinuousResourcePinReason.SELECTION)
        fixture.window.pin(0, ContinuousResourcePinReason.NAVIGATION_TARGET)

        fixture.reconcile(setOf(80), candidateOrder(80, 100))
        fixture.window.unpin(0, ContinuousResourcePinReason.SELECTION)
        fixture.reconcile(setOf(80), candidateOrder(80, 100))

        assertEquals(selected, fixture.window.resourceAt(0))
        assertEquals(ContinuousEpubResourceWindow.State.LIVE_PINNED, fixture.window.states().getValue(0))
        fixture.window.unpin(0, ContinuousResourcePinReason.NAVIGATION_TARGET)
        fixture.reconcile(setOf(80), candidateOrder(80, 100))
        assertFalse(0 in fixture.window.liveIndices())
    }

    @Test fun `eviction gives a recreated resource a new generation and stale binding cannot return`() {
        val fixture = Fixture()
        fixture.reconcile(setOf(10), candidateOrder(10, 100))
        val old = fixture.window.resourceAt(10)!!
        fixture.reconcile(setOf(90), candidateOrder(90, 100))
        assertTrue(old in fixture.released)
        fixture.reconcile(setOf(10), candidateOrder(10, 100))
        val recreated = fixture.window.resourceAt(10)!!
        assertNotEquals(old.generation, recreated.generation)
        assertEquals(recreated.generation, fixture.window.generationAt(10))
    }

    @Test fun `reconciliation is idempotent and permanent disposal releases all real resources`() {
        val fixture = Fixture()
        fixture.reconcile(setOf(10), candidateOrder(10, 100))
        val count = fixture.created.size
        fixture.reconcile(setOf(10), candidateOrder(10, 100))
        assertEquals(count, fixture.created.size)
        fixture.window.disposeAll()
        assertTrue(fixture.window.liveIndices().isEmpty())
        assertEquals(count, fixture.released.size)
    }

    @Test fun `released resource lifecycle cannot be resurrected by a stale holder callback`() {
        val fixture = Fixture()
        fixture.reconcile(setOf(42), candidateOrder(42, 100))
        val first = fixture.window.resourceAt(42)!!
        fixture.reconcile(setOf(90), candidateOrder(90, 100))
        assertTrue(first in fixture.released)
        assertFalse(42 in fixture.window.liveIndices())
        // A holder callback only observes the registry; it cannot acquire A.
        assertEquals(null, fixture.window.resourceAt(42))
        fixture.reconcile(setOf(42), candidateOrder(42, 100))
        assertNotEquals(first.generation, fixture.window.resourceAt(42)!!.generation)
    }

    @Test fun `all three simultaneous resources share one owner while eviction is resource local`() {
        val fixture = Fixture()
        fixture.reconcile(setOf(10, 11, 12), candidateOrder(11, 100))
        val a = fixture.window.resourceAt(10)!!
        val b = fixture.window.resourceAt(11)!!
        val c = fixture.window.resourceAt(12)!!
        fixture.reconcile(setOf(80), candidateOrder(80, 100))
        assertTrue(a in fixture.released)
        assertTrue(b in fixture.released)
        assertTrue(c in fixture.released)
        assertTrue(fixture.window.liveIndices().isNotEmpty())
    }

    @Test fun `local resource operation explicitly targets A or B and rejects stale or non live identity`() {
        val fixture = Fixture()
        fixture.reconcile(setOf(1, 2), emptySequence())
        val a = fixture.window.resourceAt(1)!!
        val b = fixture.window.resourceAt(2)!!
        assertEquals(a, fixture.window.withLiveResource(1, a.generation) { it })
        assertEquals(b, fixture.window.withLiveResource(2, b.generation) { it })
        fixture.reconcile(setOf(2), emptySequence())
        assertEquals(null, fixture.window.withLiveResource(1, a.generation) { it })
        fixture.reconcile(setOf(1, 2), emptySequence())
        val recreatedA = fixture.window.resourceAt(1)!!
        assertEquals(null, fixture.window.withLiveResource(1, a.generation) { it })
        assertEquals(recreatedA, fixture.window.withLiveResource(1, recreatedA.generation) { it })
    }

    private fun candidateOrder(target: Int, size: Int): Sequence<Int> = sequence {
        var distance = 1
        while (target - distance >= 0 || target + distance < size) {
            (target - distance).takeIf { it >= 0 }?.let { yield(it) }
            (target + distance).takeIf { it < size }?.let { yield(it) }
            distance++
        }
    }
}
