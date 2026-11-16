package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.readium.r2.navigator.epub.continuous.EpubContinuousLocatorAnchor

class ContinuousLocatorDispatchGateTest {
    @Test fun `manual scroll throttle samples immediately and at bounded intervals`() {
        val throttle = ContinuousManualScrollThrottle()

        assertTrue(throttle.shouldSample(1_000))
        assertFalse(throttle.shouldSample(1_124))
        assertTrue(throttle.shouldSample(1_125))
        assertFalse(throttle.shouldSample(1_249))
        assertTrue(throttle.shouldSample(1_250))
    }

    @Test fun `manual scroll throttle can restart for a new gesture`() {
        val throttle = ContinuousManualScrollThrottle()
        assertTrue(throttle.shouldSample(4_000))
        throttle.reset()
        assertTrue(throttle.shouldSample(4_010))
    }

    @Test fun `continuous samples keep active work publishable while newest target coalesces`() {
        val gate = ContinuousManualScrollPublicationGate()
        gate.activityChanged(active = true, currentNavigationGeneration = 7)
        gate.manualDragStarted(currentNavigationGeneration = 7)
        val old = gate.requestIdentity(true, currentNavigationGeneration = 7, navigationInFlight = false)!!
        val newest = gate.requestIdentity(true, currentNavigationGeneration = 7, navigationInFlight = false)!!

        assertTrue(gate.mayPublish(old, currentNavigationGeneration = 7, navigationInFlight = false))
        assertTrue(gate.mayPublish(newest, currentNavigationGeneration = 7, navigationInFlight = false))
    }

    @Test fun `programmatic navigation invalidates live request until a new manual drag`() {
        val gate = ContinuousManualScrollPublicationGate()
        gate.activityChanged(active = true, currentNavigationGeneration = 9)
        gate.manualDragStarted(currentNavigationGeneration = 9)
        val live = gate.requestIdentity(true, currentNavigationGeneration = 9, navigationInFlight = false)!!

        assertFalse(gate.mayPublish(live, currentNavigationGeneration = 10, navigationInFlight = false))
        assertNull(gate.requestIdentity(true, currentNavigationGeneration = 10, navigationInFlight = false))

        gate.manualDragStarted(currentNavigationGeneration = 10)
        val resumed = gate.requestIdentity(true, currentNavigationGeneration = 10, navigationInFlight = false)!!
        assertFalse(gate.mayPublish(live, currentNavigationGeneration = 10, navigationInFlight = false))
        assertTrue(gate.mayPublish(resumed, currentNavigationGeneration = 10, navigationInFlight = false))
    }

    @Test fun `idle epoch rejects late live result while allowing final publication`() {
        val gate = ContinuousManualScrollPublicationGate()
        gate.activityChanged(active = true, currentNavigationGeneration = 12)
        gate.manualDragStarted(currentNavigationGeneration = 12)
        val live = gate.requestIdentity(true, currentNavigationGeneration = 12, navigationInFlight = false)!!

        gate.activityChanged(active = false, currentNavigationGeneration = 12)
        val final = gate.requestIdentity(false, currentNavigationGeneration = 12, navigationInFlight = false)!!
        assertFalse(gate.mayPublish(live, currentNavigationGeneration = 12, navigationInFlight = false))
        assertTrue(gate.mayPublish(final, currentNavigationGeneration = 12, navigationInFlight = false))
    }

    @Test fun `native selection invalidates a preselection viewport locator before it can publish`() {
        val gate = ContinuousSelectionLocatorPublicationGate()
        val preSelectionEpoch = gate.captureEpoch()

        gate.begin(sessionId = 44)

        assertFalse(gate.mayRequest())
        assertFalse(gate.mayPublish(preSelectionEpoch))
    }

    @Test fun `only matching selection end reopens locator publication`() {
        val gate = ContinuousSelectionLocatorPublicationGate()
        gate.begin(sessionId = 44)
        gate.end(sessionId = 45)
        assertFalse(gate.mayRequest())

        gate.end(sessionId = 44)
        val afterSelectionEpoch = gate.captureEpoch()
        assertTrue(gate.mayRequest())
        assertTrue(gate.mayPublish(afterSelectionEpoch))
    }

    @Test fun `scroll burst runs only the active real target then its newest successor`() {
        val gate = ContinuousLocatorDispatchGate<EpubContinuousLocatorAnchor>()
        val first = anchor(generation = 1, y = 100.0)
        val newest = anchor(generation = 1, y = 220.0)

        assertEquals(first, gate.offer(first))
        assertNull(gate.offer(anchor(generation = 1, y = 140.0)))
        assertNull(gate.offer(anchor(generation = 1, y = 180.0)))
        assertNull(gate.offer(newest))

        assertEquals(newest, gate.complete(first))
        assertNull(gate.complete(newest))
    }

    @Test fun `duplicate ready and viewport targets do not create another WebView command`() {
        val gate = ContinuousLocatorDispatchGate<EpubContinuousLocatorAnchor>()
        val target = anchor(generation = 1, y = 555.0)

        assertEquals(target, gate.offer(target))
        assertNull(gate.offer(target))
        assertNull(gate.offer(target))
        assertNull(gate.complete(target))
    }

    @Test fun `recreated generation remains a distinct newest target`() {
        val gate = ContinuousLocatorDispatchGate<EpubContinuousLocatorAnchor>()
        val g1 = anchor(generation = 1, y = 555.0)
        val g2 = anchor(generation = 2, y = 555.0)

        assertEquals(g1, gate.offer(g1))
        assertNull(gate.offer(g2))
        assertEquals(g2, gate.complete(g1))
        assertNull(gate.complete(g2))
    }

    @Test fun `clearing on session disposal removes active and queued work`() {
        val gate = ContinuousLocatorDispatchGate<EpubContinuousLocatorAnchor>()
        gate.offer(anchor(generation = 1, y = 555.0))
        gate.offer(anchor(generation = 1, y = 777.0))

        gate.clear()

        val g2 = anchor(generation = 2, y = 555.0)
        assertEquals(g2, gate.offer(g2))
        assertNull(gate.complete(g2))
    }

    @Test fun `owned final locator cannot be replaced by later viewport requests`() {
        val gate = ContinuousLocatorDispatchGate<DispatchTarget>()
        val running = DispatchTarget("running")
        val final = DispatchTarget(
            "final",
            ProgressNavigationOwner(8, 3, ProgressNavigationOwner.Phase.FINAL),
        )
        val generic = DispatchTarget("generic")

        assertEquals(running, gate.offer(running))
        assertNull(gate.offer(final))
        assertNull(gate.offer(generic))
        assertEquals(final, gate.complete(running))
        assertNull(gate.complete(final))
    }

    @Test fun `active final locator cannot be displaced by a late preview`() {
        val gate = ContinuousLocatorDispatchGate<DispatchTarget>()
        val final = DispatchTarget(
            "final",
            ProgressNavigationOwner(8, 3, ProgressNavigationOwner.Phase.FINAL),
        )
        val preview = DispatchTarget(
            "preview",
            ProgressNavigationOwner(8, 2, ProgressNavigationOwner.Phase.PREVIEW),
        )

        assertEquals(final, gate.offer(final))
        assertNull(gate.offer(preview))
        assertNull(gate.complete(final))
    }

    private data class DispatchTarget(
        val id: String,
        override val owner: ProgressNavigationOwner? = null,
    ) : OwnedContinuousLocatorRequest {
        override fun reject() = Unit
    }

    private fun anchor(generation: Long, y: Double) = EpubContinuousLocatorAnchor(
        readingOrderIndex = 8,
        resourceGeneration = generation,
        layoutGeneration = 3,
        x = 540.0,
        y = y,
    )
}
