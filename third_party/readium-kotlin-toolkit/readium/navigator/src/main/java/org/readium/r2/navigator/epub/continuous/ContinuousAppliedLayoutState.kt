package org.readium.r2.navigator.epub.continuous

/** Physical WebView state survives logical transaction cancellation. */
internal class ContinuousAppliedLayoutState {
    data class Snapshot(
        val applied: ContinuousCssMutationOwner?,
        val measuredHeightPx: Long?,
        val committed: ContinuousCssMutationOwner?,
        val committedHeightPx: Long?,
    ) {
        val pending: Boolean get() = applied != null &&
            (committed != applied || measuredHeightPx == null || measuredHeightPx != committedHeightPx)
    }
    private var state = Snapshot(null, null, null, null)

    @Synchronized fun snapshot(): Snapshot = state

    @Synchronized fun applied(owner: ContinuousCssMutationOwner): ContinuousCssMutationOwner? {
        if (state.applied == owner) return null
        val transferred = state.applied?.takeIf { state.pending }
        state = state.copy(applied = owner, measuredHeightPx = null)
        return transferred
    }

    @Synchronized fun measured(layoutGeneration: Int, resourceGeneration: Long, epoch: Long, heightPx: Long): Boolean {
        val owner = state.applied ?: return false
        if (owner.layoutGeneration != layoutGeneration || owner.resourceGeneration != resourceGeneration || owner.measurementEpoch != epoch) return false
        state = state.copy(measuredHeightPx = heightPx)
        return true
    }

    @Synchronized fun commit(measurement: ResourceLayoutMeasurement): Boolean {
        val owner = state.applied ?: return false
        if (owner.layoutGeneration != measurement.layoutGeneration || owner.resourceGeneration != measurement.resourceGeneration ||
            owner.measurementEpoch != measurement.measurementEpoch || state.measuredHeightPx != measurement.heightPx ||
            (measurement.appliedCssToken != null && measurement.appliedCssToken != owner.token)) return false
        state = state.copy(committed = owner, committedHeightPx = measurement.heightPx)
        return true
    }
}
