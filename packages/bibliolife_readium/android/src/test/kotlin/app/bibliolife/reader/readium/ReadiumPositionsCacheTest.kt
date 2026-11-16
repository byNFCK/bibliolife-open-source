package app.bibliolife.reader.readium

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class ReadiumPositionsCacheTest {
    @Test fun `positions are computed once and shared by concurrent consumers`() = runBlocking {
        var loads = 0
        val positions = emptyList<List<org.readium.r2.shared.publication.Locator>>()
        val cache = ReadiumPositionsCache {
            loads += 1
            positions
        }

        val results = List(5) { async { cache.get().getOrThrow() } }.awaitAll()

        assertEquals(1, loads)
        assertEquals(0, results.first().totalLogicalPositions)
        assertEquals(0, results.first().navigationTargets.size)
        assertEquals(0, cache.cachedOrNull()?.positions?.size)
        assertEquals(0, cache.cachedOrNull()?.positionsByReadingOrder?.size)
    }

    @Test fun `failed computation is cached and not retried per locator event`() = runBlocking {
        var loads = 0
        val cache = ReadiumPositionsCache {
            loads += 1
            error("positions unavailable")
        }

        repeat(3) { assertEquals(true, cache.get().isFailure) }

        assertEquals(1, loads)
    }
}
