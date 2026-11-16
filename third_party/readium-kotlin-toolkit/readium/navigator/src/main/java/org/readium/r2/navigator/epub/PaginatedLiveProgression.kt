package org.readium.r2.navigator.epub

/** Maps the real horizontal viewport into logical progression for one paginated resource. */
internal fun paginatedLocalProgression(
    scrollX: Int,
    contentWidth: Int,
    viewportWidth: Int,
    pageCount: Int,
    rtl: Boolean,
): Double {
    if (pageCount <= 1 || viewportWidth <= 0) return 0.0

    val maxScroll = (contentWidth - viewportWidth).coerceAtLeast(0)
    if (maxScroll == 0) return 0.0

    val physicalProgression = (scrollX.toDouble() / maxScroll).coerceIn(0.0, 1.0)
    return if (rtl) 1.0 - physicalProgression else physicalProgression
}

/** Uses the publication's canonical resource span, matching Readium's locator services. */
internal fun paginatedTotalProgression(
    localProgression: Double,
    resourceStart: Double?,
    nextResourceStart: Double?,
): Double? {
    if (!localProgression.isFinite() || resourceStart == null || !resourceStart.isFinite() ||
        resourceStart !in 0.0..1.0
    ) return null

    val resourceEnd = nextResourceStart ?: 1.0
    if (!resourceEnd.isFinite() || resourceEnd !in resourceStart..1.0) return null

    val local = localProgression.coerceIn(0.0, 1.0)
    return resourceStart + local * (resourceEnd - resourceStart)
}
