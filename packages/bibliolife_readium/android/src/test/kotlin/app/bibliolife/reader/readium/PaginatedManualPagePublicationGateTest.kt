package app.bibliolife.reader.readium

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaginatedManualPagePublicationGateTest {
    @Test fun `paginated live identity remains valid while continuous gate is inactive`() {
        val paginated = PaginatedManualPagePublicationGate()
        val continuous = ContinuousManualScrollPublicationGate()
        paginated.activityChanged(active = true, navigationGeneration = 6)
        val identity = paginated.request(
            liveManual = true,
            navigationGeneration = 6,
            navigationInFlight = false,
        )!!

        assertFalse(continuous.active)
        assertTrue(paginated.mayPublish(identity, navigationGeneration = 6, navigationInFlight = false))
    }

    @Test fun `only active manual page samples in current generation are publishable`() {
        val gate = PaginatedManualPagePublicationGate()
        assertNull(gate.request(liveManual = true, navigationGeneration = 4, navigationInFlight = false))

        gate.activityChanged(active = true, navigationGeneration = 4)
        val live = gate.request(liveManual = true, navigationGeneration = 4, navigationInFlight = false)
        assertNotNull(live)
        assertTrue(gate.mayPublish(live!!, navigationGeneration = 4, navigationInFlight = false))
        assertFalse(gate.mayPublish(live, navigationGeneration = 5, navigationInFlight = false))
        assertFalse(gate.mayPublish(live, navigationGeneration = 4, navigationInFlight = true))
    }

    @Test fun `settle rejects old live sample and accepts same-page authoritative final`() {
        val gate = PaginatedManualPagePublicationGate()
        gate.activityChanged(active = true, navigationGeneration = 8)
        val live = gate.request(liveManual = true, navigationGeneration = 8, navigationInFlight = false)!!

        gate.activityChanged(active = false, navigationGeneration = 8)
        val final = gate.request(liveManual = false, navigationGeneration = 8, navigationInFlight = false)!!

        assertFalse(gate.mayPublish(live, navigationGeneration = 8, navigationInFlight = false))
        assertTrue(gate.mayPublish(final, navigationGeneration = 8, navigationInFlight = false))
    }

    @Test fun `navigation cancellation rejects pending settle but permits programmatic path`() {
        val gate = PaginatedManualPagePublicationGate()
        gate.activityChanged(active = true, navigationGeneration = 12)
        val live = gate.request(liveManual = true, navigationGeneration = 12, navigationInFlight = false)!!
        gate.activityChanged(active = false, navigationGeneration = 12)
        val pendingFinal = gate.request(liveManual = false, navigationGeneration = 12, navigationInFlight = false)!!

        assertFalse(gate.reset())
        assertFalse(gate.mayPublish(live, navigationGeneration = 12, navigationInFlight = false))
        assertFalse(gate.mayPublish(pendingFinal, navigationGeneration = 12, navigationInFlight = false))
        assertNull(gate.request(liveManual = true, navigationGeneration = 13, navigationInFlight = true))
    }

    @Test fun `new touch session fences older settled result`() {
        val gate = PaginatedManualPagePublicationGate()
        gate.activityChanged(active = true, navigationGeneration = 20)
        gate.activityChanged(active = false, navigationGeneration = 20)
        val oldFinal = gate.request(liveManual = false, navigationGeneration = 20, navigationInFlight = false)!!

        gate.activityChanged(active = true, navigationGeneration = 20)

        assertFalse(gate.mayPublish(oldFinal, navigationGeneration = 20, navigationInFlight = false))
    }

    @Test fun `owner teardown resets active and pending settle sessions idempotently`() {
        val gate = PaginatedManualPagePublicationGate()
        gate.activityChanged(active = true, navigationGeneration = 30)
        val activeSample = gate.request(liveManual = true, navigationGeneration = 30, navigationInFlight = false)!!

        assertTrue(gate.reset())
        assertFalse(gate.hasSession)
        assertFalse(gate.reset())
        assertFalse(gate.mayPublish(activeSample, navigationGeneration = 30, navigationInFlight = false))

        gate.activityChanged(active = true, navigationGeneration = 30)
        gate.activityChanged(active = false, navigationGeneration = 30)
        val pendingFinal = gate.request(liveManual = false, navigationGeneration = 30, navigationInFlight = false)!!
        assertFalse(gate.reset())
        assertFalse(gate.hasSession)
        assertFalse(gate.mayPublish(pendingFinal, navigationGeneration = 30, navigationInFlight = false))
    }

}
