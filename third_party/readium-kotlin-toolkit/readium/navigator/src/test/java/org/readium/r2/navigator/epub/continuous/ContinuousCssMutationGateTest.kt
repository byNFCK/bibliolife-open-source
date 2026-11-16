package org.readium.r2.navigator.epub.continuous

import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContinuousCssMutationGateTest {
    @Test fun `queued old script is rejected after owner revocation`() {
        val gate = ContinuousCssMutationGate()
        gate.activate(11)
        assertTrue(gate.isCurrent(11))
        gate.revoke(11)
        assertFalse(gate.begin(11))
        assertFalse(gate.isCurrent(11))
    }

    @Test fun `revocation waits for a setter already inside the JS gate`() = runBlocking {
        val gate = ContinuousCssMutationGate()
        gate.activate(21)
        assertTrue(gate.begin(21))
        val drain = gate.revoke(21)
        assertFalse(drain.isCompleted)
        val waiter = async { drain.await(); "terminal" }
        assertFalse(waiter.isCompleted)
        gate.end(21)
        assertEquals("terminal", waiter.await())
        assertFalse(gate.begin(21))
    }

    @Test fun `revocation drains every synchronous mutation section`() {
        val gate = ContinuousCssMutationGate()
        gate.activate(31)
        assertTrue(gate.begin(31))
        gate.end(31)
        assertTrue(gate.begin(31))
        val drain = gate.revoke(31)
        assertFalse(drain.isCompleted)
        gate.end(31)
        assertTrue(drain.isCompleted)
    }

    @Test fun `new owner rejects old completion while allowing current owner`() {
        val gate = ContinuousCssMutationGate()
        gate.activate(41)
        assertTrue(gate.begin(41))
        gate.activate(42)
        assertFalse(gate.begin(41))
        assertTrue(gate.begin(42))
        gate.end(41)
        assertTrue(gate.isCurrent(42))
        val drain = gate.revoke(42)
        gate.end(42)
        assertTrue(drain.isCompleted)
    }

    @Test fun `late cancellation of old owner cannot revoke successor`() {
        val gate = ContinuousCssMutationGate()
        gate.activate(61)
        assertTrue(gate.begin(61))
        gate.activate(62)
        assertTrue(gate.begin(62))
        gate.revoke(61)
        assertTrue(gate.isCurrent(62))
        assertTrue(gate.begin(62))
        gate.end(61)
        gate.end(62)
        gate.end(62)
    }

    @Test fun `guarded script checks lease immediately before setter and always ends it`() {
        val script = guardedReadiumCssScript("{\"font-size\":\"120%\"}", 51)
        assertTrue(script.indexOf("beginCssMutation(51)") < script.indexOf("readium.setCSSProperties"))
        assertTrue(script.indexOf("gate.cssApplied(51)") > script.indexOf("readium.setCSSProperties"))
        assertTrue(script.contains("finally { gate.endCssApply(51); }"))
        assertTrue(script.contains("return false"))
    }

    @Test fun `setter admission creates obligation until corresponding geometry commits`() {
        val gate = ContinuousCssMutationGate()
        gate.activate(71)
        assertFalse(gate.hasMutationObligation(71))
        assertTrue(gate.beginMutation(71))
        gate.end(71)
        assertTrue(gate.hasMutationObligation(71))
        gate.geometryCommitted(71)
        assertFalse(gate.hasMutationObligation(71))
    }

    @Test fun `measurement section alone does not create CSS mutation obligation`() {
        val gate = ContinuousCssMutationGate()
        gate.activate(81)
        assertTrue(gate.begin(81))
        gate.end(81)
        assertFalse(gate.hasMutationObligation(81))
    }
}
