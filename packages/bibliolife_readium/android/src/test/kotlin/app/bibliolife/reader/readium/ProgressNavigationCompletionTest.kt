package app.bibliolife.reader.readium

import org.junit.Assert.*
import org.junit.Test
import org.readium.r2.navigator.epub.continuous.*

class ProgressNavigationCompletionTest {
    private fun navigation(
        outcome: ContinuousNavigationOutcome = ContinuousNavigationOutcome.POSITION_APPLIED_BUT_NOT_ACCEPTED,
        classification: ContinuousViewportVerification = ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT,
        current: Boolean = true,
    ) = ContinuousNavigationResult(7, outcome, ContinuousFinalViewportVerification(
        classification, true, true, .47360001, .4736, current,
    ))

    @Test fun `three repeated trace cases commit A10 evidence despite legacy Boolean rejection`() {
        for (previewId in 1..3) {
            val result = navigation()
            assertFalse(result.accepted)
            assertEquals("preview $previewId", ProgressNavigationCompletion.COMMITTED,
                progressNavigationCompletion(result, true, true))
        }
    }

    @Test fun `final publication failure is completed navigation with separate bridge metadata`() {
        assertEquals(ProgressNavigationCompletion.COMMITTED, progressNavigationCompletion(navigation(), true, true))
        assertTrue(ReadiumReaderSession.NavigationResult.CompletedWithPublicationFailure.accepted)
        assertEquals(ReadiumPlatformViewNavigationResult.CompletedWithPublicationFailure,
            ReadiumReaderSession.NavigationResult.CompletedWithPublicationFailure.toPlatformResult())
    }

    @Test fun `mismatch missing target unavailable and incoherent evidence cannot commit`() {
        assertEquals(ProgressNavigationCompletion.FAILED, progressNavigationCompletion(null, false, true))
        for (classification in listOf(ContinuousViewportVerification.UNAVAILABLE, ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT))
            assertEquals(ProgressNavigationCompletion.FAILED, progressNavigationCompletion(navigation(classification = classification), true, true))
        val bad = navigation().let { it.copy(finalViewportVerification = it.finalViewportVerification.copy(targetRangeAtReadingAnchor = false)) }
        assertEquals(ProgressNavigationCompletion.FAILED, progressNavigationCompletion(bad, true, true))
    }

    @Test fun `superseded manual invalidation and stale result never commit`() {
        assertEquals(ProgressNavigationCompletion.SUPERSEDED,
            progressNavigationCompletion(navigation(outcome = ContinuousNavigationOutcome.SUPERSEDED_AFTER_POSITION), true, true))
        assertEquals(ProgressNavigationCompletion.FAILED,
            progressNavigationCompletion(navigation(outcome = ContinuousNavigationOutcome.FAILED_BEFORE_POSITION), true, true))
        assertEquals(ProgressNavigationCompletion.SUPERSEDED, progressNavigationCompletion(navigation(), true, false))
        assertEquals(ProgressNavigationCompletion.SUPERSEDED, progressNavigationCompletion(navigation(), false, true))
        assertEquals(ProgressNavigationCompletion.SUPERSEDED,
            progressNavigationCompletion(navigation(classification = ContinuousViewportVerification.SUPERSEDED), true, true))
        assertEquals(ProgressNavigationCompletion.FAILED, progressNavigationCompletion(navigation(current = false), true, true))
    }

    @Test fun `normalization retains invalid rejection and does not reinterpret resource as slider`() {
        for (invalid in listOf(Double.NaN, Double.POSITIVE_INFINITY, -.1, 1.1))
            assertNull(ReadiumReaderSession.normalizeRequestedProgression(invalid))
        assertEquals(.2765, ReadiumReaderSession.normalizeRequestedProgression(.2765)!!, 0.0)
        // A10 compares local .4736 with local .47360001; total .2755 and slider .2765
        // are metadata, never alternative local-progression thresholds.
        val result = navigation()
        assertEquals(.4736, result.finalViewportVerification.targetProgression!!, 0.0)
        assertEquals(ProgressNavigationCompletion.COMMITTED, progressNavigationCompletion(result, true, true))
    }
}
