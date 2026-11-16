package org.readium.r2.navigator.epub.continuous

import kotlin.math.abs

internal enum class ContinuousReflowPath(val diagnosticValue: String) {
    NO_OP("no_op"), ANCHOR_ONLY("anchor_only"), FULL_REFLOW("full_reflow")
}

/** All individual dependencies must be unchanged; cancelling height deltas are insufficient. */
internal fun continuousReflowPath(
    currentMeasurements: Boolean,
    exactAnchor: Boolean,
    geometryUnchanged: Boolean,
    anchorViewportDeltaPx: Double?,
): ContinuousReflowPath = when {
    !currentMeasurements || !exactAnchor || !geometryUnchanged || anchorViewportDeltaPx?.isFinite() != true -> ContinuousReflowPath.FULL_REFLOW
    continuousAnchorViewportMatches(anchorViewportDeltaPx) -> ContinuousReflowPath.NO_OP
    else -> ContinuousReflowPath.ANCHOR_ONLY
}

/** Android parent-layout pixels, separate from the existing semantic tolerance. */
internal fun continuousAnchorScrollRequired(deltaPx: Double): Boolean =
    deltaPx.isFinite() && abs(deltaPx) > 0.5
