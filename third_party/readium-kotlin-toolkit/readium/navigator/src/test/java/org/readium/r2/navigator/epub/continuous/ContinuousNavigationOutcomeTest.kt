package org.readium.r2.navigator.epub.continuous

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ContinuousNavigationOutcomeTest {
    private fun finalViewport(
        authority: Boolean = true,
        targetGeneration: Boolean = true,
        finalLocator: Boolean = true,
        sameResource: Boolean = true,
        rangeAtAnchor: Boolean? = true,
    ) = classifyContinuousFinalViewport(
        positionApplied = true,
        authorityStillCurrent = authority,
        targetGenerationCurrent = targetGeneration,
        finalLocatorAvailable = finalLocator,
        sameResource = sameResource,
        targetRangeAtReadingAnchor = rangeAtAnchor,
    )

    @Test
    fun `accepted seek with requested range at anchor is verified`() {
        val result = ContinuousNavigationResult(
            11L,
            ContinuousNavigationOutcome.ACCEPTED,
            ContinuousFinalViewportVerification(
                ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT,
                sameResource = true,
                targetRangeAtReadingAnchor = true,
                finalVisibleProgression = 0.42,
                targetProgression = 0.42,
                authorityStillCurrent = true,
            ),
        )

        assertTrue(result.accepted)
        assertEquals(ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT, result.finalViewportVerification.classification)
        assertEquals(ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT, finalViewport())
    }

    @Test
    fun `post position convergence rejection may still verify requested range`() {
        val result = ContinuousNavigationResult(
            12L,
            ContinuousNavigationOutcome.POSITION_APPLIED_BUT_NOT_ACCEPTED,
            ContinuousFinalViewportVerification(
                ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT,
                sameResource = true,
                targetRangeAtReadingAnchor = true,
                finalVisibleProgression = 0.53125,
                targetProgression = 0.534375,
                authorityStillCurrent = true,
            ),
        )

        assertFalse(result.accepted)
        assertEquals(ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT, result.finalViewportVerification.classification)
        assertEquals(ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT, finalViewport())
    }

    @Test
    fun `range mismatch and missing proof never verify`() {
        assertEquals(
            ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT,
            finalViewport(rangeAtAnchor = false),
        )
        assertEquals(
            ContinuousViewportVerification.UNAVAILABLE,
            finalViewport(finalLocator = false, rangeAtAnchor = null),
        )
        assertEquals(
            ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT,
            finalViewport(sameResource = false, rangeAtAnchor = null),
        )
    }

    @Test
    fun `pre position failure and supersession cannot verify`() {
        assertEquals(
            ContinuousViewportVerification.UNAVAILABLE,
            classifyContinuousFinalViewport(
                positionApplied = false,
                authorityStillCurrent = true,
                targetGenerationCurrent = true,
                finalLocatorAvailable = true,
                sameResource = true,
                targetRangeAtReadingAnchor = true,
            ),
        )
        assertEquals(ContinuousViewportVerification.SUPERSEDED, finalViewport(authority = false))
        assertEquals(ContinuousViewportVerification.SUPERSEDED, finalViewport(targetGeneration = false))
    }

    @Test
    fun `current request accepted after position`() {
        val authority = ContinuousNavigationAuthority()
        authority.begin(1L)

        val outcome = authority.outcomeAfterPosition(
            transactionId = 1L,
            targetIsAuthoritative = true,
            accepted = true,
        )

        assertEquals(ContinuousNavigationOutcome.ACCEPTED, outcome)
        assertTrue(ContinuousNavigationResult(1L, outcome).accepted)
    }

    @Test
    fun `pre position failure remains false even after a newer request starts`() {
        val authority = ContinuousNavigationAuthority()
        authority.begin(1L)
        authority.begin(2L)

        val result = ContinuousNavigationResult(
            1L,
            authority.outcomeBeforePosition(),
        )

        assertFalse(authority.isCurrent(1L))
        assertEquals(ContinuousNavigationOutcome.FAILED_BEFORE_POSITION, result.outcome)
        assertFalse(result.accepted)
    }

    @Test
    fun `current request rejected after position`() {
        val authority = ContinuousNavigationAuthority()
        authority.begin(3L)

        assertEquals(
            ContinuousNavigationOutcome.POSITION_APPLIED_BUT_NOT_ACCEPTED,
            authority.outcomeAfterPosition(3L, targetIsAuthoritative = true, accepted = false),
        )
    }

    @Test
    fun `manual drag immediately invalidates active programmatic authority`() {
        val authority = ContinuousNavigationAuthority()
        authority.begin(31L)
        authority.invalidateCurrent()

        assertFalse(authority.isCurrent(31L))
        assertEquals(
            ContinuousNavigationOutcome.SUPERSEDED_AFTER_POSITION,
            authority.outcomeAfterPosition(31L, targetIsAuthoritative = true, accepted = true),
        )
        assertEquals(ContinuousViewportVerification.SUPERSEDED, finalViewport(authority = false))
    }

    @Test
    fun `newer request supersedes after position`() {
        val authority = ContinuousNavigationAuthority()
        authority.begin(4L)
        authority.begin(5L)

        val oldOutcome = authority.outcomeAfterPosition(
            transactionId = 4L,
            targetIsAuthoritative = true,
            accepted = false,
        )

        assertEquals(ContinuousNavigationOutcome.SUPERSEDED_AFTER_POSITION, oldOutcome)
        assertFalse(ContinuousNavigationResult(4L, oldOutcome).accepted)
        assertEquals(ContinuousNavigationOutcome.ACCEPTED, authority.outcomeAfterPosition(5L, true, true))
    }

    @Test
    fun `lost target authority after position is superseded`() {
        val authority = ContinuousNavigationAuthority()
        authority.begin(6L)

        assertEquals(
            ContinuousNavigationOutcome.SUPERSEDED_AFTER_POSITION,
            authority.outcomeAfterPosition(6L, targetIsAuthoritative = false, accepted = false),
        )
    }

    @Test
    fun `stale request cannot change newer request authority or outcome`() {
        val authority = ContinuousNavigationAuthority()
        authority.begin(7L)
        authority.begin(8L)

        val stale = ContinuousNavigationResult(
            7L,
            authority.outcomeAfterPosition(7L, targetIsAuthoritative = true, accepted = true),
        )
        val current = ContinuousNavigationResult(
            8L,
            authority.outcomeAfterPosition(8L, targetIsAuthoritative = true, accepted = true),
        )

        assertEquals(7L, stale.transactionId)
        assertEquals(ContinuousNavigationOutcome.SUPERSEDED_AFTER_POSITION, stale.outcome)
        assertEquals(8L, current.transactionId)
        assertEquals(ContinuousNavigationOutcome.ACCEPTED, current.outcome)
        assertTrue(authority.isCurrent(8L))
    }

    @Test
    fun `boolean compatibility accepts only the accepted outcome`() {
        assertTrue(ContinuousNavigationResult(1L, ContinuousNavigationOutcome.ACCEPTED).accepted)
        assertFalse(ContinuousNavigationResult(1L, ContinuousNavigationOutcome.FAILED_BEFORE_POSITION).accepted)
        assertFalse(ContinuousNavigationResult(1L, ContinuousNavigationOutcome.POSITION_APPLIED_BUT_NOT_ACCEPTED).accepted)
        assertFalse(ContinuousNavigationResult(1L, ContinuousNavigationOutcome.SUPERSEDED_AFTER_POSITION).accepted)
    }
}
