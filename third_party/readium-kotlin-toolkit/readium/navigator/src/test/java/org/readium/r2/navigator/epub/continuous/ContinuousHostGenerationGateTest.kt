package org.readium.r2.navigator.epub.continuous

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ContinuousHostGenerationGateTest {
    @Test fun `G1 to G2 makes G2 authoritative and rejects late G1`() {
        val gate = ContinuousHostGenerationGate()
        assertTrue(gate.acceptAttach(1)); gate.commitAttach(1)
        assertTrue(gate.acceptAttach(1))
        assertTrue(gate.acceptsDetach(1))
        assertTrue(gate.acceptAttach(2)); gate.commitAttach(2)
        assertEquals(2, gate.activeGeneration)
        assertFalse(gate.acceptAttach(1))
        assertFalse(gate.acceptsDetach(1))
        assertTrue(gate.acceptsDetach(2))
    }

    @Test fun `dispose rejects every future host operation`() {
        val gate = ContinuousHostGenerationGate()
        gate.commitAttach(2)
        gate.dispose()
        assertFalse(gate.acceptAttach(3))
        assertFalse(gate.acceptsDetach(2))
    }
}
