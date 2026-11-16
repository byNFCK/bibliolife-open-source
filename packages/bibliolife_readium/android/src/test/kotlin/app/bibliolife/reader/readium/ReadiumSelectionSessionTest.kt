package app.bibliolife.reader.readium

import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadiumSelectionSessionTest {
    @Test fun `new coordinator is inactive with no locator`() {
        val coordinator = coordinator(FakeGateway())
        val state = coordinator.snapshot()
        assertEquals(ReadiumSelectionStatus.INACTIVE, state.status)
        assertNull(state.sessionId)
        assertNull(state.selection)
        assertFalse(state.sessionActive)
    }

    @Test fun `request without native session is typed not active`() {
        val results = mutableListOf<ReadiumSelectionRequestResult>()
        val result = coordinator(FakeGateway()).requestCurrentSelection(results::add)
        assertEquals(ReadiumSelectionRequestResult.NotActive, result)
        assertEquals(listOf(ReadiumSelectionRequestResult.NotActive), results)
    }

    @Test fun `native start enters pending and allocates identity`() {
        val coordinator = coordinator(FakeGateway())
        val id = coordinator.onNativeSelectionSessionStarted(41L)
        assertEquals(1L, id)
        assertEquals(ReadiumSelectionStatus.PENDING, coordinator.snapshot().status)
        assertEquals(41L, coordinator.snapshot().nativeSessionId)
        assertEquals(1L, coordinator.snapshot().generation)
    }

    @Test fun `repeated callback for same native selection preserves identity`() {
        val coordinator = coordinator(FakeGateway())
        val first = coordinator.onNativeSelectionSessionStarted(41L)
        val second = coordinator.onNativeSelectionSessionStarted(41L)
        assertEquals(first, second)
        assertEquals(1L, coordinator.snapshot().generation)
    }

    @Test fun `a new native selection gets a new monotonic identity`() {
        val coordinator = coordinator(FakeGateway())
        val first = coordinator.onNativeSelectionSessionStarted(41L)
        coordinator.onNativeSelectionSessionEnded(41L)
        val second = coordinator.onNativeSelectionSessionStarted(99L)
        assertEquals(1L, first)
        assertEquals(2L, second)
        assertTrue(coordinator.snapshot().generation > 1L)
    }

    @Test fun `stale end callback cannot end a newer native selection`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(41L)
        coordinator.onNativeSelectionSessionStarted(99L)
        assertFalse(coordinator.onNativeSelectionSessionEnded(41L))
        assertEquals(99L, coordinator.snapshot().nativeSessionId)
        assertTrue(coordinator.snapshot().sessionActive)
    }

    @Test fun `native end reconciles to inactive and clears locator`() {
        val gateway = FakeGateway(selection = nativeSelection("Привіт"))
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(41L)
        coordinator.requestCurrentSelection()
        runBlocking { yield() }
        assertNotNull(coordinator.snapshot().selection)
        assertTrue(coordinator.onNativeSelectionSessionEnded(41L))
        assertEquals(ReadiumSelectionStatus.INACTIVE, coordinator.snapshot().status)
        assertNull(coordinator.snapshot().selection)
    }

    @Test fun `native locator is normalized without changing Unicode text`() = runBlocking {
        val gateway = FakeGateway(selection = nativeSelection("Привіт\n世界"))
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        val results = mutableListOf<ReadiumSelectionRequestResult>()
        coordinator.requestCurrentSelection(results::add)
        yield()
        val selection = coordinator.snapshot().selection
        assertEquals(ReadiumSelectionStatus.ACTIVE, coordinator.snapshot().status)
        assertEquals("Привіт\n世界", selection?.selectedText)
        assertEquals("before", selection?.textBefore)
        assertEquals("after", selection?.textAfter)
        assertEquals(0.25, selection?.progression)
        assertEquals(0.75, selection?.totalProgression)
        assertEquals(ReadiumSelectionRequestResult.Updated(requireNotNull(selection)), results.single())
    }

    @Test fun `native rectangle is copied to a UI independent value`() = runBlocking {
        val coordinator = coordinator(FakeGateway(nativeSelection("text", ReadiumSelectionRect(1f, 2f, 3f, 4f))))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertEquals(ReadiumSelectionRect(1f, 2f, 3f, 4f), coordinator.snapshot().selection?.rect)
    }

    @Test fun `native activation refresh produces the snapshot consumed by the toolbar`() = runBlocking {
        val coordinator = coordinator(FakeGateway(nativeSelection("selected", ReadiumSelectionRect(10f, 20f, 110f, 60f))))
        coordinator.onNativeSelectionSessionStarted(7L)
        assertEquals(ReadiumSelectionStatus.PENDING, coordinator.snapshot().status)
        coordinator.requestCurrentSelection(refreshAfterInFlight = true)
        yield()
        val state = coordinator.snapshot()
        assertEquals(ReadiumSelectionStatus.ACTIVE, state.status)
        assertEquals("selected", state.selection?.selectedText)
        assertEquals(ReadiumSelectionRect(10f, 20f, 110f, 60f), state.selection?.rect)
        assertTrue(state.sessionActive)
    }

    @Test fun `blank native highlight is treated as empty`() = runBlocking {
        val coordinator = coordinator(FakeGateway(nativeSelection("   ")))
        coordinator.onNativeSelectionSessionStarted(1L)
        val results = mutableListOf<ReadiumSelectionRequestResult>()
        coordinator.requestCurrentSelection(results::add)
        yield()
        assertEquals(ReadiumSelectionStatus.PENDING, coordinator.snapshot().status)
        assertNull(coordinator.snapshot().selection)
        assertEquals(ReadiumSelectionRequestResult.Empty, results.single())
    }

    @Test fun `null native selection never becomes an invented locator`() = runBlocking {
        val coordinator = coordinator(FakeGateway(selection = null))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertNull(coordinator.snapshot().selection)
        assertEquals(ReadiumSelectionStatus.PENDING, coordinator.snapshot().status)
    }

    @Test fun `retrieval failure is explicit and retryable`() = runBlocking {
        val gateway = FakeGateway(failNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        val first = mutableListOf<ReadiumSelectionRequestResult>()
        coordinator.requestCurrentSelection(first::add)
        yield()
        assertEquals(ReadiumSelectionStatus.RETRIEVAL_FAILED, coordinator.snapshot().status)
        assertTrue(first.single() is ReadiumSelectionRequestResult.Failed)
        gateway.selection = nativeSelection("retry")
        val second = mutableListOf<ReadiumSelectionRequestResult>()
        coordinator.requestCurrentSelection(second::add)
        yield()
        assertEquals(ReadiumSelectionStatus.ACTIVE, coordinator.snapshot().status)
        assertEquals("retry", coordinator.snapshot().selection?.selectedText)
        assertTrue(second.single() is ReadiumSelectionRequestResult.Updated)
    }

    @Test fun `missing gateway is navigator not ready`() = runBlocking {
        val gateway = FakeGateway(failWithNotReady = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        val results = mutableListOf<ReadiumSelectionRequestResult>()
        coordinator.requestCurrentSelection(results::add)
        yield()
        assertEquals(ReadiumSelectionStatus.RETRIEVAL_FAILED, coordinator.snapshot().status)
        assertEquals(ReadiumSelectionRequestResult.NavigatorNotReady, results.single())
    }

    @Test fun `duplicate reads share one bounded native request`() = runBlocking {
        val gate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val gateway = FakeGateway(gate = gate)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        val first = mutableListOf<ReadiumSelectionRequestResult>()
        val second = mutableListOf<ReadiumSelectionRequestResult>()
        assertEquals(ReadiumSelectionRequestResult.Started, coordinator.requestCurrentSelection(first::add))
        yield()
        assertEquals(ReadiumSelectionRequestResult.AlreadyInFlight, coordinator.requestCurrentSelection(second::add))
        assertEquals(1, gateway.calls.size)
        gate.complete(nativeSelection("one"))
        yield()
        assertEquals(1, gateway.calls.size)
        assertTrue(first.single() is ReadiumSelectionRequestResult.Updated)
        assertTrue(second.single() is ReadiumSelectionRequestResult.Updated)
    }

    @Test fun `pending refresh runs once after the first completion`() = runBlocking {
        val firstGate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val secondGate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val gateway = FakeGateway(gates = ArrayDeque(listOf(firstGate, secondGate)))
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        coordinator.requestCurrentSelection()
        coordinator.requestCurrentSelection(refreshAfterInFlight = true)
        firstGate.complete(nativeSelection("first"))
        yield()
        assertEquals(2, gateway.calls.size)
        secondGate.complete(nativeSelection("second"))
        yield()
        assertEquals("second", coordinator.snapshot().selection?.selectedText)
        assertEquals(2, gateway.calls.size)
    }

    @Test fun `refresh callback receives the post movement snapshot not the in flight snapshot`() = runBlocking {
        val firstGate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val secondGate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val gateway = FakeGateway(gates = ArrayDeque(listOf(firstGate, secondGate)))
        val coordinator = coordinator(gateway)
        val actionResults = mutableListOf<ReadiumSelectionRequestResult>()
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()

        assertEquals(
            ReadiumSelectionRequestResult.AlreadyInFlight,
            coordinator.requestCurrentSelection(actionResults::add, refreshAfterInFlight = true),
        )
        firstGate.complete(nativeSelection("word"))
        yield()
        assertTrue(actionResults.isEmpty())
        secondGate.complete(nativeSelection("the whole selected sentence"))
        yield()

        val resolved = actionResults.single() as ReadiumSelectionRequestResult.Updated
        assertEquals("the whole selected sentence", resolved.selection.selectedText)
    }

    @Test fun `late result after native end is stale and cannot restore selection`() = runBlocking {
        val gate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val callbacks = mutableListOf<ReadiumSelectionRequestResult>()
        val coordinator = coordinator(FakeGateway(gate = gate))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection(callbacks::add)
        yield()
        coordinator.onNativeSelectionSessionEnded(1L)
        gate.complete(nativeSelection("late"))
        yield()
        assertEquals(ReadiumSelectionStatus.INACTIVE, coordinator.snapshot().status)
        assertNull(coordinator.snapshot().selection)
        assertTrue(callbacks.any { it == ReadiumSelectionRequestResult.Stale })
    }

    @Test fun `late empty result cannot erase a newer valid selection`() = runBlocking {
        val firstGate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val secondGate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val gateway = FakeGateway(gates = ArrayDeque(listOf(firstGate, secondGate)))
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        firstGate.complete(nativeSelection("first"))
        yield()
        coordinator.requestCurrentSelection()
        yield()
        secondGate.complete(null)
        yield()
        assertEquals("first", coordinator.snapshot().selection?.selectedText)
        assertEquals(ReadiumSelectionStatus.ACTIVE, coordinator.snapshot().status)
    }

    @Test fun `clear without active native session is typed not active`() {
        assertEquals(ReadiumSelectionClearResult.NotActive, coordinator(FakeGateway()).clearSelection())
    }

    @Test fun `clear dispatch enters clearing until native inactive callback`() {
        val gateway = FakeGateway(selection = nativeSelection("text"))
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        assertEquals(ReadiumSelectionClearResult.Started, coordinator.clearSelection())
        assertEquals(ReadiumSelectionStatus.CLEARING, coordinator.snapshot().status)
        assertEquals(1, gateway.clearCalls)
        coordinator.onNativeSelectionSessionEnded(1L)
        assertEquals(ReadiumSelectionStatus.INACTIVE, coordinator.snapshot().status)
    }

    @Test fun `concurrent clear requests are serialized`() {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        assertEquals(ReadiumSelectionClearResult.Started, coordinator.clearSelection())
        assertEquals(ReadiumSelectionClearResult.AlreadyClearing, coordinator.clearSelection())
        assertEquals(1, gateway.clearCalls)
    }

    @Test fun `clear failure does not pretend inactive`() {
        val gateway = FakeGateway(failClearNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        val result = coordinator.clearSelection()
        assertTrue(result is ReadiumSelectionClearResult.Failed)
        assertTrue(coordinator.snapshot().sessionActive)
        assertEquals(ReadiumSelectionStatus.PENDING, coordinator.snapshot().status)
    }

    @Test fun `clear navigator failure is typed and retryable`() {
        val gateway = FakeGateway(failClearWithNotReady = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        assertEquals(ReadiumSelectionClearResult.NavigatorNotReady, coordinator.clearSelection())
        gateway.failClearWithNotReady = false
        assertEquals(ReadiumSelectionClearResult.Started, coordinator.clearSelection())
    }

    @Test fun `clear invalidates an in flight retrieval`() = runBlocking {
        val gate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val callbacks = mutableListOf<ReadiumSelectionRequestResult>()
        val coordinator = coordinator(FakeGateway(gate = gate))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection(callbacks::add)
        yield()
        coordinator.clearSelection()
        gate.complete(nativeSelection("late"))
        yield()
        assertTrue(callbacks.any { it == ReadiumSelectionRequestResult.Stale })
        assertEquals(ReadiumSelectionStatus.CLEARING, coordinator.snapshot().status)
    }

    @Test fun `viewport epoch invalidates reads and increments generation`() = runBlocking {
        val gate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val coordinator = coordinator(FakeGateway(gate = gate))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        val before = coordinator.snapshot().generation
        coordinator.onViewportEpochChanged(7L)
        gate.complete(nativeSelection("stale"))
        yield()
        assertEquals(7L, coordinator.snapshot().viewportEpoch)
        assertTrue(coordinator.snapshot().generation > before)
        assertNull(coordinator.snapshot().selection)
    }

    @Test fun `new native session supersedes old retrieval`() = runBlocking {
        val gate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val coordinator = coordinator(FakeGateway(gate = gate))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        coordinator.onNativeSelectionSessionStarted(2L)
        gate.complete(nativeSelection("old"))
        yield()
        assertEquals(2L, coordinator.snapshot().nativeSessionId)
        assertNull(coordinator.snapshot().selection)
    }

    @Test fun `dispose is terminal and suppresses native clear`() {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.dispose()
        assertEquals(ReadiumSelectionStatus.DISPOSED, coordinator.snapshot().status)
        assertEquals(ReadiumSelectionClearResult.Disposed, coordinator.clearSelection())
        assertFalse(coordinator.onNativeSelectionSessionEnded(1L))
    }

    @Test fun `dispose emits disposed state once`() {
        val states = mutableListOf<ReadiumSelectionState>()
        val coordinator = ReadiumSelectionCoordinator(
            scope = CoroutineScope(Dispatchers.Unconfined),
            gateway = FakeGateway(),
            onStateChanged = states::add,
        )
        coordinator.dispose()
        coordinator.dispose()
        assertEquals(1, states.count { it.status == ReadiumSelectionStatus.DISPOSED })
    }

    @Test fun `start after dispose is rejected`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.dispose()
        assertNull(coordinator.onNativeSelectionSessionStarted(1L))
    }

    @Test fun `selection end after dispose is ignored`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.dispose()
        assertFalse(coordinator.onNativeSelectionSessionEnded(1L))
    }

    @Test fun `dispose sends disposed to a pending request callback`() = runBlocking {
        val gate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val results = mutableListOf<ReadiumSelectionRequestResult>()
        val coordinator = coordinator(FakeGateway(gate = gate))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection(results::add)
        yield()
        coordinator.dispose()
        assertEquals(listOf(ReadiumSelectionRequestResult.Disposed), results)
    }

    @Test fun `separate coordinators isolate session IDs`() {
        val first = coordinator(FakeGateway())
        val second = coordinator(FakeGateway())
        assertEquals(1L, first.onNativeSelectionSessionStarted(1L))
        assertEquals(1L, second.onNativeSelectionSessionStarted(1L))
        assertNull(second.snapshot().selection)
    }

    @Test fun `ending a session advances generation`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        val started = coordinator.snapshot().generation
        coordinator.onNativeSelectionSessionEnded(1L)
        assertTrue(coordinator.snapshot().generation > started)
    }

    @Test fun `clear advances generation before dispatch`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        val started = coordinator.snapshot().generation
        coordinator.clearSelection()
        assertTrue(coordinator.snapshot().generation > started)
    }

    @Test fun `same viewport epoch is idempotent`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onViewportEpochChanged(4L)
        val generation = coordinator.snapshot().generation
        coordinator.onViewportEpochChanged(4L)
        assertEquals(generation, coordinator.snapshot().generation)
    }

    @Test fun `viewport change while inactive does not invent a session`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onViewportEpochChanged(4L)
        assertEquals(ReadiumSelectionStatus.INACTIVE, coordinator.snapshot().status)
        assertNull(coordinator.snapshot().sessionId)
    }

    @Test fun `viewport change while active returns to pending`() {
        val coordinator = coordinator(FakeGateway(selection = nativeSelection("old")))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        assertEquals(ReadiumSelectionStatus.ACTIVE, coordinator.snapshot().status)
        coordinator.onViewportEpochChanged(4L)
        assertEquals(ReadiumSelectionStatus.PENDING, coordinator.snapshot().status)
        assertNull(coordinator.snapshot().selection)
    }

    @Test fun `pending status blocks user navigation`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        assertTrue(coordinator.snapshot().blocksUserNavigation)
    }

    @Test fun `inactive status does not block user navigation`() {
        assertFalse(coordinator(FakeGateway()).snapshot().blocksUserNavigation)
    }

    @Test fun `clearing status blocks user navigation until native end`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        assertTrue(coordinator.snapshot().blocksUserNavigation)
    }

    @Test fun `retrieval failure remains a live native session`() = runBlocking {
        val coordinator = coordinator(FakeGateway(failNext = true))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertTrue(coordinator.snapshot().sessionActive)
        assertTrue(coordinator.snapshot().blocksUserNavigation)
    }

    @Test fun `request while clearing is typed and does not call native`() {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        val result = coordinator.requestCurrentSelection()
        assertEquals(ReadiumSelectionRequestResult.Clearing, result)
        assertTrue(gateway.calls.isEmpty())
    }

    @Test fun `clear keeps the last normalized snapshot while awaiting native end`() = runBlocking {
        val coordinator = coordinator(FakeGateway(selection = nativeSelection("keep")))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        coordinator.clearSelection()
        assertEquals("keep", coordinator.snapshot().selection?.selectedText)
    }

    @Test fun `clear after retrieval failure still dispatches`() = runBlocking {
        val gateway = FakeGateway(failNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertEquals(ReadiumSelectionClearResult.Started, coordinator.clearSelection())
        assertEquals(1, gateway.clearCalls)
    }

    @Test fun `clear retry after a failure issues one new native call`() {
        val gateway = FakeGateway(failClearNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        assertTrue(coordinator.clearSelection() is ReadiumSelectionClearResult.Failed)
        assertEquals(ReadiumSelectionClearResult.Started, coordinator.clearSelection())
        assertEquals(2, gateway.clearCalls)
    }

    @Test fun `failed clear retains pending status`() {
        val gateway = FakeGateway(failClearNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        assertEquals(ReadiumSelectionStatus.PENDING, coordinator.snapshot().status)
    }

    @Test fun `successful clear does not emit inactive before native callback`() {
        val states = mutableListOf<ReadiumSelectionStatus>()
        val coordinator = ReadiumSelectionCoordinator(
            scope = CoroutineScope(Dispatchers.Unconfined),
            gateway = FakeGateway(),
            onStateChanged = { states += it.status },
        )
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        assertFalse(states.last() == ReadiumSelectionStatus.INACTIVE)
    }

    @Test fun `native inactive callback completes a pending clear`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        coordinator.onNativeSelectionSessionEnded(1L)
        assertEquals(ReadiumSelectionStatus.INACTIVE, coordinator.snapshot().status)
    }

    @Test fun `selection starts can continue after a retrieval failure`() = runBlocking {
        val gateway = FakeGateway(failNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        gateway.selection = nativeSelection("again")
        coordinator.onNativeSelectionSessionEnded(1L)
        coordinator.onNativeSelectionSessionStarted(2L)
        coordinator.requestCurrentSelection()
        yield()
        assertEquals("again", coordinator.snapshot().selection?.selectedText)
    }

    @Test fun `new active session clears previous error`() = runBlocking {
        val coordinator = coordinator(FakeGateway(failNext = true))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        coordinator.onNativeSelectionSessionEnded(1L)
        coordinator.onNativeSelectionSessionStarted(2L)
        assertNull(coordinator.snapshot().error)
    }

    @Test fun `stale viewport result callback is rejected`() = runBlocking {
        val gate = CompletableDeferred<ReadiumSelectionSnapshot?>()
        val callbacks = mutableListOf<ReadiumSelectionRequestResult>()
        val coordinator = coordinator(FakeGateway(gate = gate))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection(callbacks::add)
        yield()
        coordinator.onViewportEpochChanged(2L)
        gate.complete(nativeSelection("old"))
        yield()
        assertTrue(callbacks.contains(ReadiumSelectionRequestResult.Stale))
    }

    @Test fun `duplicate starts do not advance generation`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        val generation = coordinator.snapshot().generation
        coordinator.onNativeSelectionSessionStarted(1L)
        assertEquals(generation, coordinator.snapshot().generation)
    }

    @Test fun `native session ID is exposed separately from internal identity`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(87L)
        assertEquals(1L, coordinator.snapshot().sessionId)
        assertEquals(87L, coordinator.snapshot().nativeSessionId)
    }

    @Test fun `normalized state has no ActionMode or View fields`() {
        val names = ReadiumSelectionState::class.java.declaredFields.map { it.name }.toSet()
        assertFalse(names.any { it.contains("action", ignoreCase = true) })
        assertFalse(names.any { it in setOf("view", "actionMode", "menu") })
    }

    @Test fun `normalized state carries no serialized locator JSON`() {
        val names = ReadiumSelectionSnapshot::class.java.declaredFields.map { it.name }.toSet()
        assertFalse(names.any { it.contains("json", ignoreCase = true) })
    }

    @Test fun `missing optional context is allowed`() {
        val value = ReadiumSelectionSnapshot(null, "text", null, null, "chapter.xhtml", null, null, null)
        assertNull(value.textBefore)
        assertNull(value.textAfter)
    }

    @Test fun `selection text is not trimmed by the normalized model`() {
        val value = nativeSelection("  text  ")
        assertEquals("  text  ", value.selectedText)
    }

    @Test fun `Cyrillic selection text survives state transition`() = runBlocking {
        val coordinator = coordinator(FakeGateway(selection = nativeSelection("Їжак читає")))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertEquals("Їжак читає", coordinator.snapshot().selection?.selectedText)
    }

    @Test fun `empty response after valid response preserves valid snapshot`() = runBlocking {
        val gateway = FakeGateway(selection = nativeSelection("valid"))
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        gateway.selection = null
        coordinator.requestCurrentSelection()
        yield()
        assertEquals("valid", coordinator.snapshot().selection?.selectedText)
    }

    @Test fun `request callback is completed for an immediate success`() = runBlocking {
        val results = mutableListOf<ReadiumSelectionRequestResult>()
        val coordinator = coordinator(FakeGateway(selection = nativeSelection("ok")))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection(results::add)
        yield()
        assertEquals(1, results.size)
    }

    @Test fun `request after failure starts a fresh gateway call`() = runBlocking {
        val gateway = FakeGateway(failNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        gateway.selection = nativeSelection("fresh")
        coordinator.requestCurrentSelection()
        yield()
        assertEquals(2, gateway.calls.size)
    }

    @Test fun `native clear is not repeated after clear failure until explicit retry`() {
        val gateway = FakeGateway(failClearNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        assertEquals(1, gateway.clearCalls)
    }

    @Test fun `old end callback cannot clear a newer internal session`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.onNativeSelectionSessionEnded(1L)
        coordinator.onNativeSelectionSessionStarted(2L)
        assertFalse(coordinator.onNativeSelectionSessionEnded(1L))
        assertEquals(2L, coordinator.snapshot().nativeSessionId)
    }

    @Test fun `state listener receives pending then active`() = runBlocking {
        val statuses = mutableListOf<ReadiumSelectionStatus>()
        val coordinator = ReadiumSelectionCoordinator(
            scope = CoroutineScope(Dispatchers.Unconfined),
            gateway = FakeGateway(selection = nativeSelection("ok")),
            onStateChanged = { statuses += it.status },
        )
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertTrue(statuses.contains(ReadiumSelectionStatus.PENDING))
        assertTrue(statuses.contains(ReadiumSelectionStatus.ACTIVE))
    }

    @Test fun `state listener receives clearing before inactive`() {
        val statuses = mutableListOf<ReadiumSelectionStatus>()
        val coordinator = ReadiumSelectionCoordinator(
            scope = CoroutineScope(Dispatchers.Unconfined),
            gateway = FakeGateway(),
            onStateChanged = { statuses += it.status },
        )
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        coordinator.onNativeSelectionSessionEnded(1L)
        assertTrue(statuses.indexOf(ReadiumSelectionStatus.CLEARING) < statuses.indexOf(ReadiumSelectionStatus.INACTIVE))
    }

    @Test fun `dispose listener receives terminal state after active state`() {
        val statuses = mutableListOf<ReadiumSelectionStatus>()
        val coordinator = ReadiumSelectionCoordinator(
            scope = CoroutineScope(Dispatchers.Unconfined),
            gateway = FakeGateway(),
            onStateChanged = { statuses += it.status },
        )
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.dispose()
        assertEquals(ReadiumSelectionStatus.DISPOSED, statuses.last())
    }

    @Test fun `selection status error is cleared by valid update`() = runBlocking {
        val gateway = FakeGateway(failNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        gateway.selection = nativeSelection("recovered")
        coordinator.requestCurrentSelection()
        yield()
        assertNull(coordinator.snapshot().error)
    }

    @Test fun `selection state keeps viewport epoch with normalized data`() = runBlocking {
        val coordinator = coordinator(FakeGateway(selection = nativeSelection("epoch")))
        coordinator.onViewportEpochChanged(5L)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertEquals(5L, coordinator.snapshot().viewportEpoch)
    }

    @Test fun `selection gateway calls are not made while inactive`() = runBlocking {
        val gateway = FakeGateway()
        coordinator(gateway).requestCurrentSelection()
        yield()
        assertTrue(gateway.calls.isEmpty())
    }

    @Test fun `clear gateway calls are not made while inactive`() {
        val gateway = FakeGateway()
        coordinator(gateway).clearSelection()
        assertEquals(0, gateway.clearCalls)
    }

    @Test fun `clear does not change viewport epoch`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onViewportEpochChanged(9L)
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        assertEquals(9L, coordinator.snapshot().viewportEpoch)
    }

    @Test fun `selection session identity does not leak after dispose`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.dispose()
        assertNull(coordinator.snapshot().sessionId)
        assertNull(coordinator.snapshot().nativeSessionId)
    }

    @Test fun `native session start clears an old selection snapshot`() = runBlocking {
        val coordinator = coordinator(FakeGateway(selection = nativeSelection("old")))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        coordinator.onNativeSelectionSessionStarted(2L)
        assertNull(coordinator.snapshot().selection)
    }

    @Test fun `clear command is independent from selection snapshot presentation`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        assertEquals(ReadiumSelectionStatus.CLEARING, coordinator.snapshot().status)
    }

    @Test fun `retrieval does not mutate viewport epoch`() = runBlocking {
        val coordinator = coordinator(FakeGateway(selection = nativeSelection("stable")))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertEquals(0L, coordinator.snapshot().viewportEpoch)
    }

    @Test fun `retrieval does not mutate session ID`() = runBlocking {
        val coordinator = coordinator(FakeGateway(selection = nativeSelection("stable")))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertEquals(1L, coordinator.snapshot().sessionId)
    }

    @Test fun `selection status is deterministic after empty retrieval`() = runBlocking {
        val coordinator = coordinator(FakeGateway(selection = null))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.requestCurrentSelection()
        yield()
        assertEquals(ReadiumSelectionStatus.PENDING, coordinator.snapshot().status)
    }

    @Test fun `selection status is deterministic after clear failure`() {
        val coordinator = coordinator(FakeGateway(failClearNext = true))
        coordinator.onNativeSelectionSessionStarted(1L)
        coordinator.clearSelection()
        assertEquals(ReadiumSelectionStatus.PENDING, coordinator.snapshot().status)
    }

    @Test fun `selection status is deterministic after dispose`() {
        val coordinator = coordinator(FakeGateway())
        coordinator.dispose()
        assertEquals(ReadiumSelectionStatus.DISPOSED, coordinator.snapshot().status)
    }

    private fun coordinator(gateway: FakeGateway) = ReadiumSelectionCoordinator(
        scope = CoroutineScope(Dispatchers.Unconfined),
        gateway = gateway,
    )

    private class FakeGateway(
        var selection: ReadiumSelectionSnapshot? = nativeSelection("text"),
        private val gate: CompletableDeferred<ReadiumSelectionSnapshot?>? = null,
        private val gates: ArrayDeque<CompletableDeferred<ReadiumSelectionSnapshot?>> = ArrayDeque(),
        var failNext: Boolean = false,
        var failWithNotReady: Boolean = false,
        var failClearNext: Boolean = false,
        var failClearWithNotReady: Boolean = false,
    ) : ReadiumSelectionGateway {
        val calls = CopyOnWriteArrayList<Unit>()
        var clearCalls = 0

        override suspend fun currentSelection(): ReadiumSelectionSnapshot? {
            calls += Unit
            val result = if (gates.isNotEmpty()) gates.removeFirst().await() else gate?.await() ?: selection
            if (failWithNotReady) {
                failWithNotReady = false
                throw ReadiumSelectionNavigatorNotReady
            }
            if (failNext) {
                failNext = false
                error("selection_failure")
            }
            return result
        }

        override fun clearSelection() {
            clearCalls++
            if (failClearWithNotReady) throw ReadiumSelectionNavigatorNotReady
            if (failClearNext) {
                failClearNext = false
                error("clear_failure")
            }
        }
    }

    private companion object {
        fun nativeSelection(
            text: String,
            rect: ReadiumSelectionRect? = ReadiumSelectionRect(0f, 0f, 10f, 10f),
        ): ReadiumSelectionSnapshot = ReadiumSelectionSnapshot(
            locator = null,
            selectedText = text,
            textBefore = "before",
            textAfter = "after",
            href = "chapter.xhtml",
            progression = 0.25,
            totalProgression = 0.75,
            rect = rect,
        )
    }
}
