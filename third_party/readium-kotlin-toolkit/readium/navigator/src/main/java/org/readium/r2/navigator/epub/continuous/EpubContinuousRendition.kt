package org.readium.r2.navigator.epub.continuous

import android.view.ViewGroup
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.Selection
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Locator

/**
 * Narrow host boundary for the fragment-independent EPUB rendition.
 * The real Readium WebView implementation is intentionally supplied in C-2.
 */
public data class EpubContinuousHostBinding(
    val container: ViewGroup,
    val generation: Long,
)

/** Exact live WebView owner of a continuous native selection. */
public data class EpubContinuousSelectionIdentity(
    val readingOrderIndex: Int,
    val href: String,
    val resourceGeneration: Long,
)

/** Native selection lifecycle forwarded from one resource-local WebView. */
public data class EpubContinuousSelectionEvent(
    val active: Boolean,
    val identity: EpubContinuousSelectionIdentity,
    val nativeSessionId: Long,
)

/** A normal R2BasicWebView tap, already filtered by Readium's native rules. */
public data class EpubContinuousContentTapEvent(
    val identity: EpubContinuousSelectionIdentity,
)

/** A persistent decoration activation expressed in the continuous host's coordinates. */
public data class EpubContinuousDecorationActivationEvent(
    val identity: EpubContinuousSelectionIdentity,
    val decorationId: String,
    val group: String,
    val rect: android.graphics.RectF,
    val tint: Int?,
    val selectedText: String,
)

/** A resource that completed the real Readium bootstrap for this exact generation. */
public data class EpubContinuousResourceReadyEvent(
    val readingOrderIndex: Int,
    val resourceGeneration: Long,
)

/** Terminal result of a Continuous preference application.
 *
 * Geometry changes are successful only after the semantic reading position has
 * been restored and can be committed by the session. Non-geometry preferences
 * retain the lightweight [Applied] result.
 */
public sealed class EpubContinuousPreferenceResult {
    public data object Applied : EpubContinuousPreferenceResult()
    public data class ReflowCommitted(
        val locator: Locator,
        val readingOrderIndex: Int,
        val commitOwner: EpubContinuousGeometryCommitOwner? = null,
    ) : EpubContinuousPreferenceResult()
    public data class FailedAfterCommitStart(
        val commitOwner: EpubContinuousGeometryCommitOwner,
    ) : EpubContinuousPreferenceResult()
    public data object CaptureUnavailable : EpubContinuousPreferenceResult()
    public data object TargetNotReady : EpubContinuousPreferenceResult()
    public data object SemanticRestoreFailed : EpubContinuousPreferenceResult()
    public data object VisibilityMismatch : EpubContinuousPreferenceResult()
    public data object Cancelled : EpubContinuousPreferenceResult()
}

/** Exact owner of the non-interruptible visible geometry commit boundary. */
public data class EpubContinuousGeometryCommitOwner(
    val preferenceGeneration: Long,
    val transactionGeneration: Long,
    val layoutGeneration: Int,
)

/** Terminal result of one Continuous Locator navigation transaction. */
public enum class ContinuousNavigationOutcome {
    ACCEPTED,
    FAILED_BEFORE_POSITION,
    POSITION_APPLIED_BUT_NOT_ACCEPTED,
    SUPERSEDED_AFTER_POSITION,
}

/** Trust in the final Continuous viewport after the requested position was applied. */
public enum class ContinuousViewportVerification {
    VERIFIED_TARGET_VIEWPORT,
    NOT_VERIFIED_TARGET_VIEWPORT,
    SUPERSEDED,
    UNAVAILABLE,
}

/** Minimal evidence retained for session correlation and later target-identity decisions. */
public data class ContinuousFinalViewportVerification(
    val classification: ContinuousViewportVerification,
    val sameResource: Boolean,
    val targetRangeAtReadingAnchor: Boolean?,
    val finalVisibleProgression: Double?,
    val targetProgression: Double?,
    val authorityStillCurrent: Boolean,
)

internal fun classifyContinuousFinalViewport(
    positionApplied: Boolean,
    authorityStillCurrent: Boolean,
    targetGenerationCurrent: Boolean,
    finalLocatorAvailable: Boolean,
    sameResource: Boolean,
    targetRangeAtReadingAnchor: Boolean?,
): ContinuousViewportVerification = when {
    !positionApplied -> ContinuousViewportVerification.UNAVAILABLE
    !authorityStillCurrent || !targetGenerationCurrent -> ContinuousViewportVerification.SUPERSEDED
    !finalLocatorAvailable -> ContinuousViewportVerification.UNAVAILABLE
    !sameResource -> ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT
    targetRangeAtReadingAnchor == null -> ContinuousViewportVerification.UNAVAILABLE
    !targetRangeAtReadingAnchor -> ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT
    else -> ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT
}

/** Outcome paired with the caller-owned identity of the navigation request. */
public data class ContinuousNavigationResult(
    val transactionId: Long,
    val outcome: ContinuousNavigationOutcome,
    val finalViewportVerification: ContinuousFinalViewportVerification =
        ContinuousFinalViewportVerification(
            classification = ContinuousViewportVerification.UNAVAILABLE,
            sameResource = false,
            targetRangeAtReadingAnchor = null,
            finalVisibleProgression = null,
            targetProgression = null,
            authorityStillCurrent = false,
        ),
) {
    /** Preserves the historical Boolean contract of [EpubContinuousRendition.go]. */
    public val accepted: Boolean get() = outcome == ContinuousNavigationOutcome.ACCEPTED
}

/** Tracks the newest request identity without changing navigation execution. */
internal class ContinuousNavigationAuthority {
    private val latestTransactionId = java.util.concurrent.atomic.AtomicReference<Long?>(null)

    fun begin(transactionId: Long) {
        latestTransactionId.set(transactionId)
    }

    fun invalidateCurrent() {
        latestTransactionId.set(null)
    }

    fun isCurrent(transactionId: Long): Boolean = latestTransactionId.get() == transactionId

    fun outcomeBeforePosition(): ContinuousNavigationOutcome =
        ContinuousNavigationOutcome.FAILED_BEFORE_POSITION

    fun outcomeAfterPosition(
        transactionId: Long,
        targetIsAuthoritative: Boolean,
        accepted: Boolean,
    ): ContinuousNavigationOutcome = when {
        !isCurrent(transactionId) || !targetIsAuthoritative ->
            ContinuousNavigationOutcome.SUPERSEDED_AFTER_POSITION
        accepted -> ContinuousNavigationOutcome.ACCEPTED
        else -> ContinuousNavigationOutcome.POSITION_APPLIED_BUT_NOT_ACCEPTED
    }
}

public interface EpubContinuousRendition {
    public fun attach(binding: EpubContinuousHostBinding)
    public fun detach(generation: Long)
    public fun dispose()
    /** Reports parent-viewport movement; the session owns query coalescing. */
    public fun setViewportChangedListener(listener: (() -> Unit)?)
    /** Invalidates the active programmatic target as soon as a manual drag begins. */
    public fun setManualDragStartedListener(listener: (() -> Unit)?): Unit = Unit
    /** Reports entry/exit of a manual drag and its associated inertial settling. */
    public fun setManualScrollActivityChangedListener(listener: ((Boolean) -> Unit)?): Unit = Unit
    /** Reports actual viewport movement during a manual drag or its settling. */
    public fun setManualScrollProgressListener(listener: (() -> Unit)?): Unit = Unit
    /** Reports that a resource can now answer real Readium Locator commands. */
    public fun setResourceReadyListener(listener: ((EpubContinuousResourceReadyEvent) -> Unit)?)
    /** Reports the terminal outcome of the first visible continuous viewport. */
    public fun setInitialViewportListeners(
        onReady: (() -> Unit)?,
        onFailure: ((String) -> Unit)?,
    )
    /**
     * Snapshots the real resource-local target at the stable parent reading
     * anchor. A target is available only while that exact resource generation
     * is live and has completed the Readium bootstrap.
     */
    public fun currentLocatorAnchor(): EpubContinuousLocatorAnchor?
    /** Runs the real Readium Locator command against an anchor snapshot. */
    public suspend fun findLocatorAtReadingAnchor(anchor: EpubContinuousLocatorAnchor): Locator?
    /** Direct, resource-local navigation through the continuous outer host. */
    public suspend fun go(locator: Locator): Boolean
    /**
     * Direct navigation with a unique, non-negative transaction identity and
     * terminal stage. Session navigation generations provide this identity.
     */
    public suspend fun goWithOutcome(locator: Locator, transactionId: Long): ContinuousNavigationResult =
        ContinuousNavigationResult(
            transactionId,
            if (go(locator)) ContinuousNavigationOutcome.ACCEPTED
            else ContinuousNavigationOutcome.FAILED_BEFORE_POSITION,
        )
    /** Runs this navigation only while the caller's captured request owner remains current. */
    public suspend fun goWithOutcome(
        locator: Locator,
        transactionId: Long,
        isRequestCurrent: () -> Boolean,
    ): ContinuousNavigationResult = goWithOutcome(locator, transactionId)
    /**
     * Restores the reader's opening Locator only after its target has real
     * measured geometry. This keeps an initial placeholder from becoming a
     * visible, transient reading position.
     */
    public suspend fun restoreInitialLocator(locator: Locator): Boolean
    public suspend fun restoreInitialLocator(
        locator: Locator,
        onDiagnostic: (stage: String, result: String, facts: Map<String, Any?>) -> Unit,
    ): Boolean = restoreInitialLocator(locator)
    /** Whether [preferences] requires the generation-bound geometry transaction. */
    public fun requiresGeometryReflow(preferences: EpubPreferences): Boolean
    /** Prevents an active geometry transaction from publishing a stale commit. */
    public fun supersedeGeometryReflow()
    /** Cancels only settings previews older than [requestId], keeping the session alive. */
    public fun supersedeSettingsPreviewsBefore(requestId: Long) {}
    public fun hasPendingCssGeometry(): Boolean = false
    public suspend fun settingsReflowGesture(gestureId: Long, slider: String, action: String, value: Double): Boolean = false
    public suspend fun applyPreferences(
        preferences: EpubPreferences,
        preferenceGeneration: Long,
    ): EpubContinuousPreferenceResult
    public suspend fun applyPreferencesWithDiagnostics(
        preferences: EpubPreferences,
        preferenceGeneration: Long,
        diagnosticContext: EpubContinuousReflowDiagnosticContext?,
        previewRequestId: Long? = null,
        holdGeometryCommitUntilSessionAcknowledged: Boolean = false,
    ): EpubContinuousPreferenceResult = applyPreferences(preferences, preferenceGeneration)
    /** Releases a session-held visible geometry commit after canonical publication and terminal. */
    public fun acknowledgeGeometryCommit(owner: EpubContinuousGeometryCommitOwner): Boolean = false
    /** Reads the exact in-flight owner so session failure cleanup cannot leak a lease. */
    public fun geometryCommitOwner(preferenceGeneration: Long): EpubContinuousGeometryCommitOwner? = null
    /** Synchronous O(1) viewport geometry for diagnostics; never triggers a layout or locator query. */
    public fun diagnosticViewportLayoutSnapshot(
        anchorIndex: Int? = null,
    ): EpubContinuousViewportLayoutSnapshot? = null
    /** Observer-only context captured with a settings request, never part of preferences. */
    public fun setReflowDiagnosticListener(listener: ((EpubContinuousReflowDiagnosticEvent) -> Unit)?) {}
    /** Selection remains resource-local: one native WebView, one spine resource. */
    public fun setSelectionSessionListener(listener: ((EpubContinuousSelectionEvent) -> Unit)?)
    public fun setContentTapListener(listener: ((EpubContinuousContentTapEvent) -> Boolean)?)
    /** Forwards a real decoration tap from its live resource WebView. */
    public fun setDecorationActivationListener(listener: ((EpubContinuousDecorationActivationEvent) -> Boolean)?)
    /** Reuses Readium Decoration objects; non-live resources are never created for this. */
    public suspend fun applyDecorations(decorations: List<Decoration>, group: String)
    public suspend fun currentSelection(): Selection?
    public fun clearSelection()
}

/** Whitelisted settings gesture identity kept adjacent to the preference request. */
public data class EpubContinuousReflowDiagnosticContext(
    val gestureId: Long,
    val slider: String,
    val applyId: Long,
    val normalizedValue: Double,
)

/** Existing Continuous lifecycle facts, emitted without affecting layout decisions. */
public data class EpubContinuousReflowDiagnosticEvent(
    val kind: String,
    val context: EpubContinuousReflowDiagnosticContext?,
    val semanticAnchorFields: Map<String, Any> = emptyMap(),
    val preferenceGeneration: Long? = null,
    val transactionGeneration: Long? = null,
    val layoutGeneration: Int? = null,
    val resourceGeneration: Long? = null,
    val measurementGeneration: Long? = null,
    val readingOrderIndex: Int? = null,
    val oldHeightPx: Long? = null,
    val newHeightPx: Long? = null,
    val anchorBeforeIndex: Int? = null,
    val anchorBeforeOffsetPx: Int? = null,
    val scrollAnchorIndex: Int? = null,
    val scrollAnchorOffsetPx: Int? = null,
    val anchorBeforeY: Double? = null,
    val anchorBeforeYCoordinateSpace: String? = "resource_local_px",
    val anchorAfterY: Double? = null,
    val targetViewportYPx: Double? = null,
    val actualViewportYPx: Double? = null,
    val observedReadingOrderIndex: Int? = null,
    val observedProgression: Double? = null,
    val semanticProgressionDelta: Double? = null,
    val viewportScrollReason: String? = null,
    val viewportFirstVisibleIndexBefore: Int? = null,
    val viewportFirstVisibleIndexAfter: Int? = null,
    val viewportFirstVisibleTopBeforePx: Int? = null,
    val viewportFirstVisibleTopAfterPx: Int? = null,
    val viewportFirstVisibleTopDeltaPx: Int? = null,
    val result: String? = null,
    val snapshotStage: String? = null,
    val viewportSampleStage: String? = null,
    val anchorPointSampleStage: String? = null,
    val viewportFirstVisibleIndex: Int? = null,
    val viewportFirstVisibleTopPx: Int? = null,
    val viewportHeightPx: Int? = null,
    val viewportPaddingTopPx: Int? = null,
    val viewportPaddingBottomPx: Int? = null,
    val viewportAnchorIndex: Int? = null,
    val viewportAnchorTopPx: Int? = null,
    val viewportAnchorBottomPx: Int? = null,
    val webViewIdentity: Int? = null,
    val webViewIdentityUnavailableReason: String? = null,
    val anchorResourceHref: String? = null,
    val anchorResourceHrefUnavailableReason: String? = null,
    val anchorProgression: Double? = null,
    val anchorBeforeLocalYPx: Double? = null,
    val anchorBeforeViewportYPx: Double? = null,
    val anchorPointDocumentYPx: Double? = null,
    val anchorPointViewportYPx: Double? = null,
    val anchorPointAvailable: Boolean? = null,
    val anchorPointUnavailableReason: String? = null,
    val anchorViewportDeltaPx: Double? = null,
    val anchorViewportTolerancePx: Double? = null,
    val anchorSemanticMatch: Boolean? = null,
    val requestedCorrectionOffsetPx: Int? = null,
    val requestedViewportDeltaPx: Double? = null,
    val commitLockHeld: Boolean? = null,
    val predecessorMeasurementCount: Int? = null,
    val predecessorHeightDeltaPx: Long? = null,
    val batchHeightDeltaPx: Long? = null,
    val dispatchStage: String? = null,
    val dispatchIntervalSincePreviousMs: Double? = null,
    val activeApply: Boolean? = null,
    val pendingLatest: Boolean? = null,
    val scrollRequestIssued: Boolean? = null,
)

/** Returns only a short relative resource path; never diagnostic query/fragment/userinfo data. */
internal fun boundedContinuousDiagnosticResourceHref(rawHref: String): String? {
    val path = rawHref.substringBefore('?').substringBefore('#')
    if (path.isEmpty() || path.length > 160 || path.startsWith('/') || path.contains('@')) return null
    if (!Regex("^(?:[A-Za-z0-9_./-]|%[0-9A-Fa-f]{2}){1,160}$").matches(path)) return null
    return path
}

/** Synchronous RecyclerView snapshot. Missing values stay null instead of using estimated geometry. */
public data class EpubContinuousViewportLayoutSnapshot(
    val firstVisibleIndex: Int?,
    val firstVisibleTopPx: Int?,
    val heightPx: Int?,
    val paddingTopPx: Int?,
    val paddingBottomPx: Int?,
    val anchorIndex: Int?,
    val anchorTopPx: Int?,
    val anchorBottomPx: Int?,
    val webViewIdentity: Int? = null,
    val webViewIdentityUnavailableReason: String? = null,
)

/**
 * A generation-bound parent-anchor measurement. Its coordinates are local to
 * the selected resource WebView, never a RecyclerView restore position.
 */
public data class EpubContinuousLocatorAnchor(
    val readingOrderIndex: Int,
    val resourceGeneration: Long,
    val layoutGeneration: Int,
    val x: Double,
    val y: Double,
)
