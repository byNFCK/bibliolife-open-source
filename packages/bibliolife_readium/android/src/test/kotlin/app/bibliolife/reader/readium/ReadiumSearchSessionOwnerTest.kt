package app.bibliolife.reader.readium

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadiumSearchSessionOwnerTest {
    @Test fun `owner forwards one query and exposes one authoritative state`() {
        val gateway = OwnerGateway()
        val state = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
        val owner = ReadiumSearchSessionOwner(CoroutineScope(Dispatchers.Unconfined), gateway, state)

        owner.search("query")
        val firstObservation = owner.state
        val secondObservation = owner.state

        assertSame(state, firstObservation)
        assertSame(firstObservation, secondObservation)
        assertEquals(listOf("query"), gateway.queries)
        assertTrue(owner.state.value is EpubSearchState.Results)
    }

    @Test fun `clear and cancel do not start native blank searches`() {
        val gateway = OwnerGateway()
        val owner = ReadiumSearchSessionOwner(CoroutineScope(Dispatchers.Unconfined), gateway)
        owner.search("query")
        owner.clear()
        owner.cancel()

        assertEquals(listOf("query"), gateway.queries)
        assertEquals(EpubSearchState.Idle, owner.state.value)
    }

    @Test fun `dispose closes controller once and ignores later events`() {
        val gateway = OwnerGateway()
        val owner = ReadiumSearchSessionOwner(CoroutineScope(Dispatchers.Unconfined), gateway)
        owner.search("query")
        owner.close()
        owner.close()
        owner.search("after-dispose")
        owner.clear()

        assertEquals(listOf("query"), gateway.queries)
        assertEquals(1, gateway.session.closeCount)
        assertEquals(EpubSearchState.Idle, owner.state.value)
    }

    private class OwnerGateway : EpubSearchGateway {
        val queries = mutableListOf<String>()
        val session = OwnerSession()
        override suspend fun start(query: String): EpubSearchSession {
            queries += query
            return session
        }
    }

    private class OwnerSession : EpubSearchSession {
        var closeCount = 0
        override suspend fun nextPage() = Result.success(listOf(EpubSearchHit("chapter", "Chapter", null, "match", null, null, null)))
        override fun close() { closeCount++ }
    }
}
