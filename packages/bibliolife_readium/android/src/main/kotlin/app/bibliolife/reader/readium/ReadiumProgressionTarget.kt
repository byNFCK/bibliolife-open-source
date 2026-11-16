package app.bibliolife.reader.readium

import org.readium.r2.shared.publication.Locator

internal sealed interface ReadiumProgressionTarget {
    val requestedProgression: Double
}

internal data class RenderedPageTarget(
    override val requestedProgression: Double,
    val pageIndex: Int,
    val pageCount: Int,
) : ReadiumProgressionTarget

internal data class ResourceProgressionTarget(
    override val requestedProgression: Double,
    val locator: Locator,
) : ReadiumProgressionTarget

internal data class PublicationProgressionTarget(
    override val requestedProgression: Double,
    val locator: Locator,
) : ReadiumProgressionTarget

internal fun renderedPageTarget(value: Double, pageCount: Int): RenderedPageTarget? {
    if (!value.isFinite() || value !in 0.0..1.0 || pageCount < 1) return null
    val pageIndex = if (pageCount == 1) 0 else (value * (pageCount - 1)).toInt().let { floor ->
        if (value * (pageCount - 1) - floor >= 0.5) floor + 1 else floor
    }
    return RenderedPageTarget(value, pageIndex.coerceIn(0, pageCount - 1), pageCount)
}

/** Builds a clean continuous target without copying stale text, fragments or selectors. */
internal fun Locator.withContinuousProgression(value: Double): Locator? {
    val locations = continuousProgressionLocations(value) ?: return null
    return Locator(
        href = href,
        mediaType = mediaType,
        title = title,
        locations = locations,
    )
}

internal fun continuousProgressionLocations(value: Double): Locator.Locations? {
    if (!value.isFinite() || value !in 0.0..1.0) return null
    return Locator.Locations(progression = value, totalProgression = value)
}
