@file:OptIn(ExperimentalReadiumApi::class, InternalReadiumApi::class)

package org.readium.r2.navigator.epub.continuous

import android.app.Application
import android.graphics.PointF
import android.graphics.RectF
import android.util.Log
import android.view.ActionMode
import android.view.DragEvent
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONObject
import org.readium.r2.navigator.R2BasicWebView
import org.readium.r2.navigator.Selection
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.DecorationChange
import org.readium.r2.navigator.epub.EpubDefaults
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubResourceCallbacks
import org.readium.r2.navigator.epub.EpubResourceWebViewFactory
import org.readium.r2.navigator.epub.EpubSettingsResolver
import org.readium.r2.navigator.epub.update
import org.readium.r2.navigator.epub.extensions.javascriptForGroup
import org.readium.r2.navigator.html.HtmlDecorationTemplates
import org.readium.r2.navigator.epub.EpubWebPublicationEnvironment
import org.readium.r2.navigator.epub.EpubWebResourceIdentity
import org.readium.r2.navigator.epub.WebViewServer
import org.readium.r2.navigator.epub.css.ReadiumCss
import org.readium.r2.navigator.epub.css.readiumBeforeCssContentLoader
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.toAbsoluteUrl
import org.readium.r2.shared.util.resource.Resource

/**
 * The real C-2 renderer. It owns one publication environment and therefore one
 * WebViewServer; every concurrently-live spine resource is configured through
 * the same Readium factory and served URL space.
 */
/** Single owner of the semantic transaction; callbacks only advance this state. */
internal class ContinuousGeometryReflowTransaction(
    val generation: Long,
    val preferenceGeneration: Long = 0L,
    val anchor: ContinuousAnchorLocator,
    val requestedPreferences: EpubPreferences,
) {
    enum class State { CAPTURED, MATERIALIZED, RESTORED, CONVERGED, COMPLETED, CANCELLED }

    var targetReadingOrderIndex: Int = anchor.index
        private set
    var targetResourceGeneration: Long? = null
        private set
    var targetLayoutGeneration: Int? = null
        private set
    var materialized = false
        private set
    var restored = false
        private set
    var converged = false
        private set
    var state = State.CAPTURED
        private set
    var layoutGeneration: Int? = null
        private set
    var commitOwner: EpubContinuousGeometryCommitOwner? = null
        private set
    var verifiedLocatorPoint: ContinuousResolvedLocatorPoint? = null
        private set
    var verifiedViewportDeltaPx: Double? = null
        private set
    var verifiedObservedProgression: Double? = null
        private set
    var presentationTransactionActive: Boolean = false
        private set
    var anchorScrollRequested: Boolean = false
    var superseded = false
        private set

    fun bindLayoutGeneration(value: Int) {
        check(layoutGeneration == null || layoutGeneration == value)
        layoutGeneration = value
    }

    fun tryBeginCommit(owner: ContinuousGeometryBatchOwner): Boolean {
        if (!matchesCommitOwner(owner)) return false
        val expected = EpubContinuousGeometryCommitOwner(preferenceGeneration, generation, requireNotNull(layoutGeneration))
        if (commitOwner != null) return commitOwner == expected
        if (terminal || superseded) return false
        commitOwner = expected
        return true
    }

    fun tryMarkSuperseded(): Boolean {
        if (commitOwner != null) return false
        if (terminal) return true
        superseded = true
        return true
    }

    fun matchesCommitOwner(owner: ContinuousGeometryBatchOwner): Boolean =
        owner.preferenceGeneration == preferenceGeneration &&
            owner.transactionGeneration == generation && owner.layoutGeneration == layoutGeneration

    val terminal: Boolean get() = state == State.COMPLETED || state == State.CANCELLED

    fun markMaterialized(target: ContinuousReflowTarget): Boolean {
        if (terminal || target.index != anchor.index) return false
        targetReadingOrderIndex = target.index
        targetResourceGeneration = target.resourceGeneration
        targetLayoutGeneration = target.layoutGeneration
        materialized = true
        state = State.MATERIALIZED
        return true
    }

    fun canRestore(target: ContinuousReflowTarget): Boolean =
        !terminal && materialized && target.index == targetReadingOrderIndex &&
            target.resourceGeneration == targetResourceGeneration && target.layoutGeneration == targetLayoutGeneration

    fun markRestored(): Boolean = if (canAdvance(State.MATERIALIZED)) {
        restored = true
        state = State.RESTORED
        true
    } else false

    fun beginPresentationTransaction(): Boolean {
        if (terminal || commitOwner == null || presentationTransactionActive) return false
        presentationTransactionActive = true
        return true
    }

    fun finishPresentationTransaction(): Boolean {
        if (!presentationTransactionActive) return false
        presentationTransactionActive = false
        return true
    }

    fun markConverged(
        locatorPoint: ContinuousResolvedLocatorPoint,
        viewportDeltaPx: Double,
        observedProgression: Double?,
    ): Boolean =
        if (canAdvance(State.RESTORED) && viewportDeltaPx.isFinite()) {
        verifiedLocatorPoint = locatorPoint
        verifiedViewportDeltaPx = viewportDeltaPx
        verifiedObservedProgression = observedProgression
        converged = true
        state = State.CONVERGED
        true
    } else false

    fun complete(): Boolean = if (canAdvance(State.CONVERGED)) {
        state = State.COMPLETED
        true
    } else false

    fun cancel() {
        if (!terminal) state = State.CANCELLED
    }

    fun failAfterCommitStart() {
        if (!terminal) state = State.CANCELLED
    }

    private fun canAdvance(expected: State): Boolean = state == expected && !terminal
}

/** A cancelled preview is an operation result, never cancellation of its session parent. */
internal suspend fun <T> runCancellableSettingsPreviewOperation(
    onStarted: (Job) -> Unit,
    operation: suspend () -> T,
    onCancelled: () -> T,
    onBeforeTerminal: suspend () -> Unit = {},
    onTerminal: (T) -> Unit,
    onFailure: (Throwable) -> Unit,
    onFinished: (Job) -> Unit,
): T = coroutineScope {
    val operationJob = Job(currentCoroutineContext()[Job])
    try {
        onStarted(operationJob)
        val result = try {
            withContext(operationJob) { operation() }
        } catch (_: CancellationException) {
            onBeforeTerminal()
            onCancelled()
        } catch (error: Throwable) {
            onBeforeTerminal()
            onFailure(error)
            throw error
        }
        onBeforeTerminal()
        onTerminal(result)
        result
    } finally {
        onFinished(operationJob)
        operationJob.complete()
    }
}

internal fun EpubContinuousPreferenceResult.toSettingsReflowTerminalResult(
    superseded: Boolean = false,
): String = when (this) {
    EpubContinuousPreferenceResult.Applied,
    is EpubContinuousPreferenceResult.ReflowCommitted,
    -> "committed"
    is EpubContinuousPreferenceResult.FailedAfterCommitStart -> "failed_after_commit_start"
    EpubContinuousPreferenceResult.Cancelled -> if (superseded) "superseded" else "failed"
    EpubContinuousPreferenceResult.CaptureUnavailable,
    EpubContinuousPreferenceResult.TargetNotReady,
    EpubContinuousPreferenceResult.SemanticRestoreFailed,
    EpubContinuousPreferenceResult.VisibilityMismatch,
    -> "failed"
}

internal fun isOlderSettingsPreviewRequest(requestId: Long?, cutoff: Long): Boolean =
    requestId != null && requestId < cutoff

internal fun runGeometryReflowSupersessionIfUnlocked(
    transaction: ContinuousGeometryReflowTransaction?,
    supersede: () -> Unit,
): Boolean {
    if (transaction != null && !transaction.tryMarkSuperseded()) return false
    supersede()
    return true
}

internal fun acknowledgeGeometryCommitForDirectCaller(
    holdUntilSessionAcknowledged: Boolean,
    owner: EpubContinuousGeometryCommitOwner?,
    acknowledge: (EpubContinuousGeometryCommitOwner) -> Unit,
) {
    if (!holdUntilSessionAcknowledged) owner?.let(acknowledge)
}

public class ContinuousEpubRendition private constructor(
    private val publication: Publication,
    private val environment: EpubWebPublicationEnvironment,
    private val css: ReadiumCss,
    private val resourceFactory: EpubResourceWebViewFactory,
    initialPreferences: EpubPreferences,
    private val selectionActionModeCallback: ActionMode.Callback?,
    private val decorationTemplates: HtmlDecorationTemplates,
    private val sessionInstanceId: String,
) : EpubContinuousRendition {
    private var host: ContinuousReflowableHostView? = null
    private var disposed = false
    private val navigationAuthority = ContinuousNavigationAuthority()
    // Session gate generations are positive. Negative IDs are reserved for
    // callers of the historical Boolean adapter and share the same authority.
    private val compatibilityNavigationIds = AtomicLong(-1L)
    private val hostGenerationGate = ContinuousHostGenerationGate()
    private val settingsResolver = EpubSettingsResolver(publication.metadata, EpubDefaults())
    private var resolvedSettings = settingsResolver.settings(initialPreferences)
    private var resolvedCss = css.update(resolvedSettings, useReadiumCssFontSize = true)
    private var reflowGeneration = 0L
    private var activeReflowTransaction: ContinuousGeometryReflowTransaction? = null
    private data class SettingsPreviewOperation(
        val requestId: Long?,
        val preferenceGeneration: Long,
        val job: Job,
        var superseded: Boolean = false,
        var cssOwnerDrains: List<kotlinx.coroutines.CompletableDeferred<Unit>> = emptyList(),
    )
    private var activeSettingsPreview: SettingsPreviewOperation? = null
    private var supersededSettingsPreviewRequestId = 0L
    private var geometryReflowPinLeaseActive = false
    private var geometryReflowHandoffPending = false
    // A rapid preference sequence retains its first pre-reflow semantic anchor.
    // Intermediate geometry must never become a new reading position.
    private var carriedReflowAnchor: ContinuousAnchorLocator? = null
    private val gestureBaseline = ContinuousGestureReflowBaseline<ContinuousAnchorLocator>()

    private fun emitGestureBaseline(result: String, context: EpubContinuousReflowDiagnosticContext, anchor: ContinuousAnchorLocator?, reason: String? = null, actualY: Double? = null) {
        val identity = anchor?.locator?.locations?.get("continuousDomAnchor") as? Map<*, *>
        emitReflowDiagnostic(EpubContinuousReflowDiagnosticEvent(
            kind = "gesture_reflow_baseline", context = context, result = result,
            readingOrderIndex = anchor?.index,
            semanticAnchorFields = buildMap {
                put("anchorIdentityType", if (identity?.get("id") != null) "exact_dom_point" else "progression_fallback")
                (identity?.get("id") as? String)?.let { put("anchorIdentityId", it) }
                (identity?.get("charOffset") as? Number)?.let { put("anchorCharacterOffset", it.toInt()) }
                anchor?.let {
                    put("resourceIndex", it.index)
                    put("originalTargetViewportYPx", it.viewportY)
                    put("pointToTargetOffsetPx", it.viewportY - it.targetViewportY)
                }
                actualY?.let { put("actualBeforeReflowViewportYPx", it) }
                reason?.let { put("reason", it) }
            },
            targetViewportYPx = anchor?.viewportY,
        ))
    }

    private fun invalidateGestureBaseline(reason: String) {
        val owner = gestureBaseline.owner ?: return
        emitGestureBaseline("released", EpubContinuousReflowDiagnosticContext(owner.gestureId, owner.slider, 0, 0.0), gestureBaseline.anchor, reason)
        gestureBaseline.invalidate()
        carriedReflowAnchor = null
    }

    override suspend fun settingsReflowGesture(gestureId: Long, slider: String, action: String, value: Double): Boolean {
        if (disposed) return false
        val context = EpubContinuousReflowDiagnosticContext(gestureId, slider, 0, value)
        when (action) {
            "begin" -> {
                val previousOwner = gestureBaseline.owner
                val previousAnchor = gestureBaseline.anchor
                val owner = gestureBaseline.begin(gestureId, slider)
                if (gestureBaseline.owner != owner) return false
                previousOwner?.takeIf { it != owner }?.let {
                    emitGestureBaseline("released", EpubContinuousReflowDiagnosticContext(it.gestureId, it.slider, 0, 0.0), previousAnchor, "invalidated")
                }
                if (gestureBaseline.anchor != null) return true
                activeSettingsPreview?.job?.join()
                if (disposed || gestureBaseline.owner != owner) return false
                val anchor = captureContinuousAnchor {} ?: run {
                    emitGestureBaseline("unavailable", context, null, "anchor_unavailable")
                    return false
                }
                if (disposed || !gestureBaseline.install(owner, anchor)) return false
                emitGestureBaseline("created", context, anchor)
            }
            "end", "cancel" -> {
                if (!gestureBaseline.matches(gestureId, slider)) return false
                val anchor = gestureBaseline.anchor
                gestureBaseline.release(gestureId)
                emitGestureBaseline("released", context, anchor, if (action == "end") "final_committed" else "cancelled")
            }
            else -> return false
        }
        return true
    }
    private val navigationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var selectionSessionListener: ((EpubContinuousSelectionEvent) -> Unit)? = null
    private var contentTapListener: ((EpubContinuousContentTapEvent) -> Boolean)? = null
    private var resourceReadyListener: ((EpubContinuousResourceReadyEvent) -> Unit)? = null
    private var initialViewportReadyListener: (() -> Unit)? = null
    private var initialViewportFailureListener: ((String) -> Unit)? = null
    private var manualDragStartedListener: (() -> Unit)? = null
    private var manualScrollActivityChangedListener: ((Boolean) -> Unit)? = null
    private var manualScrollProgressListener: (() -> Unit)? = null
    private var reflowEventPortOverride: ContinuousReflowEventPort? = null
    private var reflowHostFactoryOverride: ContinuousReflowHostFactory? = null
    private var reflowHostTestBindingOverride: ContinuousReflowHostTestBinding? = null
    private var activeSelectionOwner: EpubWebResourceIdentity? = null
    private var activeSelectionSessionId: Long? = null
    private var decorationActivationListener: ((EpubContinuousDecorationActivationEvent) -> Boolean)? = null
    private var reflowDiagnosticListener: ((EpubContinuousReflowDiagnosticEvent) -> Unit)? = null
    private val decorations = mutableMapOf<String, List<Decoration>>()

    override fun attach(binding: EpubContinuousHostBinding) {
        check(!disposed) { "Continuous rendition is disposed" }
        val active = hostGenerationGate.activeGeneration
        if (!hostGenerationGate.acceptAttach(binding.generation)) return
        val container = binding.container
        host?.let { existing ->
            if (active == binding.generation && existing.parent === container) {
                Log.d("BiblioLifeContinuous", "CONTINUOUS_HOST_VISUAL_ATTACH generation=${binding.generation} result=already_attached")
                return
            }
            if (existing.parent !== container) {
                (existing.parent as? ViewGroup)?.removeView(existing)
                container.addView(existing)
            }
            hostGenerationGate.commitAttach(binding.generation)
            Log.d("BiblioLifeContinuous", "CONTINUOUS_HOST_VISUAL_ATTACH generation=${binding.generation} result=rebound")
            return
        }
        host = (reflowHostFactoryOverride ?: RuntimeContinuousReflowHostFactory).create(
            context = container.context,
            publication = publication,
            readingOrder = publication.readingOrder,
            eventPort = reflowEventPortOverride ?: RuntimeContinuousReflowEventPort(),
            resourceFactory = ReadiumServedContinuousResourceFactory(
                servedUrl = { _, link -> environment.urlTo(link).toString() },
                configureReadiumWebView = { webView, _, link, resourceGeneration ->
                    resourceFactory.configure(
                        webView = webView,
                        link = link,
                        callbacks = Callbacks(
                            environment = environment,
                            css = { resolvedCss },
                            link = link,
                            index = publication.readingOrder.indexOf(link),
                            generation = resourceGeneration,
                            onInternalLink = ::navigateInternalLink,
                            onSelectionSessionChanged = ::onResourceSelectionSessionChanged,
                            onContentTap = ::onResourceContentTap,
                            onDecorationActivated = ::onResourceDecorationActivated,
                            actionModeCallback = selectionActionModeCallback,
                        ),
                        textZoom = 100,
                    )
                    // Continuous resources never use a nested WebView scroll or page columns.
                    webView.scrollModeFlow.value = true
                    webView.setUserPageNavigationEnabled(ContinuousPresentation.userPageNavigationEnabled)
                },
                applyReadiumCss = ::applyCurrentReadiumCss,
                sessionInstanceId = sessionInstanceId,
            ),
            testBinding = reflowHostTestBindingOverride ?: ContinuousReflowHostTestBinding.None,
        ).also { created ->
            BiblioLifeOpenTimingDiagnostics.lifecycle("HOST_CREATE", instanceId = sessionInstanceId, sessionId = sessionInstanceId, hostId = created.diagnosticHostId, generation = binding.generation)
            created.setResourceReleasedListener(::onResourceReleased)
            created.setResourceReadyListener(::onResourceReady)
            created.setReflowDiagnosticListener(::emitReflowDiagnostic)
            created.setManualDragStartedListener(::onManualDragStarted)
            created.setManualScrollActivityChangedListener { manualScrollActivityChangedListener?.invoke(it) }
            created.setManualScrollProgressListener { manualScrollProgressListener?.invoke() }
            created.setDecorationSnapshotProvider {
                decorations.mapValues { (_, requested) -> requested to decorationTemplates }
            }
            created.setInitialViewportReadyListener { initialViewportReadyListener?.invoke() }
            created.setInitialViewportFailureListener { reason -> initialViewportFailureListener?.invoke(reason) }
            container.addView(created)
        }
        hostGenerationGate.commitAttach(binding.generation)
        Log.d("BiblioLifeContinuous", "CONTINUOUS_HOST_VISUAL_ATTACH generation=${binding.generation} result=created")
    }

    override fun detach(generation: Long) {
        if (disposed || !hostGenerationGate.acceptsDetach(generation)) return
        gestureBaseline.owner?.let { owner ->
            invalidateGestureBaseline("route_closed")
            gestureBaseline.release(owner.gestureId)
        }
        host?.let { current ->
            Log.d("BiblioLifeContinuous", "CONTINUOUS_HOST_VISUAL_DETACH generation=$generation parent=${current.parent?.javaClass?.simpleName}")
            (current.parent as? ViewGroup)?.removeView(current)
        }
    }

    override fun setViewportChangedListener(listener: (() -> Unit)?) {
        host?.setViewportChangedListener(listener)
    }

    override fun setManualDragStartedListener(listener: (() -> Unit)?) {
        manualDragStartedListener = listener
    }

    override fun setManualScrollActivityChangedListener(listener: ((Boolean) -> Unit)?) {
        manualScrollActivityChangedListener = listener
    }

    override fun setManualScrollProgressListener(listener: (() -> Unit)?) {
        manualScrollProgressListener = listener
    }

    private fun onManualDragStarted() {
        if (gestureBaseline.owner != null) {
            invalidateGestureBaseline("manual_scroll")
            supersedeGeometryReflow()
            carriedReflowAnchor = null
        }
        navigationAuthority.invalidateCurrent()
        manualDragStartedListener?.invoke()
    }

    override fun setResourceReadyListener(listener: ((EpubContinuousResourceReadyEvent) -> Unit)?) {
        resourceReadyListener = listener
    }

    override fun setInitialViewportListeners(
        onReady: (() -> Unit)?,
        onFailure: ((String) -> Unit)?,
    ) {
        initialViewportReadyListener = onReady
        initialViewportFailureListener = onFailure
    }

    /** Test-only construction input; production continues to use the runtime port. */
    internal fun setReflowEventPortForTest(port: ContinuousReflowEventPort) {
        check(host == null) { "The reflow event port must be installed before attach" }
        reflowEventPortOverride = port
    }

    /** Internal JVM construction seam; runtime construction remains the default. */
    internal fun setReflowHostTestFactory(
        factory: ContinuousReflowHostFactory,
        binding: ContinuousReflowHostTestBinding,
    ) {
        check(host == null) { "The reflow host factory must be installed before attach" }
        reflowHostFactoryOverride = factory
        reflowHostTestBindingOverride = binding
    }

    override fun setSelectionSessionListener(listener: ((EpubContinuousSelectionEvent) -> Unit)?) {
        selectionSessionListener = listener
    }

    override fun setContentTapListener(listener: ((EpubContinuousContentTapEvent) -> Boolean)?) {
        contentTapListener = listener
    }

    override fun setDecorationActivationListener(
        listener: ((EpubContinuousDecorationActivationEvent) -> Boolean)?,
    ) {
        decorationActivationListener = listener
    }

    override fun setReflowDiagnosticListener(listener: ((EpubContinuousReflowDiagnosticEvent) -> Unit)?) {
        reflowDiagnosticListener = listener
        host?.setReflowDiagnosticListener(::emitReflowDiagnostic)
    }

    override suspend fun applyDecorations(decorations: List<Decoration>, group: String) {
        if (disposed) return
        this.decorations[group] = decorations.toList()
        // Apply only to materialized resources. Future/recreated resources
        // read this current logical state from their own ready callback.
        host?.applyToLiveResources { it.replaceDecorations(group, decorations, decorationTemplates) }
    }

    override suspend fun currentSelection(): Selection? {
        val owner = activeSelectionOwner ?: return null
        if (disposed || host?.isLiveResource(owner.readingOrderIndex, owner.generation) != true) return null
        val selection = host?.currentSelection(owner.readingOrderIndex, owner.generation) ?: return null
        return if (!disposed && activeSelectionOwner == owner &&
            host?.isLiveResource(owner.readingOrderIndex, owner.generation) == true
        ) selection else null
    }

    override fun clearSelection() {
        val owner = activeSelectionOwner ?: return
        // Do the real native clear first. Never clear a recreated generation.
        host?.clearSelection(owner.readingOrderIndex, owner.generation)
        clearSelectionOwner(owner, activeSelectionSessionId)
    }

    private fun onResourceDecorationActivated(
        identity: EpubWebResourceIdentity,
        decorationId: String,
        group: String,
        resourceLocalRect: RectF,
    ): Boolean {
        if (disposed) return false
        val rect = host?.decorationRectInHostCoordinates(
            index = identity.readingOrderIndex,
            generation = identity.generation,
            resourceLocalRect = resourceLocalRect,
        ) ?: return false
        val decoration = decorations[group]
            ?.firstOrNull { it.id == decorationId }
            ?: return false
        val tint = (decoration.style as? Decoration.Style.Tinted)?.tint
        return decorationActivationListener?.invoke(
            EpubContinuousDecorationActivationEvent(
                identity = EpubContinuousSelectionIdentity(
                    readingOrderIndex = identity.readingOrderIndex,
                    href = identity.href,
                    resourceGeneration = identity.generation,
                ),
                decorationId = decorationId,
                group = group,
                rect = rect,
                tint = tint,
                selectedText = decoration.locator.text.highlight.orEmpty(),
            ),
        ) ?: false
    }

    override fun currentLocatorAnchor(): EpubContinuousLocatorAnchor? =
        if (disposed) null else host?.currentLocatorAnchor()

    override suspend fun findLocatorAtReadingAnchor(anchor: EpubContinuousLocatorAnchor): Locator? =
        if (disposed) null else host?.findLocatorAtReadingAnchor(anchor)

    override suspend fun go(locator: Locator): Boolean =
        navigateWithOutcome(locator, compatibilityNavigationIds.getAndDecrement()) { true }.accepted

    override suspend fun goWithOutcome(locator: Locator, transactionId: Long): ContinuousNavigationResult {
        require(transactionId >= 0L) { "Continuous navigation transaction IDs must be non-negative" }
        return navigateWithOutcome(locator, transactionId) { true }
    }

    override suspend fun goWithOutcome(
        locator: Locator,
        transactionId: Long,
        isRequestCurrent: () -> Boolean,
    ): ContinuousNavigationResult {
        require(transactionId >= 0L) { "Continuous navigation transaction IDs must be non-negative" }
        return navigateWithOutcome(locator, transactionId, isRequestCurrent)
    }

    private suspend fun navigateWithOutcome(
        locator: Locator,
        transactionId: Long,
        isRequestCurrent: () -> Boolean,
    ): ContinuousNavigationResult {
        navigationAuthority.begin(transactionId)
        val result = if (disposed) {
            ContinuousNavigationResult(transactionId, ContinuousNavigationOutcome.FAILED_BEFORE_POSITION)
        } else {
            host?.goWithOutcome(locator, transactionId, navigationAuthority, isRequestCurrent)
                ?: ContinuousNavigationResult(transactionId, ContinuousNavigationOutcome.FAILED_BEFORE_POSITION)
        }
        return result
    }

    override suspend fun restoreInitialLocator(locator: Locator): Boolean =
        !disposed && (host?.restoreInitialLocator(locator) == true)

    override suspend fun restoreInitialLocator(
        locator: Locator,
        onDiagnostic: (String, String, Map<String, Any?>) -> Unit,
    ): Boolean {
        val activeHost = host
        if (disposed || activeHost == null) {
            onDiagnostic("target_resource_resolution", "failed", mapOf(
                "failureReason" to if (disposed) "rendition_disposed" else "rendition_host_unavailable",
            ))
            return false
        }
        return activeHost.restoreInitialLocator(locator, onDiagnostic)
    }

    override fun requiresGeometryReflow(preferences: EpubPreferences): Boolean =
        !disposed && (affectsContinuousGeometry(resolvedSettings, settingsResolver.settings(preferences)) || host?.hasPendingCssGeometry() == true)

    override fun hasPendingCssGeometry(): Boolean = !disposed && host?.hasPendingCssGeometry() == true

    override fun supersedeGeometryReflow() {
        ContinuousCssMutationGate.withOwnershipLock {
            val preferenceGeneration = activeSettingsPreview?.preferenceGeneration
            if (preferenceGeneration != null && host?.mustFinishCssGeometry(preferenceGeneration) == true) {
                // Finish this single physical CSS obligation, retaining only the
                // latest pending successor. This is not the geometry commit lock.
                emitReflowDiagnostic(EpubContinuousReflowDiagnosticEvent(
                    kind = "css_generation_state", context = null,
                    preferenceGeneration = preferenceGeneration, result = "supersession_deferred_for_geometry",
                ))
                host?.requestPendingCssMeasurements()
                return@withOwnershipLock
            }
            val transaction = activeReflowTransaction
            // Once the host has begun its visible atomic geometry commit, a newer
            // preference may queue but cannot invalidate this owner mid-restore.
            runGeometryReflowSupersessionIfUnlocked(transaction) {
                transaction?.let { carriedReflowAnchor = it.anchor }
                if (activeSettingsPreview != null) {
                    // A stale suspended capture cannot continue into CSS apply.
                    activeSettingsPreview?.let { operation ->
                        operation.superseded = true
                        operation.cssOwnerDrains = host?.revokePreferenceCssOwners(operation.preferenceGeneration).orEmpty()
                        operation.job.cancel(CancellationException("Geometry reflow superseded"))
                    }
                }
                if (transaction != null) {
                    reflowGeneration += 1
                    geometryReflowHandoffPending = true
                    host?.cancelGeometryReflowWaiters()
                }
            }
        }
    }

    override fun supersedeSettingsPreviewsBefore(requestId: Long) {
        if (disposed || requestId <= supersededSettingsPreviewRequestId) return
        supersededSettingsPreviewRequestId = requestId
        val active = activeSettingsPreview ?: return
        if (isOlderSettingsPreviewRequest(active.requestId, requestId)) {
            supersedeGeometryReflow()
        }
    }

    private var diagnosticPreferenceGeneration: Long? = null
    private var diagnosticPreferenceFontFamily: String = "original"

    override suspend fun applyPreferences(
        preferences: EpubPreferences,
        preferenceGeneration: Long,
    ): EpubContinuousPreferenceResult = applyPreferencesWithDiagnostics(
        preferences,
        preferenceGeneration,
        null,
    )

    override suspend fun applyPreferencesWithDiagnostics(
        preferences: EpubPreferences,
        preferenceGeneration: Long,
        diagnosticContext: EpubContinuousReflowDiagnosticContext?,
        previewRequestId: Long?,
        holdGeometryCommitUntilSessionAcknowledged: Boolean,
    ): EpubContinuousPreferenceResult {
        if (disposed || (previewRequestId != null &&
                (previewRequestId <= 0 || previewRequestId < supersededSettingsPreviewRequestId))
        ) {
            return EpubContinuousPreferenceResult.Cancelled.also { result ->
                emitReflowDiagnostic(
                    EpubContinuousReflowDiagnosticEvent(
                        kind = "reflow_terminal",
                        context = diagnosticContext,
                        preferenceGeneration = preferenceGeneration,
                        result = result.toSettingsReflowTerminalResult(superseded = true),
                    ),
                )
            }
        }

        lateinit var operation: SettingsPreviewOperation
        return runCancellableSettingsPreviewOperation(
            onStarted = { operationJob ->
                operation = SettingsPreviewOperation(previewRequestId, preferenceGeneration, operationJob)
                activeSettingsPreview = operation
                geometryReflowHandoffPending = false
            },
            operation = {
                applyPreferencesTransaction(
                    preferences,
                    preferenceGeneration,
                    diagnosticContext,
                    previewRequestId,
                    holdGeometryCommitUntilSessionAcknowledged,
                )
            },
            onCancelled = {
                activeReflowTransaction?.commitOwner
                    ?.takeIf { it.preferenceGeneration == preferenceGeneration }
                    ?.let { owner -> EpubContinuousPreferenceResult.FailedAfterCommitStart(owner) }
                    ?: EpubContinuousPreferenceResult.Cancelled
            },
            onBeforeTerminal = {
                if (operation.cssOwnerDrains.isEmpty()) {
                    operation.cssOwnerDrains = host?.revokePreferenceCssOwners(preferenceGeneration).orEmpty()
                }
                host?.awaitCssOwnerDrain(operation.cssOwnerDrains)
                operation.cssOwnerDrains = emptyList()
            },
            onTerminal = { result ->
                host?.emitCssConsistency()
                emitReflowTerminal(
                    diagnosticContext,
                    preferenceGeneration,
                    result.toSettingsReflowTerminalResult(superseded = operation.superseded),
                    settled = result is EpubContinuousPreferenceResult.ReflowCommitted,
                )
            },
            onFailure = {
                emitReflowTerminal(diagnosticContext, preferenceGeneration, "failed")
            },
            onFinished = {
                if (activeSettingsPreview === operation) activeSettingsPreview = null
                val heldCommitOwner = activeReflowTransaction?.commitOwner
                    ?.takeIf { it.preferenceGeneration == preferenceGeneration }
                acknowledgeGeometryCommitForDirectCaller(
                    holdGeometryCommitUntilSessionAcknowledged,
                    heldCommitOwner,
                    ::acknowledgeGeometryCommit,
                )
                if (!geometryReflowHandoffPending && heldCommitOwner == null) {
                    host?.finishGeometryReflowPinLease()
                    geometryReflowPinLeaseActive = false
                    carriedReflowAnchor = null
                }
            },
        )
    }

    private fun emitReflowTerminal(
        context: EpubContinuousReflowDiagnosticContext?,
        preferenceGeneration: Long,
        result: String,
        settled: Boolean = false,
    ) = emitReflowDiagnostic(
        EpubContinuousReflowDiagnosticEvent(
            kind = if (settled) "reflow_settled" else "reflow_terminal",
            context = context,
            preferenceGeneration = preferenceGeneration,
            result = result,
        ),
    )

    private suspend fun applyPreferencesTransaction(
        preferences: EpubPreferences,
        preferenceGeneration: Long,
        diagnosticContext: EpubContinuousReflowDiagnosticContext?,
        previewRequestId: Long?,
        holdGeometryCommitUntilSessionAcknowledged: Boolean,
    ): EpubContinuousPreferenceResult {
        if (disposed) return EpubContinuousPreferenceResult.Cancelled
        if (diagnosticContext != null && gestureBaseline.isStale(diagnosticContext.gestureId, diagnosticContext.slider)) {
            return EpubContinuousPreferenceResult.Cancelled
        }
        val nextSettings = settingsResolver.settings(preferences)
        diagnosticPreferenceGeneration = preferenceGeneration
        diagnosticPreferenceFontFamily = nextSettings.fontFamily?.name ?: "original"
        if (!affectsContinuousGeometry(resolvedSettings, nextSettings) && host?.hasPendingCssGeometry() != true) {
            resolvedSettings = nextSettings
            resolvedCss = css.update(nextSettings, useReadiumCssFontSize = true)
            host?.applyCurrentReadiumCssToLiveResources(preferenceGeneration)
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "css_apply",
                    context = diagnosticContext,
                    preferenceGeneration = preferenceGeneration,
                    result = "applied",
                ),
            )
            return EpubContinuousPreferenceResult.Applied
        }

        // Capture the semantic locator and its actual rendered progression-point
        // viewport Y before invalidating old WebViews.
        var captureUnavailableReason: String? = null
        val gestureOwner = gestureBaseline.owner?.takeIf {
            diagnosticContext != null && gestureBaseline.matches(diagnosticContext.gestureId, diagnosticContext.slider)
        }
        var baselineAnchor = if (gestureOwner != null) gestureBaseline.anchor else null
        var beforeBaselinePoint: ContinuousResolvedLocatorPoint? = null
        if (baselineAnchor != null) {
            beforeBaselinePoint = host?.resolveLocatorPointGeometry(baselineAnchor.index, baselineAnchor.resourceGeneration, baselineAnchor.locator)
            if (gestureBaseline.owner != gestureOwner) return EpubContinuousPreferenceResult.Cancelled
            if (continuousSemanticAnchorQuality(baselineAnchor.locator, beforeBaselinePoint, true) != ContinuousSemanticAnchorQuality.EXACT_DOM_POINT) {
                invalidateGestureBaseline("anchor_unavailable")
                baselineAnchor = null
            }
        }
        val captureOwner = gestureBaseline.owner
        val anchor = baselineAnchor ?: (if (gestureOwner == null) carriedReflowAnchor else null) ?: captureContinuousAnchor { reason ->
            captureUnavailableReason = reason
        } ?: run {
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "reflow_capture",
                    context = diagnosticContext,
                    preferenceGeneration = preferenceGeneration,
                    result = "unavailable",
                    anchorPointUnavailableReason = captureUnavailableReason,
                ),
            )
            return EpubContinuousPreferenceResult.CaptureUnavailable
        }
        if (gestureOwner != null) {
            val currentOwner = gestureBaseline.owner
            if (currentOwner == null || currentOwner != captureOwner || !gestureBaseline.matches(gestureOwner.gestureId, gestureOwner.slider)) return EpubContinuousPreferenceResult.Cancelled
            if (baselineAnchor == null) {
                if (!gestureBaseline.install(currentOwner, anchor)) return EpubContinuousPreferenceResult.Cancelled
                emitGestureBaseline("created", requireNotNull(diagnosticContext), anchor)
            }
            emitGestureBaseline("used", requireNotNull(diagnosticContext), anchor, actualY = beforeBaselinePoint?.viewportY ?: anchor.viewportY)
        }
        val transaction = ContinuousGeometryReflowTransaction(
            generation = ++reflowGeneration,
            preferenceGeneration = preferenceGeneration,
            anchor = anchor,
            requestedPreferences = preferences,
        )
        activeReflowTransaction = transaction
        Log.d(
            "BiblioLifeContinuous",
            "CONTINUOUS_REFLOW_STAGE begin transactionGeneration=${transaction.generation} index=${anchor.index} " +
                "lg=${anchor.layoutGeneration} rg=${anchor.resourceGeneration} " +
                "oldFont=${resolvedSettings.fontSize} newFont=${nextSettings.fontSize}",
        )
        emitReflowDiagnostic(
            EpubContinuousReflowDiagnosticEvent(
                kind = "reflow_start",
                context = diagnosticContext,
                preferenceGeneration = preferenceGeneration,
                transactionGeneration = transaction.generation,
                layoutGeneration = anchor.layoutGeneration,
                resourceGeneration = anchor.resourceGeneration,
                readingOrderIndex = anchor.index,
                anchorBeforeY = anchor.localY,
                result = "started",
            ),
        )
        host?.emitViewportSnapshot(
                snapshotStage = "before_reflow",
                context = diagnosticContext,
                preferenceGeneration = preferenceGeneration,
                transactionGeneration = transaction.generation,
                layoutGeneration = anchor.layoutGeneration,
                resourceGeneration = anchor.resourceGeneration,
                anchorIndex = anchor.index,
                anchorProgression = anchor.locator.locations.progression,
                anchorPointDocumentYPx = anchor.documentYLayoutPx,
                anchorPointViewportYPx = anchor.viewportY,
                anchorPointAvailable = anchor.documentYLayoutPx != null,
                anchorPointUnavailableReason = if (anchor.documentYLayoutPx == null) "pre_reflow_point_missing" else null,
                anchorPointSampleStage = "before_reflow",
                anchorBeforeLocalYPx = anchor.localY,
                anchorBeforeViewportYPx = anchor.viewportY,
                anchorResourceHref = boundedContinuousDiagnosticResourceHref(anchor.locator.href.toString()),
                result = "captured",
            )
        resolvedSettings = nextSettings
        resolvedCss = css.update(nextSettings, useReadiumCssFontSize = true)
        if (!geometryReflowPinLeaseActive) {
            host?.beginGeometryReflowPinLease()
            geometryReflowPinLeaseActive = true
        }
        host?.applyInPlaceLayoutGeneration(transaction, diagnosticContext, preferenceGeneration)
        val result = try {
            host?.restoreAfterGeometryReflow(
                locator = anchor.locator,
                transaction = transaction,
                isTransactionCurrent = { isCurrentReflowTransaction(transaction) },
            ) ?: ContinuousReflowRestoreOutcome.Cancelled
        } catch (cancelled: CancellationException) {
            val commitOwner = transaction.commitOwner
            if (commitOwner != null) {
                transaction.failAfterCommitStart()
                host?.finishFreshLocatorObservation(transaction)
                return EpubContinuousPreferenceResult.FailedAfterCommitStart(commitOwner)
            }
            transaction.cancel()
            if (activeReflowTransaction === transaction) activeReflowTransaction = null
            host?.finishFreshLocatorObservation(transaction)
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "reflow_end",
                    context = diagnosticContext,
                    preferenceGeneration = preferenceGeneration,
                    transactionGeneration = transaction.generation,
                    layoutGeneration = transaction.targetLayoutGeneration,
                    resourceGeneration = transaction.targetResourceGeneration,
                    readingOrderIndex = transaction.targetReadingOrderIndex,
                    result = "superseded",
                ),
            )
            throw cancelled
        } catch (_: Throwable) {
            val commitOwner = transaction.commitOwner
            if (commitOwner != null) {
                transaction.failAfterCommitStart()
                host?.finishFreshLocatorObservation(transaction)
                return EpubContinuousPreferenceResult.FailedAfterCommitStart(commitOwner)
            }
            transaction.cancel()
            if (activeReflowTransaction === transaction) activeReflowTransaction = null
            host?.finishFreshLocatorObservation(transaction)
            return EpubContinuousPreferenceResult.SemanticRestoreFailed
        }
        if (gestureOwner != null && gestureBaseline.matches(gestureOwner.gestureId, gestureOwner.slider) &&
            transaction.verifiedLocatorPoint?.semanticAnchorExact == false
        ) invalidateGestureBaseline("anchor_unavailable")
        try {
        if (!isCurrentReflowTransaction(transaction)) {
            val commitOwner = transaction.commitOwner
            if (commitOwner != null) {
                transaction.failAfterCommitStart()
                host?.finishFreshLocatorObservation(transaction)
                return EpubContinuousPreferenceResult.FailedAfterCommitStart(commitOwner)
            }
            transaction.cancel()
            if (activeReflowTransaction === transaction) activeReflowTransaction = null
            host?.finishFreshLocatorObservation(transaction)
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "reflow_end",
                    context = diagnosticContext,
                    preferenceGeneration = preferenceGeneration,
                    transactionGeneration = transaction.generation,
                    layoutGeneration = transaction.targetLayoutGeneration,
                    resourceGeneration = transaction.targetResourceGeneration,
                    readingOrderIndex = transaction.targetReadingOrderIndex,
                    result = "cancelled",
                ),
            )
            Log.d(
                "BiblioLifeContinuous",
                "CONTINUOUS_REFLOW_STAGE outcome transactionGeneration=${transaction.generation} index=${anchor.index} " +
                    "lg=${anchor.layoutGeneration} rg=${anchor.resourceGeneration} result=cancelled",
            )
            return EpubContinuousPreferenceResult.Cancelled
        }
        val commitOwner = transaction.commitOwner
        if (commitOwner == null) {
            activeReflowTransaction = null
        }
        carriedReflowAnchor = null
        val rawPreferenceResult = when (result) {
            is ContinuousReflowRestoreOutcome.Restored -> if (host?.hasCommittedCssGeometry(transaction) == true && transaction.complete()) {
                host?.emitAfterReflowCommitSnapshot(transaction, diagnosticContext)
                EpubContinuousPreferenceResult.ReflowCommitted(
                    locator = result.observedLocator,
                    readingOrderIndex = result.readingOrderIndex,
                    commitOwner = commitOwner,
                )
            } else EpubContinuousPreferenceResult.SemanticRestoreFailed
            ContinuousReflowRestoreOutcome.TargetNotReady -> EpubContinuousPreferenceResult.TargetNotReady.also { transaction.cancel() }
            ContinuousReflowRestoreOutcome.SemanticRestoreFailed -> EpubContinuousPreferenceResult.SemanticRestoreFailed.also { transaction.cancel() }
            ContinuousReflowRestoreOutcome.VisibilityMismatch -> EpubContinuousPreferenceResult.VisibilityMismatch.also { transaction.cancel() }
            ContinuousReflowRestoreOutcome.Ready,
            ContinuousReflowRestoreOutcome.Cancelled,
            -> EpubContinuousPreferenceResult.Cancelled.also { transaction.cancel() }
        }
        val preferenceResult = if (commitOwner != null && rawPreferenceResult !is EpubContinuousPreferenceResult.ReflowCommitted) {
            EpubContinuousPreferenceResult.FailedAfterCommitStart(commitOwner)
        } else rawPreferenceResult
        host?.finishFreshLocatorObservation(transaction)
        if (preferenceResult is EpubContinuousPreferenceResult.ReflowCommitted) {
            host?.handoffCommittedCssOwner(transaction.generation)
        }
        emitReflowDiagnostic(
            EpubContinuousReflowDiagnosticEvent(
                kind = "reflow_end",
                context = diagnosticContext,
                preferenceGeneration = preferenceGeneration,
                transactionGeneration = transaction.generation,
                layoutGeneration = transaction.targetLayoutGeneration,
                resourceGeneration = transaction.targetResourceGeneration,
                readingOrderIndex = transaction.targetReadingOrderIndex,
                result = preferenceResult.reflowDiagnosticResult,
            ),
        )
        Log.d(
            "BiblioLifeContinuous",
            "CONTINUOUS_REFLOW_STAGE outcome transactionGeneration=${transaction.generation} index=${anchor.index} " +
                "lg=${anchor.layoutGeneration} rg=${anchor.resourceGeneration} " +
                "result=${preferenceResult.reflowDiagnosticResult}",
        )
        return preferenceResult
        } catch (error: Throwable) {
            val owner = transaction.commitOwner ?: throw error
            transaction.failAfterCommitStart()
            runCatching { host?.finishFreshLocatorObservation(transaction) }
            runCatching {
                emitReflowDiagnostic(
                    EpubContinuousReflowDiagnosticEvent(
                        kind = "reflow_end",
                        context = diagnosticContext,
                        preferenceGeneration = preferenceGeneration,
                        transactionGeneration = transaction.generation,
                        layoutGeneration = transaction.targetLayoutGeneration,
                        resourceGeneration = transaction.targetResourceGeneration,
                        readingOrderIndex = transaction.targetReadingOrderIndex,
                        result = "failed_after_commit_start",
                    ),
                )
            }
            return EpubContinuousPreferenceResult.FailedAfterCommitStart(owner)
        }
    }

    override fun acknowledgeGeometryCommit(owner: EpubContinuousGeometryCommitOwner): Boolean {
        val transaction = activeReflowTransaction ?: return false
        if (transaction.commitOwner != owner || !transaction.terminal) return false
        if (host?.acknowledgeGeometryCommit(owner) != true) return false
        // Clear the exact transaction owner before best-effort pin-window
        // housekeeping, so a cleanup exception cannot retain the commit lock.
        activeReflowTransaction = null
        if (!geometryReflowHandoffPending) {
            geometryReflowPinLeaseActive = false
            carriedReflowAnchor = null
            runCatching { host?.finishGeometryReflowPinLease() }
                .onFailure { error ->
                    Log.w("BiblioLifeContinuous", "CONTINUOUS_REFLOW_GATE pin_cleanup_failed type=${error::class.simpleName}")
                }
        }
        return true
    }

    override fun diagnosticViewportLayoutSnapshot(
        anchorIndex: Int?,
    ): EpubContinuousViewportLayoutSnapshot? = host?.diagnosticViewportLayoutSnapshot(anchorIndex)

    override fun geometryCommitOwner(preferenceGeneration: Long): EpubContinuousGeometryCommitOwner? =
        activeReflowTransaction?.commitOwner?.takeIf { it.preferenceGeneration == preferenceGeneration }

    private fun emitReflowDiagnostic(event: EpubContinuousReflowDiagnosticEvent) {
        try {
            reflowDiagnosticListener?.invoke(event)
        } catch (_: Throwable) {
            // Diagnostics are observers and must never affect preference application.
        }
    }

    private val EpubContinuousPreferenceResult.reflowDiagnosticResult: String
        get() = when (this) {
            EpubContinuousPreferenceResult.Applied -> "applied"
            is EpubContinuousPreferenceResult.ReflowCommitted -> "committed"
            EpubContinuousPreferenceResult.CaptureUnavailable -> "capture_unavailable"
            EpubContinuousPreferenceResult.TargetNotReady -> "target_not_ready"
            EpubContinuousPreferenceResult.SemanticRestoreFailed -> "semantic_restore_failed"
            EpubContinuousPreferenceResult.VisibilityMismatch -> "visibility_mismatch"
            EpubContinuousPreferenceResult.Cancelled -> "cancelled"
            is EpubContinuousPreferenceResult.FailedAfterCommitStart -> "failed_after_commit_start"
        }

    private fun isCurrentReflowTransaction(transaction: ContinuousGeometryReflowTransaction): Boolean =
        !disposed && !transaction.superseded && activeReflowTransaction === transaction && transaction.generation == reflowGeneration

    /** Values that can change line breaks, document height, or locator Y. */
    private fun affectsContinuousGeometry(
        old: org.readium.r2.navigator.epub.EpubSettings,
        new: org.readium.r2.navigator.epub.EpubSettings,
    ): Boolean = old.fontFamily != new.fontFamily ||
        old.fontSize != new.fontSize ||
        old.fontWeight != new.fontWeight ||
        old.lineHeight != new.lineHeight ||
        old.pageMargins != new.pageMargins ||
        old.textAlign != new.textAlign ||
        old.publisherStyles != new.publisherStyles ||
        old.typeScale != new.typeScale ||
        old.letterSpacing != new.letterSpacing ||
        old.wordSpacing != new.wordSpacing ||
        old.paragraphIndent != new.paragraphIndent ||
        old.paragraphSpacing != new.paragraphSpacing ||
        old.hyphens != new.hyphens ||
        old.ligatures != new.ligatures ||
        old.textNormalization != new.textNormalization ||
        old.language != new.language ||
        old.verticalText != new.verticalText

    private fun applyCurrentReadiumCss(
        webView: R2BasicWebView,
        readingOrderIndex: Int,
        resourceGeneration: Long,
        ownerToken: Long,
        onApplied: (Boolean) -> Unit,
    ) {
        val preferenceGeneration = diagnosticPreferenceGeneration
        if (preferenceGeneration != null) {
            Log.d(
                "BiblioLifeContinuous",
                "PREFERENCE_APPLY generation=$preferenceGeneration resource=$readingOrderIndex/$resourceGeneration",
            )
        }
        val properties = resolvedCss.run { rsProperties.toCssProperties() + userProperties.toCssProperties() }
        webView.runJavaScript(guardedReadiumCssScript(JSONObject(properties.toMap()).toString(), ownerToken,
            webView.continuousTextRenderDiagnosticContext)) { result ->
            onApplied(result.toBoolean())
        }
        webView.setScrollMode(ContinuousPresentation.scrollMode)
        if (preferenceGeneration != null) {
            Log.d(
                "BiblioLifeContinuous",
                "PREFERENCE_EFFECTIVE generation=$preferenceGeneration resource=$readingOrderIndex/$resourceGeneration value=$diagnosticPreferenceFontFamily",
            )
        }
    }

    private fun navigateInternalLink(source: EpubWebResourceIdentity, target: Link) {
        navigationScope.launch {
            // Both dispatch and commit are source-generation checked. A late
            // callback from a released/recreated WebView can never impersonate
            // the current resource at the same reading-order index.
            if (disposed || host?.isLiveResource(source.readingOrderIndex, source.generation) != true) return@launch
            val locator = publication.locatorFromLink(target) ?: return@launch
            if (disposed || host?.isLiveResource(source.readingOrderIndex, source.generation) != true) return@launch
            host?.go(locator)
        }
    }

    override fun dispose() {
        if (disposed) return
        gestureBaseline.owner?.let { owner ->
            invalidateGestureBaseline("session_closed")
            gestureBaseline.release(owner.gestureId)
        }
        activeSettingsPreview?.job?.cancel(CancellationException("Continuous rendition disposed"))
        activeSettingsPreview = null
        activeSelectionOwner?.let { owner -> clearSelectionOwner(owner, activeSelectionSessionId) }
        disposed = true
        reflowGeneration += 1
        activeReflowTransaction = null
        hostGenerationGate.dispose()
        host?.let { current ->
            // The resource window is emptied by host disposal before this
            // rendition closes its shared publication environment/server.
            current.dispose()
            check(current.liveResourceCount == 0) { "Continuous resource window must be empty before environment disposal" }
            (current.parent as? ViewGroup)?.removeView(current)
        }
        host = null
        environment.dispose()
    }

    internal suspend fun findFirstVisibleLocator(index: Int, generation: Long): Locator? =
        if (disposed) null else host?.findFirstVisibleLocator(index, generation)

    internal suspend fun findLocatorAtReadingAnchor(): ContinuousAnchorLocator? {
        if (disposed) return null
        val target = host?.currentLocatorAnchor() ?: return null
        val locator = host?.findLocatorAtReadingAnchor(target) ?: return null
        val point = host?.resolveLocatorPointGeometry(
            target.readingOrderIndex,
            target.resourceGeneration,
            locator,
        ) ?: return null
        return ContinuousAnchorLocator(
            index = target.readingOrderIndex,
            resourceGeneration = target.resourceGeneration,
            layoutGeneration = target.layoutGeneration,
            localY = target.y,
            viewportY = point.viewportY,
            documentYLayoutPx = point.documentYLayoutPx,
            locator = locator,
        )
    }

    private suspend fun captureContinuousAnchor(onUnavailable: (String) -> Unit): ContinuousAnchorLocator? {
        val currentHost = host ?: run { onUnavailable("host_missing"); return null }
        val target = currentHost.currentLocatorAnchor() ?: run {
            onUnavailable("target_unavailable")
            return null
        }
        val locator = currentHost.findLocatorAtReadingAnchor(target, stableDom = true) ?: run {
            onUnavailable("locator_unavailable")
            return null
        }
        val point = currentHost.resolveLocatorPointGeometry(
            target.readingOrderIndex,
            target.resourceGeneration,
            locator,
        ) ?: run {
            onUnavailable("point_geometry_unavailable")
            return null
        }
        return ContinuousAnchorLocator(
            index = target.readingOrderIndex,
            resourceGeneration = target.resourceGeneration,
            layoutGeneration = target.layoutGeneration,
            localY = target.y,
            viewportY = point.viewportY,
            documentYLayoutPx = point.documentYLayoutPx,
            targetViewportY = point.viewportY - (
                ((locator.locations["continuousDomAnchor"] as? Map<*, *>)
                    ?.get("pointToTargetOffsetCssPx") as? Number)?.toDouble() ?: 0.0
                ) * currentHost.resources.displayMetrics.density,
            locator = locator,
        )
    }

    internal suspend fun resolveLocatorVerticalOffset(
        index: Int,
        generation: Long,
        locator: Locator,
    ): Double? = if (disposed) null else host?.resolveLocatorVerticalOffset(index, generation, locator)

    public companion object {
        public fun create(
            application: Application,
            publication: Publication,
            configuration: EpubNavigatorFragment.Configuration,
            initialPreferences: EpubPreferences,
            sessionInstanceId: String = "unavailable",
        ): ContinuousEpubRendition {
            val environment = EpubWebPublicationEnvironment.create(
                application = application,
                publication = publication,
                configuration = configuration,
                onResourceLoadFailed = { _, _ -> },
            )
            val css = ReadiumCss(
                rsProperties = configuration.readiumCssRsProperties,
                fontFamilyDeclarations = configuration.fontFamilyDeclarations,
                assetsBaseHref = WebViewServer.assetsBaseHref,
                beforeCssContentLoader = readiumBeforeCssContentLoader(
                    application,
                    WebViewServer.assetsBaseHref,
                ),
            )
            return ContinuousEpubRendition(
                publication = publication,
                environment = environment,
                css = css,
                resourceFactory = EpubResourceWebViewFactory(environment),
                initialPreferences = initialPreferences,
                selectionActionModeCallback = configuration.selectionActionModeCallback,
                decorationTemplates = configuration.decorationTemplates,
                sessionInstanceId = sessionInstanceId,
            )
        }
    }

    private class Callbacks(
        private val environment: EpubWebPublicationEnvironment,
        private val css: () -> ReadiumCss,
        link: Link,
        index: Int,
        generation: Long,
        private val onInternalLink: (EpubWebResourceIdentity, Link) -> Unit,
        private val onSelectionSessionChanged: (EpubWebResourceIdentity, Boolean, Long) -> Unit,
        private val onContentTap: (EpubWebResourceIdentity) -> Boolean,
        private val onDecorationActivated: (EpubWebResourceIdentity, String, String, RectF) -> Boolean,
        private val actionModeCallback: ActionMode.Callback?,
    ) : EpubResourceCallbacks {
        override val resourceIdentity = EpubWebResourceIdentity.from(link, index.coerceAtLeast(0), generation)
        override val readingProgression: ReadingProgression = ReadingProgression.LTR
        override val verticalText: Boolean = false
        override fun shouldOverrideUrlLoading(webView: WebView, request: WebResourceRequest): Boolean {
            val url = request.url.toAbsoluteUrl() ?: return false
            val target = environment.linkAt(url) ?: return false
            onInternalLink(resourceIdentity, target)
            return true
        }
        override fun onFootnoteLinkActivated(url: AbsoluteUrl, context: org.readium.r2.navigator.HyperlinkNavigator.FootnoteContext) = Unit
        override fun shouldInterceptRequest(webView: WebView, request: WebResourceRequest): WebResourceResponse? =
            environment.shouldInterceptRequest(request, css())
        override fun resourceAtUrl(url: AbsoluteUrl): Resource? = environment.resourceAt(url)
        override fun onSelectionSessionChanged(active: Boolean, sessionId: Long) {
            onSelectionSessionChanged(resourceIdentity, active, sessionId)
        }
        override fun onTap(point: PointF): Boolean = onContentTap(resourceIdentity)
        override fun onDecorationActivated(
            id: String,
            group: String,
            rect: RectF,
            point: PointF,
        ): Boolean = onDecorationActivated(resourceIdentity, id, group, rect)
        override val selectionActionModeCallback: ActionMode.Callback?
            get() = actionModeCallback
    }

    private fun onResourceSelectionSessionChanged(
        identity: EpubWebResourceIdentity,
        active: Boolean,
        sessionId: Long,
    ) {
        if (disposed || host?.isLiveResource(identity.readingOrderIndex, identity.generation) != true) return
        if (active) {
            if (activeSelectionOwner == identity && activeSelectionSessionId == sessionId) return
            activeSelectionOwner?.let { previous -> clearSelectionOwner(previous, activeSelectionSessionId) }
            activeSelectionOwner = identity
            activeSelectionSessionId = sessionId
            host?.pinResource(identity.readingOrderIndex, ContinuousResourcePinReason.SELECTION)
            host?.setSelectionTouchOwner(identity.readingOrderIndex, identity.generation)
            selectionSessionListener?.invoke(identity.toSelectionEvent(true, sessionId))
        } else if (activeSelectionOwner == identity && activeSelectionSessionId == sessionId) {
            clearSelectionOwner(identity, sessionId)
        }
    }

    private fun onResourceReleased(index: Int, generation: Long) {
        gestureBaseline.anchor?.takeIf { it.index == index && it.resourceGeneration == generation }?.let {
            invalidateGestureBaseline("resource_released")
        }
        val owner = activeSelectionOwner
        if (owner?.readingOrderIndex == index && owner.generation == generation) {
            // Resource-window disposal owns its pin cleanup. Do not reconcile
            // while it is releasing this resource.
            activeSelectionOwner = null
            val sessionId = activeSelectionSessionId
            activeSelectionSessionId = null
            if (sessionId != null) selectionSessionListener?.invoke(owner.toSelectionEvent(false, sessionId))
        }
    }

    private fun onResourceReady(index: Int, generation: Long) {
        if (disposed) return
        val stillLive = host?.applyToLiveResource(index, generation) { resource ->
            decorations.forEach { (group, requested) ->
                resource.replaceDecorations(group, requested, decorationTemplates)
            }
        } == true
        if (stillLive) {
            Log.d("BiblioLifeContinuous", "CONTINUOUS_RESOURCE_READY index=$index generation=$generation")
            resourceReadyListener?.invoke(EpubContinuousResourceReadyEvent(index, generation))
        }
    }

    private fun clearSelectionOwner(owner: EpubWebResourceIdentity, sessionId: Long?) {
        if (activeSelectionOwner != owner) return
        activeSelectionOwner = null
        activeSelectionSessionId = null
        host?.clearSelectionTouchOwner(owner.readingOrderIndex, owner.generation)
        host?.unpinResource(owner.readingOrderIndex, ContinuousResourcePinReason.SELECTION)
        if (sessionId != null) selectionSessionListener?.invoke(owner.toSelectionEvent(false, sessionId))
    }

    private fun EpubWebResourceIdentity.toSelectionEvent(active: Boolean, sessionId: Long) =
        EpubContinuousSelectionEvent(
            active = active,
            identity = EpubContinuousSelectionIdentity(readingOrderIndex, href, generation),
            nativeSessionId = sessionId,
        )

    private fun onResourceContentTap(identity: EpubWebResourceIdentity): Boolean {
        if (disposed || activeSelectionOwner != null ||
            host?.isLiveResource(identity.readingOrderIndex, identity.generation) != true
        ) return false
        return contentTapListener?.invoke(
            EpubContinuousContentTapEvent(
                EpubContinuousSelectionIdentity(identity.readingOrderIndex, identity.href, identity.generation),
            ),
        ) ?: false
    }
}
