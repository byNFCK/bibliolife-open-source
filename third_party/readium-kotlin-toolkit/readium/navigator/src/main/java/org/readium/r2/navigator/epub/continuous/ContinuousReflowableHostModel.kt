package org.readium.r2.navigator.epub.continuous

import kotlin.math.max
import kotlin.math.min

/**
 * Geometry and lifecycle contract for a future native continuous reflowable
 * host. It is deliberately independent from the production reader: actual
 * resource views report their measured HTML height into this model.
 *
 * The model owns one parent vertical coordinate system. A resource keeps its
 * EPUB href and is never merged into a different document.
 */
internal class ContinuousReflowableHostModel(
    private val readingOrder: List<String>,
    private val preloadDistancePx: Long = 1_800,
    private val maxNonVisibleLiveResources: Int = 8,
) {
    init {
        require(readingOrder.isNotEmpty())
        require(readingOrder.distinct().size == readingOrder.size)
        require(preloadDistancePx >= 0)
        require(maxNonVisibleLiveResources >= 0)
    }

    data class ResourceGeometry(
        val index: Int,
        val href: String,
        val startPx: Long,
        val heightPx: Long,
    ) {
        val endPx: Long get() = startPx + heightPx
    }

    data class VirtualizationPlan(
        val liveIndices: Set<Int>,
        val recycleIndices: Set<Int>,
    )

    data class LocatorAnchor(
        val href: String,
        val progression: Double,
    )

    /** A stable parent-viewport anchor, expressed only transiently in layout pixels. */
    data class ViewportReadingAnchor(
        val resource: ResourceGeometry,
        val localY: Long,
        val fraction: Double,
    )

    private data class MeasuredHeight(
        val generation: Int,
        val heightPx: Long,
    )

    private val measuredHeights = mutableMapOf<Int, MeasuredHeight>()
    // Last known values remain useful for RecyclerView geometry while a
    // retained WebView is measuring its new CSS layout. They are deliberately
    // separate from current-generation measurements.
    private val geometryPlaceholders = mutableMapOf<Int, Long>()
    private val liveIndices = mutableSetOf<Int>()
    private val selectionPinnedIndices = mutableSetOf<Int>()

    var layoutGeneration: Int = 0
        private set

    /** A recycled view releases its WebView, but keeps this generation's height placeholder. */
    fun reportMeasuredHeight(index: Int, heightPx: Long, generation: Int = layoutGeneration) {
        checkIndex(index)
        require(heightPx > 0)
        require(generation == layoutGeneration) { "Stale resource measurement" }
        measuredHeights[index] = MeasuredHeight(generation, heightPx)
        geometryPlaceholders[index] = heightPx
    }

    /** Validates the complete set before changing any current-generation geometry. */
    fun reportMeasuredHeightsTogether(measurements: Collection<ResourceLayoutMeasurement>) {
        require(measurements.isNotEmpty())
        require(measurements.map { it.index }.distinct().size == measurements.size)
        measurements.forEach { measurement ->
            checkIndex(measurement.index)
            require(measurement.heightPx > 0)
            require(measurement.layoutGeneration == layoutGeneration) { "Stale resource measurement" }
        }
        measurements.forEach { measurement ->
            measuredHeights[measurement.index] = MeasuredHeight(layoutGeneration, measurement.heightPx)
            geometryPlaceholders[measurement.index] = measurement.heightPx
        }
    }

    fun measuredHeightOrNull(index: Int): Long? {
        checkIndex(index)
        return measuredHeights[index]
            ?.takeIf { it.generation == layoutGeneration }
            ?.heightPx
    }

    fun geometryHeightOrNull(index: Int): Long? {
        checkIndex(index)
        return measuredHeights[index]
            ?.takeIf { it.generation == layoutGeneration }
            ?.heightPx ?: geometryPlaceholders[index]
    }

    /**
     * Replaces a live measurement while preserving the logical content under
     * the parent viewport if the changed resource is entirely above it.
     */
    fun replaceMeasuredHeightAndAdjustScroll(
        index: Int,
        heightPx: Long,
        currentScrollPx: Long,
    ): Long {
        val oldGeometry = geometryFor(index)
        reportMeasuredHeight(index, heightPx)
        val delta = heightPx - oldGeometry.heightPx
        return if (oldGeometry.endPx <= currentScrollPx) max(0, currentScrollPx + delta) else currentScrollPx
    }

    fun invalidateForReflow(): Int {
        layoutGeneration += 1
        measuredHeights.clear()
        geometryPlaceholders.clear()
        liveIndices.clear()
        return layoutGeneration
    }

    /** Advances freshness while retaining real heights solely as interim geometry. */
    fun beginInPlaceReflow(): Int {
        measuredHeights.forEach { (index, measured) -> geometryPlaceholders[index] = measured.heightPx }
        layoutGeneration += 1
        measuredHeights.clear()
        return layoutGeneration
    }

    fun geometryFor(index: Int): ResourceGeometry {
        checkIndex(index)
        requireAllResourcesMeasured()
        val startPx = (0 until index).sumOf { measuredHeights.getValue(it).heightPx }
        return ResourceGeometry(index, readingOrder[index], startPx, measuredHeights.getValue(index).heightPx)
    }

    fun geometry(): List<ResourceGeometry> = readingOrder.indices.map(::geometryFor)

    fun documentHeightPx(): Long = geometry().last().endPx

    fun visibleResources(scrollPx: Long, viewportHeightPx: Long): List<ResourceGeometry> {
        require(scrollPx >= 0)
        require(viewportHeightPx > 0)
        val viewportEnd = scrollPx + viewportHeightPx
        return geometry().filter { it.startPx < viewportEnd && it.endPx > scrollPx }
    }

    /** The first intersecting resource is the future primary Locator owner. */
    fun activeResource(scrollPx: Long, viewportHeightPx: Long): ResourceGeometry =
        visibleResources(scrollPx, viewportHeightPx).first()

    /**
     * Selects the resource containing a stable point in the parent viewport.
     * This avoids letting a few trailing pixels of A override B when the
     * reader's actual anchor is already inside B.
     */
    fun readingAnchor(
        scrollPx: Long,
        viewportHeightPx: Long,
        fraction: Double = READING_ANCHOR_FRACTION,
    ): ViewportReadingAnchor {
        require(scrollPx >= 0)
        require(viewportHeightPx > 0)
        require(fraction in 0.0..1.0)
        val anchorY = (scrollPx + viewportHeightPx * fraction).toLong()
            .coerceIn(0, max(0, documentHeightPx() - 1))
        val resource = geometry().first { anchorY >= it.startPx && anchorY < it.endPx }
        return ViewportReadingAnchor(resource, anchorY - resource.startPx, fraction)
    }

    /** One scroll state; crossing a seam is just a change in global offset. */
    fun scrollBy(currentScrollPx: Long, deltaPx: Long, viewportHeightPx: Long): Long {
        val maximum = max(0, documentHeightPx() - viewportHeightPx)
        return (currentScrollPx + deltaPx).coerceIn(0, maximum)
    }

    fun setSelectionPinned(index: Int, pinned: Boolean) {
        checkIndex(index)
        if (pinned) selectionPinnedIndices += index else selectionPinnedIndices -= index
    }

    /**
     * Keeps every visible resource, pinned selection, and a pixel-based
     * preload window. The cap applies only to non-visible, non-pinned views,
     * so short resources are never replaced with viewport-sized gaps.
     */
    fun planVirtualization(scrollPx: Long, viewportHeightPx: Long): VirtualizationPlan {
        val visible = visibleResources(scrollPx, viewportHeightPx).map { it.index }.toSet()
        val preloadStart = max(0, scrollPx - preloadDistancePx)
        val preloadEnd = min(documentHeightPx(), scrollPx + viewportHeightPx + preloadDistancePx)
        val candidates = geometry()
            .filter { it.startPx < preloadEnd && it.endPx > preloadStart }
            .map { it.index }
            .filterNot { it in visible || it in selectionPinnedIndices }
            .sortedBy { index -> distanceToViewport(geometryFor(index), scrollPx, viewportHeightPx) }
            .take(maxNonVisibleLiveResources)

        val nextLive = visible + selectionPinnedIndices + candidates
        val recycle = liveIndices - nextLive
        liveIndices.clear()
        liveIndices += nextLive
        return VirtualizationPlan(nextLive, recycle)
    }

    fun liveResourceIndices(): Set<Int> = liveIndices.toSet()

    fun locatorAnchor(scrollPx: Long, viewportHeightPx: Long, resourceProgression: Double): LocatorAnchor {
        val resource = activeResource(scrollPx, viewportHeightPx)
        return LocatorAnchor(resource.href, resourceProgression.coerceIn(0.0, 1.0))
    }

    private fun distanceToViewport(
        geometry: ResourceGeometry,
        scrollPx: Long,
        viewportHeightPx: Long,
    ): Long = when {
        geometry.endPx < scrollPx -> scrollPx - geometry.endPx
        geometry.startPx > scrollPx + viewportHeightPx -> geometry.startPx - (scrollPx + viewportHeightPx)
        else -> 0
    }

    private fun requireAllResourcesMeasured() {
        require(measuredHeights.size == readingOrder.size) { "Geometry requires current-generation heights for every resource" }
        require(measuredHeights.values.all { it.generation == layoutGeneration })
    }

    private fun checkIndex(index: Int) {
        require(index in readingOrder.indices)
    }

    private companion object {
        const val READING_ANCHOR_FRACTION = 0.25
    }
}

/** One generation-owned collection of parent geometry measurements. */
internal data class ContinuousGeometryBatchOwner(
    val preferenceGeneration: Long?,
    val transactionGeneration: Long,
    val layoutGeneration: Int,
)

internal enum class ContinuousGeometryBatchState {
    COLLECTING, READY, COMMIT_STARTED, APPLIED, COMMITTED, DISCARDED, FAILED, FAILED_AFTER_COMMIT_START,
}

internal enum class ContinuousGeometryBatchCollection { REQUIRED, DEFERRED, READY, DUPLICATE, STALE }

internal class ContinuousGeometryMeasurementBatch(
    val owner: ContinuousGeometryBatchOwner,
    val anchor: ContinuousReflowTarget,
    requiredResourceGenerations: Map<Int, Long>,
) {
    private val required = requiredResourceGenerations.toMap()
    private val requiredMeasurements = linkedMapOf<Int, ResourceLayoutMeasurement>()
    private val deferredMeasurements = linkedMapOf<Int, ResourceLayoutMeasurement>()
    private val commitStartedMeasurements = linkedMapOf<Int, ResourceLayoutMeasurement>()

    var state: ContinuousGeometryBatchState = ContinuousGeometryBatchState.COLLECTING
        private set
    var failedResource: ContinuousReflowTarget? = null
        private set

    init {
        require(owner.layoutGeneration == anchor.layoutGeneration)
        require(required[anchor.index] == anchor.resourceGeneration)
        require(required.isNotEmpty())
    }

    fun requiredResourceGenerations(): Map<Int, Long> = required

    /** Snapshot of required resources that have not reported for this batch. */
    fun missingRequiredResourceGenerations(): Map<Int, Long> =
        required.filterKeys { it !in requiredMeasurements }

    fun isRequired(index: Int, resourceGeneration: Long): Boolean =
        required[index] == resourceGeneration

    fun collect(measurement: ResourceLayoutMeasurement): ContinuousGeometryBatchCollection {
        if (measurement.layoutGeneration == owner.layoutGeneration &&
            state == ContinuousGeometryBatchState.COMMIT_STARTED
        ) {
            val previous = commitStartedMeasurements[measurement.index]
            if (previous != null && previous.measurementGeneration >= measurement.measurementGeneration) {
                return ContinuousGeometryBatchCollection.DUPLICATE
            }
            commitStartedMeasurements[measurement.index] = measurement
            return ContinuousGeometryBatchCollection.DEFERRED
        }
        if (measurement.layoutGeneration != owner.layoutGeneration ||
            state in setOf(
                ContinuousGeometryBatchState.DISCARDED,
                ContinuousGeometryBatchState.FAILED,
                ContinuousGeometryBatchState.FAILED_AFTER_COMMIT_START,
                ContinuousGeometryBatchState.COMMIT_STARTED,
                ContinuousGeometryBatchState.COMMITTED,
            )
        ) return ContinuousGeometryBatchCollection.STALE

        val requiredGeneration = required[measurement.index]
        if (state in setOf(ContinuousGeometryBatchState.COLLECTING, ContinuousGeometryBatchState.READY) &&
            requiredGeneration == measurement.resourceGeneration
        ) {
            val previous = requiredMeasurements[measurement.index]
            if (previous != null && previous.measurementGeneration >= measurement.measurementGeneration) {
                return ContinuousGeometryBatchCollection.DUPLICATE
            }
            requiredMeasurements[measurement.index] = measurement
            if (requiredMeasurements.keys.containsAll(required.keys)) {
                state = ContinuousGeometryBatchState.READY
                return ContinuousGeometryBatchCollection.READY
            }
            return ContinuousGeometryBatchCollection.REQUIRED
        }

        val previous = deferredMeasurements[measurement.index]
        if (previous == null || previous.measurementGeneration < measurement.measurementGeneration) {
            deferredMeasurements[measurement.index] = measurement
        } else {
            return ContinuousGeometryBatchCollection.DUPLICATE
        }
        return ContinuousGeometryBatchCollection.DEFERRED
    }

    fun failRequired(target: ContinuousReflowTarget): Boolean {
        if (state !in setOf(ContinuousGeometryBatchState.COLLECTING, ContinuousGeometryBatchState.READY) ||
            !isRequired(target.index, target.resourceGeneration) ||
            target.layoutGeneration != owner.layoutGeneration
        ) return false
        failedResource = target
        state = ContinuousGeometryBatchState.FAILED
        requiredMeasurements.clear()
        deferredMeasurements.clear()
        return true
    }

    fun requiredMeasurementsForCommit(): List<ResourceLayoutMeasurement>? =
        if (state == ContinuousGeometryBatchState.READY) {
            required.keys.sorted().mapNotNull(requiredMeasurements::get).takeIf { it.size == required.size }
        } else null

    /** Current optional reports can join the atomic apply without extending the wait. */
    fun optionalMeasurementsForCommit(): List<ResourceLayoutMeasurement> =
        if (state == ContinuousGeometryBatchState.READY) {
            deferredMeasurements.values.filterNot { it.index in required }.sortedBy { it.index }
        } else emptyList()

    fun markApplied(): Boolean {
        if (state != ContinuousGeometryBatchState.COMMIT_STARTED) return false
        state = ContinuousGeometryBatchState.APPLIED
        deferredMeasurements.clear()
        return true
    }

    /** Fresh same-height ownership, with no parent dimension or layout mutation. */
    fun acknowledgeUnchangedGeometry(): Boolean {
        if (state !in setOf(ContinuousGeometryBatchState.READY, ContinuousGeometryBatchState.COMMIT_STARTED)) return false
        state = ContinuousGeometryBatchState.APPLIED
        deferredMeasurements.clear()
        return true
    }

    fun beginCommit(): Boolean {
        if (state != ContinuousGeometryBatchState.READY) return false
        state = ContinuousGeometryBatchState.COMMIT_STARTED
        return true
    }

    fun markCommitted(): Boolean {
        if (state != ContinuousGeometryBatchState.APPLIED) return false
        state = ContinuousGeometryBatchState.COMMITTED
        return true
    }

    fun discard(): Boolean {
        if (state == ContinuousGeometryBatchState.COMMITTED || state == ContinuousGeometryBatchState.DISCARDED ||
            state == ContinuousGeometryBatchState.FAILED || state == ContinuousGeometryBatchState.APPLIED ||
            state == ContinuousGeometryBatchState.COMMIT_STARTED || state == ContinuousGeometryBatchState.FAILED_AFTER_COMMIT_START
        ) return false
        state = ContinuousGeometryBatchState.DISCARDED
        requiredMeasurements.clear()
        deferredMeasurements.clear()
        return true
    }

    fun fail(): Boolean {
        if (state == ContinuousGeometryBatchState.COMMITTED || state == ContinuousGeometryBatchState.DISCARDED ||
            state == ContinuousGeometryBatchState.FAILED || state == ContinuousGeometryBatchState.APPLIED ||
            state == ContinuousGeometryBatchState.COMMIT_STARTED || state == ContinuousGeometryBatchState.FAILED_AFTER_COMMIT_START
        ) return false
        state = ContinuousGeometryBatchState.FAILED
        requiredMeasurements.clear()
        deferredMeasurements.clear()
        return true
    }

    fun failAfterCommitStart(): Boolean {
        if (state !in setOf(ContinuousGeometryBatchState.COMMIT_STARTED, ContinuousGeometryBatchState.APPLIED)) return false
        state = ContinuousGeometryBatchState.FAILED_AFTER_COMMIT_START
        requiredMeasurements.clear()
        return true
    }

    /** Post-restore measurements retain REG2D-R2 handling through the host's normal path. */
    fun finish(): List<ResourceLayoutMeasurement> {
        val pending = (deferredMeasurements.values + commitStartedMeasurements.values)
            .groupBy { it.index }
            .values
            .map { measurements -> measurements.maxBy { it.measurementGeneration } }
            .sortedBy { it.index }
        deferredMeasurements.clear()
        commitStartedMeasurements.clear()
        requiredMeasurements.clear()
        return pending
    }
}

/** Maps a resource Locator progression through Readium position counts, never resource index/count. */
internal object ContinuousPublicationProgression {
    fun totalProgression(positionCounts: List<Int>, resourceIndex: Int, progression: Double): Double {
        require(positionCounts.isNotEmpty())
        require(resourceIndex in positionCounts.indices)
        require(positionCounts.all { it > 0 })
        val total = positionCounts.sum().toDouble()
        val before = positionCounts.take(resourceIndex).sum()
        return ((before + positionCounts[resourceIndex] * progression.coerceIn(0.0, 1.0)) / total)
            .coerceIn(0.0, 1.0)
    }
}

/** Integration invariant for the future host; it must stay inside the existing PlatformView/session. */
internal data class ContinuousHostOwnership(
    val platformViewCount: Int,
    val publicationCount: Int,
    val readerSessionCount: Int,
) {
    init {
        require(platformViewCount == 1)
        require(publicationCount == 1)
        require(readerSessionCount == 1)
    }
}
