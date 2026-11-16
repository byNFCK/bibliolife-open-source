package app.bibliolife.reader.readium

import kotlin.math.roundToInt
import org.readium.r2.shared.publication.Locator

/**
 * Immutable publication-position index for the continuous rendition. Its
 * ordering comes exclusively from Readium's positionsByReadingOrder service;
 * physical resource heights and resource count are intentionally irrelevant.
 */
internal class ContinuousPublicationPositionMap(
    val positionsByReadingOrder: List<List<Locator>>,
) {
    private val index = ContinuousPublicationPositionIndex(
        positionsByReadingOrder.map { resource ->
            resource.map { locator ->
                ContinuousPublicationPositionIndex.Entry(
                    value = locator,
                    href = locator.href.toString(),
                    position = locator.locations.position,
                    progression = locator.locations.progression,
                    totalProgression = locator.locations.totalProgression,
                )
            }
        },
    )

    val totalPositionCount: Int get() = index.totalPositionCount

    fun progressionFor(readingOrderIndex: Int?, locator: Locator): Double? {
        return index.progressionFor(
            readingOrderIndex = readingOrderIndex,
            href = locator.href.toString(),
            position = locator.locations.position,
            progression = locator.locations.progression,
            totalProgression = locator.locations.totalProgression,
        )
    }

    /** Preserves the point Locator while attaching its canonical Readium position. */
    fun withCanonicalPosition(readingOrderIndex: Int?, locator: Locator): Locator {
        return resolvePosition(readingOrderIndex, locator)?.locator ?: locator
    }

    fun resolvePosition(
        readingOrderIndex: Int?,
        locator: Locator,
    ): ContinuousResolvedPublicationPosition? {
        val localProgression = locator.locations.progression
            ?.takeIf { it.isFinite() && it in 0.0..1.0 }
            ?: return null
        val canonical = index.positionFor(
            readingOrderIndex = readingOrderIndex,
            href = locator.href.toString(),
            progression = localProgression,
        ) ?: return null
        val enriched = locator.copyWithLocations(
            progression = localProgression,
            position = canonical.position,
            totalProgression = canonical.totalProgression,
        )
        val totalProgression = progressionFor(readingOrderIndex, enriched) ?: return null
        return ContinuousResolvedPublicationPosition(enriched, totalProgression)
    }

    fun targetFor(progression: Double): Locator? {
        return index.targetFor(progression)
    }

}

internal data class ContinuousResolvedPublicationPosition(
    val locator: Locator,
    val totalProgression: Double,
)

/** Pure position arithmetic, kept Android-free for deterministic JVM coverage. */
internal class ContinuousPublicationPositionIndex<T>(
    positionsByReadingOrder: List<List<Entry<T>>>,
) {
    internal data class Entry<T>(
        val value: T,
        val href: String,
        val position: Int?,
        val progression: Double?,
        val totalProgression: Double?,
    )

    private val byResource = positionsByReadingOrder
    private val positions = positionsByReadingOrder.flatten()
    val totalPositionCount: Int get() = positions.size

    fun progressionFor(
        readingOrderIndex: Int?,
        href: String,
        position: Int?,
        progression: Double?,
        totalProgression: Double?,
    ): Double? {
        totalProgression?.takeIf { it in 0.0..1.0 }?.let { return it }
        position?.let { requested ->
            positions.indexOfFirst { it.position == requested }.takeIf { it >= 0 }?.let { return progressionAtIndex(it) }
        }
        val resourceIndex = readingOrderIndex
            ?.takeIf { it in byResource.indices }
            ?: byResource.indexOfFirst { resource -> resource.any { it.href == href } }
                .takeIf { it >= 0 }
            ?: return null
        val resourcePositions = byResource[resourceIndex]
        val local = progression?.coerceIn(0.0, 1.0) ?: return null
        if (resourcePositions.isEmpty()) return null
        val start = byResource.take(resourceIndex).sumOf { it.size }
        val offset = if (resourcePositions.size == 1) 0 else (local * (resourcePositions.size - 1)).roundToInt()
        return progressionAtIndex(start + offset.coerceIn(0, resourcePositions.lastIndex))
    }

    fun targetFor(progression: Double): T? {
        if (positions.isEmpty()) return null
        val normalized = progression.coerceIn(0.0, 1.0)
        val totalBased = positions.minByOrNull { entry ->
            entry.totalProgression?.let { kotlin.math.abs(it - normalized) } ?: Double.POSITIVE_INFINITY
        }?.takeIf { it.totalProgression != null }
        return (totalBased ?: positions[if (positions.size == 1) 0 else (normalized * (positions.size - 1)).roundToInt()]).value
    }

    fun positionFor(readingOrderIndex: Int?, href: String, progression: Double): Entry<T>? {
        val resource = readingOrderIndex
            ?.takeIf { it in byResource.indices }
            ?.let(byResource::get)
            ?: byResource.firstOrNull { entries -> entries.any { it.href == href } }
            ?: return null
        if (resource.isEmpty()) return null
        val offset = if (resource.size == 1) 0 else (progression.coerceIn(0.0, 1.0) * (resource.size - 1)).roundToInt()
        return resource[offset.coerceIn(0, resource.lastIndex)]
    }

    private fun progressionAtIndex(index: Int): Double =
        if (positions.size <= 1) 0.0 else index.toDouble() / (positions.size - 1)
}
