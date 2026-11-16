package app.bibliolife.reader.readium

import org.junit.Assert.*
import org.junit.Test
import org.readium.r2.navigator.epub.continuous.ContinuousFinalViewportVerification
import org.readium.r2.navigator.epub.continuous.ContinuousViewportVerification

class ProgressScrubDiagnosticsTest {
    private fun evidence(classification: ContinuousViewportVerification) = ContinuousFinalViewportVerification(
        classification, true, false, 0.5, 0.5, true,
    )

    @Test fun equalProgressCannotTurnA10MismatchIntoVerified() {
        val fields = progressVerificationDiagnosticFields(evidence(ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT), 0.7, 3, true)
        assertEquals("mismatch", fields["result"])
        assertEquals(0.0, fields["resourceProgressError"])
        assertEquals(0.7, fields["requestedProgress"])
        assertEquals(3, fields["requestedReadingOrderIndex"])
        assertEquals(false, fields["targetRangeAtReadingAnchor"])
    }

    @Test fun staleOwnerRemainsSupersededEvenWithVerifiedEvidence() {
        val fields = progressVerificationDiagnosticFields(evidence(ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT), 0.7, 3, false)
        assertEquals("superseded", fields["result"])
    }

    @Test fun unavailableEvidenceDoesNotInventObservedProgressOrBookContent() {
        val fields = progressVerificationDiagnosticFields(null, 0.7, null, true)
        assertEquals("failed", fields["result"])
        assertNull(fields["observedProgression"])
        assertFalse(fields.keys.any { it.contains("text", true) || it.contains("html", true) || it.contains("locatorJson", true) })
    }
}
