package app.bibliolife.reader.readium

import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadiumDecorationCoordinatorTest {
    @Test
    fun `initial empty snapshot is submitted after readiness to clear restored native state`() = runBlocking {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        val results = mutableListOf<ReadiumDecorationCoordinator.Result>()

        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, emptyList(), results::add)
        assertTrue(gateway.calls.isEmpty())
        coordinator.onNavigatorReady()
        yield()

        assertEquals(1, gateway.calls.size)
        assertTrue(gateway.calls.single().decorations.isEmpty())
        assertEquals(ReadiumDecorationCoordinator.Result.Applied, results.single())
    }

    @Test
    fun `queues a snapshot before navigator readiness and applies it once`() = runBlocking {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        val results = mutableListOf<ReadiumDecorationCoordinator.Result>()

        assertEquals(
            ReadiumDecorationCoordinator.Result.Queued,
            coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, listOf(spec("a")), results::add),
        )
        assertTrue(gateway.calls.isEmpty())
        coordinator.onNavigatorReady()
        yield()

        assertEquals(listOf("bibliolife-reader-annotations"), gateway.calls.map { it.group })
        assertEquals(listOf(ReadiumDecorationCoordinator.Result.Applied), results)
    }

    @Test
    fun `identical pending snapshots are deduplicated`() = runBlocking {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        coordinator.onNavigatorReady()
        val results = mutableListOf<ReadiumDecorationCoordinator.Result>()
        val value = listOf(spec("a"))

        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, value, results::add)
        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, value, results::add)
        yield()

        assertEquals(1, gateway.calls.size)
        assertEquals(2, results.size)
        assertEquals(ReadiumDecorationCoordinator.Result.Unchanged, results[1])
    }

    @Test
    fun `latest pending snapshot supersedes the older pending snapshot`() = runBlocking {
        val gate = CompletableDeferred<Unit>()
        val gateway = FakeGateway(gate)
        val coordinator = coordinator(gateway)
        coordinator.onNavigatorReady()
        val results = mutableListOf<ReadiumDecorationCoordinator.Result>()

        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, listOf(spec("a")), results::add)
        yield()
        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, listOf(spec("b")), results::add)
        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, listOf(spec("c")), results::add)
        gate.complete(Unit)
        yield()

        assertEquals(listOf("a", "c"), gateway.calls.map { it.decorations.single().id })
        assertTrue(results.contains(ReadiumDecorationCoordinator.Result.Superseded))
        assertEquals(ReadiumDecorationCoordinator.Result.Applied, results.last())
    }

    @Test
    fun `a failed request remains retryable`() = runBlocking {
        val gateway = FakeGateway(failNext = true)
        val coordinator = coordinator(gateway)
        coordinator.onNavigatorReady()
        val results = mutableListOf<ReadiumDecorationCoordinator.Result>()
        val value = listOf(spec("retry"))

        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, value, results::add)
        yield()
        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, value, results::add)
        yield()

        assertEquals(2, gateway.calls.size)
        assertEquals(ReadiumDecorationCoordinator.Result.Failed, results[0])
        assertEquals(ReadiumDecorationCoordinator.Result.Applied, results[1])
    }

    @Test
    fun `persistent and search groups are isolated`() = runBlocking {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        coordinator.onNavigatorReady()
        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, listOf(spec("persistent")))
        coordinator.replace(ReadiumDecorationGroup.SEARCH_RESULT, listOf(spec("search")))
        yield()

        assertEquals(
            setOf("bibliolife-reader-annotations", "search-result"),
            gateway.calls.map { it.group }.toSet(),
        )
    }

    @Test
    fun `search waits while selection is protected`() = runBlocking {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        coordinator.onNavigatorReady()
        coordinator.setSelectionProtected(true)
        coordinator.replace(ReadiumDecorationGroup.SEARCH_RESULT, listOf(spec("search")))
        yield()
        assertTrue(gateway.calls.isEmpty())

        coordinator.setSelectionProtected(false)
        yield()
        assertEquals(listOf("search-result"), gateway.calls.map { it.group })
    }

    @Test
    fun `dispose cancels pending and suppresses later completion state`() = runBlocking {
        val gate = CompletableDeferred<Unit>()
        val gateway = FakeGateway(gate)
        val coordinator = coordinator(gateway)
        coordinator.onNavigatorReady()
        val results = mutableListOf<ReadiumDecorationCoordinator.Result>()
        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, listOf(spec("a")), results::add)
        yield()
        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, listOf(spec("b")), results::add)
        coordinator.dispose()
        gate.complete(Unit)
        yield()

        assertTrue(results.contains(ReadiumDecorationCoordinator.Result.SessionDisposed))
        assertFalse(coordinator.snapshot(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS).isApplying)
    }

    @Test
    fun `duplicate IDs are reduced to the first stable entry`() = runBlocking {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        coordinator.onNavigatorReady()
        coordinator.replace(
            ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS,
            listOf(spec("same", tint = 1), spec("same", tint = 2)),
        )
        yield()

        assertEquals(1, gateway.calls.single().decorations.size)
        assertEquals(1, gateway.calls.single().decorations.single().style.let { (it as ReadiumDecorationStyle.Highlight).tint })
    }

    @Test
    fun `empty replacement clears a group`() = runBlocking {
        val gateway = FakeGateway()
        val coordinator = coordinator(gateway)
        coordinator.onNavigatorReady()
        coordinator.replace(ReadiumDecorationGroup.SEARCH_RESULT, listOf(spec("search")))
        yield()
        coordinator.replace(ReadiumDecorationGroup.SEARCH_RESULT, emptyList())
        yield()

        assertEquals(2, gateway.calls.size)
        assertTrue(gateway.calls.last().decorations.isEmpty())
    }

    @Test
    fun `native calls are serialized across groups`() = runBlocking {
        val first = CompletableDeferred<Unit>()
        val gateway = FakeGateway(first)
        val coordinator = coordinator(gateway)
        coordinator.onNavigatorReady()
        coordinator.replace(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, listOf(spec("a")))
        yield()
        coordinator.replace(ReadiumDecorationGroup.SEARCH_RESULT, listOf(spec("s")))
        yield()
        assertEquals(1, gateway.maxActive)
        first.complete(Unit)
        yield()
        assertEquals(2, gateway.calls.size)
    }

    private fun coordinator(gateway: FakeGateway) = ReadiumDecorationCoordinator(
        scope = CoroutineScope(Dispatchers.Unconfined),
        gateway = gateway,
    )

    private fun spec(id: String, tint: Int = 7): ReadiumDecorationSpec = ReadiumDecorationSpec(
        id = id,
        locator = null,
        style = ReadiumDecorationStyle.Highlight(tint),
    )

    private class FakeGateway(
        private val gate: CompletableDeferred<Unit>? = null,
        private var failNext: Boolean = false,
    ) : ReadiumDecorationGateway {
        data class Call(val group: String, val decorations: List<ReadiumDecorationSpec>)

        val calls = CopyOnWriteArrayList<Call>()
        var active = 0
        var maxActive = 0

        override suspend fun replace(group: String, decorations: List<ReadiumDecorationSpec>) {
            active++
            maxActive = maxOf(maxActive, active)
            calls += Call(group, decorations)
            try {
                gate?.await()
                if (failNext) {
                    failNext = false
                    error("fake_failure")
                }
            } finally {
                active--
            }
        }
    }
}
