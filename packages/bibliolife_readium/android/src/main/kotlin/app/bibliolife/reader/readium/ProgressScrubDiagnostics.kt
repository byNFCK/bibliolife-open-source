package app.bibliolife.reader.readium

import org.readium.r2.navigator.epub.continuous.ContinuousFinalViewportVerification
import org.readium.r2.navigator.epub.continuous.ContinuousViewportVerification

/** Formats existing A10 evidence; never decides whether navigation may publish. */
internal fun progressVerificationDiagnosticFields(
    verification: ContinuousFinalViewportVerification?,
    requested: Double,
    requestedIndex: Int?,
    ownerCurrent: Boolean,
): Map<String, Any?> = mapOf(
    "requestedProgress" to requested,
    "requestedReadingOrderIndex" to requestedIndex,
    "requestedProgression" to verification?.targetProgression,
    "observedProgression" to verification?.finalVisibleProgression,
    "sameRequestedResource" to verification?.sameResource,
    "targetRangeAtReadingAnchor" to verification?.targetRangeAtReadingAnchor,
    "authorityStillCurrent" to verification?.authorityStillCurrent,
    "viewportVerification" to verification?.classification?.name,
    "resourceProgressError" to verification?.let { v -> v.finalVisibleProgression?.let { actual -> v.targetProgression?.let { actual - it } } },
    "result" to when {
        !ownerCurrent || verification?.classification == ContinuousViewportVerification.SUPERSEDED -> "superseded"
        verification?.classification == ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT -> "verified"
        verification?.classification == ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT -> "mismatch"
        else -> "failed"
    },
)
