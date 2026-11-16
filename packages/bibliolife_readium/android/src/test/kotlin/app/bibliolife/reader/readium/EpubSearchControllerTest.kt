package app.bibliolife.reader.readium

import java.util.ArrayDeque
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** JVM coverage for the production latest-query-wins coordinator. */
class EpubSearchControllerTest {
    @Test fun `query is trimmed while internal unicode whitespace is preserved`() {
        val gateway = FakeGateway()
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)

        controller.submitQuery("  Київ\t  центр  ")

        assertEquals(listOf("Київ\t  центр"), gateway.queries)
        assertEquals("Київ\t  центр", (state.value as EpubSearchState.Results).query)
    }

    @Test fun `blank query does not invoke gateway and clears state`() {
        val gateway = FakeGateway()
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)

        controller.submitQuery(" \n\t ")

        assertTrue(gateway.queries.isEmpty())
        assertEquals(EpubSearchState.Idle, state.value)
    }

    @Test fun `explicit identical query reruns deterministically`() {
        val gateway = FakeGateway()
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)

        controller.submitQuery("same")
        controller.submitQuery(" same ")

        assertEquals(listOf("same", "same"), gateway.queries)
        assertEquals(2, gateway.sessions.size)
        assertEquals(1, gateway.sessions[0].closeCount)
    }

    @Test fun `ready state preserves source order across batches and marks completion`() {
        val gateway = FakeGateway(
            pages = listOf(
                listOf(hit("one", position = 1), hit("two", position = 2)),
                listOf(hit("three", position = 3)),
                emptyList(),
            ),
        )
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)

        controller.submitQuery("q")
        assertEquals(listOf("one", "two"), resultHighlights(state))
        assertTrue((state.value as EpubSearchState.Results).hasMore)
        controller.loadNextPage()
        assertEquals(listOf("one", "two", "three"), resultHighlights(state))
        controller.loadNextPage()

        val complete = state.value as EpubSearchState.Results
        assertEquals(listOf("one", "two", "three"), complete.results.map { it.highlight })
        assertFalse(complete.hasMore)
        assertEquals(1, gateway.sessions.single().closeCount)
    }

    @Test fun `empty and failure states are nonfatal and close iterator`() {
        val emptyGateway = FakeGateway(pages = listOf(emptyList()))
        val emptyState = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        controller(emptyGateway, emptyState).submitQuery("empty")
        assertEquals(EpubSearchState.Empty("empty", 1), emptyState.value)
        assertEquals(1, emptyGateway.sessions.single().closeCount)

        val failedGateway = QueueGateway(
            listOf(
                FakeSession(pages = emptyList(), failNextPage = true),
                FakeSession(listOf(listOf(hit("recovered")))),
            ),
        )
        val failedState = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val failedController = controller(failedGateway, failedState)
        failedController.submitQuery("failed")
        assertTrue(failedState.value is EpubSearchState.Error)
        assertEquals(1, (failedGateway.sessionsForTest[0] as FakeSession).closeCount)
        failedController.submitQuery("recovered")
        assertTrue(failedState.value is EpubSearchState.Results)
    }

    @Test fun `replacement closes only old iterator and keeps latest results`() {
        val first = GatedSession()
        val second = FakeSession(listOf(listOf(hit("new"))))
        val gateway = QueueGateway(listOf(first, second))
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)

        controller.submitQuery("old")
        controller.submitQuery("new")
        assertEquals("new", (state.value as EpubSearchState.Results).query)
        first.complete(Result.success(listOf(hit("stale"))))

        assertEquals("new", (state.value as EpubSearchState.Results).query)
        assertEquals(listOf("new"), resultHighlights(state))
        assertEquals(1, first.closeCount)
        assertEquals(0, second.closeCount)
    }

    @Test fun `stale failure cannot replace newer successful state`() {
        val first = GatedSession()
        val second = FakeSession(listOf(listOf(hit("fresh"))))
        val gateway = QueueGateway(listOf(first, second))
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)

        controller.submitQuery("old")
        controller.submitQuery("new")
        first.complete(Result.failure(IllegalStateException("stale")))

        assertEquals(listOf("fresh"), resultHighlights(state))
        assertEquals("new", (state.value as EpubSearchState.Results).query)
    }

    @Test fun `ids are deterministic within generation and distinct for duplicates`() {
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val first = EpubSearchHit("chapter.xhtml", "Chapter", "before", "match", "after", 4, .2)
        val duplicate = first.copy()
        val mappedA = EpubSearchResultMapper.map(first, "7:${EpubSearchResultMapper.identity(first)}:0")
        val mappedB = EpubSearchResultMapper.map(duplicate, "7:${EpubSearchResultMapper.identity(duplicate)}:1")

        assertNotEquals(mappedA.result.id, mappedB.result.id)
        assertEquals(mappedA.result, EpubSearchResultMapper.map(first, mappedA.result.id).result)
        assertEquals("chapter.xhtml", mappedA.result.href)
        assertEquals(4, mappedA.result.position)
        assertEquals(.2, mappedA.result.progression)
        assertEquals(EpubSearchState.Idle, state.value)
    }

    @Test fun `old result id is obsolete after replacement and unknown ids are typed`() {
        val gateway = FakeGateway(pages = listOf(listOf(hit("old")), listOf(hit("new"))))
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)
        controller.submitQuery("old")
        val oldId = (state.value as EpubSearchState.Results).results.single().id
        controller.submitQuery("new")

        assertEquals(EpubSearchController.TargetResolution.Obsolete, controller.targetFor(oldId))
        assertEquals(EpubSearchController.TargetResolution.Unknown, controller.targetFor("does-not-exist"))
    }

    @Test fun `dispose closes active iterator and ignores repeated disposal`() {
        val session = FakeSession(listOf(listOf(hit("active"))))
        val gateway = QueueGateway(listOf(session))
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)
        controller.submitQuery("active")
        controller.close()
        controller.close()

        assertEquals(1, session.closeCount)
        assertEquals(EpubSearchState.Idle, state.value)
    }

    @Test fun `explicit cancellation closes active iterator and is idempotent`() {
        val session = GatedSession()
        val gateway = QueueGateway(listOf(session))
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)
        controller.submitQuery("cancel")
        controller.clear()
        controller.clear()
        session.complete(Result.success(listOf(hit("late"))))

        assertEquals(1, session.closeCount)
        assertEquals(EpubSearchState.Idle, state.value)
    }

    @Test fun `late result after disposal cannot mutate idle state`() {
        val session = GatedSession()
        val gateway = QueueGateway(listOf(session))
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val controller = controller(gateway, state)
        controller.submitQuery("dispose")
        controller.close()
        session.complete(Result.success(listOf(hit("late"))))

        assertEquals(EpubSearchState.Idle, state.value)
        assertEquals(1, session.closeCount)
    }

    private fun controller(gateway: EpubSearchGateway, state: MutableStateFlow<EpubSearchState>) =
        EpubSearchController(CoroutineScope(Dispatchers.Unconfined), gateway, state)

    private fun resultHighlights(state: MutableStateFlow<EpubSearchState>) =
        (state.value as EpubSearchState.Results).results.map { it.highlight }

    private fun hit(text: String, position: Int? = null) = EpubSearchHit(
        href = "chapter.xhtml",
        title = "Chapter",
        before = "before",
        highlight = text,
        after = "after",
        position = position,
        progression = null,
    )

    private class FakeGateway(
        private val pages: List<List<EpubSearchHit>> = listOf(
            listOf(EpubSearchHit("chapter.xhtml", "Chapter", "before", "match", "after", null, null)),
        ),
        private val failNextPage: Boolean = false,
    ) : EpubSearchGateway {
        val queries = mutableListOf<String>()
        val sessions = mutableListOf<FakeSession>()
        override suspend fun start(query: String): EpubSearchSession {
            queries += query
            val session = FakeSession(pages, failNextPage)
            sessions += session
            return session
        }
    }

    private class QueueGateway(private val queued: List<EpubSearchSession>) : EpubSearchGateway {
        val queries = mutableListOf<String>()
        val sessionsForTest = queued
        private val sessions = ArrayDeque(queued)
        override suspend fun start(query: String): EpubSearchSession {
            queries += query
            return sessions.removeFirst()
        }
    }

    private open class FakeSession(
        private val pages: List<List<EpubSearchHit>>,
        private val failNextPage: Boolean = false,
    ) : EpubSearchSession {
        private var pageIndex = 0
        var closeCount = 0
            private set
        override suspend fun nextPage(): Result<List<EpubSearchHit>> {
            if (failNextPage) return Result.failure(IllegalStateException("iterator failure"))
            return Result.success(pages.getOrElse(pageIndex++) { emptyList() })
        }
        override fun close() { closeCount++ }
    }

    private class GatedSession : EpubSearchSession {
        private val gate = CompletableDeferred<Result<List<EpubSearchHit>>>()
        var closeCount = 0
            private set
        override suspend fun nextPage(): Result<List<EpubSearchHit>> =
            withContext(NonCancellable) { gate.await() }
        fun complete(value: Result<List<EpubSearchHit>>) { gate.complete(value) }
        override fun close() { closeCount++ }
    }
}
