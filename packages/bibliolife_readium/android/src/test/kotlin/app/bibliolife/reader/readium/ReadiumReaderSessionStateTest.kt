package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.continuous.ContinuousNavigationOutcome
import org.readium.r2.navigator.epub.continuous.ContinuousNavigationResult
import org.readium.r2.navigator.epub.continuous.ContinuousFinalViewportVerification
import org.readium.r2.navigator.epub.continuous.ContinuousViewportVerification
import org.readium.r2.navigator.epub.continuous.EpubContinuousReflowDiagnosticEvent
import org.readium.r2.navigator.epub.continuous.EpubContinuousViewportLayoutSnapshot
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ReadiumReaderSessionStateTest {
    @Test fun `progress terminal authority is revoked by manual drag and newer generation`() {
        val state = restoredNavigator()
        val first = assertGranted(state.beginNavigation())
        assertTrue(state.isCurrentContinuousNavigation(first.generation))
        state.invalidateContinuousNavigationAuthority()
        assertFalse(state.isCurrentContinuousNavigation(first.generation))
        state.completeNavigation(first.generation)
        val second = assertGranted(state.beginNavigation())
        assertTrue(state.isCurrentContinuousNavigation(second.generation))
        assertFalse(state.isCurrentContinuousNavigation(first.generation))
        state.dispose()
        assertFalse(state.isCurrentContinuousNavigation(second.generation))
    }
    @Test fun `initialize starts only once`() {
        val state = ReadiumReaderSessionState()
        assertTrue(state.start())
        assertFalse(state.start())
        assertEquals(ReadiumReaderSessionState.Phase.OPENING_PUBLICATION, state.phase)
    }

    @Test fun `duplicate initialize cannot open publication twice`() {
        val state = ReadiumReaderSessionState()
        state.start()
        assertTrue(state.publicationOpened())
        assertFalse(state.publicationOpened())
    }

    @Test fun `publication success advances session state`() {
        val state = ReadiumReaderSessionState()
        state.start()
        assertTrue(state.publicationOpened())
        assertEquals(ReadiumReaderSessionState.Phase.PUBLICATION_OPENED, state.phase)
    }

    @Test fun `continuous pending follows publication opening without attaching a navigator`() {
        val state = readyToAttach()
        assertTrue(state.continuousRenditionPending())
        assertEquals(ReadiumReaderSessionState.Phase.CONTINUOUS_RENDITION_PENDING, state.phase)
        assertFalse(state.navigatorAttached(reusedRestoredNavigator = false))
        assertEquals(ReadiumNavigationGate.NotReady, state.beginNavigation())
    }

    @Test fun `continuous pending disposal is safe and idempotent`() {
        val state = readyToAttach()
        state.continuousRenditionPending()
        assertTrue(state.dispose())
        assertFalse(state.dispose())
        assertEquals(ReadiumReaderSessionState.Phase.DISPOSED, state.phase)
    }

    @Test fun `publication failure produces error state`() {
        val state = ReadiumReaderSessionState()
        state.start()
        assertTrue(state.fail())
        assertEquals(ReadiumReaderSessionState.Phase.FAILED, state.phase)
    }

    @Test fun `navigator attachment occurs only once`() {
        val state = readyToAttach()
        assertTrue(state.navigatorAttached(reusedRestoredNavigator = false))
        assertFalse(state.navigatorAttached(reusedRestoredNavigator = false))
    }

    @Test fun `existing restored navigator is marked for reuse`() {
        val state = readyToAttach()
        assertTrue(state.navigatorAttached(reusedRestoredNavigator = true))
        assertTrue(state.reusedRestoredNavigator)
        assertTrue(state.navigatorReady())
        assertEquals(ReadiumReaderSessionState.Phase.NAVIGATOR_READY, state.phase)
    }

    @Test fun `initial locator restoration occurs only once`() {
        val state = readyNavigator()
        assertTrue(state.initialLocatorRestored())
        assertFalse(state.initialLocatorRestored())
    }

    @Test fun `callbacks after disposal are ignored`() {
        val state = readyNavigator()
        state.dispose()
        assertFalse(state.initialLocatorRestored())
        assertFalse(state.navigatorReady())
        assertFalse(state.isActive())
    }

    @Test fun `dispose is idempotent`() {
        val state = ReadiumReaderSessionState()
        assertTrue(state.dispose())
        assertFalse(state.dispose())
        assertEquals(ReadiumReaderSessionState.Phase.DISPOSED, state.phase)
    }

    @Test fun `locator observation starts once after initial restoration`() {
        val state = restoredNavigator()
        assertTrue(state.startLocatorObservation())
        assertFalse(state.startLocatorObservation())
    }

    @Test fun `navigation before ready is rejected`() {
        val state = readyNavigator()
        assertEquals(ReadiumNavigationGate.NotReady, state.beginNavigation())
    }

    @Test fun `navigation after disposal is rejected`() {
        val state = restoredNavigator()
        state.dispose()
        assertEquals(ReadiumNavigationGate.Disposed, state.beginNavigation())
    }

    @Test fun `navigation commands are serialized`() {
        val state = restoredNavigator()
        val first = assertGranted(state.beginNavigation())
        assertEquals(ReadiumNavigationGate.Busy, state.beginNavigation())
        assertTrue(state.completeNavigation(first.generation))
        assertGranted(state.beginNavigation())
    }

    @Test fun `continuous result is recorded only for the matching active navigation`() {
        val state = restoredNavigator()
        val first = assertGranted(state.beginNavigation())
        val accepted = verifiedResult(first.generation)

        assertTrue(state.recordContinuousNavigationResult(accepted, first.generation))
        assertEquals(accepted, state.latestContinuousNavigationResult)
    }

    @Test fun `stale continuous result cannot overwrite newer navigation outcome`() {
        val state = restoredNavigator()
        val first = assertGranted(state.beginNavigation())
        assertTrue(state.completeNavigation(first.generation))
        val second = assertGranted(state.beginNavigation())
        val stale = verifiedResult(first.generation)
        val current = ContinuousNavigationResult(
            second.generation,
            ContinuousNavigationOutcome.POSITION_APPLIED_BUT_NOT_ACCEPTED,
            verifiedViewport(),
        )

        assertFalse(state.recordContinuousNavigationResult(stale, second.generation))
        assertTrue(state.recordContinuousNavigationResult(current, second.generation))
        assertEquals(current, state.latestContinuousNavigationResult)
    }

    @Test fun `drag before result recording rejects current programmatic authority`() {
        val state = restoredNavigator()
        val navigation = assertGranted(state.beginNavigation())
        state.invalidateContinuousNavigationAuthority()

        assertFalse(state.recordContinuousNavigationResult(verifiedResult(navigation.generation), navigation.generation))
        assertEquals(null, state.latestContinuousNavigationResult)
        assertTrue(state.completeNavigation(navigation.generation))
    }

    @Test fun `drag after result recording invalidates verification before idle`() {
        val state = restoredNavigator()
        val navigation = assertGranted(state.beginNavigation())
        assertTrue(state.recordContinuousNavigationResult(verifiedResult(navigation.generation), navigation.generation))

        state.invalidateContinuousNavigationAuthority()

        val invalidated = assertNotNullResult(state.latestContinuousNavigationResult)
        assertEquals(navigation.generation, invalidated.transactionId)
        assertEquals(ContinuousNavigationOutcome.ACCEPTED, invalidated.outcome)
        assertEquals(ContinuousViewportVerification.SUPERSEDED, invalidated.finalViewportVerification.classification)
        assertFalse(invalidated.finalViewportVerification.authorityStillCurrent)
    }

    @Test fun `new navigation creates fresh authority after prior drag invalidation`() {
        val state = restoredNavigator()
        val first = assertGranted(state.beginNavigation())
        state.invalidateContinuousNavigationAuthority()
        assertFalse(state.recordContinuousNavigationResult(verifiedResult(first.generation), first.generation))
        assertTrue(state.completeNavigation(first.generation))

        val next = assertGranted(state.beginNavigation())
        val current = verifiedResult(next.generation)
        assertTrue(state.recordContinuousNavigationResult(current, next.generation))
        assertEquals(current, state.latestContinuousNavigationResult)
    }

    @Test fun `verified canonical seek overrides publication identity and retains actual visible locator`() {
        val (state, generation) = canonicalNavigation()
        val actual = visiblePosition()
        assertTrue(state.recordContinuousNavigationResult(verifiedResult(generation), generation))

        val result = state.applyVerifiedContinuousCanonicalPosition(actual, readingOrderIndex = 15)

        assertEquals(171, result.locator.locations.position)
        assertEquals(0.53125, result.locator.locations.totalProgression!!, 0.0)
        assertEquals(0.53125, result.progression!!, 0.0)
        assertEquals(actual.locator.href, result.locator.href)
        assertEquals(actual.locator.locations.progression, result.locator.locations.progression)
        assertEquals("p:nth-child(8)", result.locator.locations["cssSelector"])
        assertEquals("visible DOM quote", result.locator.text.highlight)
        assertEquals(321, result.totalLogicalPositions)
    }

    @Test fun `unverified failed and missing canonical targets do not override publication identity`() {
        val (unverified, unverifiedGeneration) = canonicalNavigation()
        val notVerified = verifiedResult(unverifiedGeneration).copy(
            finalViewportVerification = verifiedViewport().copy(
                classification = ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT,
            ),
        )
        assertTrue(unverified.recordContinuousNavigationResult(notVerified, unverifiedGeneration))
        assertEquals(170, unverified.applyVerifiedContinuousCanonicalPosition(visiblePosition(), 15).locator.locations.position)

        val (failed, failedGeneration) = canonicalNavigation()
        assertTrue(failed.recordContinuousNavigationResult(
            ContinuousNavigationResult(failedGeneration, ContinuousNavigationOutcome.FAILED_BEFORE_POSITION, verifiedViewport()),
            failedGeneration,
        ))
        assertEquals(170, failed.applyVerifiedContinuousCanonicalPosition(visiblePosition(), 15).locator.locations.position)

        val (missing, missingGeneration) = canonicalNavigation(position = null)
        assertFalse(missing.recordContinuousCanonicalTarget(missingGeneration, "OPS/h-16.xhtml", 15, null, 0.53125))
        assertTrue(missing.recordContinuousNavigationResult(verifiedResult(missingGeneration), missingGeneration))
        assertEquals(170, missing.applyVerifiedContinuousCanonicalPosition(visiblePosition(), 15).locator.locations.position)
    }

    @Test fun `drag invalidates canonical identity immediately and manual position stays mapped`() {
        val (state, generation) = canonicalNavigation()
        assertTrue(state.recordContinuousNavigationResult(verifiedResult(generation), generation))
        state.invalidateContinuousNavigationAuthority()

        val afterDrag = state.applyVerifiedContinuousCanonicalPosition(visiblePosition(), 15)
        assertEquals(170, afterDrag.locator.locations.position)
        assertEquals(0.528, afterDrag.progression!!, 0.0)
        assertEquals(ContinuousViewportVerification.SUPERSEDED,
            state.latestContinuousNavigationResult!!.finalViewportVerification.classification)
    }

    @Test fun `new navigation resource mismatch and stale result cannot reactivate target`() {
        val (state, oldGeneration) = canonicalNavigation()
        assertTrue(state.recordContinuousNavigationResult(verifiedResult(oldGeneration), oldGeneration))
        assertEquals(170, state.applyVerifiedContinuousCanonicalPosition(visiblePosition(), 14).locator.locations.position)
        assertTrue(state.completeNavigation(oldGeneration))

        val newGeneration = assertGranted(state.beginNavigation()).generation
        assertFalse(state.recordContinuousNavigationResult(verifiedResult(oldGeneration), newGeneration))
        assertEquals(170, state.applyVerifiedContinuousCanonicalPosition(visiblePosition(), 15).locator.locations.position)
    }

    @Test fun `verified but unaccepted navigation keeps its outcome while canonical identity is available`() {
        val (state, generation) = canonicalNavigation()
        val result = ContinuousNavigationResult(
            generation,
            ContinuousNavigationOutcome.POSITION_APPLIED_BUT_NOT_ACCEPTED,
            verifiedViewport(),
        )
        assertTrue(state.recordContinuousNavigationResult(result, generation))

        assertFalse(state.latestContinuousNavigationResult!!.accepted)
        assertEquals(171, state.applyVerifiedContinuousCanonicalPosition(visiblePosition(), 15).locator.locations.position)
    }

    @Test fun `verified unaccepted continuous navigation publishes visible locator`() {
        assertTrue(
            shouldPublishContinuousNavigationLocator(
                resultRecorded = true,
                accepted = false,
                verification = ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT,
            ),
        )
        assertTrue(
            shouldPublishContinuousNavigationLocator(
                resultRecorded = true,
                accepted = true,
                verification = ContinuousViewportVerification.UNAVAILABLE,
            ),
        )
        assertFalse(
            shouldPublishContinuousNavigationLocator(
                resultRecorded = true,
                accepted = false,
                verification = ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT,
            ),
        )
        assertFalse(
            shouldPublishContinuousNavigationLocator(
                resultRecorded = false,
                accepted = false,
                verification = ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT,
            ),
        )
    }

    @Test fun `dispose clears canonical publication identity`() {
        val (state, generation) = canonicalNavigation()
        assertTrue(state.recordContinuousNavigationResult(verifiedResult(generation), generation))
        state.dispose()
        assertEquals(170, state.applyVerifiedContinuousCanonicalPosition(visiblePosition(), 15).locator.locations.position)
    }

    private fun canonicalNavigation(position: Int? = 171): Pair<ReadiumReaderSessionState, Long> {
        val state = restoredNavigator()
        val generation = assertGranted(state.beginNavigation()).generation
        state.recordContinuousCanonicalTarget(
            generation = generation,
            href = "OPS/h-16.xhtml",
            readingOrderIndex = 15,
            position = position,
            totalProgression = 0.53125,
        )
        return state to generation
    }

    private fun visiblePosition(): ReadiumPositionState {
        val locator = Locator(
            href = Url("served-h16.xhtml")!!,
            mediaType = MediaType.XHTML,
            locations = Locator.Locations(
                progression = 0.583303,
                position = 170,
                totalProgression = 0.528,
                otherLocations = mapOf("cssSelector" to "p:nth-child(8)"),
            ),
            text = Locator.Text(highlight = "visible DOM quote"),
        )
        return ReadiumPositionState(
            locator = locator,
            progression = 0.528,
            totalLogicalPositions = 321,
            presentation = ReadiumPresentationState.Scrolling,
        )
    }

    private fun verifiedViewport() = ContinuousFinalViewportVerification(
        classification = ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT,
        sameResource = true,
        targetRangeAtReadingAnchor = true,
        finalVisibleProgression = 0.4,
        targetProgression = 0.4,
        authorityStillCurrent = true,
    )

    private fun verifiedResult(generation: Long) = ContinuousNavigationResult(
        generation,
        ContinuousNavigationOutcome.ACCEPTED,
        verifiedViewport(),
    )

    private fun assertNotNullResult(result: ContinuousNavigationResult?): ContinuousNavigationResult =
        checkNotNull(result)

    @Test fun `stale command completion is ignored`() {
        val state = restoredNavigator()
        val first = assertGranted(state.beginNavigation())
        assertTrue(state.completeNavigation(first.generation))
        val second = assertGranted(state.beginNavigation())
        assertFalse(state.completeNavigation(first.generation))
        assertTrue(state.completeNavigation(second.generation))
    }

    @Test fun `dispose cancels active navigation`() {
        val state = restoredNavigator()
        val command = assertGranted(state.beginNavigation())
        state.dispose()
        assertFalse(state.completeNavigation(command.generation))
    }

    @Test fun `same href different progression position remains distinct`() {
        val first = fingerprint(0.2)
        val second = fingerprint(0.7)
        assertFalse(first == second)
    }

    @Test fun `identical locator position can be deduplicated`() {
        assertEquals(fingerprint(0.2), fingerprint(0.2))
    }

    @Test fun `same canonical position at a different point remains a new continuous locator`() {
        assertFalse(fingerprint(0.2, "body > p:nth-child(2)") == fingerprint(0.2, "body > p:nth-child(8)"))
    }

    @Test fun `progression is clamped and invalid values are rejected`() {
        assertEquals(0.0, ReadiumReaderSession.normalizeObservedProgression(-0.2))
        assertEquals(1.0, ReadiumReaderSession.normalizeObservedProgression(1.2))
        assertEquals(0.0, ReadiumReaderSession.normalizeRequestedProgression(-0.0000001))
        assertEquals(1.0, ReadiumReaderSession.normalizeRequestedProgression(1.0000001))
        assertEquals(null, ReadiumReaderSession.normalizeRequestedProgression(-0.1))
    }

    @Test fun `nan and infinite progression are rejected`() {
        assertEquals(null, ReadiumReaderSession.normalizeObservedProgression(Double.NaN))
        assertEquals(null, ReadiumReaderSession.normalizeRequestedProgression(Double.POSITIVE_INFINITY))
    }

    @Test fun `preference request before navigator readiness is rejected`() {
        val coordinator = ReadiumPreferenceCoordinator<String>()
        assertEquals(ReadiumPreferenceCoordinator.Action.NotReady, coordinator.request("dark"))
    }

    @Test fun `initial factory preferences are recorded as applied once`() {
        val coordinator = ReadiumPreferenceCoordinator<String>()
        coordinator.onNavigatorReady()
        coordinator.seedInitialApplied("sepia")
        assertEquals("sepia", coordinator.snapshot().requested)
        assertEquals("sepia", coordinator.snapshot().applied)
        assertEquals(ReadiumPreferenceCoordinator.Action.Unchanged, coordinator.request("sepia"))
    }

    @Test fun `restored navigator can retain an unknown existing applied preference`() {
        val coordinator = ReadiumPreferenceCoordinator<String>()
        coordinator.onNavigatorReady()
        coordinator.seedInitialRequested("system")
        assertEquals("system", coordinator.snapshot().requested)
        assertEquals(null, coordinator.snapshot().applied)
    }

    @Test fun `pending physical CSS bypasses unchanged preference shortcut without building FIFO`() {
        val coordinator = ReadiumPreferenceCoordinator<String>()
        coordinator.onNavigatorReady()
        coordinator.seedInitialApplied("original")
        val first = coordinator.request("original", forceApply = true) as ReadiumPreferenceCoordinator.Action.Start
        val queued = coordinator.request("original", forceApply = true) as ReadiumPreferenceCoordinator.Action.Queued
        val latest = coordinator.request("latest", forceApply = true) as ReadiumPreferenceCoordinator.Action.Queued
        assertEquals(queued.request, latest.supersededPendingRequest)
        val completion = coordinator.complete(first.request.generation, true, committedDuringSupersession = true) as ReadiumPreferenceCoordinator.Completion.Processed
        assertEquals(ReadiumPreferenceCoordinator.Outcome.APPLIED, completion.outcome)
        assertEquals("latest", completion.next?.value)
    }

    @Test fun `runtime preference forwards the complete requested value`() {
        val coordinator = readyPreferences()
        val request = assertPreferenceStart(coordinator.request("dark|1.2|1.6|1.0|false"))
        val completion = assertPreferenceCompletion(coordinator.complete(request.generation, succeeded = true))
        assertEquals(ReadiumPreferenceCoordinator.Outcome.APPLIED, completion.outcome)
        assertEquals("dark|1.2|1.6|1.0|false", coordinator.snapshot().applied)
    }

    @Test fun `preview dispatch diagnostics use monotonic receive intervals and coordinator actions`() {
        var elapsedRealtimeMs = 100L
        val clock = ReadiumPreviewDispatchClock { elapsedRealtimeMs }
        val coordinator = readyPreferences("light")

        val firstInterval = clock.intervalSincePreviousMs()
        assertEquals(null, firstInterval)
        val running = coordinator.request("font-1")
        val first = requireNotNull(readiumPreviewDispatchDiagnostic(running, firstInterval))
        assertEquals(true, first.activeApply)
        assertEquals(false, first.pendingLatest)
        assertEquals(null, first.intervalSincePreviousMs)

        elapsedRealtimeMs = 143L
        val secondInterval = clock.intervalSincePreviousMs()
        assertEquals(43.0, secondInterval ?: -1.0, 0.0)
        val queued = coordinator.request("font-2")
        val latest = requireNotNull(readiumPreviewDispatchDiagnostic(queued, secondInterval))
        assertEquals(true, latest.activeApply)
        assertEquals(true, latest.pendingLatest)
        assertEquals(43.0, latest.intervalSincePreviousMs ?: -1.0, 0.0)
        assertEquals(null, readiumPreviewDispatchDiagnostic(ReadiumPreferenceCoordinator.Action.Unchanged, 5.0))
    }

    @Test fun `canonical position publication carries its matching physical viewport snapshot`() {
        val verifiedAnchor = EpubContinuousReflowDiagnosticEvent(
            kind = "viewport_snapshot",
            context = null,
            preferenceGeneration = 9,
            transactionGeneration = 4,
            layoutGeneration = 7,
            resourceGeneration = 3,
            readingOrderIndex = 6,
            snapshotStage = "after_anchor_verified",
            anchorPointSampleStage = "after_anchor_verified",
            anchorPointDocumentYPx = 1_240.0,
            anchorPointViewportYPx = 326.0,
            anchorPointAvailable = true,
            anchorResourceHref = "OPS/chapter-6.xhtml",
            webViewIdentity = 2468,
            anchorBeforeLocalYPx = 155.0,
            anchorBeforeViewportYPx = 326.0,
            anchorSemanticMatch = true,
            anchorViewportDeltaPx = 1.0,
            anchorViewportTolerancePx = 4.0,
        )
        val fields = continuousViewportPositionPublicationFields(
            preferenceGeneration = 9,
            readingOrderIndex = 6,
            logicalPosition = 87,
            progression = 0.42,
            viewport = EpubContinuousViewportLayoutSnapshot(
                firstVisibleIndex = 5,
                firstVisibleTopPx = -16,
                heightPx = 1_000,
                paddingTopPx = 12,
                paddingBottomPx = 10,
                anchorIndex = 6,
                anchorTopPx = -3,
                anchorBottomPx = 980,
                webViewIdentity = 2468,
            ),
            verifiedAnchor = verifiedAnchor,
        )

        assertEquals("viewport_position_publication", fields["kind"])
        assertEquals(6, fields["readingOrderIndex"])
        assertEquals(87, fields["logicalPosition"])
        assertEquals(0.42, fields["positionProgression"])
        assertEquals(5, fields["viewportFirstVisibleIndex"])
        assertEquals(-16, fields["viewportFirstVisibleTopPx"])
        assertEquals("after_anchor_verified", fields["anchorPointSampleStage"])
        assertEquals(326.0, fields["anchorPointViewportYPx"])
        assertEquals(2468, fields["webViewIdentity"])
    }

    @Test fun `failed preference retains the last applied value`() {
        val coordinator = readyPreferences("light")
        val request = assertPreferenceStart(coordinator.request("dark"))
        val completion = assertPreferenceCompletion(coordinator.complete(request.generation, succeeded = false))
        assertEquals(ReadiumPreferenceCoordinator.Outcome.FAILED, completion.outcome)
        assertEquals("dark", coordinator.snapshot().requested)
        assertEquals("light", coordinator.snapshot().applied)
    }

    @Test fun `unchanged preference does not submit again`() {
        val coordinator = readyPreferences("light")
        assertEquals(ReadiumPreferenceCoordinator.Action.Unchanged, coordinator.request("light"))
    }

    @Test fun `failed preference can be retried`() {
        val coordinator = readyPreferences("light")
        val first = assertPreferenceStart(coordinator.request("dark"))
        coordinator.complete(first.generation, succeeded = false)
        val retry = assertPreferenceStart(coordinator.request("dark"))
        assertTrue(retry.generation > first.generation)
    }

    @Test fun `rapid preference changes retain only the latest pending request`() {
        val coordinator = readyPreferences("light")
        val first = assertPreferenceStart(coordinator.request("sepia"))
        val second = assertPreferenceQueued(coordinator.request("dark"))
        val third = assertPreferenceQueued(coordinator.request("light"))
        assertEquals(second.request, third.supersededPendingRequest)
        val firstCompletion = assertPreferenceCompletion(coordinator.complete(first.generation, succeeded = true))
        assertEquals(ReadiumPreferenceCoordinator.Outcome.SUPERSEDED, firstCompletion.outcome)
        assertEquals(third.request, firstCompletion.next)
        val finalCompletion = assertPreferenceCompletion(coordinator.complete(third.request.generation, succeeded = true))
        assertEquals(ReadiumPreferenceCoordinator.Outcome.APPLIED, finalCompletion.outcome)
        assertEquals("light", coordinator.snapshot().applied)
    }

    @Test fun `locked running preference commits before the latest pending request`() {
        val coordinator = readyPreferences("light")
        val running = assertPreferenceStart(coordinator.request("font-1"))
        val pendingB = assertPreferenceQueued(coordinator.request("font-2"))
        val pendingC = assertPreferenceQueued(coordinator.request("font-3"))
        assertEquals(pendingB.request, pendingC.supersededPendingRequest)

        val completion = assertPreferenceCompletion(
            coordinator.complete(running.generation, succeeded = true, committedDuringSupersession = true),
        )

        assertEquals(ReadiumPreferenceCoordinator.Outcome.APPLIED, completion.outcome)
        assertEquals(pendingC.request, completion.next)
        assertEquals("font-1", coordinator.snapshot().applied)
        assertEquals("font-3", coordinator.snapshot().requested)
        val latest = assertPreferenceCompletion(coordinator.complete(pendingC.request.generation, succeeded = true))
        assertEquals(ReadiumPreferenceCoordinator.Outcome.APPLIED, latest.outcome)
        assertEquals("font-3", coordinator.snapshot().applied)
    }

    @Test fun `locked failure releases exact running request and starts latest pending`() {
        val coordinator = readyPreferences("light")
        val running = assertPreferenceStart(coordinator.request("font-1"))
        assertPreferenceQueued(coordinator.request("font-2"))
        val latest = assertPreferenceQueued(coordinator.request("font-3")).request

        val completion = assertPreferenceCompletion(
            coordinator.complete(running.generation, succeeded = false, committedDuringSupersession = true),
        )

        assertEquals(ReadiumPreferenceCoordinator.Outcome.FAILED, completion.outcome)
        assertEquals(latest, completion.next)
        assertEquals("light", coordinator.snapshot().applied)
        assertEquals("font-3", coordinator.snapshot().requested)
        assertTrue(coordinator.snapshot().isApplying)
    }

    @Test fun `next preference starts after owner release even when acknowledgement cleanup throws`() {
        var ownerHeld = true
        val order = mutableListOf<String>()

        val released = releaseCommitOwnerBeforeStartingNext(
            releaseOwner = {
                ownerHeld = false
                order += "owner_released"
                throw IllegalStateException("pin cleanup failed after owner release")
            },
            isOwnerHeld = { ownerHeld },
            startNext = {
                assertFalse(ownerHeld)
                order += "next_started"
            },
        )

        assertTrue(released)
        assertEquals(listOf("owner_released", "next_started"), order)

        var retainedOwnerStartedNext = false
        assertFalse(
            releaseCommitOwnerBeforeStartingNext(
                releaseOwner = { false },
                isOwnerHeld = { true },
                startNext = { retainedOwnerStartedNext = true },
            ),
        )
        assertFalse(retainedOwnerStartedNext)
    }

    @Test fun `stale preference completion cannot replace latest applied state`() {
        val coordinator = readyPreferences("light")
        val first = assertPreferenceStart(coordinator.request("dark"))
        assertEquals(ReadiumPreferenceCoordinator.Completion.Stale, coordinator.complete(first.generation + 1, succeeded = true))
        assertEquals("light", coordinator.snapshot().applied)
        assertPreferenceCompletion(coordinator.complete(first.generation, succeeded = true))
        assertEquals("dark", coordinator.snapshot().applied)
    }

    @Test fun `cancelled running preview preserves applied value and starts latest pending request`() {
        val coordinator = readyPreferences("light")
        val running = assertPreferenceStart(coordinator.request("preview-1"))
        val pending = assertPreferenceQueued(coordinator.request("preview-2")).request

        val completion = assertPreferenceCompletion(coordinator.cancel(running.generation))

        assertEquals(ReadiumPreferenceCoordinator.Outcome.SUPERSEDED, completion.outcome)
        assertEquals(pending, completion.next)
        assertEquals("light", coordinator.snapshot().applied)
        assertEquals("preview-2", coordinator.snapshot().requested)
        assertTrue(coordinator.snapshot().isApplying)
        val applied = assertPreferenceCompletion(coordinator.complete(pending.generation, succeeded = true))
        assertEquals(ReadiumPreferenceCoordinator.Outcome.APPLIED, applied.outcome)
        assertEquals("preview-2", coordinator.snapshot().applied)
    }

    @Test fun `cancelled running preview without pending request stays unapplied`() {
        val coordinator = readyPreferences("light")
        val running = assertPreferenceStart(coordinator.request("preview"))

        val completion = assertPreferenceCompletion(coordinator.cancel(running.generation))

        assertEquals(ReadiumPreferenceCoordinator.Outcome.SUPERSEDED, completion.outcome)
        assertEquals(null, completion.next)
        assertEquals("light", coordinator.snapshot().applied)
        assertFalse(coordinator.snapshot().isApplying)
    }

    @Test fun `dispose cancels running and pending preference requests`() {
        val coordinator = readyPreferences("light")
        val running = assertPreferenceStart(coordinator.request("dark"))
        val pending = assertPreferenceQueued(coordinator.request("sepia")).request
        assertEquals(listOf(running, pending), coordinator.dispose())
        assertEquals(ReadiumPreferenceCoordinator.Action.Disposed, coordinator.request("light"))
        assertEquals(ReadiumPreferenceCoordinator.Completion.Stale, coordinator.complete(running.generation, succeeded = true))
    }

    private fun readyToAttach(): ReadiumReaderSessionState = ReadiumReaderSessionState().also {
        it.start()
        it.publicationOpened()
    }

    private fun readyNavigator(): ReadiumReaderSessionState = readyToAttach().also {
        it.navigatorAttached(reusedRestoredNavigator = false)
        it.navigatorReady()
    }

    private fun restoredNavigator(): ReadiumReaderSessionState = readyNavigator().also {
        it.initialLocatorRestored()
    }

    private fun assertGranted(gate: ReadiumNavigationGate): ReadiumNavigationGate.Granted {
        assertTrue(gate is ReadiumNavigationGate.Granted)
        return gate as ReadiumNavigationGate.Granted
    }

    private fun readyPreferences(initial: String? = null) = ReadiumPreferenceCoordinator<String>().also {
        it.onNavigatorReady()
        initial?.let(it::seedInitialApplied)
    }

    private fun assertPreferenceStart(
        action: ReadiumPreferenceCoordinator.Action<String>,
    ): ReadiumPreferenceCoordinator.Request<String> {
        assertTrue(action is ReadiumPreferenceCoordinator.Action.Start)
        return (action as ReadiumPreferenceCoordinator.Action.Start).request
    }

    private fun assertPreferenceQueued(
        action: ReadiumPreferenceCoordinator.Action<String>,
    ): ReadiumPreferenceCoordinator.Action.Queued<String> {
        assertTrue(action is ReadiumPreferenceCoordinator.Action.Queued)
        return action as ReadiumPreferenceCoordinator.Action.Queued
    }

    private fun assertPreferenceCompletion(
        completion: ReadiumPreferenceCoordinator.Completion<String>,
    ): ReadiumPreferenceCoordinator.Completion.Processed<String> {
        assertTrue(completion is ReadiumPreferenceCoordinator.Completion.Processed)
        return completion as ReadiumPreferenceCoordinator.Completion.Processed
    }

    private fun fingerprint(progression: Double, cssSelector: String = "body > p") = ReadiumPositionFingerprint(
        href = "chapter.xhtml",
        fragments = listOf("#page"),
        cssSelector = cssSelector,
        position = 1,
        resourceProgression = progression,
        totalProgression = progression,
    )
}
