package app.bibliolife.reader.readium

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.junit.Assert.*
import org.junit.Test

class ProgressUiCommandPriorityTest {
    @Test fun `explicit new session replaces queued preview behind one active seek`() = runBlocking {
        exercise(cancel = false, oldFinal = false)
    }
    @Test fun `Cancel discards explicit final before native slot is available`() = runBlocking {
        exercise(cancel = true, oldFinal = false)
    }
    @Test fun `new explicit final supersedes old final with no old persistence`() = runBlocking {
        exercise(cancel = false, oldFinal = true)
    }
    private suspend fun exercise(cancel: Boolean, oldFinal: Boolean) = coroutineScope {
        val gate = ProgressScrubOwnership().also { it.open(1) }
        val a = ProgressNavigationOwner(1, 1, if (oldFinal) ProgressNavigationOwner.Phase.FINAL else ProgressNavigationOwner.Phase.PREVIEW)
        val b = ProgressNavigationOwner(1, 2, ProgressNavigationOwner.Phase.PREVIEW)
        val c = ProgressNavigationOwner(2, 1, ProgressNavigationOwner.Phase.FINAL)
        val mutex = Mutex()
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val dispatched = mutableListOf<ProgressNavigationOwner>()
        val persisted = mutableListOf<ProgressNavigationOwner>()
        var active = 0
        var maxActive = 0
        assertTrue(gate.reserve(a))
        val old = launch {
            mutex.withLock {
                active++; maxActive = maxOf(maxActive, active)
                dispatched += a
                entered.complete(Unit)
                release.await()
                if (oldFinal && gate.isCurrent(a)) persisted += a
                gate.finish(a, false)
                active--
            }
        }
        entered.await()
        val pendingPreview = if (!oldFinal) {
            assertTrue(gate.reserve(b))
            launch { mutex.withLock { if (gate.isCurrent(b)) dispatched += b } }
        } else null
        // Acceptance happens while A still holds the native slot.
        assertTrue(mutex.isLocked)
        assertTrue(gate.open(2))
        assertTrue(gate.reserve(c))
        assertFalse(gate.isCurrent(a))
        val explicit = launch {
            mutex.withLock {
                if (!gate.isCurrent(c)) return@withLock
                active++; maxActive = maxOf(maxActive, active)
                dispatched += c
                persisted += c // Represents the verified final commit boundary.
                active--
                gate.finish(c, true)
            }
        }
        yield()
        assertEquals(listOf(a), dispatched)
        if (cancel) assertTrue(gate.invalidate(2))
        release.complete(Unit)
        old.join(); pendingPreview?.join(); explicit.join()
        assertEquals(1, maxActive)
        assertFalse(dispatched.contains(b))
        assertEquals(if (cancel) listOf(a) else listOf(a, c), dispatched)
        assertEquals(if (cancel) emptyList<ProgressNavigationOwner>() else listOf(c), persisted)
        assertFalse(gate.isCurrent(a))
    }
}
