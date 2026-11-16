package org.readium.r2.navigator.epub.continuous

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ContinuousResourceCallbackGateTest {
    private fun gate() = ContinuousResourceCallbackGate()

    @Test fun `runtime probe uses the unquoted WebView boolean result`() {
        assertFalse(READIUM_RUNTIME_PROBE.contains(".toString()"))
        assertTrue(isReadiumRuntimeProbeSuccess("true"))
        assertFalse(isReadiumRuntimeProbeSuccess("\"true\""))

        val state = ContinuousReadiumBootstrapState(index = 8, generation = 1)
        state.onDocumentFinished(8, 1)
        state.onScriptLoaded(8, 1)
        assertTrue(state.onRuntimeVerified(8, 1, isReadiumRuntimeProbeSuccess("true")))
        assertTrue(state.canRunCommands)
    }

    @Test fun `stale ready resize failure and locator resource generation are rejected`() {
        val gate = gate()
        listOf("ready", "resize", "failure", "locator").forEach {
            assertFalse(gate.accepts(10, 1, 4, 4, 2), it)
        }
    }

    @Test fun `stale layout and released resource are rejected while valid delayed resize is accepted`() {
        val gate = gate()
        assertFalse(gate.accepts(10, 2, 3, 4, 2))
        assertFalse(gate.accepts(10, 2, 4, 4, null))
        assertTrue(gate.accepts(10, 2, 4, 4, 2))
    }

    @Test fun `disposed rendition gate rejects every callback kind`() {
        val gate = gate(); gate.dispose()
        listOf("ready", "resize", "failure", "locator").forEach {
            assertFalse(gate.accepts(10, 2, 4, 4, 2), it)
        }
    }

    @Test fun `Readium commands wait for real bootstrap and stale G1 cannot affect G2`() {
        val g1 = ContinuousReadiumBootstrapState(index = 7, generation = 1)
        assertFalse(g1.canRunCommands)
        assertTrue(g1.onDocumentFinished(7, 1))
        assertFalse(g1.shouldVerifyRuntime)
        assertTrue(g1.onScriptLoaded(7, 1))
        assertTrue(g1.shouldVerifyRuntime)
        assertTrue(g1.onRuntimeVerified(7, 1, readiumExists = true))
        assertTrue(g1.canRunCommands)

        g1.dispose()
        val g2 = ContinuousReadiumBootstrapState(index = 7, generation = 2)
        assertFalse(g2.onScriptLoaded(7, 1), "late G1 ready must not mark G2 ready")
        assertFalse(g2.onScriptFailed(7, 1), "late G1 failure must not invalidate G2")
        assertTrue(g2.onDocumentFinished(7, 2))
        assertTrue(g2.onScriptLoaded(7, 2))
        assertTrue(g2.onRuntimeVerified(7, 2, readiumExists = true))
        assertTrue(g2.canRunCommands)
    }

    @Test fun `resource-ready boundary follows bootstrap success and rejects stale callbacks`() {
        val g1 = ContinuousReadiumBootstrapState(index = 7, generation = 1)
        assertFalse(g1.canRunCommands, "a pre-bootstrap resource cannot produce a Locator")
        assertTrue(g1.onDocumentFinished(7, 1))
        assertTrue(g1.onScriptLoaded(7, 1))
        assertTrue(g1.onRuntimeVerified(7, 1, readiumExists = true))
        assertTrue(g1.canRunCommands, "only this generation may signal Locator readiness")

        g1.dispose()
        val g2 = ContinuousReadiumBootstrapState(index = 7, generation = 2)
        assertFalse(g2.onRuntimeVerified(7, 1, readiumExists = true), "late G1 readiness must not make G2 queryable")
        assertFalse(g2.canRunCommands)
    }

    @Test fun `missing runtime becomes bounded failure with no command capability`() {
        val state = ContinuousReadiumBootstrapState(index = 700, generation = 4)
        state.onDocumentFinished(700, 4)
        state.onScriptLoaded(700, 4)
        assertTrue(state.onRuntimeVerified(700, 4, readiumExists = false))
        assertFalse(state.canRunCommands)
        assertFalse(state.onScriptLoaded(700, 4), "a failed bootstrap cannot restart an invalid command loop")
    }
}
