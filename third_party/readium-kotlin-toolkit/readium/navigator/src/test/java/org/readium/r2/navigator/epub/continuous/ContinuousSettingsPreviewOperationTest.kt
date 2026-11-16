@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package org.readium.r2.navigator.epub.continuous

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ContinuousSettingsPreviewOperationTest {
    @Test fun `superseding during anchor capture prevents stale CSS apply without cancelling parent`() = runBlocking {
        val operationJob = CompletableDeferred<Job>()
        val entered = CompletableDeferred<Unit>()
        val neverCompletes = CompletableDeferred<Unit>()
        var cssApplyStarted = false
        val terminals = mutableListOf<String>()
        val parent = coroutineContext[Job]

        val result = async {
            runCancellableSettingsPreviewOperation(
                onStarted = operationJob::complete,
                operation = {
                    entered.complete(Unit)
                    neverCompletes.await()
                    cssApplyStarted = true
                    "applied"
                },
                onCancelled = { "superseded" },
                onTerminal = terminals::add,
                onFailure = { throw AssertionError("unexpected operation failure", it) },
                onFinished = {},
            )
        }
        entered.await()
        operationJob.await().cancel()

        assertEquals("superseded", result.await())
        assertFalse("stale capture must not continue into CSS application", cssApplyStarted)
        assertEquals(listOf("superseded"), terminals)
        assertFalse(requireNotNull(parent).isCancelled)
    }

    @Test fun `successful preview completes its child job and returns`() = runBlocking {
        var operationJob: Job? = null
        val terminals = mutableListOf<String>()

        val result = runCancellableSettingsPreviewOperation(
            onStarted = { operationJob = it },
            operation = { "applied" },
            onCancelled = { "cancelled" },
            onTerminal = terminals::add,
            onFailure = { throw AssertionError("unexpected operation failure", it) },
            onFinished = {},
        )

        assertEquals("applied", result)
        assertEquals(listOf("applied"), terminals)
        assertFalse(requireNotNull(operationJob).isActive)
    }

    @Test fun `failed preview reports one failure terminal and rethrows`() = runBlocking {
        val failure = IllegalStateException("css failed")
        val terminals = mutableListOf<String>()
        var reportedFailure: Throwable? = null

        val thrown = runCatching {
            runCancellableSettingsPreviewOperation(
                onStarted = {},
                operation = { throw failure },
                onCancelled = { "cancelled" },
                onTerminal = terminals::add,
                onFailure = { reportedFailure = it; terminals += "failed" },
                onFinished = {},
            )
        }.exceptionOrNull()

        assertTrue(thrown is IllegalStateException)
        assertEquals(failure.message, thrown?.message)
        assertTrue(reportedFailure is IllegalStateException)
        assertEquals(failure.message, reportedFailure?.message)
        assertEquals(listOf("failed"), terminals)
    }

    @Test fun `reflow terminal values are committed superseded or failed only`() {
        assertEquals("committed", EpubContinuousPreferenceResult.Applied.toSettingsReflowTerminalResult())
        assertEquals("superseded", EpubContinuousPreferenceResult.Cancelled.toSettingsReflowTerminalResult(superseded = true))
        assertEquals("failed", EpubContinuousPreferenceResult.Cancelled.toSettingsReflowTerminalResult())
        assertEquals("failed", EpubContinuousPreferenceResult.TargetNotReady.toSettingsReflowTerminalResult())
    }

    @Test fun `stale preview cutoff never cancels an untagged terminal apply`() {
        assertFalse(isOlderSettingsPreviewRequest(null, cutoff = 8))
        assertTrue(isOlderSettingsPreviewRequest(7, cutoff = 8))
        assertFalse(isOlderSettingsPreviewRequest(8, cutoff = 8))
        assertFalse(isOlderSettingsPreviewRequest(9, cutoff = 8))
    }

    @Test fun `geometry commit owner blocks supersession only after exact owner lock`() {
        fun transaction(generation: Long) = ContinuousGeometryReflowTransaction(
            generation = generation,
            preferenceGeneration = 23,
            anchor = ContinuousAnchorLocator(
                index = 4,
                resourceGeneration = 91,
                layoutGeneration = 7,
                localY = 120.0,
                locator = Locator(
                    href = Url("chapter.xhtml")!!,
                    mediaType = MediaType.XHTML,
                    locations = Locator.Locations(progression = 0.5),
                ),
            ),
            requestedPreferences = EpubPreferences(),
        )

        val beforeCommit = transaction(10)
        beforeCommit.bindLayoutGeneration(8)
        assertTrue(beforeCommit.tryMarkSuperseded())
        assertFalse(beforeCommit.tryBeginCommit(ContinuousGeometryBatchOwner(23, 10, 8)))

        val committing = transaction(11)
        committing.bindLayoutGeneration(8)
        assertFalse(committing.tryBeginCommit(ContinuousGeometryBatchOwner(22, 11, 8)))
        val owner = EpubContinuousGeometryCommitOwner(23, 11, 8)
        assertTrue(committing.tryBeginCommit(ContinuousGeometryBatchOwner(23, 11, 8)))
        assertEquals(owner, committing.commitOwner)
        assertFalse(committing.superseded)
        assertFalse(committing.tryMarkSuperseded())
        assertEquals(ContinuousGeometryReflowTransaction.State.CAPTURED, committing.state)
        assertEquals(owner, committing.commitOwner)
    }

    @Test fun `production supersession gate cancels before lock and preserves job and generations after lock`() {
        fun transaction(generation: Long) = ContinuousGeometryReflowTransaction(
            generation = generation,
            preferenceGeneration = 31,
            anchor = ContinuousAnchorLocator(
                index = 4,
                resourceGeneration = 91,
                layoutGeneration = 7,
                localY = 120.0,
                locator = Locator(
                    href = Url("chapter.xhtml")!!,
                    mediaType = MediaType.XHTML,
                    locations = Locator.Locations(progression = 0.5),
                ),
            ),
            requestedPreferences = EpubPreferences(),
        )

        var revokes = 0
        var generationChanges = 0
        val beforeLockJob = Job()
        val beforeLock = transaction(40)
        assertTrue(runGeometryReflowSupersessionIfUnlocked(beforeLock) {
            revokes += 1
            generationChanges += 1
            beforeLockJob.cancel()
        })
        assertTrue(beforeLockJob.isCancelled)
        assertEquals(1, revokes)
        assertEquals(1, generationChanges)

        val committingJob = Job()
        val committing = transaction(41).also { it.bindLayoutGeneration(8) }
        assertTrue(committing.tryBeginCommit(ContinuousGeometryBatchOwner(31, 41, 8)))
        assertFalse(runGeometryReflowSupersessionIfUnlocked(committing) {
            revokes += 1
            generationChanges += 1
            committingJob.cancel()
        })
        assertTrue(committingJob.isActive)
        assertEquals(1, revokes)
        assertEquals(1, generationChanges)
        assertEquals(41L, committing.generation)
        assertFalse(committing.superseded)
    }

    @Test fun `direct callers auto acknowledge while session-held owners wait`() {
        val owner = EpubContinuousGeometryCommitOwner(4, 5, 6)
        val acknowledgements = mutableListOf<EpubContinuousGeometryCommitOwner>()
        acknowledgeGeometryCommitForDirectCaller(false, owner, acknowledgements::add)
        assertEquals(listOf(owner), acknowledgements)

        acknowledgeGeometryCommitForDirectCaller(true, owner, acknowledgements::add)
        assertEquals("The session performs the held acknowledgement after publication", listOf(owner), acknowledgements)
    }
}
