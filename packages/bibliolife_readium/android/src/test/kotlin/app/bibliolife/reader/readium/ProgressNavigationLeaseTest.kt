package app.bibliolife.reader.readium

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.junit.Assert.*
import org.junit.Test

class ProgressNavigationLeaseTest {
    @Test fun `late automatic locator from recovered generation cannot publish or persist`() {
        val fence = RecoveredProgressPublicationFence()
        fence.recover(3)
        assertFalse(fence.mayPublish(3, ContinuousPositionSource.HOST_VIEWPORT.automatic))
        assertFalse(fence.mayPublish(3, ContinuousPositionSource.RESOURCE_READY.automatic))
        assertTrue(fence.mayPublish(4, ContinuousPositionSource.HOST_VIEWPORT.automatic))
        assertTrue(fence.mayPublish(3, ContinuousPositionSource.VERIFIED_NAVIGATION.automatic))
        assertTrue(fence.mayPublish(3, ContinuousPositionSource.REFLOW_COMMITTED.automatic))
        fence.manualDragStarted()
        assertTrue(fence.mayPublish(3, ContinuousPositionSource.HOST_VIEWPORT.automatic))
    }
    private fun preview(session: Long = 1, request: Long = 1) =
        ProgressNavigationOwner(session, request, ProgressNavigationOwner.Phase.PREVIEW)
    private fun finalOwner(session: Long = 1, request: Long = 4) =
        ProgressNavigationOwner(session, request, ProgressNavigationOwner.Phase.FINAL)

    @Test fun `lost callback is cancelled before release and exact final gets the mutex next`() = runBlocking {
        val ownership = ProgressScrubOwnership().also { it.open(1) }
        val old = preview(request = 3)
        assertTrue(ownership.reserve(old))
        val mutex = Mutex()
        val entered = CompletableDeferred<Unit>()
        val lost = CompletableDeferred<String>()
        var active = 0
        var maximumActive = 0
        var releases = 0
        var persisted = 0
        val logs = mutableListOf<Map<String, Any?>>()
        val lease = ProgressNavigationLease(old, 3, 40) { _, fields -> logs += fields }
        val work = launch {
            mutex.withLock {
                active++; maximumActive = maxOf(maximumActive, active)
                try {
                    val result = lease.awaitVerification { entered.complete(Unit); lost.await() }
                    assertNull(result); assertTrue(lease.timedOut)
                } finally {
                    lease.finish("recovered_timeout") {
                        ownership.finish(old, false); active--; releases++
                    }
                }
            }
        }
        entered.await()
        val final = finalOwner()
        assertTrue(ownership.reserve(final)) // Replaces any older pending preview.
        val finalWork = launch {
            mutex.withLock {
                assertTrue(ownership.reserve(final))
                active++; maximumActive = maxOf(maximumActive, active)
                val finalLease = ProgressNavigationLease(final, 4)
                try {
                    assertEquals("verified", finalLease.awaitVerification { finalLease.markVerified(); "verified" })
                    persisted++
                } finally {
                    finalLease.finish("committed") { ownership.finish(final, true); active--; releases++ }
                }
            }
        }
        work.join(); finalWork.join()
        assertEquals(1, maximumActive)
        assertEquals(2, releases)
        assertEquals(1, persisted)
        assertFalse(ownership.isCurrent(old))
        assertFalse(ownership.reserve(old))
        lost.complete("late callback")
        assertFalse(lease.finish("committed") { releases++; persisted++ })
        assertTrue(ownership.isCurrent(final))
        assertEquals(1, persisted)
        assertEquals(1, logs.count { it["result"] == "fired" })
    }

    @Test fun `100ms and 800ms normal navigations never fire conservative watchdog`() = runBlocking {
        assertEquals(8_000L, PROGRESS_NAVIGATION_WATCHDOG_MS)
        for (duration in listOf(100L, 800L)) {
            val logs = mutableListOf<Map<String, Any?>>()
            val lease = ProgressNavigationLease(preview(), 1, diagnostic = { _, fields -> logs += fields })
            assertEquals("verified", lease.awaitVerification { delay(duration); lease.markVerified(); "verified" })
            assertFalse(lease.timedOut)
            assertTrue(lease.verified)
            assertEquals(listOf("armed", "cancelled"), logs.map { it["result"] })
        }
    }

    @Test fun `final timeout never verifies or persists and next gesture is usable`() = runBlocking {
        val ownership = ProgressScrubOwnership().also { it.open(1) }
        val final = finalOwner()
        ownership.reserve(final)
        val lease = ProgressNavigationLease(final, 4, 20)
        var persisted = false
        try {
            if (lease.awaitVerification { awaitCancellation(); "unreachable" } != null) persisted = true
        } finally { lease.finish("recovered_timeout") { ownership.finish(final, false) } }
        assertFalse(persisted); assertFalse(lease.verified)
        assertFalse(ownership.isCurrent(final))
        assertTrue(ownership.open(2)); assertTrue(ownership.reserve(preview(2)))
    }

    @Test fun `exception and cancellation always release exactly once`() = runBlocking {
        var releases = 0
        val failure = ProgressNavigationLease(preview(), 1)
        try {
            failure.awaitVerification<String> { throw IllegalStateException("failed") }
            fail("Expected failure")
        } catch (_: IllegalStateException) {
        } finally { failure.finish("failed") { releases++ } }
        assertEquals(1, releases)
        val cancelled = ProgressNavigationLease(preview(request = 2), 2)
        val entered = CompletableDeferred<Unit>()
        val job = launch {
            try { cancelled.awaitVerification<Unit> { entered.complete(Unit); awaitCancellation() } }
            finally { cancelled.finish("cancelled") { releases++ } }
        }
        entered.await(); job.cancelAndJoin()
        assertEquals(2, releases)
        assertFalse(cancelled.finish("committed") { releases++ })
        assertEquals(2, releases)
    }

    @Test fun `new gesture pending while old owner cancels cannot be retired by old cleanup`() = runBlocking {
        val ownership = ProgressScrubOwnership().also { it.open(1) }
        val old = preview()
        ownership.reserve(old)
        val lease = ProgressNavigationLease(old, 1, 20)
        val entered = CompletableDeferred<Unit>()
        val work = launch {
            try { lease.awaitVerification<Unit> { entered.complete(Unit); awaitCancellation() } }
            finally { lease.finish("recovered_timeout") { ownership.finish(old, false) } }
        }
        entered.await()
        assertTrue(ownership.open(2))
        val newest = preview(2, 7)
        assertTrue(ownership.reserve(newest))
        work.join()
        assertTrue(ownership.isCurrent(newest))
        assertFalse(ownership.reserve(old))
    }

    @Test fun `committed publication authority survives terminal cleanup but duplicate dispatch is rejected`() {
        val ownership = ProgressScrubOwnership().also { it.open(1) }
        val owner = preview()
        ownership.reserve(owner)
        ownership.finish(owner, true)
        assertTrue(ownership.isCurrent(owner))
        assertFalse(ownership.reserve(owner))
        assertTrue(ownership.reserve(preview(request = 2)))
    }

    @Test fun `diagnostic failures cannot prevent timeout or release`() = runBlocking {
        val lease = ProgressNavigationLease(preview(), 1, 20) { _, _ -> throw IllegalStateException("observer") }
        assertNull(lease.awaitVerification<Unit> { awaitCancellation() })
        var released = false
        assertTrue(lease.finish("recovered_timeout") { released = true })
        assertTrue(released)
    }
}
