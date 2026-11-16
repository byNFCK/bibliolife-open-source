package app.bibliolife.reader.readium

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.readium.r2.shared.publication.Locator

internal data class CachedReadiumPositions(
    val positions: List<Locator>,
    val positionsByReadingOrder: List<List<Locator>>,
    val navigationTargets: List<ProgressNavigationTarget>,
) {
    val totalLogicalPositions: Int get() = positions.size
    val continuousPositionMap: ContinuousPublicationPositionMap by lazy {
        ContinuousPublicationPositionMap(positionsByReadingOrder)
    }

    fun continuousPositionState(
        locator: Locator,
        readingOrderIndex: Int?,
        presentation: ReadiumPresentationState,
    ): ReadiumPositionState? {
        val resolved = continuousPositionMap.resolvePosition(readingOrderIndex, locator) ?: return null
        return ReadiumPositionState(
            locator = resolved.locator,
            progression = resolved.totalProgression,
            totalLogicalPositions = totalLogicalPositions,
            presentation = presentation,
        )
    }
}

/** Computes Readium's publication positions at most once for one reader session. */
internal class ReadiumPositionsCache(
    private val loader: suspend () -> List<List<Locator>>,
) {
    private val mutex = Mutex()

    @Volatile
    private var result: Result<CachedReadiumPositions>? = null

    fun cachedOrNull(): CachedReadiumPositions? = result?.getOrNull()

    suspend fun get(): Result<CachedReadiumPositions> {
        result?.let { return it }
        return mutex.withLock {
            result?.let { return@withLock it }
            runCatching {
                val positionsByReadingOrder = loader()
                val positions = positionsByReadingOrder.flatten()
                CachedReadiumPositions(
                    positions = positions,
                    positionsByReadingOrder = positionsByReadingOrder,
                    navigationTargets = ProgressNavigationModel.targets(positions),
                )
            }.also { result = it }
        }
    }
}
