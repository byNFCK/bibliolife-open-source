package app.bibliolife.reader.readium

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgressScrubOwnershipTest {
    private val gate = ProgressScrubOwnership()

    @Test fun `newer preview supersedes an earlier callback immediately`() {
        gate.open(41)
        val first = owner(41, 1, ProgressNavigationOwner.Phase.PREVIEW)
        val latest = owner(41, 2, ProgressNavigationOwner.Phase.PREVIEW)

        assertTrue(gate.reserve(first))
        assertTrue(gate.reserve(latest))
        assertFalse(gate.isCurrent(first))
        assertTrue(gate.isCurrent(latest))
    }

    @Test fun `final request supersedes preview and closes preview admission`() {
        gate.open(41)
        val preview = owner(41, 5, ProgressNavigationOwner.Phase.PREVIEW)
        val final = owner(41, 6, ProgressNavigationOwner.Phase.FINAL)

        assertTrue(gate.reserve(preview))
        assertTrue(gate.reserve(final))
        assertFalse(gate.isCurrent(preview))
        assertTrue(gate.isCurrent(final))
        assertFalse(gate.reserve(owner(41, 7, ProgressNavigationOwner.Phase.PREVIEW)))
        assertFalse(gate.reserve(owner(41, 8, ProgressNavigationOwner.Phase.FINAL)))
    }

    @Test fun `stale session and nonmonotonic request cannot claim current ownership`() {
        gate.open(42)
        val current = owner(42, 3, ProgressNavigationOwner.Phase.PREVIEW)
        assertTrue(gate.reserve(current))

        assertFalse(gate.reserve(owner(41, 99, ProgressNavigationOwner.Phase.FINAL)))
        assertFalse(gate.reserve(owner(42, 2, ProgressNavigationOwner.Phase.PREVIEW)))
        assertTrue(gate.isCurrent(current))
    }

    @Test fun `invalidate rejects delayed final and preview publications`() {
        gate.open(42)
        val preview = owner(42, 1, ProgressNavigationOwner.Phase.PREVIEW)
        val final = owner(42, 2, ProgressNavigationOwner.Phase.FINAL)
        assertTrue(gate.reserve(preview))
        assertTrue(gate.reserve(final))

        assertTrue(gate.invalidate(42))
        assertFalse(gate.isCurrent(preview))
        assertFalse(gate.isCurrent(final))
        assertFalse(gate.invalidate(41))
    }

    @Test fun `closed session cannot be reopened by a delayed old open command`() {
        assertTrue(gate.open(41))
        assertTrue(gate.reserve(owner(41, 1, ProgressNavigationOwner.Phase.PREVIEW)))
        assertTrue(gate.invalidate(41))
        assertTrue(gate.open(42))

        assertFalse(gate.open(41))
        assertFalse(gate.reserve(owner(41, 2, ProgressNavigationOwner.Phase.FINAL)))
        val current = owner(42, 1, ProgressNavigationOwner.Phase.PREVIEW)
        assertTrue(gate.reserve(current))
        assertTrue(gate.isCurrent(current))
    }

    @Test fun `reserved final is idempotent and rejects all previews`() {
        assertTrue(gate.open(43))
        val final = owner(43, 7, ProgressNavigationOwner.Phase.FINAL)

        assertTrue(gate.reserveFinal(final.sessionId, final.requestId) == final)
        assertTrue(gate.reserve(final))
        assertFalse(gate.reserve(owner(43, 8, ProgressNavigationOwner.Phase.PREVIEW)))
        assertTrue(gate.isCurrent(final))
    }

    private fun owner(sessionId: Long, requestId: Long, phase: ProgressNavigationOwner.Phase) =
        ProgressNavigationOwner(sessionId, requestId, phase)
}
