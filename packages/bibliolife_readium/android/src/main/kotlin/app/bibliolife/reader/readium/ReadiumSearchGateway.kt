package app.bibliolife.reader.readium

import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.services.search.SearchIterator
import org.readium.r2.shared.publication.services.search.search

internal interface EpubSearchGateway {
    suspend fun start(query: String): EpubSearchSession
}

internal interface EpubSearchSession : AutoCloseable {
    suspend fun nextPage(): Result<List<EpubSearchHit>>
    override fun close()
}

@OptIn(ExperimentalReadiumApi::class)
internal class ReadiumSearchGateway(private val publication: Publication) : EpubSearchGateway {
    override suspend fun start(query: String): EpubSearchSession =
        ReadiumSearchSession(publication.search(query) ?: error("Readium search is unavailable"))
}

private class ReadiumSearchSession(private val iterator: SearchIterator) : EpubSearchSession {
    private var closed = false
    override suspend fun nextPage(): Result<List<EpubSearchHit>> = runCatching {
        check(!closed)
        val page = iterator.next().getOrNull() ?: error("Readium search failed")
        page.locators.map(EpubSearchHit::from)
    }
    override fun close() { if (!closed) { closed = true; iterator.close() } }
}
