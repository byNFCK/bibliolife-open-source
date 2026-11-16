package org.readium.r2.navigator.epub.continuous

import org.json.JSONObject

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.graphics.RectF
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.readium.r2.navigator.R2BasicWebView
import org.readium.r2.navigator.R2JavascriptExecutor
import org.readium.r2.navigator.javascriptResultObject
import org.readium.r2.navigator.Selection
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.DecorationChange
import org.readium.r2.navigator.epub.extensions.javascriptForGroup
import org.readium.r2.navigator.html.HtmlDecorationTemplates
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.resume
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.roundToInt

/**
 * A native selection may ask its RecyclerView parent to reveal a WebView
 * rectangle while ActionMode is being created. That request is presentation
 * work, not reader navigation, so it must not replace the parent reading
 * anchor or publish a new position.
 */
internal class ContinuousSelectionViewportGate {
    private var owner: Pair<Int, Long>? = null

    fun activate(nextOwner: Pair<Int, Long>) {
        owner = nextOwner
    }

    fun clear(expectedOwner: Pair<Int, Long>) {
        if (owner == expectedOwner) owner = null
    }

    fun clearAll() {
        owner = null
    }

    fun blocksParentScroll(): Boolean = owner != null

    fun blocksViewportPublication(): Boolean = owner != null
}

/** Stops only selection-driven child-rectangle reveal requests. */
private class SelectionPreservingRecyclerView(
    context: Context,
    private val blocksSelectionParentScroll: () -> Boolean,
    private val onSelectionParentScrollSuppressed: () -> Unit,
) : RecyclerView(context) {
    override fun requestChildRectangleOnScreen(child: View, rect: Rect, immediate: Boolean): Boolean =
        if (blocksSelectionParentScroll()) {
            onSelectionParentScrollSuppressed()
            false
        } else {
            super.requestChildRectangleOnScreen(child, rect, immediate)
        }
}

/** A parent vertical host. RecyclerView hosts slots, while [resourceWindow] owns real WebViews. */
@SuppressLint("SetJavaScriptEnabled")
internal class ContinuousReflowableHostView(
    context: Context,
    val publication: Publication,
    private val readingOrder: List<Link>,
    private val resourceFactory: ContinuousResourceViewFactory,
    private val reflowEventPort: ContinuousReflowEventPort = RuntimeContinuousReflowEventPort(),
    private val testBinding: ContinuousReflowHostTestBinding = ContinuousReflowHostTestBinding.None,
) : FrameLayout(context) {
    private val sessionInstanceId: String = resourceFactory.diagnosticSessionId
    internal val diagnosticHostId: String = BiblioLifeOpenTimingDiagnostics.nextHostId()
    private val tag = "BiblioLifeContinuous"
    private val layoutManager = ContinuousLayoutManager(context)
    internal var scrollToPositionCallObserverForTest: ((index: Int, offsetPx: Int) -> Unit)? = null
    internal var geometryBatchAfterFirstHeightMutationForTest: (() -> Unit)? = null
    internal var beforeLocatorPointGeometryForTest: (suspend (ContinuousReflowTarget) -> Unit)? = null
    private val selectionViewportGate = ContinuousSelectionViewportGate()
    private var manualDragStartedListener: (() -> Unit)? = null
    private val recyclerView = SelectionPreservingRecyclerView(
        context = context,
        blocksSelectionParentScroll = { selectionViewportGate.blocksParentScroll() },
        onSelectionParentScrollSuppressed = {
            Log.d(tag, "CONTINUOUS_SELECTION_PARENT_SCROLL_SUPPRESSED reason=native_selection_active")
        },
    )

    /** Suppresses only the generic focus reveal for an already visible live resource. */
    private inner class ContinuousLayoutManager(context: Context) :
        LinearLayoutManager(context, RecyclerView.VERTICAL, false) {

        override fun scrollToPositionWithOffset(position: Int, offset: Int) {
            super.scrollToPositionWithOffset(position, offset)
            scrollToPositionCallObserverForTest?.invoke(position, offset)
        }

        override fun onLayoutCompleted(state: RecyclerView.State?) {
            // super consumes LinearLayoutManager's pending position/offset.
            // A global-layout notification by itself does not establish this.
            super.onLayoutCompleted(state)
            if (state?.isPreLayout == false) {
                initialRestoreAuthority.geometryTarget()?.let { target ->
                    if (initialRestoreAuthority.isRestoreRequested()) {
                        initialRestoreAuthority.markRestoreCommitted(target)
                    }
                }
            }
        }

        override fun requestChildRectangleOnScreen(
            parent: RecyclerView,
            child: View,
            rect: Rect,
            immediate: Boolean,
            focusedChildVisible: Boolean,
        ): Boolean {
            val childTop = getDecoratedTop(child)
            val childBottom = getDecoratedBottom(child)
            val intersectsViewport = childBottom > parent.paddingTop &&
                childTop < parent.height - parent.paddingBottom
            val restoreAuthorityBlocks = initialRestoreAuthority.blocksViewportPublication()
            val explicitPositioningActive = pins.values.any {
                ContinuousResourcePinReason.NAVIGATION_TARGET in it
            }
            val holder = if (parent === recyclerView && parent.layoutManager === this) {
                runCatching { parent.getChildViewHolder(child) as? ResourceHolder }.getOrNull()
            } else null
            val index = holder?.boundIndex ?: RecyclerView.NO_POSITION
            val materialization = attachedMaterializations[index]
            val resource = materialization?.resource
            val liveAttachedResource = holder != null &&
                holder.itemView === child &&
                holder.container === child &&
                child.isAttachedToWindow &&
                holder.boundIndex == index &&
                holder.bindingAdapterPosition == index &&
                resource != null &&
                resource.parent === child &&
                materialization.target.index == index &&
                materialization.target.layoutGeneration == layoutGeneration &&
                materialization.target.resourceGeneration == resource.generation &&
                resourceWindow.withLiveResource(index, resource.generation) { it } === resource
            val suppress = liveAttachedResource && intersectsViewport &&
                !restoreAuthorityBlocks && !explicitPositioningActive
            return if (suppress) false else super.requestChildRectangleOnScreen(
                parent,
                child,
                rect,
                immediate,
                focusedChildVisible,
            )
        }
    }
    /**
     * The PlatformView is already opaque while its first Recycler child still
     * has zero bounds. Keep a real native loading surface over that interval;
     * it is released only at an actual initial-ready boundary, never by time.
     */
    private val initialViewportCover = FrameLayout(context).apply {
        setBackgroundColor(Color.WHITE)
        addView(
            ProgressBar(context),
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                android.view.Gravity.CENTER,
            ),
        )
    }
    private var initialRestorePending = false
    /** Owns the initial restore viewport until its exact target reaches a terminal outcome. */
    private val initialRestoreAuthority = ContinuousInitialRestoreAuthorityGate()
    private val deferredInitialRestoreReadyEvents = ContinuousInitialRestoreReadyEvents()
    private var initialViewportRevealed = false
    // Extend the existing initial-reveal preload gate through the real visual commit.
    private var initialViewportPreloadsReleased = false
    private var proximityPreloadsEnabled = false
    private var userScrollGestureActive = false
    private var manualScrollActive = false
    private var initialViewportTargetIndex: Int? = null
    private var initialViewportFailureReported = false
    private var initialViewportVisualStateRequestId = 0L
    private val layoutModel = ContinuousReflowableHostModel(readingOrder.map { it.href.toString() })
    private val pins = mutableMapOf<Int, MutableSet<ContinuousResourcePinReason>>()
    private var geometryReflowPinLease: Set<Int> = emptySet()
    private data class ActiveGeometryCssOwner(
        val layoutGeneration: Int,
        val preferenceGeneration: Long?,
        val transactionGeneration: Long?,
        var revoked: Boolean = false,
    )
    private var activeGeometryCssOwner: ActiveGeometryCssOwner? = null
    private var disposed = false
    private var layoutGeneration = 0
    private val callbackGate = ContinuousResourceCallbackGate()
    private val adapter = ResourceAdapter()
    private var viewportChangedListener: (() -> Unit)? = null
    private var resourceReleasedListener: ((Int, Long) -> Unit)? = null
    private var resourceReadyListener: ((Int, Long) -> Unit)? = null
    private var manualScrollActivityChangedListener: ((Boolean) -> Unit)? = null
    private var manualScrollProgressListener: (() -> Unit)? = null
    private var decorationSnapshotProvider: (() -> Map<String, Pair<List<Decoration>, HtmlDecorationTemplates>>)? = null
    private var initialViewportReadyListener: (() -> Unit)? = null
    private var initialViewportFailureListener: ((String) -> Unit)? = null
    private val reflowTargetWaiters = mutableMapOf<ContinuousReflowTarget, CompletableDeferred<ContinuousReflowRestoreOutcome>>()
    private val postRestoreLayoutWaiters = mutableMapOf<ContinuousReflowTarget, Pair<Long, CompletableDeferred<ContinuousReflowRestoreOutcome>>>()
    private val reattachWaiters = mutableMapOf<ContinuousReflowTarget, ReattachWaiter>()
    private val reflowTargetBarrier = ContinuousReflowTargetBarrier()
    private val reflowDiagnosticTransactions = mutableMapOf<ContinuousReflowTarget, ContinuousGeometryReflowTransaction>()
    private val reflowDiagnosticOwners = ContinuousReflowDiagnosticOwnerRegistry()
    private val reflowDiagnosticViewportBaselines = LinkedHashMap<Int, EpubContinuousViewportLayoutSnapshot>()
    private val reportedReflowMeasurements = mutableMapOf<Triple<Int, Int, Long>, Pair<Long, String>>()
    private var reflowDiagnosticListener: ((EpubContinuousReflowDiagnosticEvent) -> Unit)? = null
    private val freshLocatorObservationBarrier = ContinuousFreshLocatorObservationBarrier()
    private var activeGeometryBatch: ContinuousGeometryMeasurementBatch? = null
    private val geometryBatchReadyWaiters = mutableMapOf<ContinuousGeometryBatchOwner, CompletableDeferred<Unit>>()
    private data class PreparedGeometryBatchCommit(
        val batch: ContinuousGeometryMeasurementBatch,
        val transaction: ContinuousGeometryReflowTransaction,
        val measurements: List<ResourceLayoutMeasurement>,
        val resources: List<ContinuousResourceView>,
    )
    private var activeGeometryTransaction: ContinuousGeometryReflowTransaction? = null
    private var manualDragDiagnosticReportedTransaction: Long? = null
    private var recyclerLayoutPass = 0L
    private var selectionTouchOwner: Pair<Int, Long>? = null
    /**
     * The only source of queryable resource identity. A live resource is not
     * queryable until its real RecyclerView holder has attached its real view.
     */
    private val attachedMaterializations = mutableMapOf<Int, ContinuousResourceMaterialization>()
    private val resourceWindow = ContinuousEpubResourceWindow(
        create = ::createLiveResource,
        release = ::releaseLiveResource,
    )
    /**
     * A liveness boundary after startup is restricted to the visible/restore
     * target. A lost native callback must not retain the loading cover forever.
     */
    private val initialViewportTimeout = Runnable {
        initialRestoreAuthority.geometryTarget()?.let { target ->
            failReflowTarget(target, ContinuousReflowRestoreOutcome.TargetNotReady)
        }
        reportInitialViewportFailure("readiness_timeout")
    }

    /** A RecyclerView global-layout pass, rather than requestLayout(), settles a reflow boundary. */
    private val recyclerLayoutListener = ViewTreeObserver.OnGlobalLayoutListener {
        reflowEventPort.recyclerLayoutCommitted()
    }

    private val reflowEventSink = object : ContinuousReflowEventPort.Sink {
        override fun onRecyclerLayoutCommitted() {
            recyclerLayoutPass += 1
            reflowTargetBarrier.markAttachedLayouts(recyclerLayoutPass, ::isTargetAttached)
            reflowDiagnosticTransactions.forEach { (target, transaction) ->
                logReflowStage("prelayout", transaction, target, reflowTargetBarrier.isReady(target).toString())
            }
            completeReflowTargetIfReady()
            completePostRestoreLayouts()
        }

        override fun onTrueReady(target: ContinuousReflowTarget) {
            BiblioLifeOpenTimingDiagnostics.internal(
                stage = "W7_TRUE_READY_RECEIVED_NATIVE",
                index = target.index,
                webViewId = attachedMaterializations[target.index]?.resource?.webViewIdentity,
            )
            onReflowTargetReady(target)
        }

        override fun onMeasurement(measurement: ResourceLayoutMeasurement) {
            onMeasurementFromPort(measurement)
        }

        override fun onDisposed() = Unit
    }

    init {
        require(readingOrder.isNotEmpty())
        recyclerView.layoutManager = layoutManager
        recyclerView.adapter = adapter
        recyclerView.itemAnimator = null
        // A cached holder must never become an implicit R2BasicWebView cache.
        recyclerView.setItemViewCacheSize(0)
        recyclerView.recycledViewPool.setMaxRecycledViews(RESOURCE_VIEW_TYPE, MAX_NON_VISIBLE_PRELOAD_RESOURCES)
        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (userScrollGestureActive && (dx != 0 || dy != 0)) {
                    proximityPreloadsEnabled = true
                }
                if (manualScrollActive && (dx != 0 || dy != 0)) {
                    manualScrollProgressListener?.invoke()
                }
                reconcileResourceWindow()
            }
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (newState == RecyclerView.SCROLL_STATE_DRAGGING && !userScrollGestureActive) {
                    emitReflowManualDragSnapshot()
                    manualDragStartedListener?.invoke()
                    manualScrollActive = true
                    manualScrollActivityChangedListener?.invoke(true)
                }
                userScrollGestureActive = newState == RecyclerView.SCROLL_STATE_DRAGGING
                if (newState != RecyclerView.SCROLL_STATE_IDLE) return
                if (manualScrollActive) {
                    manualScrollActive = false
                    manualScrollActivityChangedListener?.invoke(false)
                }
                if (initialRestoreAuthority.blocksViewportPublication()) {
                    Log.d(tag, "CONTINUOUS_INITIAL_RESTORE_VIEWPORT_SUPPRESSED source=scroll_idle")
                    return
                }
                if (selectionViewportGate.blocksViewportPublication()) {
                    Log.d(tag, "CONTINUOUS_SELECTION_VIEWPORT_UPDATE_SUPPRESSED reason=native_selection_active")
                    return
                }
                viewportChangedListener?.invoke()
            }
        })
        recyclerView.viewTreeObserver.addOnGlobalLayoutListener(recyclerLayoutListener)
        reflowEventPort.bind(reflowEventSink)
        addView(recyclerView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(initialViewportCover, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        Log.d(
            tag,
            "CONTINUOUS_COVER_STATE state=covered reason=awaiting_real_geometry lg=$layoutGeneration " +
                "visibility=${initialViewportCover.visibility}",
        )
        postDelayed(initialViewportTimeout, INITIAL_VIEWPORT_TIMEOUT_MS)
    }


    internal fun applyInPlaceLayoutGeneration(
        transaction: ContinuousGeometryReflowTransaction,
        diagnosticContext: EpubContinuousReflowDiagnosticContext? = null,
        preferenceGeneration: Long? = null,
    ) {
        if (disposed) return
        val previousLayoutGeneration = layoutGeneration
        val visibleBefore = visibleResourceRange()
        val previouslyAcceptedGeometry = readingOrder.indices.filterTo(mutableSetOf()) {
            layoutModel.geometryHeightOrNull(it) != null
        }
        val attachedBefore = attachedMaterializations.values.filter { materialization ->
            val target = materialization.target
            val resource = materialization.resource
            target.layoutGeneration == previousLayoutGeneration &&
                target.resourceGeneration == resource.generation &&
                resource.parent != null && resource.isAttachedToWindow &&
                resourceWindow.withLiveResource(target.index, target.resourceGeneration) { it } === resource
        }.associate { it.target.index to it.target.resourceGeneration }
        activeGeometryBatch?.let { previous ->
            val wasApplied = previous.state == ContinuousGeometryBatchState.APPLIED
            emitMissingGeometryBatchMeasurements(previous, "geometry_batch_pending", "unmeasured_on_terminal")
            if (previous.discard()) {
                emitGeometryBatchEvent(
                    kind = "geometry_batch_discarded",
                    batch = previous,
                    result = if (wasApplied) "superseded_after_apply" else "superseded",
                )
            }
        }
        activeGeometryBatch = null
        clearFreshLocatorObservation()
        finishAllReflowWaiters(ContinuousReflowRestoreOutcome.Cancelled)
        reflowTargetBarrier.clear()
        layoutGeneration = layoutModel.beginInPlaceReflow()
        transaction.bindLayoutGeneration(layoutGeneration)
        activeGeometryTransaction = transaction
        val anchorTarget = ContinuousReflowTarget(
            index = transaction.anchor.index,
            layoutGeneration = layoutGeneration,
            resourceGeneration = transaction.anchor.resourceGeneration,
        )
        val requiredResourceGenerations = linkedMapOf(anchorTarget.index to anchorTarget.resourceGeneration)
        visibleBefore?.let { visible ->
            for (index in visible.firstVisibleIndex..visible.lastVisibleIndex) {
                attachedBefore[index]?.let { requiredResourceGenerations[index] = it }
            }
        }
        attachedBefore.forEach { (index, resourceGeneration) ->
            if (index < transaction.anchor.index) {
                requiredResourceGenerations[index] = resourceGeneration
            }
        }
        val batch = ContinuousGeometryMeasurementBatch(
            owner = ContinuousGeometryBatchOwner(
                preferenceGeneration = preferenceGeneration,
                transactionGeneration = transaction.generation,
                layoutGeneration = layoutGeneration,
            ),
            anchor = anchorTarget,
            requiredResourceGenerations = requiredResourceGenerations,
        )
        activeGeometryBatch = batch
        activeGeometryCssOwner = ActiveGeometryCssOwner(
            layoutGeneration = layoutGeneration,
            preferenceGeneration = preferenceGeneration,
            transactionGeneration = transaction.generation,
        )
        val evictedGeneration = reflowDiagnosticOwners.record(layoutGeneration, ReflowDiagnosticOwner(
            context = diagnosticContext,
            preferenceGeneration = preferenceGeneration,
            transactionGeneration = transaction.generation,
            anchorIndex = transaction.anchor.index,
            anchorBeforeY = transaction.anchor.localY,
        ))
        evictedGeneration?.let { evicted ->
            reportedReflowMeasurements.keys.removeAll { it.second == evicted }
            reflowDiagnosticViewportBaselines.remove(evicted)
        }
        emitGeometryBatchEvent("geometry_batch_created", batch, "created")
        requiredResourceGenerations.forEach { (index, resourceGeneration) ->
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "geometry_batch_required",
                    context = diagnosticContext,
                    preferenceGeneration = preferenceGeneration,
                    transactionGeneration = transaction.generation,
                    layoutGeneration = layoutGeneration,
                    resourceGeneration = resourceGeneration,
                    readingOrderIndex = index,
                    oldHeightPx = resourceWindow.withLiveResource(index, resourceGeneration) { it.currentHeightPx },
                    result = "required_at_snapshot",
                ),
            )
        }
        if (attachedBefore[anchorTarget.index] != anchorTarget.resourceGeneration) {
            emitMissingGeometryBatchMeasurements(batch, "geometry_batch_pending", "unmeasured_on_terminal")
            batch.failRequired(anchorTarget)
            emitGeometryBatchEvent(
                kind = "geometry_batch_discarded",
                batch = batch,
                result = "anchor_not_attached_at_snapshot",
            )
        }
        if (diagnosticContext != null) {
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "layout_generation",
                    context = diagnosticContext,
                    preferenceGeneration = preferenceGeneration,
                    transactionGeneration = transaction.generation,
                    layoutGeneration = layoutGeneration,
                    readingOrderIndex = transaction.anchor.index,
                    anchorBeforeY = transaction.anchor.localY,
                    result = "created",
                ),
            )
        }
        // Keep each live resource and its WebView attached. Only its layout
        // generation changes; old heights remain geometry placeholders until
        // a measurement tagged with the new generation is accepted.
        for (childIndex in 0 until recyclerView.childCount) {
            (recyclerView.getChildViewHolder(recyclerView.getChildAt(childIndex)) as? ResourceHolder)
                ?.refreshMaterialization()
        }
        resourceWindow.liveIndices()
            .sortedWith(compareBy<Int> { if (it == transaction.anchor.index) 0 else 1 }.thenBy { it })
            .forEach { index ->
            val resource = resourceWindow.resourceAt(index) ?: return@forEach
            resource.configureTextRenderDiagnostics(
                if (diagnosticContext != null && index == transaction.anchor.index) transaction.anchor.locator else null,
            )
            resource.setCssStateDiagnosticListener { event ->
                emitReflowDiagnostic(event.copy(context = event.layoutGeneration?.let { reflowDiagnosticOwners.ownerFor(it)?.context }))
            }
            val target = ContinuousReflowTarget(index, layoutGeneration, resource.generation)
            val owner = reflowDiagnosticOwners.ownerFor(layoutGeneration)
            if (owner != null) {
                resource.setReflowDiagnosticLifecycleListener { stage ->
                    emitReflowDiagnostic(
                        EpubContinuousReflowDiagnosticEvent(
                            kind = "resource_$stage",
                            context = owner.context,
                            preferenceGeneration = owner.preferenceGeneration,
                            transactionGeneration = owner.transactionGeneration,
                            layoutGeneration = target.layoutGeneration,
                            resourceGeneration = target.resourceGeneration,
                            readingOrderIndex = target.index,
                            oldHeightPx = resource.currentHeightPx,
                            newHeightPx = resource.currentHeightPx,
                            anchorBeforeY = owner.anchorBeforeY,
                            result = "webview_${resource.webViewIdentity}",
                        ),
                    )
                }
            }
            val oldHeightPx = resource.currentHeightPx
            val onCssApplied: (Boolean) -> Unit = { applied ->
                if (!disposed && layoutGeneration == target.layoutGeneration &&
                    isLiveResource(target.index, target.resourceGeneration)
                ) {
                    if (owner != null) {
                        emitReflowDiagnostic(
                            EpubContinuousReflowDiagnosticEvent(
                                kind = if (index == transaction.anchor.index) "resource_in_place_css" else "neighbor_update",
                                context = owner.context,
                                preferenceGeneration = owner.preferenceGeneration,
                                transactionGeneration = owner.transactionGeneration,
                                layoutGeneration = target.layoutGeneration,
                                resourceGeneration = target.resourceGeneration,
                                readingOrderIndex = target.index,
                                oldHeightPx = oldHeightPx,
                                newHeightPx = resource.currentHeightPx,
                                anchorBeforeY = owner.anchorBeforeY,
                                result = if (applied) "applied_same_webview_${resource.webViewIdentity}" else "failed",
                            ),
                        )
                    }
                    if (applied) onReflowTargetReady(target) else onReflowTargetFailed(target)
                }
            }
            if (resource.isBootstrapPending && !resource.cssApplicationPending) {
                val deferred = resource.deferCssUntilBootstrap(
                    nextLayoutGeneration = layoutGeneration,
                    preferenceGeneration = preferenceGeneration,
                    transactionGeneration = transaction.generation,
                    onApplied = onCssApplied,
                )
                if (deferred) {
                    if (owner != null) {
                        emitReflowDiagnostic(
                            EpubContinuousReflowDiagnosticEvent(
                                kind = "neighbor_update",
                                context = owner.context,
                                preferenceGeneration = owner.preferenceGeneration,
                                transactionGeneration = owner.transactionGeneration,
                                layoutGeneration = target.layoutGeneration,
                                resourceGeneration = target.resourceGeneration,
                                readingOrderIndex = target.index,
                                oldHeightPx = resource.currentHeightPx,
                                newHeightPx = resource.currentHeightPx,
                                anchorBeforeY = owner.anchorBeforeY,
                                result = "deferred_until_bootstrap_webview_${resource.webViewIdentity}",
                            ),
                        )
                    }
                    return@forEach
                }
            }
            if (!resource.canFindLocator && !resource.cssApplicationPending) {
                onReflowTargetFailed(target)
                return@forEach
            }
            resource.applyCssForLayoutGeneration(
                nextLayoutGeneration = layoutGeneration,
                preferenceGeneration = preferenceGeneration,
                transactionGeneration = transaction.generation,
                onApplied = onCssApplied,
            )
        }
        logTransactionState("after_in_place_css", transaction, null)
    }

    internal fun setViewportChangedListener(listener: (() -> Unit)?) {
        viewportChangedListener = listener
    }

    internal fun setReflowDiagnosticListener(listener: ((EpubContinuousReflowDiagnosticEvent) -> Unit)?) {
        reflowDiagnosticListener = listener
    }

    private fun emitReflowDiagnostic(event: EpubContinuousReflowDiagnosticEvent) {
        try {
            reflowDiagnosticListener?.invoke(event)
        } catch (_: Throwable) {
            // Diagnostic observers must not enter the reflow decision path.
        }
    }

    private fun emitReflowManualDragSnapshot() {
        val active = reflowDiagnosticTransactions.entries.firstOrNull { (_, transaction) ->
            !transaction.terminal
        } ?: return
        val (target, transaction) = active
        if (manualDragDiagnosticReportedTransaction == transaction.generation) return
        val owner = reflowDiagnosticOwners.ownerFor(target.layoutGeneration) ?: return
        emitViewportSnapshot(
            snapshotStage = "user_drag_during_reflow",
            context = owner.context,
            preferenceGeneration = owner.preferenceGeneration,
            transactionGeneration = transaction.generation,
            layoutGeneration = target.layoutGeneration,
            resourceGeneration = target.resourceGeneration,
            anchorIndex = target.index,
            anchorProgression = transaction.anchor.locator.locations.progression,
            anchorPointDocumentYPx = null,
            anchorPointViewportYPx = null,
            anchorPointAvailable = false,
            anchorPointUnavailableReason = "not_sampled_during_user_drag",
            anchorBeforeLocalYPx = transaction.anchor.localY,
            anchorBeforeViewportYPx = transaction.anchor.viewportY,
            commitLockHeld = activeGeometryTransaction?.generation == transaction.generation,
            result = "user_dragging",
        )
        manualDragDiagnosticReportedTransaction = transaction.generation
    }

    internal fun diagnosticViewportLayoutSnapshot(
        anchorIndex: Int?,
    ): EpubContinuousViewportLayoutSnapshot? = captureDiagnosticViewportLayoutSnapshot(anchorIndex)

    internal fun emitAfterReflowCommitSnapshot(
        transaction: ContinuousGeometryReflowTransaction,
        context: EpubContinuousReflowDiagnosticContext?,
    ) {
        val point = transaction.verifiedLocatorPoint
        val targetIndex = transaction.targetReadingOrderIndex
        val targetGeneration = transaction.targetResourceGeneration
        val currentResource = targetGeneration?.let { generation ->
            resourceWindow.withLiveResource(targetIndex, generation) { it }
        }
        val pointIsCurrent = !disposed &&
            transaction.state == ContinuousGeometryReflowTransaction.State.COMPLETED &&
            !transaction.presentationTransactionActive && transaction.converged &&
            transaction.layoutGeneration == layoutGeneration && currentResource != null && point != null &&
            transaction.verifiedViewportDeltaPx?.let(::continuousAnchorViewportMatches) == true
        emitViewportSnapshot(
            snapshotStage = "after_reflow_commit",
            context = context,
            preferenceGeneration = transaction.preferenceGeneration,
            transactionGeneration = transaction.generation,
            layoutGeneration = transaction.layoutGeneration,
            resourceGeneration = transaction.targetResourceGeneration,
            anchorIndex = targetIndex,
            anchorProgression = transaction.anchor.locator.locations.progression,
            anchorPointDocumentYPx = point?.documentYLayoutPx,
            anchorPointViewportYPx = point?.viewportY?.takeIf { pointIsCurrent },
            anchorPointAvailable = pointIsCurrent,
            anchorPointUnavailableReason = if (pointIsCurrent) null else "verified_point_or_resource_stale_at_transaction_completion",
            anchorPointSampleStage = if (pointIsCurrent) "after_anchor_verified" else "unavailable_at_transaction_completion",
            anchorBeforeLocalYPx = transaction.anchor.localY,
            anchorBeforeViewportYPx = transaction.anchor.viewportY,
            anchorResourceHref = boundedContinuousDiagnosticResourceHref(transaction.anchor.locator.href.toString()),
            anchorViewportDeltaPx = transaction.verifiedViewportDeltaPx?.takeIf { pointIsCurrent },
            anchorViewportTolerancePx = CONTINUOUS_ANCHOR_VIEWPORT_TOLERANCE_PX,
            anchorSemanticMatch = pointIsCurrent &&
                (transaction.anchor.locator.locations["continuousDomAnchor"] == null ||
                    continuousSemanticAnchorQuality(transaction.anchor.locator, point, true) == ContinuousSemanticAnchorQuality.EXACT_DOM_POINT),
            observedReadingOrderIndex = targetIndex.takeIf { pointIsCurrent },
            observedProgression = transaction.verifiedObservedProgression.takeIf { pointIsCurrent },
            commitLockHeld = transaction.commitOwner != null,
            result = if (pointIsCurrent) "transaction_completed_cached_verified_point" else "verified_sample_stale_at_transaction_completion",
        )
    }

    private fun captureDiagnosticViewportLayoutSnapshot(
        anchorIndex: Int?,
    ): EpubContinuousViewportLayoutSnapshot? {
        if (disposed || Looper.myLooper() != Looper.getMainLooper()) return null
        val firstVisible = layoutManager.findFirstVisibleItemPosition()
            .takeIf { it != RecyclerView.NO_POSITION }
        val firstView = firstVisible?.let(layoutManager::findViewByPosition)
        val anchorView = anchorIndex?.let(layoutManager::findViewByPosition)
        val anchorIsAttached = anchorView?.isAttachedToWindow == true
        val webView = anchorIndex?.let(attachedMaterializations::get)?.resource
        return EpubContinuousViewportLayoutSnapshot(
            firstVisibleIndex = firstVisible,
            firstVisibleTopPx = firstView?.let(layoutManager::getDecoratedTop),
            heightPx = recyclerView.height.takeIf { it > 0 },
            paddingTopPx = recyclerView.paddingTop,
            paddingBottomPx = recyclerView.paddingBottom,
            anchorIndex = anchorIndex?.takeIf { anchorIsAttached },
            anchorTopPx = anchorView?.takeIf { anchorIsAttached }?.let(layoutManager::getDecoratedTop),
            anchorBottomPx = anchorView?.takeIf { anchorIsAttached }?.let(layoutManager::getDecoratedBottom),
            webViewIdentity = webView?.webViewIdentity,
            webViewIdentityUnavailableReason = if (webView == null) "resource_not_materialized" else null,
        )
    }

    internal fun emitViewportSnapshot(
        snapshotStage: String,
        context: EpubContinuousReflowDiagnosticContext?,
        preferenceGeneration: Long?,
        transactionGeneration: Long,
        layoutGeneration: Int?,
        resourceGeneration: Long?,
        anchorIndex: Int?,
        anchorProgression: Double?,
        anchorPointDocumentYPx: Double?,
        anchorPointViewportYPx: Double?,
        anchorPointAvailable: Boolean,
        anchorPointUnavailableReason: String? = null,
        anchorPointSampleStage: String? = null,
        anchorBeforeLocalYPx: Double? = null,
        anchorBeforeViewportYPx: Double? = null,
        anchorResourceHref: String? = null,
        anchorViewportDeltaPx: Double? = null,
        anchorViewportTolerancePx: Double? = null,
        anchorSemanticMatch: Boolean? = null,
        observedReadingOrderIndex: Int? = null,
        observedProgression: Double? = null,
        requestedCorrectionOffsetPx: Int? = null,
        requestedViewportDeltaPx: Double? = null,
        scrollRequestIssued: Boolean? = null,
        commitLockHeld: Boolean? = null,
        predecessorMeasurementCount: Int? = null,
        predecessorHeightDeltaPx: Long? = null,
        batchHeightDeltaPx: Long? = null,
        result: String? = null,
    ) {
        // Diagnostic collection is deliberately best-effort: a view getter or
        // payload construction failure must never enter the reflow path.
        runCatching {
            val viewport = captureDiagnosticViewportLayoutSnapshot(anchorIndex)
            if (snapshotStage == "before_reflow" && layoutGeneration != null && viewport != null) {
                reflowDiagnosticViewportBaselines[layoutGeneration] = viewport
                while (reflowDiagnosticViewportBaselines.size > 12) {
                    reflowDiagnosticViewportBaselines.remove(reflowDiagnosticViewportBaselines.keys.first())
                }
            }
            val rawHref = anchorResourceHref ?: activeGeometryTransaction?.anchor
                ?.takeIf { it.index == anchorIndex }?.locator?.href?.toString()
            val safeHref = rawHref?.let(::boundedContinuousDiagnosticResourceHref)
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                kind = "viewport_snapshot",
                context = context,
                preferenceGeneration = preferenceGeneration,
                transactionGeneration = transactionGeneration,
                layoutGeneration = layoutGeneration,
                resourceGeneration = resourceGeneration,
                readingOrderIndex = anchorIndex,
                snapshotStage = snapshotStage,
                viewportSampleStage = snapshotStage,
                anchorPointSampleStage = anchorPointSampleStage,
                viewportFirstVisibleIndex = viewport?.firstVisibleIndex,
                viewportFirstVisibleTopPx = viewport?.firstVisibleTopPx,
                viewportHeightPx = viewport?.heightPx,
                viewportPaddingTopPx = viewport?.paddingTopPx,
                viewportPaddingBottomPx = viewport?.paddingBottomPx,
                viewportAnchorIndex = viewport?.anchorIndex,
                viewportAnchorTopPx = viewport?.anchorTopPx,
                viewportAnchorBottomPx = viewport?.anchorBottomPx,
                webViewIdentity = viewport?.webViewIdentity,
                webViewIdentityUnavailableReason = viewport?.webViewIdentityUnavailableReason
                    ?: if (viewport == null) "viewport_unavailable" else null,
                anchorProgression = anchorProgression?.takeIf { it.isFinite() },
                anchorBeforeLocalYPx = anchorBeforeLocalYPx?.takeIf { it.isFinite() },
                anchorBeforeViewportYPx = anchorBeforeViewportYPx?.takeIf { it.isFinite() },
                anchorResourceHref = safeHref,
                anchorResourceHrefUnavailableReason = if (safeHref == null) "not_relative_or_unavailable" else null,
                anchorPointDocumentYPx = anchorPointDocumentYPx?.takeIf { it.isFinite() },
                anchorPointViewportYPx = anchorPointViewportYPx?.takeIf { it.isFinite() },
                targetViewportYPx = anchorBeforeViewportYPx?.takeIf { it.isFinite() },
                actualViewportYPx = anchorPointViewportYPx?.takeIf { it.isFinite() },
                anchorPointAvailable = anchorPointAvailable,
                anchorPointUnavailableReason = anchorPointUnavailableReason,
                anchorViewportDeltaPx = anchorViewportDeltaPx?.takeIf { it.isFinite() },
                anchorViewportTolerancePx = anchorViewportTolerancePx?.takeIf { it.isFinite() },
                anchorSemanticMatch = anchorSemanticMatch,
                observedReadingOrderIndex = observedReadingOrderIndex,
                observedProgression = observedProgression?.takeIf { it.isFinite() },
                semanticProgressionDelta = if (anchorProgression != null && observedProgression != null) {
                    (observedProgression - anchorProgression).takeIf { it.isFinite() }
                } else null,
                requestedCorrectionOffsetPx = requestedCorrectionOffsetPx,
                requestedViewportDeltaPx = requestedViewportDeltaPx?.takeIf { it.isFinite() },
                scrollRequestIssued = scrollRequestIssued,
                commitLockHeld = commitLockHeld,
                predecessorMeasurementCount = predecessorMeasurementCount,
                predecessorHeightDeltaPx = predecessorHeightDeltaPx,
                batchHeightDeltaPx = batchHeightDeltaPx,
                viewportFirstVisibleIndexBefore = if (snapshotStage == "after_anchor_verified") {
                    layoutGeneration?.let(reflowDiagnosticViewportBaselines::get)?.firstVisibleIndex
                } else null,
                viewportFirstVisibleIndexAfter = viewport?.firstVisibleIndex,
                viewportFirstVisibleTopBeforePx = if (snapshotStage == "after_anchor_verified") {
                    layoutGeneration?.let(reflowDiagnosticViewportBaselines::get)?.firstVisibleTopPx
                } else null,
                viewportFirstVisibleTopAfterPx = viewport?.firstVisibleTopPx,
                viewportFirstVisibleTopDeltaPx = if (snapshotStage == "after_anchor_verified") {
                    val beforeTop = layoutGeneration?.let(reflowDiagnosticViewportBaselines::get)?.firstVisibleTopPx
                    if (beforeTop != null && viewport?.firstVisibleTopPx != null) viewport.firstVisibleTopPx - beforeTop else null
                } else null,
                result = result,
            ),
            )
            if (snapshotStage == "after_anchor_verified") {
                val before = layoutGeneration?.let(reflowDiagnosticViewportBaselines::get)
                emitReflowDiagnostic(
                    EpubContinuousReflowDiagnosticEvent(
                        kind = "viewport_delta",
                        context = context,
                        preferenceGeneration = preferenceGeneration,
                        transactionGeneration = transactionGeneration,
                        layoutGeneration = layoutGeneration,
                        resourceGeneration = resourceGeneration,
                        readingOrderIndex = anchorIndex,
                        snapshotStage = snapshotStage,
                        viewportSampleStage = snapshotStage,
                        anchorResourceHref = safeHref,
                        anchorResourceHrefUnavailableReason = if (safeHref == null) "not_relative_or_unavailable" else null,
                        anchorProgression = anchorProgression?.takeIf { it.isFinite() },
                        observedReadingOrderIndex = observedReadingOrderIndex,
                        observedProgression = observedProgression?.takeIf { it.isFinite() },
                        semanticProgressionDelta = if (anchorProgression != null && observedProgression != null) {
                            (observedProgression - anchorProgression).takeIf { it.isFinite() }
                        } else null,
                        targetViewportYPx = anchorBeforeViewportYPx?.takeIf { it.isFinite() },
                        actualViewportYPx = anchorPointViewportYPx?.takeIf { it.isFinite() },
                        anchorViewportDeltaPx = anchorViewportDeltaPx?.takeIf { it.isFinite() },
                        anchorViewportTolerancePx = anchorViewportTolerancePx?.takeIf { it.isFinite() },
                        anchorSemanticMatch = anchorSemanticMatch,
                        anchorPointAvailable = anchorPointAvailable,
                        anchorPointUnavailableReason = anchorPointUnavailableReason,
                        viewportFirstVisibleIndexBefore = before?.firstVisibleIndex,
                        viewportFirstVisibleIndexAfter = viewport?.firstVisibleIndex,
                        viewportFirstVisibleTopBeforePx = before?.firstVisibleTopPx,
                        viewportFirstVisibleTopAfterPx = viewport?.firstVisibleTopPx,
                        viewportFirstVisibleTopDeltaPx = if (before?.firstVisibleTopPx != null && viewport?.firstVisibleTopPx != null) {
                            viewport.firstVisibleTopPx - before.firstVisibleTopPx
                        } else null,
                        result = result,
                    ),
                )
                if (before?.firstVisibleIndex != null && viewport?.firstVisibleIndex != null &&
                    before.firstVisibleIndex != viewport.firstVisibleIndex
                ) {
                    emitReflowDiagnostic(
                        EpubContinuousReflowDiagnosticEvent(
                            kind = "viewport_resource_transition",
                            context = context,
                            preferenceGeneration = preferenceGeneration,
                            transactionGeneration = transactionGeneration,
                            layoutGeneration = layoutGeneration,
                            readingOrderIndex = anchorIndex,
                            snapshotStage = snapshotStage,
                            viewportSampleStage = snapshotStage,
                            viewportFirstVisibleIndexBefore = before.firstVisibleIndex,
                            viewportFirstVisibleIndexAfter = viewport.firstVisibleIndex,
                            viewportFirstVisibleTopBeforePx = before.firstVisibleTopPx,
                            viewportFirstVisibleTopAfterPx = viewport.firstVisibleTopPx,
                            viewportFirstVisibleTopDeltaPx = if (before.firstVisibleTopPx != null && viewport.firstVisibleTopPx != null) {
                                viewport.firstVisibleTopPx - before.firstVisibleTopPx
                            } else null,
                            result = "first_visible_resource_changed",
                        ),
                    )
                }
            }
        }
    }

    internal fun setManualDragStartedListener(listener: (() -> Unit)?) {
        manualDragStartedListener = listener
    }

    internal fun setManualScrollActivityChangedListener(listener: ((Boolean) -> Unit)?) {
        manualScrollActivityChangedListener = listener
    }

    internal fun setManualScrollProgressListener(listener: (() -> Unit)?) {
        manualScrollProgressListener = listener
    }

    internal fun setResourceReleasedListener(listener: ((Int, Long) -> Unit)?) {
        resourceReleasedListener = listener
    }

    internal fun setResourceReadyListener(listener: ((Int, Long) -> Unit)?) {
        resourceReadyListener = listener
    }

    internal fun setDecorationSnapshotProvider(provider: (() -> Map<String, Pair<List<Decoration>, HtmlDecorationTemplates>>)?): Unit {
        decorationSnapshotProvider = provider
    }

    internal fun setInitialViewportReadyListener(listener: (() -> Unit)?) {
        initialViewportReadyListener = listener
    }

    internal fun setInitialViewportFailureListener(listener: ((String) -> Unit)?) {
        initialViewportFailureListener = listener
    }

    internal fun setSelectionTouchOwner(index: Int, generation: Long) {
        if (isLiveResource(index, generation)) {
            val owner = index to generation
            selectionTouchOwner = owner
            selectionViewportGate.activate(owner)
        }
    }

    internal fun clearSelectionTouchOwner(index: Int, generation: Long) {
        val owner = index to generation
        if (selectionTouchOwner == owner) selectionTouchOwner = null
        selectionViewportGate.clear(owner)
    }

    internal fun pinResource(index: Int, reason: ContinuousResourcePinReason) {
        if (disposed || index !in readingOrder.indices) return
        if (!initialViewportPreloadsReleased && reason == ContinuousResourcePinReason.NAVIGATION_TARGET) {
            selectInitialViewportTarget(index)
        }
        pins.getOrPut(index, ::mutableSetOf).add(reason)
        resourceWindow.pin(index, reason)
        reconcileResourceWindow()
        Log.d(tag, "CONTINUOUS_HOST_PIN index=$index reason=$reason")
    }

    internal fun unpinResource(index: Int, reason: ContinuousResourcePinReason) {
        val resourceGeneration = resourceWindow.generationAt(index)
        pins[index]?.apply { remove(reason); if (isEmpty()) pins.remove(index) }
        resourceWindow.unpin(index, reason)
        Log.d(
            tag,
            "CONTINUOUS_TARGET_RELEASE index=$index lg=$layoutGeneration rg=$resourceGeneration reason=$reason",
        )
        reconcileResourceWindow()
    }

    /** Holds the current live window through a settings-preview handoff. */
    internal fun beginGeometryReflowPinLease() {
        if (disposed || geometryReflowPinLease.isNotEmpty()) return
        val live = resourceWindow.liveIndices()
        geometryReflowPinLease = live
        live.forEach { index ->
            pins.getOrPut(index, ::mutableSetOf).add(ContinuousResourcePinReason.GEOMETRY_REFLOW)
            resourceWindow.pin(index, ContinuousResourcePinReason.GEOMETRY_REFLOW)
        }
        reconcileResourceWindow()
    }

    /** Releases the retained window only when the latest settings request is terminal. */
    internal fun finishGeometryReflowPinLease() {
        if (geometryReflowPinLease.isEmpty()) return
        val leased = geometryReflowPinLease
        geometryReflowPinLease = emptySet()
        leased.forEach { index ->
            pins[index]?.apply {
                remove(ContinuousResourcePinReason.GEOMETRY_REFLOW)
                if (isEmpty()) pins.remove(index)
            }
            resourceWindow.unpin(index, ContinuousResourcePinReason.GEOMETRY_REFLOW)
        }
        reconcileResourceWindow()
    }

    /** Wakes transaction barriers before its owning preview job is cancelled. */
    internal fun cancelGeometryReflowWaiters() {
        finishAllReflowWaiters(ContinuousReflowRestoreOutcome.Cancelled)
        geometryBatchReadyWaiters.values.forEach { it.complete(Unit) }
    }

    /** Direct target preparation never materializes preceding spine resources. */
    internal fun prepareTargetResource(index: Int) {
        if (!disposed && index in readingOrder.indices) {
            if (initialViewportFailureReported) return
            selectInitialViewportTarget(index)
            resourceWindow.reconcile(
                setOf(index),
                emptySequence(),
            )
        }
    }

    internal suspend fun findFirstVisibleLocator(index: Int, generation: Long): Locator? {
        if (disposed) return null
        val resource = resourceWindow.withLiveResource(index, generation) { it } ?: return null
        val locator = resource.findFirstVisibleLocator() ?: return null
        return resourceWindow.withLiveResource(index, generation) { locator }
    }

    /**
     * Resolves the logical reading anchor in the parent viewport, not the top
     * of a child WebView. The anchor is captured in Android View pixels; the
     * resource WebView converts it to CSS pixels before invoking DOM point APIs.
     */
    /**
     * A query is scheduled only for a currently-visible, bootstrap-ready
     * resource. Scroll callbacks which cannot identify such a resource never
     * enter the session dispatcher and therefore cannot form a null-result
     * loop while RecyclerView is relaying layout work.
     */
    internal fun currentLocatorAnchor(): EpubContinuousLocatorAnchor? {
        if (disposed || recyclerView.height <= 0) return null
        val viewportAnchorY = recyclerView.height * READING_ANCHOR_FRACTION
        val child = recyclerView.findChildViewUnder(recyclerView.width / 2f, viewportAnchorY) ?: return null
        val index = recyclerView.getChildAdapterPosition(child).takeIf { it != RecyclerView.NO_POSITION } ?: return null
        val materialization = attachedMaterializations[index] ?: return null
        val resource = resourceWindow.withLiveResource(index, materialization.target.resourceGeneration) { it }
            ?.takeIf { it === materialization.resource }
            ?: return null
        val generation = resource.generation
        if (!reflowEventPort.canAnswerLocator(ContinuousReflowTarget(index, layoutGeneration, generation)) { resource.canFindLocator }) return null
        val localY = (viewportAnchorY - child.top).coerceAtLeast(0f).toDouble()
        return EpubContinuousLocatorAnchor(
            readingOrderIndex = index,
            resourceGeneration = generation,
            layoutGeneration = layoutGeneration,
            x = recyclerView.width / 2.0,
            y = localY,
        )
    }

    /**
     * Executes against only the resource captured above. Both pre- and
     * post-WebView checks retain the exact resource generation, so a released
     * or recreated child can never answer a Locator request for its predecessor.
     */
    internal suspend fun findLocatorAtReadingAnchor(anchor: EpubContinuousLocatorAnchor, stableDom: Boolean = false, diagnostic: Boolean = true): Locator? {
        if (disposed || anchor.layoutGeneration != layoutGeneration) return null
        val materialization = attachedMaterializations[anchor.readingOrderIndex]
            ?.takeIf { it.target.layoutGeneration == anchor.layoutGeneration && it.target.resourceGeneration == anchor.resourceGeneration }
            ?: return null
        val resource = resourceWindow.withLiveResource(anchor.readingOrderIndex, anchor.resourceGeneration) { it }
            ?.takeIf { it === materialization.resource }
            ?: return null
        val target = ContinuousReflowTarget(anchor.readingOrderIndex, anchor.layoutGeneration, anchor.resourceGeneration)
        if (!reflowEventPort.canAnswerLocator(target) { resource.canFindLocator }) return null
        Log.d(
            tag,
            "CONTINUOUS_FIND_LOCATOR_AT_POINT index=${anchor.readingOrderIndex} generation=${anchor.resourceGeneration} x=${anchor.x} y=${anchor.y}",
        )
        val resourceLocator = reflowEventPort.observeLocator(anchor) {
            if (stableDom) resource.captureContinuousReadingAnchor(anchor.x, anchor.y)
            else resource.findLocatorAtPoint(anchor.x, anchor.y, diagnostic)
        }
            ?: run {
                Log.w(tag, "CONTINUOUS_FIND_LOCATOR_DROP reason=webview_no_locator index=${anchor.readingOrderIndex} generation=${anchor.resourceGeneration}")
                return null
            }
        val locator = ContinuousResourceLocatorNormalizer.normalize(
            resourceLocator = resourceLocator,
            readingOrderLink = readingOrder[anchor.readingOrderIndex],
        ) ?: run {
            Log.w(tag, "CONTINUOUS_FIND_LOCATOR_DROP reason=semantic_progression_unavailable index=${anchor.readingOrderIndex} generation=${anchor.resourceGeneration}")
            return null
        }
        return resourceWindow.withLiveResource(anchor.readingOrderIndex, anchor.resourceGeneration) { locator }
            ?: run {
                Log.w(tag, "CONTINUOUS_FIND_LOCATOR_DROP reason=resource_not_live_after_callback index=${anchor.readingOrderIndex} generation=${anchor.resourceGeneration}")
                null
            }
    }

    internal suspend fun resolveLocatorVerticalOffset(
        index: Int,
        generation: Long,
        locator: Locator,
    ): Double? {
        if (disposed) return null
        val resource = resourceWindow.withLiveResource(index, generation) { it } ?: return null
        val target = ContinuousReflowTarget(index, layoutGeneration, generation)
        val operation = continuousLocatorOffsetDiagnosticOperation(target, resource, locator)
        Log.d(
            tag,
            "${operation}_REQUEST sessionGeneration=unavailable attached=${isTargetAttached(target)} " +
                "trueReady=${reflowEventPort.canAnswerLocator(target) { resource.canFindLocator }} " +
                "measured=${layoutModel.measuredHeightOrNull(index) != null}",
        )
        val offset = reflowEventPort.resolveLocatorVerticalOffset(target, locator) {
            resource.resolveLocatorVerticalOffset(locator, operation)
        } ?: return null
        return resourceWindow.withLiveResource(index, generation) { offset } ?: run {
            Log.w(tag, "${operation}_DROP result=stale-generation-rejected")
            null
        }
    }

    /** Measures the captured progression caret in the actual parent viewport. */
    internal suspend fun resolveLocatorPointGeometry(
        index: Int,
        generation: Long,
        locator: Locator,
    ): ContinuousResolvedLocatorPoint? {
        if (disposed || index !in readingOrder.indices) return null
        val materialization = attachedMaterializations[index] ?: return null
        if (materialization.target.resourceGeneration != generation) return null
        val resource = resourceWindow.withLiveResource(index, generation) { it }
            ?.takeIf { it === materialization.resource }
            ?: return null
        val target = ContinuousReflowTarget(index, layoutGeneration, generation)
        if (!isTargetAttached(target)) return null
        beforeLocatorPointGeometryForTest?.invoke(target)
        val point = reflowEventPort.resolveLocatorPointGeometry(target, locator) {
            resource.continuousLocatorPointGeometry(locator)
        } ?: return null
        val density = resources.displayMetrics.density.toDouble()
        val viewportY = withContext(Dispatchers.Main.immediate) {
            if (disposed || layoutGeneration != target.layoutGeneration || !isTargetAttached(target)) return@withContext null
            val resourceLocation = IntArray(2)
            val viewportLocation = IntArray(2)
            resource.getLocationOnScreen(resourceLocation)
            recyclerView.getLocationOnScreen(viewportLocation)
            val y = resourceLocation[1] - viewportLocation[1] +
                point.viewportTopCssPx * density
            y.takeIf(Double::isFinite)
        } ?: return null
        val documentYLayoutPx = point.documentYCssPx * density
        if (!documentYLayoutPx.isFinite() || documentYLayoutPx < 0.0) return null
        return resourceWindow.withLiveResource(index, generation) {
            ContinuousResolvedLocatorPoint(documentYLayoutPx, viewportY, point.semanticAnchorExact,
                point.anchorIdentityId, point.anchorCharacterOffset)
        }
    }

    private fun continuousLocatorOffsetDiagnosticOperation(
        target: ContinuousReflowTarget,
        resource: ContinuousResourceView,
        locator: Locator,
    ): String {
        val selector = locator.locations["cssSelector"]?.toString() ?: "absent"
        return "CONTINUOUS_LOCATOR_OFFSET lg=${target.layoutGeneration} rg=${target.resourceGeneration} " +
            "index=${target.index} webViewId=${resource.webViewIdentity} href=${locator.href} " +
            "selector=$selector " +
            "textBefore=${!locator.text.before.isNullOrEmpty()} textAfter=${!locator.text.after.isNullOrEmpty()} " +
            "progression=${locator.locations.progression}"
    }

    /**
     * Random-access Locator navigation. The target resource is the only
     * materialized spine entry; offsets are measured in its document and then
     * aligned to the stable parent reading anchor.
     */
    internal suspend fun go(locator: Locator): Boolean {
        val authority = ContinuousNavigationAuthority().apply { begin(0L) }
        return goWithOutcome(locator, 0L, authority).accepted
    }

    internal suspend fun goWithOutcome(
        locator: Locator,
        transactionId: Long,
        navigationAuthority: ContinuousNavigationAuthority,
        isRequestCurrent: () -> Boolean = { true },
    ): ContinuousNavigationResult {
        val targetIndex = readingOrder.indexOfFirst { it.url().isEquivalent(locator.href.removeFragment()) }
        if (disposed || targetIndex < 0 || !isRequestCurrent()) return failedBeforePosition(transactionId, locator)
        pinResource(targetIndex, ContinuousResourcePinReason.NAVIGATION_TARGET)
        try {
            val target = withContext(Dispatchers.Main.immediate) {
                if (disposed || !isRequestCurrent() || !navigationAuthority.isCurrent(transactionId)) {
                    return@withContext null
                }
                prepareTargetResource(targetIndex)
                if (disposed || !isRequestCurrent() || !navigationAuthority.isCurrent(transactionId)) {
                    return@withContext null
                }
                layoutManager.scrollToPositionWithOffset(targetIndex, readingAnchorOffsetPx())
                recyclerView.requestLayout()
                reconcileResourceWindow()
                resourceWindow.resourceAt(targetIndex)?.let {
                    ContinuousReflowTarget(targetIndex, layoutGeneration, it.generation)
                }
            } ?: return failedBeforePosition(transactionId, locator)
            if (awaitReflowTarget(target) != ContinuousReflowRestoreOutcome.Ready ||
                !isRequestCurrent() || !navigationAuthority.isCurrent(transactionId)
            ) {
                return failedBeforePosition(transactionId, locator)
            }
            val offset = resolveLocatorVerticalOffset(target.index, target.resourceGeneration, locator)
                ?: return failedBeforePosition(transactionId, locator)
            val postRestoreLayoutPass = recyclerLayoutPass
            withContext(Dispatchers.Main.immediate) {
                if (disposed || !isRequestCurrent() || !navigationAuthority.isCurrent(transactionId) ||
                    layoutGeneration != target.layoutGeneration ||
                    !isLiveResource(target.index, target.resourceGeneration)
                ) return@withContext
                layoutManager.scrollToPositionWithOffset(
                    target.index,
                    (readingAnchorOffsetPx() - offset).toInt(),
                )
                recyclerView.requestLayout()
                reconcileResourceWindow()
            }
            if (awaitPostRestoreLayout(target, postRestoreLayoutPass) != ContinuousReflowRestoreOutcome.Ready) {
                return failedBeforePosition(transactionId, locator)
            }
            val observed = observeRestoredLocator(target)
            val accepted = if (observed == null) {
                false
            } else {
                val resource = resourceWindow.withLiveResource(target.index, target.resourceGeneration) { it }
                resource != null && (semanticLocatorsConverge(locator, observed) ||
                    resource.locatorsShareMeaningfulBlock(locator, observed))
            }
            val targetIsAuthoritative = !disposed &&
                layoutGeneration == target.layoutGeneration &&
                isLiveResource(target.index, target.resourceGeneration)
            val sameResource = observed != null &&
                readingOrder[target.index].url().isEquivalent(observed.href.removeFragment())
            val verification = verifyFinalViewport(
                target = target,
                requested = locator,
                observed = observed,
                sameResource = sameResource,
                targetIsAuthoritative = targetIsAuthoritative,
                navigationAuthority = navigationAuthority,
                transactionId = transactionId,
            )
            val outcome = navigationAuthority.outcomeAfterPosition(
                transactionId = transactionId,
                targetIsAuthoritative = !disposed &&
                    layoutGeneration == target.layoutGeneration &&
                    isLiveResource(target.index, target.resourceGeneration),
                accepted = accepted,
            )
            return ContinuousNavigationResult(transactionId, outcome, verification)
        } finally {
            unpinResource(targetIndex, ContinuousResourcePinReason.NAVIGATION_TARGET)
        }
    }

    private fun failedBeforePosition(transactionId: Long, locator: Locator) =
        ContinuousNavigationResult(
            transactionId = transactionId,
            outcome = ContinuousNavigationOutcome.FAILED_BEFORE_POSITION,
            finalViewportVerification = ContinuousFinalViewportVerification(
                classification = ContinuousViewportVerification.UNAVAILABLE,
                sameResource = false,
                targetRangeAtReadingAnchor = null,
                finalVisibleProgression = null,
                targetProgression = locator.locations.progression,
                authorityStillCurrent = false,
            ),
        )

    private suspend fun verifyFinalViewport(
        target: ContinuousReflowTarget,
        requested: Locator,
        observed: Locator?,
        sameResource: Boolean,
        targetIsAuthoritative: Boolean,
        navigationAuthority: ContinuousNavigationAuthority,
        transactionId: Long,
    ): ContinuousFinalViewportVerification {
        val targetProgression = requested.locations.progression
        val finalProgression = observed?.locations?.progression
        val authorityStillCurrent = navigationAuthority.isCurrent(transactionId)
        if (!targetIsAuthoritative || !authorityStillCurrent) {
            return ContinuousFinalViewportVerification(
                ContinuousViewportVerification.SUPERSEDED,
                sameResource,
                null,
                finalProgression,
                targetProgression,
                false,
            )
        }
        if (observed == null) {
            return ContinuousFinalViewportVerification(
                ContinuousViewportVerification.UNAVAILABLE,
                sameResource = false,
                targetRangeAtReadingAnchor = null,
                finalVisibleProgression = null,
                targetProgression = targetProgression,
                authorityStillCurrent = true,
            )
        }
        if (!sameResource || !isReadingAnchorInResource(target.index)) {
            return ContinuousFinalViewportVerification(
                ContinuousViewportVerification.NOT_VERIFIED_TARGET_VIEWPORT,
                sameResource,
                null,
                finalProgression,
                targetProgression,
                true,
            )
        }
        val anchor = currentLocatorAnchor() ?: return ContinuousFinalViewportVerification(
            ContinuousViewportVerification.UNAVAILABLE,
            sameResource,
            null,
            finalProgression,
            targetProgression,
            true,
        )
        if (!isTargetReadingAnchor(target, anchor)) {
            return ContinuousFinalViewportVerification(
                ContinuousViewportVerification.UNAVAILABLE,
                sameResource,
                null,
                finalProgression,
                targetProgression,
                true,
            )
        }
        val resource = resourceWindow.withLiveResource(target.index, target.resourceGeneration) { it }
            ?: return ContinuousFinalViewportVerification(
                ContinuousViewportVerification.SUPERSEDED,
                sameResource,
                null,
                finalProgression,
                targetProgression,
                false,
            )
        val targetRangeAtAnchor = resource.isLocatorRangeAtVerticalAnchor(requested, anchor.y)
        val currentAnchor = currentLocatorAnchor()
        val currentAuthorityAfterProbe = navigationAuthority.isCurrent(transactionId)
        val targetGenerationCurrent = !disposed &&
            layoutGeneration == target.layoutGeneration &&
            isLiveResource(target.index, target.resourceGeneration)
        val currentAnchorMatchesTarget = currentAnchor == anchor &&
            isTargetReadingAnchor(target, anchor) &&
            reflowTargetBarrier.isReady(target)
        val classification = classifyContinuousFinalViewport(
            positionApplied = true,
            authorityStillCurrent = currentAuthorityAfterProbe,
            targetGenerationCurrent = targetGenerationCurrent,
            finalLocatorAvailable = currentAnchorMatchesTarget,
            sameResource = true,
            targetRangeAtReadingAnchor = targetRangeAtAnchor,
        )
        return ContinuousFinalViewportVerification(
            classification = classification,
            sameResource = true,
            targetRangeAtReadingAnchor = targetRangeAtAnchor,
            finalVisibleProgression = finalProgression,
            targetProgression = targetProgression,
            authorityStillCurrent = currentAuthorityAfterProbe && targetGenerationCurrent,
        )
    }

    /**
     * Initial opening differs from ordinary navigation: showing a saved
     * Locator while its target still has the 800 px placeholder exposes that
     * placeholder's later replacement as a visible viewport jump. The same
     * real target boundary used by reflow (bootstrap, measurement and an
     * attached RecyclerView layout) is therefore reached before the one
     * authoritative opening restore.
     */
    internal suspend fun restoreInitialLocator(
        locator: Locator,
        onDiagnostic: ((String, String, Map<String, Any?>) -> Unit)? = null,
    ): Boolean {
        fun report(stage: String, result: String, facts: Map<String, Any?> = emptyMap()) {
            onDiagnostic?.invoke(stage, result, facts)
        }
        fun failed(stage: String, reason: String, facts: Map<String, Any?> = emptyMap()): Boolean {
            report(stage, "failed", mapOf("failureReason" to reason) + facts)
            return false
        }
        report("target_resource_resolution", "started")
        val targetIndex = readingOrder.indexOfFirst { it.url().isEquivalent(locator.href.removeFragment()) }
        if (disposed) return failed("target_resource_resolution", "host_disposed")
        if (targetIndex < 0) return failed("target_resource_resolution", "target_not_in_reading_order")
        report("target_resource_resolution", "success", mapOf("resolvedReadingOrderIndex" to targetIndex))
        initialRestorePending = true
        initialRestoreAuthority.begin(targetIndex)
        BiblioLifeOpenTimingDiagnostics.targetSelected(targetIndex)
        var target: ContinuousReflowTarget? = null
        pinResource(targetIndex, ContinuousResourcePinReason.NAVIGATION_TARGET)
        try {
            report("target_materialization", "started")
            val materializedTarget = withContext(Dispatchers.Main.immediate) {
                prepareTargetResource(targetIndex)
                layoutManager.scrollToPositionWithOffset(targetIndex, readingAnchorOffsetPx())
                recyclerView.requestLayout()
                reconcileResourceWindow(includePreloads = false)
                resourceWindow.resourceAt(targetIndex)?.let {
                    ContinuousReflowTarget(targetIndex, layoutGeneration, it.generation)
                }
            } ?: return failed("target_materialization", "target_not_materialized")
            target = materializedTarget
            if (!initialRestoreAuthority.materialize(materializedTarget)) {
                return failed("target_materialization", "target_authority_rejected")
            }
            report("target_materialization", "success")
            Log.d(tag, "CONTINUOUS_INITIAL_RESTORE materialized index=${materializedTarget.index} lg=${materializedTarget.layoutGeneration} rg=${materializedTarget.resourceGeneration}")
            report("target_geometry", "started")
            val ready = awaitReflowTarget(materializedTarget)
            Log.d(tag, "CONTINUOUS_INITIAL_RESTORE geometry_ready index=${materializedTarget.index} result=${ready.reflowDiagnosticResult}")
            if (ready != ContinuousReflowRestoreOutcome.Ready) return failed("target_geometry", ready.reflowDiagnosticResult)
            report("target_geometry", "success")
            fun geometryRevision() = resourceWindow.resourceAt(materializedTarget.index)?.let {
                Triple(it.currentHeightPx, it.reportedMeasurementGenerationForOpen, it.currentMeasurementEpoch)
            }
            var resolvedGeometry = geometryRevision()
            report("locator_offset", "started")
            var offset = resolveLocatorVerticalOffset(materializedTarget.index, materializedTarget.resourceGeneration, locator)
                ?: return failed("locator_offset", "locator_offset_unavailable")
            report("locator_offset", "success")
            Log.d(tag, "CONTINUOUS_INITIAL_RESTORE offset index=${materializedTarget.index} result=resolved")
            val postRestoreLayoutPass = recyclerLayoutPass
            report("viewport_positioning", "started", mapOf("positioningOutcome" to "position_requested"))
            val geometry = if (onDiagnostic != null) mutableMapOf<String, Any?>(
                "targetDocumentOffsetLayoutPx" to offset,
                "requestedLocatorFields" to initialRestoreLocatorFields(locator),
            ) else null
            withContext(Dispatchers.Main.immediate) {
                if (disposed || layoutGeneration != materializedTarget.layoutGeneration ||
                    !isLiveResource(materializedTarget.index, materializedTarget.resourceGeneration)
                ) {
                    report("viewport_positioning", "skipped", mapOf("positioningOutcome" to "target_no_longer_live"))
                    return@withContext
                }
                val requestedItemOffset = (readingAnchorOffsetPx() - offset).toInt()
                geometry?.apply {
                    put("requestedItemOffsetPx", requestedItemOffset)
                    put("beforePositioning", initialRestoreGeometry(materializedTarget))
                }
                initialRestoreAuthority.markRestoreRequested(materializedTarget)
                layoutManager.scrollToPositionWithOffset(materializedTarget.index, requestedItemOffset)
                recyclerView.requestLayout()
                reconcileResourceWindow()
                report("viewport_positioning", "success", mapOf(
                    "positioningOutcome" to "position_accepted",
                ))
            }
            Log.d(tag, "CONTINUOUS_INITIAL_RESTORE restore index=${materializedTarget.index} result=requested")
            report("post_restore_layout", "started")
            val postRestore = awaitPostRestoreLayout(materializedTarget, postRestoreLayoutPass)
            Log.d(tag, "CONTINUOUS_INITIAL_RESTORE postlayout index=${materializedTarget.index} result=${postRestore.reflowDiagnosticResult}")
            if (postRestore != ContinuousReflowRestoreOutcome.Ready) {
                report("post_restore_layout", "failed", mapOf(
                    "failureReason" to postRestore.reflowDiagnosticResult,
                    "initialLocatorGeometry" to geometry,
                ))
                return false
            }
            report("viewport_positioning", "success", mapOf("positioningOutcome" to "position_applied"))
            // ResizeObserver can deliver a new geometry while the offset query or
            // positioning layout is in flight. Re-resolve once against that real
            // update. Later revisions require current-point proof after layout;
            // revision inequality alone is not a positioning failure.
            if (geometryRevision() != resolvedGeometry) {
                geometry?.put("beforeRecovery", initialRestoreGeometry(materializedTarget))
                geometry?.put("offsetBeforeRecoveryPx", offset)
                resolvedGeometry = geometryRevision()
                report("locator_offset", "started", mapOf("positioningOutcome" to "geometry_invalidated"))
                offset = resolveLocatorVerticalOffset(materializedTarget.index, materializedTarget.resourceGeneration, locator)
                    ?: return failed("locator_offset", "locator_offset_unavailable")
                // Keep the pre-query revision as the verification baseline.
                // If it changed during this query, the result remains provisional
                // until the owned positioning layout and current-point proof below.
                report("locator_offset", "success", if (geometryRevision() != resolvedGeometry) {
                    mapOf("positioningOutcome" to "offset_provisional_until_layout")
                } else emptyMap())
                val recoveryLayoutPass = recyclerLayoutPass
                if (disposed || !initialRestoreAuthority.isCurrentTarget(materializedTarget) ||
                    layoutGeneration != materializedTarget.layoutGeneration ||
                    !isLiveResource(materializedTarget.index, materializedTarget.resourceGeneration)
                ) return failed("viewport_positioning", "target_no_longer_live")
                val requestedItemOffset = (readingAnchorOffsetPx() - offset).toInt()
                report("viewport_positioning", "started", mapOf("positioningOutcome" to "position_requested"))
                initialRestoreAuthority.markRestoreRequested(materializedTarget)
                layoutManager.scrollToPositionWithOffset(materializedTarget.index, requestedItemOffset)
                recyclerView.requestLayout()
                geometry?.put("targetDocumentOffsetLayoutPx", offset)
                geometry?.put("requestedItemOffsetPx", requestedItemOffset)
                report("viewport_positioning", "success", mapOf("positioningOutcome" to "position_accepted"))
                val recovery = awaitPostRestoreLayout(materializedTarget, recoveryLayoutPass)
                if (recovery != ContinuousReflowRestoreOutcome.Ready) {
                    return failed("post_restore_layout", recovery.reflowDiagnosticResult)
                }
                if (geometryRevision() != resolvedGeometry) {
                    // A later measurement can change only the tail of the resource.
                    // Revision inequality does not prove that its saved point moved.
                    // Revalidate current geometry without issuing another scroll.
                    if (recyclerView.isLayoutRequested || recyclerView.isComputingLayout) {
                        val settled = awaitPostRestoreLayout(materializedTarget, recyclerLayoutPass)
                        if (settled != ContinuousReflowRestoreOutcome.Ready) {
                            return failed("post_restore_layout", settled.reflowDiagnosticResult)
                        }
                    }
                    val currentRevision = geometryRevision()
                    val currentOffset = resolveLocatorVerticalOffset(materializedTarget.index, materializedTarget.resourceGeneration, locator)
                        ?: return failed("locator_offset", "locator_offset_unavailable")
                    geometry?.put("afterRecovery", initialRestoreGeometry(materializedTarget))
                    geometry?.put("offsetAfterRecoveryPx", currentOffset)
                    if (disposed || layoutGeneration != materializedTarget.layoutGeneration ||
                        !initialRestoreAuthority.isCurrentTarget(materializedTarget) ||
                        !isLiveResource(materializedTarget.index, materializedTarget.resourceGeneration)
                    ) return failed("post_restore_layout", "target_no_longer_live")
                    if (geometryRevision() != currentRevision || recyclerView.isLayoutRequested || recyclerView.isComputingLayout) {
                        geometry?.put("recoveryOffsetCheck", "unstable_geometry")
                        return failed("post_restore_layout", "geometry_unstable_during_verification", mapOf("initialLocatorGeometry" to geometry))
                    }
                    val anchor = currentLocatorAnchor()
                    val exactCurrentPoint = anchor != null && isTargetReadingAnchor(materializedTarget, anchor) &&
                        kotlin.math.abs(anchor.y - currentOffset) <= 1.0
                    val clampedCandidate = isInitialRestoreTopBoundaryLocator(locator.locations, locator.text) &&
                        resourceWindow.resourceAt(materializedTarget.index)?.let {
                            captureInitialRestoreStartBoundary(materializedTarget, it, currentOffset)
                        } != null
                    geometry?.put("recoveryOffsetCheck", if (exactCurrentPoint) "current_point_aligned" else if (clampedCandidate) "boundary_proof_required" else "target_offset_mismatch")
                    // Pixel equality is diagnostic, not Locator identity. The owned
                    // integer RecyclerView offset may precede a subpixel DOM reflow.
                    // Stable live geometry must reach the semantic/Range proof below;
                    // a genuinely relocated point still fails that proof. Do not scroll
                    // again or widen its tolerance to compensate for this difference.
                    offset = currentOffset
                    geometry?.put("targetDocumentOffsetLayoutPx", offset)
                    report("locator_offset", "success", mapOf("positioningOutcome" to "geometry_revalidated", "initialLocatorGeometry" to geometry))
                }
                report("viewport_positioning", "success", mapOf("positioningOutcome" to "position_applied"))
            }
            report("post_restore_layout", "success", mapOf("positioningOutcome" to "position_settled"))
            report("viewport_verification", "started")
            geometry?.put("afterPositioningLayout", initialRestoreGeometry(materializedTarget))
            val observed = observeRestoredLocator(materializedTarget)
            var verificationCheck: String? = null
            val converged = initialRestoreLocatorsConverge(materializedTarget, locator, observed, offset,
                onEvidence = if (geometry == null) null else { fields -> geometry.putAll(fields) },
            ) { check ->
                verificationCheck = check
            }
            if (geometry != null) {
                geometry["verificationCheck"] = verificationCheck
                geometry["afterVerification"] = initialRestoreGeometry(materializedTarget)
                if (observed != null) geometry["observedLocatorFields"] = initialRestoreLocatorFields(observed)
            }
            Log.d(tag, "CONTINUOUS_INITIAL_RESTORE convergence index=${materializedTarget.index} result=${if (converged) "converged" else "mismatch"}")
            if (converged) revealInitialViewport("semantic_restore_converged", materializedTarget)
            if (onDiagnostic != null) runCatching {
                val actualIndex = observed?.let { actual ->
                    readingOrder.indexOfFirst { it.url().isEquivalent(actual.href.removeFragment()) }.takeIf { it >= 0 }
                }
                report("viewport_verification", if (converged) "success" else "failed", mapOf(
                    "actualReadingOrderIndex" to actualIndex,
                    "actualResourceProgression" to observed?.locations?.progression?.takeIf(Double::isFinite),
                    "viewportAnchorIndex" to currentLocatorAnchor()?.readingOrderIndex,
                    "initialLocatorGeometry" to geometry,
                    "viewportVerification" to when {
                        converged -> "verified"
                        verificationCheck == "viewport_locator_unavailable" -> "unavailable"
                        else -> "not_verified"
                    },
                    "failureReason" to when {
                        converged -> null
                        verificationCheck == "viewport_locator_unavailable" -> "viewport_locator_unavailable"
                        observed != null && !locator.href.removeFragment().isEquivalent(observed.href.removeFragment()) -> "viewport_resource_mismatch"
                        else -> "viewport_locator_did_not_converge"
                    },
                ))
            }
            return converged
        } finally {
            if (target != null && initialRestoreAuthority.isCurrentTarget(target)) {
                postRestoreLayoutWaiters.remove(target)?.second?.complete(ContinuousReflowRestoreOutcome.Cancelled)
            }
            initialRestoreAuthority.finish(target)
            dispatchDeferredInitialRestoreReadyEvents()
            unpinResource(targetIndex, ContinuousResourcePinReason.NAVIGATION_TARGET)
        }
    }

    private fun initialRestoreGeometry(target: ContinuousReflowTarget): Map<String, Any?>? = runCatching {
        if (disposed || Looper.myLooper() != Looper.getMainLooper()) return@runCatching null
        val view = layoutManager.findViewByPosition(target.index)?.takeIf { it.isAttachedToWindow }
        val resource = resourceWindow.resourceAt(target.index)
        val anchorY = (recyclerView.height * READING_ANCHOR_FRACTION).toDouble()
        val anchorChild = recyclerView.findChildViewUnder(recyclerView.width / 2f, anchorY.toFloat())
        mapOf(
            "layoutGeneration" to layoutGeneration,
            "resourceGeneration" to resource?.generation,
            "reportedMeasurementGeneration" to resource?.reportedMeasurementGenerationForOpen,
            "measurementEpoch" to resource?.currentMeasurementEpoch,
            "layoutPass" to recyclerLayoutPass,
            "geometryReady" to reflowTargetBarrier.isReady(target),
            "resourceTopPx" to view?.top,
            "resourceHeightPx" to view?.height,
            "committedResourceHeightPx" to layoutModel.measuredHeightOrNull(target.index),
            "viewportHeightPx" to recyclerView.height,
            "viewportPaddingTopPx" to recyclerView.paddingTop,
            "viewportAnchorYPx" to anchorY,
            "anchorLocalYPx" to view?.takeIf { it === anchorChild }?.let { anchorY - it.top },
            "density" to resource?.resources?.displayMetrics?.density,
            "canScrollTowardStart" to recyclerView.canScrollVertically(-1),
        )
    }.getOrNull()

    private fun initialRestoreLocatorFields(locator: Locator): Map<String, Boolean> = mapOf(
        "hasSelector" to (locator.locations["cssSelector"] is String),
        "hasFragment" to locator.locations.fragments.isNotEmpty(),
        "hasCfi" to (locator.locations["cfi"] != null ||
            locator.locations["partialCfi"] != null ||
            locator.locations.fragments.any { it.startsWith("epubcfi(") }),
        "hasQuote" to !locator.text.highlight.isNullOrBlank(),
        "hasPosition" to (locator.locations.position != null),
        "hasTotalProgression" to (locator.locations.totalProgression != null),
    )

    /**
     * The geometry-reflow restore path has one readiness boundary and one
     * semantic offset resolution. Unlike general navigation it never retries
     * a locator command or falls back to another reading-order entry.
     */
    internal suspend fun restoreAfterGeometryReflow(
        locator: Locator,
        transaction: ContinuousGeometryReflowTransaction,
        isTransactionCurrent: () -> Boolean,
    ): ContinuousReflowRestoreOutcome {
        val targetIndex = readingOrder.indexOfFirst { it.url().isEquivalent(locator.href.removeFragment()) }
        if (disposed || targetIndex < 0) return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
        val geometryBatch = activeGeometryBatch?.takeIf {
            it.owner.transactionGeneration == transaction.generation && it.anchor.index == targetIndex
        }
        when (geometryBatch?.state) {
            ContinuousGeometryBatchState.FAILED -> return ContinuousReflowRestoreOutcome.TargetNotReady
            ContinuousGeometryBatchState.FAILED_AFTER_COMMIT_START -> return ContinuousReflowRestoreOutcome.TargetNotReady
            ContinuousGeometryBatchState.DISCARDED -> return ContinuousReflowRestoreOutcome.Cancelled
            else -> Unit
        }
        val expectedLayoutGeneration = layoutGeneration
        var diagnosticTarget: ContinuousReflowTarget? = null
        pinResource(targetIndex, ContinuousResourcePinReason.NAVIGATION_TARGET)
        try {
            val target = withContext(Dispatchers.Main.immediate) {
                if (!isTransactionCurrent()) return@withContext null
                prepareTargetResource(targetIndex)
                val currentTarget = resourceWindow.resourceAt(targetIndex)?.let {
                    ContinuousReflowTarget(targetIndex, expectedLayoutGeneration, it.generation)
                }
                val batchAnchorIsAttached = geometryBatch != null &&
                    geometryBatch.state in setOf(
                        ContinuousGeometryBatchState.COLLECTING,
                        ContinuousGeometryBatchState.READY,
                        ContinuousGeometryBatchState.COMMIT_STARTED,
                        ContinuousGeometryBatchState.APPLIED,
                    ) && currentTarget == geometryBatch.anchor && isTargetAttached(geometryBatch.anchor)
                if (geometryBatch != null && !batchAnchorIsAttached) {
                    failGeometryBatchForMeasurements(geometryBatch, "anchor_lost_before_restore")
                    return@withContext null
                }
                if (geometryBatch == null && !batchAnchorIsAttached) {
                    layoutManager.scrollToPositionWithOffset(targetIndex, readingAnchorOffsetPx())
                    recyclerView.requestLayout()
                }
                reconcileResourceWindow(includePreloads = false)
                resourceWindow.resourceAt(targetIndex)?.let {
                    ContinuousReflowTarget(targetIndex, expectedLayoutGeneration, it.generation)
                }
            } ?: return ContinuousReflowRestoreOutcome.TargetNotReady
            logTransactionState("after_prepare_target", transaction, target)
            if (!transaction.markMaterialized(target) || !isTransactionCurrent()) {
                transaction.cancel()
                return ContinuousReflowRestoreOutcome.Cancelled
            }
            diagnosticTarget = target
            reflowDiagnosticTransactions[target] = transaction
            logReflowStage("materialized", transaction, target, "true")
            var preflightPoint: ContinuousResolvedLocatorPoint? = null
            var preflightCorrectionOffsetPx: Int? = null
            var preflightViewportBefore: EpubContinuousViewportLayoutSnapshot? = null
            if (geometryBatch != null) {
                emitMissingGeometryBatchMeasurements(
                    geometryBatch,
                    "reflow_wait",
                    "required_measurement_pending",
                )
                if (!awaitGeometryBatchReady(geometryBatch)) {
                    return if (geometryBatch.state == ContinuousGeometryBatchState.DISCARDED) {
                        ContinuousReflowRestoreOutcome.Cancelled
                    } else ContinuousReflowRestoreOutcome.TargetNotReady
                }
                withContext(Dispatchers.Main.immediate) {
                    restoreUnchangedGeometryIfPossible(geometryBatch, transaction, target, locator, isTransactionCurrent)
                }?.let {
                    return it
                }
                val prepared = withContext(Dispatchers.Main.immediate) {
                    if (disposed || activeGeometryBatch !== geometryBatch ||
                        activeGeometryTransaction !== transaction || !isTransactionCurrent() ||
                        target.layoutGeneration != layoutGeneration || !isTargetAttached(target)
                    ) return@withContext null
                    prepareGeometryBatchCommit(geometryBatch)
                } ?: return ContinuousReflowRestoreOutcome.TargetNotReady

                // Read the same semantic point after CSS/measurement is ready but
                // before changing parent heights. This query is the only suspension
                // between locking the batch owner and installing its compensation.
                val pointBeforeGeometry = resolveLocatorPointGeometry(target.index, target.resourceGeneration, locator)
                if (pointBeforeGeometry == null) {
                    failGeometryBatchForMeasurements(geometryBatch, "anchor_point_unavailable_before_geometry_commit")
                    return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
                }
                val applied = withContext(Dispatchers.Main.immediate) {
                    if (disposed || activeGeometryBatch !== geometryBatch ||
                        activeGeometryTransaction !== transaction || !isTransactionCurrent() ||
                        target.layoutGeneration != layoutGeneration || !isTargetAttached(target)
                    ) {
                        failGeometryBatchForMeasurements(geometryBatch, "owner_changed_after_anchor_preflight")
                        return@withContext false
                    }
                    val child = recyclerView.findViewHolderForAdapterPosition(target.index)?.itemView
                        ?: run {
                            failGeometryBatchForMeasurements(geometryBatch, "anchor_holder_missing_after_preflight")
                            return@withContext false
                        }
                    val deltaPx = continuousAnchorViewportDelta(transaction.anchor.viewportY, pointBeforeGeometry.viewportY)
                        ?: run {
                            failGeometryBatchForMeasurements(geometryBatch, "anchor_viewport_delta_invalid_before_commit")
                            return@withContext false
                        }
                    val pendingOffset = continuousAnchorCorrectionOffset(
                        currentDecoratedTop = layoutManager.getDecoratedTop(child),
                        paddingTop = recyclerView.paddingTop,
                        viewportDeltaPx = deltaPx,
                    ) ?: run {
                        failGeometryBatchForMeasurements(geometryBatch, "anchor_offset_invalid_before_commit")
                        return@withContext false
                    }
                    preflightViewportBefore = captureDiagnosticViewportLayoutSnapshot(target.index)
                    if (!applyReadyGeometryBatch(prepared, pointBeforeGeometry, pendingOffset)) {
                        return@withContext false
                    }
                    preflightCorrectionOffsetPx = pendingOffset.takeIf { transaction.anchorScrollRequested }
                    true
                }
                if (!applied) return ContinuousReflowRestoreOutcome.TargetNotReady
                preflightPoint = pointBeforeGeometry
            }
            val ready = awaitReflowTarget(target)
            logReflowStage("barrier_exit", transaction, target, ready.reflowDiagnosticResult)
            logTransactionState("barrier_exit", transaction, target)
            if (ready != ContinuousReflowRestoreOutcome.Ready) return ready
            if (!transaction.canRestore(target) || !isTransactionCurrent()) {
                transaction.cancel()
                return ContinuousReflowRestoreOutcome.Cancelled
            }
            logTransactionState("offset_start", transaction, target)
            val capturedPoint = preflightPoint ?: resolveLocatorPointGeometry(target.index, target.resourceGeneration, locator)
            logReflowStage("offset", transaction, target, if (capturedPoint == null) "unavailable" else "resolved")
            logTransactionState("offset_end", transaction, target)
            if (capturedPoint == null) return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
            reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.let { owner ->
                emitViewportSnapshot(
                    snapshotStage = if (geometryBatch != null) "before_geometry_commit" else "after_geometry_before_anchor",
                    context = owner.context,
                    preferenceGeneration = owner.preferenceGeneration,
                    transactionGeneration = transaction.generation,
                    layoutGeneration = target.layoutGeneration,
                    resourceGeneration = target.resourceGeneration,
                    anchorIndex = target.index,
                    anchorProgression = locator.locations.progression,
                    anchorPointDocumentYPx = capturedPoint.documentYLayoutPx,
                    anchorPointViewportYPx = capturedPoint.viewportY,
                    anchorPointAvailable = true,
                    anchorPointSampleStage = if (geometryBatch != null) "after_css_before_geometry_commit" else "after_geometry_before_anchor",
                    anchorBeforeLocalYPx = transaction.anchor.localY,
                    anchorBeforeViewportYPx = transaction.anchor.viewportY,
                    commitLockHeld = geometryBatch?.state in setOf(
                        ContinuousGeometryBatchState.COMMIT_STARTED,
                        ContinuousGeometryBatchState.APPLIED,
                    ),
                    result = if (geometryBatch != null) "preflight_captured_before_geometry" else "captured",
                )
            }
            val postRestoreLayoutPass = recyclerLayoutPass
            withContext(Dispatchers.Main.immediate) {
                if (disposed || layoutGeneration != target.layoutGeneration ||
                    !isLiveResource(target.index, target.resourceGeneration) || !isTransactionCurrent() ||
                    !transaction.markRestored()
                ) return@withContext
                // Observe the real batch-adjusted layout before correcting.
                // The single correction below uses the measured same-point delta.
                recyclerView.requestLayout()
                reconcileResourceWindow(includePreloads = false)
                testBinding.onAuthoritativeRestore(target, recyclerView)
            }
            logReflowStage("restore", transaction, target, if (transaction.restored) "committed" else "cancelled")
            if (!transaction.restored) return ContinuousReflowRestoreOutcome.Cancelled
            reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.let { owner ->
                emitReflowDiagnostic(
                    EpubContinuousReflowDiagnosticEvent(
                        kind = "anchor_restore",
                        context = owner.context,
                        preferenceGeneration = owner.preferenceGeneration,
                        transactionGeneration = owner.transactionGeneration,
                        layoutGeneration = target.layoutGeneration,
                        resourceGeneration = target.resourceGeneration,
                        readingOrderIndex = target.index,
                        anchorBeforeY = transaction.anchor.viewportY,
                        anchorBeforeYCoordinateSpace = "recycler_view_px",
                        anchorAfterY = null,
                        result = if (transaction.anchorScrollRequested) "scroll_requested" else "layout_requested",
                    ),
                )
            }
            val postRestore = awaitPostRestoreLayout(target, postRestoreLayoutPass)
            logReflowStage("postlayout", transaction, target, postRestore.reflowDiagnosticResult)
            if (postRestore != ContinuousReflowRestoreOutcome.Ready) return postRestore
            var restoredPoint = resolveLocatorPointGeometry(target.index, target.resourceGeneration, locator)
                ?: return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
            var viewportDeltaPx = continuousAnchorViewportDelta(transaction.anchor.viewportY, restoredPoint.viewportY)
                ?: return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
            var scrollRequestIssued = transaction.anchorScrollRequested
            var requestedCorrectionOffsetPx: Int? = preflightCorrectionOffsetPx
            var correctionViewportBefore: EpubContinuousViewportLayoutSnapshot? = preflightViewportBefore
            val requestedViewportDeltaPx = viewportDeltaPx
            if (!continuousAnchorViewportMatches(viewportDeltaPx)) {
                if (geometryBatch != null) {
                    // The batched same-layout offset is the only correction
                    // permitted for this transaction. A residual mismatch is a
                    // verification failure, not grounds for a second scroll.
                    return ContinuousReflowRestoreOutcome.VisibilityMismatch
                }
                val correctionLayoutPass = recyclerLayoutPass
                val corrected = withContext(Dispatchers.Main.immediate) {
                    if (disposed || layoutGeneration != target.layoutGeneration || !isTransactionCurrent() ||
                        !isTargetAttached(target)
                    ) return@withContext false
                    val child = recyclerView.findViewHolderForAdapterPosition(target.index)?.itemView
                        ?: return@withContext false
                    correctionViewportBefore = captureDiagnosticViewportLayoutSnapshot(target.index)
                    val currentDecoratedTop = layoutManager.getDecoratedTop(child)
                    val correctedOffset = continuousAnchorCorrectionOffset(
                        currentDecoratedTop = currentDecoratedTop,
                        paddingTop = recyclerView.paddingTop,
                        viewportDeltaPx = viewportDeltaPx,
                    ) ?: return@withContext false
                    layoutManager.scrollToPositionWithOffset(target.index, correctedOffset)
                    recyclerView.requestLayout()
                    reconcileResourceWindow(includePreloads = false)
                    scrollRequestIssued = true
                    requestedCorrectionOffsetPx = correctedOffset
                    reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.let { owner ->
                        emitViewportSnapshot(
                            snapshotStage = "after_anchor_scroll_request",
                            context = owner.context,
                            preferenceGeneration = owner.preferenceGeneration,
                            transactionGeneration = transaction.generation,
                            layoutGeneration = target.layoutGeneration,
                            resourceGeneration = target.resourceGeneration,
                            anchorIndex = target.index,
                            anchorProgression = locator.locations.progression,
                            anchorPointDocumentYPx = null,
                            anchorPointViewportYPx = null,
                            anchorPointAvailable = false,
                            anchorPointUnavailableReason = "post_scroll_point_not_sampled",
                            anchorBeforeLocalYPx = transaction.anchor.localY,
                            anchorBeforeViewportYPx = transaction.anchor.viewportY,
                            requestedCorrectionOffsetPx = correctedOffset,
                            requestedViewportDeltaPx = viewportDeltaPx,
                            scrollRequestIssued = true,
                            commitLockHeld = geometryBatch?.state == ContinuousGeometryBatchState.APPLIED,
                            result = "correction_requested",
                        )
                    }
                    true
                }
                if (!corrected) return ContinuousReflowRestoreOutcome.VisibilityMismatch
                val correctionLayout = awaitPostRestoreLayout(target, correctionLayoutPass)
                if (correctionLayout != ContinuousReflowRestoreOutcome.Ready) return correctionLayout
                restoredPoint = resolveLocatorPointGeometry(target.index, target.resourceGeneration, locator)
                    ?: return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
                viewportDeltaPx = continuousAnchorViewportDelta(transaction.anchor.viewportY, restoredPoint.viewportY)
                    ?: return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
                runCatching {
                    val afterViewport = captureDiagnosticViewportLayoutSnapshot(target.index)
                    val beforeViewport = correctionViewportBefore
                    val owner = reflowDiagnosticOwners.ownerFor(target.layoutGeneration)
                    emitReflowDiagnostic(
                        EpubContinuousReflowDiagnosticEvent(
                            kind = "viewport_scroll",
                            context = owner?.context,
                            preferenceGeneration = owner?.preferenceGeneration,
                            transactionGeneration = transaction.generation,
                            layoutGeneration = target.layoutGeneration,
                            resourceGeneration = target.resourceGeneration,
                            readingOrderIndex = target.index,
                            snapshotStage = "after_anchor_scroll_request",
                            viewportSampleStage = "after_anchor_scroll_request",
                            anchorResourceHref = boundedContinuousDiagnosticResourceHref(locator.href.toString()),
                            anchorResourceHrefUnavailableReason = if (boundedContinuousDiagnosticResourceHref(locator.href.toString()) == null) "not_relative_or_unavailable" else null,
                            anchorProgression = locator.locations.progression,
                            targetViewportYPx = transaction.anchor.viewportY,
                            actualViewportYPx = restoredPoint.viewportY,
                            anchorViewportDeltaPx = viewportDeltaPx,
                            anchorViewportTolerancePx = CONTINUOUS_ANCHOR_VIEWPORT_TOLERANCE_PX,
                            requestedCorrectionOffsetPx = requestedCorrectionOffsetPx,
                            requestedViewportDeltaPx = requestedViewportDeltaPx,
                            viewportScrollReason = "anchor_restore",
                            viewportFirstVisibleIndexBefore = beforeViewport?.firstVisibleIndex,
                            viewportFirstVisibleIndexAfter = afterViewport?.firstVisibleIndex,
                            viewportFirstVisibleTopBeforePx = beforeViewport?.firstVisibleTopPx,
                            viewportFirstVisibleTopAfterPx = afterViewport?.firstVisibleTopPx,
                            viewportFirstVisibleTopDeltaPx = if (beforeViewport?.firstVisibleTopPx != null && afterViewport?.firstVisibleTopPx != null) {
                                afterViewport.firstVisibleTopPx - beforeViewport.firstVisibleTopPx
                            } else null,
                            anchorPointAvailable = true,
                            anchorPointUnavailableReason = "none",
                            scrollRequestIssued = true,
                            commitLockHeld = geometryBatch?.state == ContinuousGeometryBatchState.APPLIED,
                            result = "correction_and_fresh_point_sampled",
                        ),
                    )
                }
            }
            if (!scrollRequestIssued) {
                reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.let { owner ->
                    emitViewportSnapshot(
                        snapshotStage = "after_anchor_scroll_request",
                        context = owner.context,
                        preferenceGeneration = owner.preferenceGeneration,
                        transactionGeneration = transaction.generation,
                        layoutGeneration = target.layoutGeneration,
                        resourceGeneration = target.resourceGeneration,
                        anchorIndex = target.index,
                        anchorProgression = locator.locations.progression,
                        anchorPointDocumentYPx = restoredPoint.documentYLayoutPx,
                        anchorPointViewportYPx = restoredPoint.viewportY,
                        anchorPointAvailable = true,
                        anchorPointSampleStage = "post_restore_no_correction",
                        anchorBeforeLocalYPx = transaction.anchor.localY,
                        anchorBeforeViewportYPx = transaction.anchor.viewportY,
                        anchorViewportDeltaPx = viewportDeltaPx,
                        anchorViewportTolerancePx = CONTINUOUS_ANCHOR_VIEWPORT_TOLERANCE_PX,
                        requestedCorrectionOffsetPx = null,
                        requestedViewportDeltaPx = requestedViewportDeltaPx,
                        scrollRequestIssued = false,
                        commitLockHeld = geometryBatch?.state == ContinuousGeometryBatchState.APPLIED,
                        result = "no_correction_required",
                    )
                }
            }
            val reattached = awaitReattachForFreshObservation(target, transaction, isTransactionCurrent)
            logReflowStage("reattach", transaction, target, reattached.reflowDiagnosticResult)
            if (reattached != ContinuousReflowRestoreOutcome.Ready) return reattached
            beginFreshLocatorObservation(target, transaction)
            logTransactionState("observe_start", transaction, target)
            val domAnchor = locator.locations["continuousDomAnchor"] as? Map<*, *>
            val observed = observeRestoredLocator(target, diagnostic = domAnchor == null)
            logReflowStage("observe", transaction, target, if (observed == null) "unavailable" else "observed")
            logTransactionState("observe_end", transaction, target)
            if (observed == null) return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
            val resource = resourceWindow.withLiveResource(target.index, target.resourceGeneration) { it }
                ?: return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
            val sameResource = observed.href.removeFragment() == locator.href.removeFragment()
            val quality = continuousSemanticAnchorQuality(locator, restoredPoint, sameResource)
            val semanticMatch = if (domAnchor != null) {
                quality == ContinuousSemanticAnchorQuality.EXACT_DOM_POINT
            } else semanticLocatorsConverge(locator, observed) ||
                resource.locatorsShareMeaningfulBlock(locator, observed)
            val targetProgression = locator.locations.progression
            val observedProgression = observed.locations.progression
            val viewportMatch = continuousAnchorViewportMatches(viewportDeltaPx)
            // Explicit progression degradation can finish geometry safely, but is
            // never reported as exact semantic preservation.
            val restoreUsable = semanticMatch || (domAnchor != null &&
                quality == ContinuousSemanticAnchorQuality.PROGRESSION_FALLBACK)
            val converged = restoreUsable && viewportMatch &&
                transaction.markConverged(restoredPoint, viewportDeltaPx, observed.locations.progression) && isTransactionCurrent()
            if (domAnchor != null && isTransactionCurrent()) {
                val exact = quality == ContinuousSemanticAnchorQuality.EXACT_DOM_POINT
                val fields = buildMap<String, Any> {
                    put("identityType", if (exact) "exact_dom_point" else "progression_fallback")
                    put("anchorIdentityType", if (exact) "exact_dom_point" else "progression_fallback")
                    put("semanticAnchorQuality", quality.name)
                    restoredPoint.anchorIdentityId?.let { put("anchorIdentityId", it) }
                    restoredPoint.anchorCharacterOffset?.let { put("anchorCharacterOffset", it) }
                    put("sameResource", sameResource)
                    put("sameDomIdentity", exact)
                    put("sameCharacterOffset", exact)
                    put("semanticAnchorResolved", exact)
                    put("semanticAnchorExact", exact)
                    put("fallbackUsed", !exact)
                    put("beforeViewportY", transaction.anchor.viewportY)
                    put("anchorCaptureViewportY", transaction.anchor.viewportY)
                    put("anchorTargetViewportY", transaction.anchor.targetViewportY)
                    put("pointToTargetOffsetPx", transaction.anchor.viewportY - transaction.anchor.targetViewportY)
                    put("resolvedBeforeCorrectionViewportY", capturedPoint.viewportY)
                    put("anchorResolvedViewportYBeforeCorrection", capturedPoint.viewportY)
                    put("finalViewportY", restoredPoint.viewportY)
                    put("anchorFinalViewportY", restoredPoint.viewportY)
                    put("finalDeltaPx", viewportDeltaPx)
                }
                emitReflowDiagnostic(EpubContinuousReflowDiagnosticEvent(
                    kind = "semantic_anchor_compare",
                    context = reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.context,
                    preferenceGeneration = transaction.preferenceGeneration,
                    transactionGeneration = transaction.generation,
                    layoutGeneration = target.layoutGeneration,
                    resourceGeneration = target.resourceGeneration,
                    readingOrderIndex = target.index,
                    semanticAnchorFields = fields,
                    anchorProgression = locator.locations.progression,
                    anchorViewportDeltaPx = viewportDeltaPx,
                    result = if (exact) "exact_dom_point" else "progression_fallback",
                ))
                emitReflowDiagnostic(EpubContinuousReflowDiagnosticEvent(
                    kind = "gesture_baseline_delta",
                    context = reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.context,
                    preferenceGeneration = transaction.preferenceGeneration,
                    transactionGeneration = transaction.generation,
                    layoutGeneration = target.layoutGeneration,
                    resourceGeneration = target.resourceGeneration,
                    semanticAnchorFields = mapOf(
                        "originalTargetViewportYPx" to transaction.anchor.viewportY,
                        "actualFinalViewportYPx" to restoredPoint.viewportY,
                        "errorFromOriginalBaselinePx" to viewportDeltaPx,
                        "cumulativeDriftFromGestureStartPx" to viewportDeltaPx,
                    ),
                    result = if (exact) "exact_dom_point" else "progression_fallback",
                ))
            }
            logReflowStage("convergence", transaction, target, when {
                !converged -> "verification_failed"
                semanticMatch -> "semantic_and_viewport_verified"
                else -> "progression_fallback_viewport_verified"
            })
            reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.let { owner ->
                emitViewportSnapshot(
                    snapshotStage = "after_anchor_verified",
                    context = owner.context,
                    preferenceGeneration = owner.preferenceGeneration,
                    transactionGeneration = transaction.generation,
                    layoutGeneration = target.layoutGeneration,
                    resourceGeneration = target.resourceGeneration,
                    anchorIndex = target.index,
                    anchorProgression = locator.locations.progression,
                    anchorPointDocumentYPx = restoredPoint.documentYLayoutPx,
                    anchorPointViewportYPx = restoredPoint.viewportY,
                    anchorPointAvailable = true,
                    anchorPointSampleStage = "after_anchor_verified",
                    anchorBeforeLocalYPx = transaction.anchor.localY,
                    anchorBeforeViewportYPx = transaction.anchor.viewportY,
                    anchorResourceHref = boundedContinuousDiagnosticResourceHref(locator.href.toString()),
                    anchorViewportDeltaPx = viewportDeltaPx,
                    anchorViewportTolerancePx = CONTINUOUS_ANCHOR_VIEWPORT_TOLERANCE_PX,
                    anchorSemanticMatch = semanticMatch,
                    observedReadingOrderIndex = target.index.takeIf {
                        observed.href.removeFragment() == locator.href.removeFragment()
                    },
                    observedProgression = observed.locations.progression,
                    requestedCorrectionOffsetPx = requestedCorrectionOffsetPx,
                    requestedViewportDeltaPx = requestedViewportDeltaPx,
                    scrollRequestIssued = scrollRequestIssued,
                    commitLockHeld = geometryBatch?.state == ContinuousGeometryBatchState.APPLIED,
                    result = if (semanticMatch && viewportMatch) "verified" else "verification_failed",
                )
                emitReflowDiagnostic(
                    EpubContinuousReflowDiagnosticEvent(
                        kind = "anchor_restore_verified",
                        context = owner.context,
                        preferenceGeneration = owner.preferenceGeneration,
                        transactionGeneration = owner.transactionGeneration,
                        layoutGeneration = target.layoutGeneration,
                        resourceGeneration = target.resourceGeneration,
                        readingOrderIndex = target.index,
                        anchorBeforeY = transaction.anchor.viewportY,
                        anchorBeforeYCoordinateSpace = "recycler_view_px",
                        anchorAfterY = restoredPoint.viewportY,
                        anchorResourceHref = boundedContinuousDiagnosticResourceHref(locator.href.toString()),
                        anchorResourceHrefUnavailableReason = if (boundedContinuousDiagnosticResourceHref(locator.href.toString()) == null) "not_relative_or_unavailable" else null,
                        targetViewportYPx = transaction.anchor.viewportY,
                        actualViewportYPx = restoredPoint.viewportY,
                        anchorSemanticMatch = semanticMatch,
                        anchorViewportDeltaPx = viewportDeltaPx,
                        anchorViewportTolerancePx = CONTINUOUS_ANCHOR_VIEWPORT_TOLERANCE_PX,
                        anchorPointAvailable = true,
                        anchorPointUnavailableReason = "none",
                        observedReadingOrderIndex = target.index.takeIf {
                            observed.href.removeFragment() == locator.href.removeFragment()
                        },
                        observedProgression = observedProgression,
                        semanticProgressionDelta = if (targetProgression != null && observedProgression != null) {
                            observedProgression - targetProgression
                        } else null,
                        result = when {
                            !semanticMatch -> "semantic_mismatch"
                            !viewportMatch -> "semantic_match_viewport_delta_exceeded"
                            else -> "semantic_and_viewport_verified"
                        },
                    ),
                )
            }
            if (converged && geometryBatch != null) {
                reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.let { owner ->
                    emitViewportSnapshot(
                        snapshotStage = "after_presentation_commit",
                        context = owner.context,
                        preferenceGeneration = owner.preferenceGeneration,
                        transactionGeneration = transaction.generation,
                        layoutGeneration = target.layoutGeneration,
                        resourceGeneration = target.resourceGeneration,
                        anchorIndex = target.index,
                        anchorProgression = locator.locations.progression,
                        anchorPointDocumentYPx = restoredPoint.documentYLayoutPx,
                        anchorPointViewportYPx = restoredPoint.viewportY,
                        anchorPointAvailable = true,
                        anchorPointSampleStage = "after_anchor_verified",
                        anchorBeforeLocalYPx = transaction.anchor.localY,
                        anchorBeforeViewportYPx = transaction.anchor.viewportY,
                        anchorResourceHref = boundedContinuousDiagnosticResourceHref(locator.href.toString()),
                        anchorViewportDeltaPx = viewportDeltaPx,
                        anchorViewportTolerancePx = CONTINUOUS_ANCHOR_VIEWPORT_TOLERANCE_PX,
                        anchorSemanticMatch = semanticMatch,
                        observedReadingOrderIndex = target.index,
                        observedProgression = observed.locations.progression,
                        requestedCorrectionOffsetPx = requestedCorrectionOffsetPx,
                        requestedViewportDeltaPx = requestedViewportDeltaPx,
                        scrollRequestIssued = scrollRequestIssued,
                        commitLockHeld = true,
                        result = if (semanticMatch) "semantic_and_viewport_verified" else "progression_fallback_viewport_verified",
                    )
                }
                emitPresentationTransactionEvent(geometryBatch, "end", transaction, "committed")
            }
            return if (converged) {
                ContinuousReflowRestoreOutcome.Restored(target.index, observed)
            } else ContinuousReflowRestoreOutcome.VisibilityMismatch
        } finally {
            if (transaction.presentationTransactionActive && geometryBatch != null) {
                emitPresentationTransactionEvent(geometryBatch, "end", transaction, "aborted")
            }
            cancelReattachWaiter(transaction = transaction)
            diagnosticTarget?.let { target ->
                if (reflowDiagnosticTransactions[target] === transaction) reflowDiagnosticTransactions.remove(target)
            }
            unpinResource(targetIndex, ContinuousResourcePinReason.NAVIGATION_TARGET)
        }
    }

    /**
     * Ends the narrow window only after the owning transaction reached its
     * terminal state in [ContinuousEpubRendition]. Deferred measurements are
     * revalidated and then applied through the ordinary geometry path.
     */
    internal fun finishFreshLocatorObservation(transaction: ContinuousGeometryReflowTransaction) {
        val deferred = freshLocatorObservationBarrier.finish(transaction).toMutableList()
        activeGeometryBatch?.takeIf { it.owner.transactionGeneration == transaction.generation }?.let { batch ->
            if (transaction.state == ContinuousGeometryReflowTransaction.State.COMPLETED && batch.markCommitted()) {
                emitGeometryBatchEvent("geometry_batch_committed", batch, "anchor_verified")
            } else {
                emitMissingGeometryBatchMeasurements(batch, "geometry_batch_pending", "unmeasured_on_terminal")
                val commitStarted = batch.state in setOf(
                    ContinuousGeometryBatchState.COMMIT_STARTED,
                    ContinuousGeometryBatchState.APPLIED,
                )
                val failed = if (commitStarted) batch.failAfterCommitStart() else batch.fail()
                if (failed) {
                    emitGeometryBatchEvent(
                        if (commitStarted) "geometry_batch_failed" else "geometry_batch_discarded",
                        batch,
                        if (commitStarted) "FAILED_AFTER_COMMIT_START" else "transaction_not_committed",
                    )
                }
            }
            deferred += batch.finish()
            geometryBatchReadyWaiters.remove(batch.owner)?.complete(Unit)
            if (activeGeometryBatch === batch) activeGeometryBatch = null
        }
        if (activeGeometryTransaction === transaction && transaction.commitOwner == null) {
            activeGeometryTransaction = null
        }
        flushDeferredGeometryMeasurements(deferred.distinctBy { Triple(it.index, it.resourceGeneration, it.measurementGeneration) })
        // The reflow target and visible resources were already materialized with
        // current generations. Resume optional offscreen preloads only after the
        // authoritative semantic restore has reached its terminal boundary.
        reconcileResourceWindow()
        Log.d(
            tag,
            "READIUM_TX_TERMINAL type=${transaction.state.name.lowercase()} prefGen=${transaction.generation} " +
                "releasedTarget=${!pins.containsKey(transaction.targetReadingOrderIndex)} releasedBarrier=true " +
                "deferred=${deferred.size} preloadResume=true",
        )
    }

    internal fun acknowledgeGeometryCommit(owner: EpubContinuousGeometryCommitOwner): Boolean {
        val transaction = activeGeometryTransaction ?: return false
        if (transaction.commitOwner != owner) return false
        reflowDiagnosticOwners.ownerFor(owner.layoutGeneration)?.let { diagnosticOwner ->
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "geometry_commit_lock",
                    context = diagnosticOwner.context,
                    preferenceGeneration = owner.preferenceGeneration,
                    transactionGeneration = owner.transactionGeneration,
                    layoutGeneration = owner.layoutGeneration,
                    readingOrderIndex = transaction.anchor.index,
                    commitLockHeld = false,
                    result = "released_on_session_ack",
                ),
            )
        }
        activeGeometryTransaction = null
        return true
    }

    private suspend fun awaitReflowTarget(target: ContinuousReflowTarget): ContinuousReflowRestoreOutcome {
        if (disposed || layoutGeneration != target.layoutGeneration ||
            !isLiveResource(target.index, target.resourceGeneration)
        ) return ContinuousReflowRestoreOutcome.Cancelled
        val batch = activeGeometryBatch?.takeIf { it.anchor == target }
        if (batch?.state in setOf(
                ContinuousGeometryBatchState.FAILED,
                ContinuousGeometryBatchState.FAILED_AFTER_COMMIT_START,
            )
        ) return ContinuousReflowRestoreOutcome.TargetNotReady
        if (batch?.state == ContinuousGeometryBatchState.DISCARDED) return ContinuousReflowRestoreOutcome.Cancelled
        if (reflowTargetBarrier.isReady(target)) {
            return ContinuousReflowRestoreOutcome.Ready
        }
        emitReflowWait(target, "true_ready_measurement_layout")
        return reflowTargetWaiters.getOrPut(target) { CompletableDeferred() }.await()
    }

    private fun emitReflowWait(target: ContinuousReflowTarget, reason: String) {
        val transaction = reflowDiagnosticTransactions[target] ?: return
        val owner = reflowDiagnosticOwners.ownerFor(target.layoutGeneration) ?: return
        emitReflowDiagnostic(
            EpubContinuousReflowDiagnosticEvent(
                kind = "reflow_wait",
                context = owner.context,
                preferenceGeneration = owner.preferenceGeneration,
                transactionGeneration = transaction.generation,
                layoutGeneration = target.layoutGeneration,
                resourceGeneration = target.resourceGeneration,
                readingOrderIndex = target.index,
                result = reason,
            ),
        )
    }

    private fun onReflowTargetReady(target: ContinuousReflowTarget) {
        reflowTargetBarrier.markReady(target)
        reflowDiagnosticTransactions[target]?.let { transaction ->
            logReflowStage("true_ready", transaction, target, reflowTargetBarrier.isReady(target).toString())
        }
        completeReflowTargetIfReady()
    }

    private fun onReflowTargetMeasured(target: ContinuousReflowTarget) {
        reflowTargetBarrier.markMeasured(target, recyclerLayoutPass)
        reflowDiagnosticTransactions[target]?.let { transaction ->
            logReflowStage("measured", transaction, target, reflowTargetBarrier.isReady(target).toString())
        }
        completeReflowTargetIfReady()
    }

    private fun logReflowStage(
        stage: String,
        transaction: ContinuousGeometryReflowTransaction,
        target: ContinuousReflowTarget,
        result: String,
    ) {
        Log.d(
            tag,
            "CONTINUOUS_REFLOW_STAGE $stage transactionGeneration=${transaction.generation} index=${target.index} " +
                "lg=${target.layoutGeneration} rg=${target.resourceGeneration} recyclerPass=$recyclerLayoutPass " +
                "attached=${isTargetAttached(target)} result=$result",
        )
    }

    private fun logTransactionState(
        stage: String,
        transaction: ContinuousGeometryReflowTransaction,
        target: ContinuousReflowTarget?,
    ) {
        val states = resourceWindow.states()
        val live = states.keys.sorted().joinToString(",")
        val pinned = states.filterValues { it == ContinuousEpubResourceWindow.State.LIVE_PINNED }.keys.sorted().joinToString(",")
        val preloads = states.filterValues { it == ContinuousEpubResourceWindow.State.LIVE_PRELOAD }.keys.sorted().joinToString(",")
        Log.d(
            tag,
            "READIUM_TX_STATE stage=$stage prefGen=${transaction.generation} lg=$layoutGeneration " +
                "target=${target?.index ?: transaction.targetReadingOrderIndex}/${target?.resourceGeneration ?: "none"} " +
                "live=[$live] pinned=[$pinned] deferred=[${freshLocatorObservationBarrier.pendingIndices().sorted().joinToString(",")}] " +
                "preloads=[$preloads] cover=${if (initialViewportRevealed) "revealed" else "covered"} tx=${transaction.state.name.lowercase()}",
        )
    }

    private val ContinuousReflowRestoreOutcome.reflowDiagnosticResult: String
        get() = when (this) {
            ContinuousReflowRestoreOutcome.Ready -> "ready"
            is ContinuousReflowRestoreOutcome.Restored -> "restored"
            ContinuousReflowRestoreOutcome.TargetNotReady -> "target_not_ready"
            ContinuousReflowRestoreOutcome.SemanticRestoreFailed -> "semantic_restore_failed"
            ContinuousReflowRestoreOutcome.VisibilityMismatch -> "visibility_mismatch"
            ContinuousReflowRestoreOutcome.Cancelled -> "cancelled"
        }

    private fun completeReflowTargetIfReady() {
        reflowTargetWaiters.keys.toList().forEach { target ->
            if (reflowTargetBarrier.isReady(target)) {
                reflowTargetWaiters.remove(target)?.complete(ContinuousReflowRestoreOutcome.Ready)
            }
        }
    }

    private fun failReflowTarget(target: ContinuousReflowTarget, outcome: ContinuousReflowRestoreOutcome) {
        reflowTargetBarrier.invalidate(target)
        reflowTargetWaiters.remove(target)?.complete(outcome)
        postRestoreLayoutWaiters.remove(target)?.second?.complete(outcome)
        reattachWaiters.remove(target)?.completion?.complete(outcome)
    }

    private fun finishAllReflowWaiters(outcome: ContinuousReflowRestoreOutcome) {
        reflowTargetWaiters.values.forEach { it.complete(outcome) }
        reflowTargetWaiters.clear()
        postRestoreLayoutWaiters.values.forEach { (_, waiter) -> waiter.complete(outcome) }
        postRestoreLayoutWaiters.clear()
        reattachWaiters.values.forEach { it.completion.complete(outcome) }
        reattachWaiters.clear()
    }

    /**
     * A post-restore detach is recovered only by RecyclerView attaching the
     * exact still-live N/LG/RG resource again. No layout callback, retry, or
     * detached query can open this boundary.
     */
    private suspend fun awaitReattachForFreshObservation(
        target: ContinuousReflowTarget,
        transaction: ContinuousGeometryReflowTransaction,
        isTransactionCurrent: () -> Boolean,
    ): ContinuousReflowRestoreOutcome {
        val registration = withContext(Dispatchers.Main.immediate) {
            val resource = resourceWindow.withLiveResource(target.index, target.resourceGeneration) { it }
            when {
                disposed || layoutGeneration != target.layoutGeneration || resource == null ||
                    reflowDiagnosticTransactions[target] !== transaction ||
                    !transaction.canRestore(target) || !isTransactionCurrent() ->
                    ReattachRegistration(ContinuousReflowRestoreOutcome.Cancelled)
                attachedMaterializations[target.index]?.let {
                    it.target == target && it.resource === resource
                } == true -> ReattachRegistration(ContinuousReflowRestoreOutcome.Ready)
                else -> {
                    val waiter = ReattachWaiter(
                        transaction = transaction,
                        transactionGeneration = transaction.generation,
                        target = target,
                        resource = resource,
                        isTransactionCurrent = isTransactionCurrent,
                    )
                    reattachWaiters.remove(target)?.completion?.complete(ContinuousReflowRestoreOutcome.Cancelled)
                    reattachWaiters[target] = waiter
                    emitReflowWait(target, "same_resource_reattach")
                    ReattachRegistration(waiter = waiter)
                }
            }
        }
        registration.immediateOutcome?.let { return it }
        val waiter = checkNotNull(registration.waiter)
        return try {
            waiter.completion.await()
        } finally {
            withContext(NonCancellable + Dispatchers.Main.immediate) {
                if (reattachWaiters[target] === waiter) reattachWaiters.remove(target)
            }
        }
    }

    private fun initialPositionApplied(target: ContinuousReflowTarget): Boolean =
        !initialRestoreAuthority.isCurrentTarget(target) ||
            !initialRestoreAuthority.isRestoreRequested() || initialRestoreAuthority.isRestoreCommitted()

    private suspend fun awaitPostRestoreLayout(
        target: ContinuousReflowTarget,
        afterLayoutPass: Long,
    ): ContinuousReflowRestoreOutcome {
        if (disposed || layoutGeneration != target.layoutGeneration ||
            !isLiveResource(target.index, target.resourceGeneration)
        ) {
            return ContinuousReflowRestoreOutcome.Cancelled
        }
        if (recyclerLayoutPass > afterLayoutPass && initialPositionApplied(target) && reflowTargetBarrier.isReady(target)) {
            return ContinuousReflowRestoreOutcome.Ready
        }
        emitReflowWait(target, "post_restore_layout_pass_${afterLayoutPass + 1}")
        return postRestoreLayoutWaiters.getOrPut(target) {
            afterLayoutPass to CompletableDeferred()
        }.second.await()
    }

    private fun completePostRestoreLayouts() {
        postRestoreLayoutWaiters.entries.toList().forEach { (target, pending) ->
            val (afterLayoutPass, waiter) = pending
            when {
                disposed || layoutGeneration != target.layoutGeneration ||
                    !isLiveResource(target.index, target.resourceGeneration) -> {
                    postRestoreLayoutWaiters.remove(target)?.second?.complete(ContinuousReflowRestoreOutcome.Cancelled)
                }
                recyclerLayoutPass > afterLayoutPass && initialPositionApplied(target) && reflowTargetBarrier.isReady(target) -> {
                    postRestoreLayoutWaiters.remove(target)?.second?.complete(ContinuousReflowRestoreOutcome.Ready)
                }
            }
        }
    }

    private fun isTargetAttached(target: ContinuousReflowTarget): Boolean =
        layoutGeneration == target.layoutGeneration &&
            isLiveResource(target.index, target.resourceGeneration) &&
            (recyclerView.findViewHolderForAdapterPosition(target.index) as? ResourceHolder)
                ?.itemView?.isAttachedToWindow == true

    private suspend fun observeRestoredLocator(target: ContinuousReflowTarget, diagnostic: Boolean = true): Locator? {
        if (!isReadingAnchorInResource(target.index)) return null
        val anchor = currentLocatorAnchor() ?: return null
        if (anchor.readingOrderIndex != target.index || anchor.resourceGeneration != target.resourceGeneration ||
            anchor.layoutGeneration != target.layoutGeneration
        ) return null
        return reflowEventPort.observeLocator(anchor) { findLocatorAtReadingAnchor(anchor, diagnostic = diagnostic) }
    }

    /**
     * Initial fragment restores retain strict semantic convergence. A fragment
     * without selector or quote has one additional proof: its own DOM Range,
     * the same one used for locatorVerticalOffset(), must be at the current
     * reading anchor or at its visible position at the publication start boundary.
     * At the start boundary the first measured resource may end above the usual
     * anchor. The exact live materialization and Range provide the proof there.
     */
    private suspend fun initialRestoreLocatorsConverge(
        target: ContinuousReflowTarget,
        requested: Locator,
        observed: Locator?,
        targetDocumentOffset: Double,
        onEvidence: ((Map<String, Any?>) -> Unit)? = null,
        onCheck: (String) -> Unit,
    ): Boolean {
        fun result(check: String, matched: Boolean = false): Boolean {
            onCheck(check)
            return matched
        }
        onEvidence?.invoke(mapOf(
            *buildList<Pair<String, Any?>> {
                if (observed != null) add("sameResource" to (observed.href.removeFragment() == requested.href.removeFragment()))
                if (requested.locations["cssSelector"] is String && observed?.locations?.get("cssSelector") is String) {
                    add("selectorEqual" to (requested.locations["cssSelector"] == observed.locations["cssSelector"]))
                }
                if (!requested.text.highlight.isNullOrBlank() && !observed?.text?.highlight.isNullOrBlank()) {
                    add("quoteEqual" to (requested.text.highlight == observed.text.highlight))
                }
            }.toTypedArray(),
        ))
        if (observed != null && semanticLocatorsConverge(requested, observed)) return result("semantic_identity", true)
        val resource = resourceWindow.withLiveResource(target.index, target.resourceGeneration) { it }
            ?: return result("resource_no_longer_live")
        val domEquivalent = observed != null && resource.locatorsShareMeaningfulBlock(requested, observed)
        if (observed != null) onEvidence?.invoke(mapOf("domEquivalence" to domEquivalent))
        if (domEquivalent) {
            return result("meaningful_block", true)
        }
        if (
            isInitialRestoreTopBoundaryLocator(requested.locations, requested.text) &&
            (observed?.let { initialRestoreRequiresRequestedRangeAnchor(requested, it) }
                ?: !isReadingAnchorInResource(target.index))
        ) {
            val boundary = captureInitialRestoreStartBoundary(target, resource, targetDocumentOffset)
            if (boundary != null) {
                var rangeEvidence: Map<String, Any?> = emptyMap()
                val rangeMatches = resource.isLocatorRangeAtVerticalAnchor(requested, boundary.rangeY) { fields ->
                    rangeEvidence = fields
                    onEvidence?.invoke(mapOf("rangeEvidence" to fields))
                }
                if (captureInitialRestoreStartBoundary(target, resource, targetDocumentOffset) != boundary) {
                    return result("start_boundary_changed_during_range")
                }
                if (!rangeMatches) return result("requested_range_not_at_start_boundary")
                // Retain the existing exact-zero proof. The new nonzero case
                // additionally proves a resolved, finite visible caret Range.
                if (requested.locations.progression == 0.0) return result("requested_range_at_start_boundary", true)
                val height = (rangeEvidence["rangeHeightCssPx"] as? Number)?.toDouble()
                val density = resource.resources.displayMetrics.density.toDouble()
                if (rangeEvidence["rangeResolved"] != true || rangeEvidence["rangeCollapsed"] != true ||
                    rangeEvidence["finiteInputs"] != true || height == null || !height.isFinite() || height <= 0.0 ||
                    boundary.rangeY + height * density > boundary.visibleHeightPx
                ) return result("range_not_visible")
                return result("top_boundary_clamp_verified", true)
            }
        }
        if (observed == null) return result("viewport_locator_unavailable")
        if (!initialRestoreRequiresRequestedRangeAnchor(requested, observed)) return result("requested_range_not_eligible")
        if (!reflowTargetBarrier.isReady(target)) return result("geometry_not_ready_before_range")
        val anchor = currentLocatorAnchor() ?: return result("anchor_unavailable")
        if (!isTargetReadingAnchor(target, anchor)) return result("anchor_target_mismatch")
        val rangeAtAnchor = resource.isLocatorRangeAtVerticalAnchor(requested, anchor.y,
            onEvidence?.let { observer -> { fields -> observer(mapOf("rangeEvidence" to fields)) } },
        )
        val currentAnchor = currentLocatorAnchor()
        val geometryReady = reflowTargetBarrier.isReady(target)
        val matched = isInitialRestoreRangeAnchorCurrent(
            target = target,
            anchor = anchor,
            currentAnchor = currentAnchor,
            geometryReady = geometryReady,
            rangeAtAnchor = rangeAtAnchor,
        )
        return result(when {
            matched -> "requested_range_at_anchor"
            !geometryReady -> "geometry_not_ready_after_range"
            currentAnchor != anchor -> "anchor_changed_during_range"
            !rangeAtAnchor -> "requested_range_not_at_anchor"
            else -> "requested_range_verification_failed"
        }, matched)
    }

    private data class InitialRestoreStartBoundarySample(
        val resourceView: View,
        val resourceTopPx: Int,
        val resourceHeightPx: Int,
        val visibleHeightPx: Int,
        val viewportAnchorYPx: Double,
        val measurementGeneration: Long,
        val rangeY: Double,
    )

    private fun captureInitialRestoreStartBoundary(
        target: ContinuousReflowTarget,
        resource: ContinuousResourceView,
        targetDocumentOffset: Double,
    ): InitialRestoreStartBoundarySample? {
        if (disposed || target.index != 0 || layoutGeneration != target.layoutGeneration ||
            !initialRestoreAuthority.isCurrentTarget(target) || !initialRestoreAuthority.isRestoreCommitted() ||
            !reflowTargetBarrier.isReady(target) || !resource.canFindLocator
        ) return null
        val materialization = attachedMaterializations[target.index] ?: return null
        if (materialization.target != target || materialization.resource !== resource ||
            resourceWindow.resourceAt(target.index) !== resource
        ) return null
        val first = layoutManager.findViewByPosition(target.index) ?: return null
        if (resource.parent !== first || !resource.isAttachedToWindow ||
            layoutModel.measuredHeightOrNull(target.index) != resource.height.toLong()
        ) return null
        val viewportAnchorY = (recyclerView.height * READING_ANCHOR_FRACTION).toDouble()
        val resourceTopPx = first.top + resource.top
        val viewportContentHeight = recyclerView.height - recyclerView.paddingTop - recyclerView.paddingBottom
        val visibleHeightPx = minOf(resource.height, viewportContentHeight)
        val rangeY = initialRestoreStartBoundaryRangeY(
            targetIndex = target.index,
            targetDocumentOffset = targetDocumentOffset,
            resourceTopPx = resourceTopPx,
            viewportPaddingTopPx = recyclerView.paddingTop,
            visibleHeightPx = visibleHeightPx,
            viewportAnchorYPx = viewportAnchorY,
            canScrollTowardStart = recyclerView.canScrollVertically(-1),
        ) ?: return null
        return InitialRestoreStartBoundarySample(
            first,
            resourceTopPx,
            resource.height,
            visibleHeightPx,
            viewportAnchorY,
            resource.reportedMeasurementGenerationForOpen,
            rangeY,
        )
    }


    private fun isReadingAnchorInResource(index: Int): Boolean {
        if (disposed || recyclerView.height <= 0) return false
        val child = recyclerView.findChildViewUnder(
            recyclerView.width / 2f,
            recyclerView.height * READING_ANCHOR_FRACTION,
        ) ?: return false
        return recyclerView.getChildAdapterPosition(child) == index
    }

    internal fun visibleResourceRange(): ContinuousVisibleResourceRange? {
        val first = layoutManager.findFirstVisibleItemPosition().takeIf { it != RecyclerView.NO_POSITION } ?: return null
        val last = layoutManager.findLastVisibleItemPosition().takeIf { it != RecyclerView.NO_POSITION } ?: return null
        return ContinuousVisibleResourceRange(first, last, recyclerView.computeVerticalScrollOffset().toLong())
    }

    internal fun applyToLiveResources(action: (ContinuousResourceView) -> Unit) {
        resourceWindow.liveIndices().forEach { index -> resourceWindow.resourceAt(index)?.let(action) }
    }

    internal fun revokePreferenceCssOwners(preferenceGeneration: Long): List<CompletableDeferred<Unit>> = buildList {
        activeGeometryCssOwner?.takeIf { it.preferenceGeneration == preferenceGeneration }?.revoked = true
        applyToLiveResources { resource ->
            resource.revokeCssMutationOwnerForPreference(preferenceGeneration)?.let(::add)
        }
    }

    internal fun hasPendingCssGeometry(): Boolean = resourceWindow.liveIndices().any {
        resourceWindow.resourceAt(it)?.hasPendingCssGeometry == true
    }

    internal fun mustFinishCssGeometry(preferenceGeneration: Long): Boolean = resourceWindow.liveIndices().any {
        resourceWindow.resourceAt(it)?.mustFinishCssGeometry(preferenceGeneration) == true
    }

    internal fun requestPendingCssMeasurements() = applyToLiveResources {
        if (it.hasPendingCssGeometry) it.requestCurrentCssMeasurement()
    }

    internal fun emitCssConsistency() = applyToLiveResources { it.emitCssConsistency() }

    internal fun hasCommittedCssGeometry(transaction: ContinuousGeometryReflowTransaction): Boolean {
        val batch = activeGeometryBatch?.takeIf { it.owner.transactionGeneration == transaction.generation } ?: return false
        return batch.requiredResourceGenerations().all { (index, generation) ->
            resourceWindow.withLiveResource(index, generation) { !it.hasPendingCssGeometry } == true
        }
    }

    internal suspend fun awaitCssOwnerDrain(drains: List<CompletableDeferred<Unit>>) {
        drains.forEach { it.await() }
    }

    internal suspend fun handoffCommittedCssOwner(transactionGeneration: Long) {
        val resources = mutableListOf<ContinuousResourceView>()
        applyToLiveResources { resources += it }
        resources.forEach { it.handoffCssMutationOwner(null, transactionGeneration) }
        if (activeGeometryCssOwner?.transactionGeneration == transactionGeneration) {
            activeGeometryCssOwner = null
        }
    }

    internal suspend fun applyCurrentReadiumCssToLiveResources(preferenceGeneration: Long) {
        // Retain ownership until the complete CSS-only request succeeds. A
        // partial application must never become ambient after cancellation.
        val owner = ActiveGeometryCssOwner(
            layoutGeneration = layoutGeneration,
            preferenceGeneration = preferenceGeneration,
            transactionGeneration = null,
        )
        activeGeometryCssOwner = owner
        val resources = mutableListOf<ContinuousResourceView>()
        applyToLiveResources { resources += it }
        try {
            // Install the newest intent on every loading resource before the
            // first ready-resource CSS call can suspend. Otherwise a failure
            // midway could leave an older bootstrap callback reading newer,
            // mutable resolved CSS after that request has been revoked.
            for (resource in resources) {
                if (!resource.canFindLocator &&
                    !resource.deferCurrentEpochCssUntilBootstrap(preferenceGeneration, null)
                ) {
                    owner.revoked = true
                    withContext(NonCancellable) {
                        awaitCssOwnerDrain(revokePreferenceCssOwners(preferenceGeneration))
                    }
                    return
                }
            }
            for (resource in resources) {
                if (disposed || activeGeometryCssOwner !== owner || owner.revoked) return
                if (resource.canFindLocator &&
                    !resource.applyCurrentReadiumCss(preferenceGeneration, deferAmbientHandoff = true)
                ) {
                    owner.revoked = true
                    withContext(NonCancellable) {
                        awaitCssOwnerDrain(revokePreferenceCssOwners(preferenceGeneration))
                    }
                    return
                }
            }
            if (disposed || activeGeometryCssOwner !== owner || owner.revoked) return
            val currentResources = mutableListOf<ContinuousResourceView>()
            applyToLiveResources { currentResources += it }
            currentResources.forEach { it.handoffCssMutationOwner(preferenceGeneration, null) }
            if (activeGeometryCssOwner === owner) activeGeometryCssOwner = null
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            owner.revoked = true
            withContext(NonCancellable) {
                awaitCssOwnerDrain(revokePreferenceCssOwners(preferenceGeneration))
            }
            throw cancelled
        } catch (failure: Throwable) {
            owner.revoked = true
            withContext(NonCancellable) {
                awaitCssOwnerDrain(revokePreferenceCssOwners(preferenceGeneration))
            }
            throw failure
        }
    }

    internal fun applyToLiveResource(index: Int, generation: Long, action: (ContinuousResourceView) -> Unit): Boolean =
        resourceWindow.withLiveResource(index, generation) { action(it); true } ?: false

    internal fun isLiveResource(index: Int, generation: Long): Boolean =
        resourceWindow.generationAt(index) == generation

    private fun dispatchDeferredInitialRestoreReadyEvents() {
        val readyEvents = deferredInitialRestoreReadyEvents.takeReady(
            restoreGateBlocksPublication = initialRestoreAuthority.blocksViewportPublication(),
        ) { target ->
            !disposed && target.layoutGeneration == layoutGeneration &&
                isLiveResource(target.index, target.resourceGeneration)
        }
        readyEvents.forEach { target ->
            resourceReadyListener?.invoke(target.index, target.resourceGeneration)
        }
    }

    /** Converts a live resource WebView rectangle into this navigator's coordinates. */
    internal fun decorationRectInHostCoordinates(
        index: Int,
        generation: Long,
        resourceLocalRect: RectF,
    ): RectF? = resourceWindow.withLiveResource(index, generation) { resource ->
        resourceSelectionRectInHostCoordinates(resource, resourceLocalRect)
    }

    internal suspend fun currentSelection(index: Int, generation: Long): Selection? {
        if (disposed) return null
        val resource = resourceWindow.withLiveResource(index, generation) { it } ?: return null
        val selection = resource.currentSelection() ?: return null
        // The WebView callback is asynchronous. Re-check the same generation
        // after completion so an old resource can never impersonate a remake.
        return withContext(Dispatchers.Main.immediate) {
            resourceWindow.withLiveResource(index, generation) {
                selection.copy(
                    rect = selection.rect?.let { resourceLocalRect ->
                        resourceSelectionRectInHostCoordinates(resource, resourceLocalRect)
                    },
                )
            }
        }
    }

    /**
     * A resource WebView reports selection rectangles in its own layout
     * coordinate system. Translate that real, attached resource geometry into
     * this navigator's coordinate system before exposing [Selection.rect].
     */
    private fun resourceSelectionRectInHostCoordinates(
        resource: ContinuousResourceView,
        resourceLocalRect: RectF,
    ): RectF? {
        val resourceLocation = IntArray(2)
        val hostLocation = IntArray(2)
        resource.getLocationOnScreen(resourceLocation)
        getLocationOnScreen(hostLocation)
        val offsetX = resourceLocation[0] - hostLocation[0]
        val offsetY = resourceLocation[1] - hostLocation[1]
        return RectF(
            offsetX + resourceLocalRect.left,
            offsetY + resourceLocalRect.top,
            offsetX + resourceLocalRect.right,
            offsetY + resourceLocalRect.bottom,
        )
    }

    internal fun clearSelection(index: Int, generation: Long): Boolean =
        resourceWindow.withLiveResource(index, generation) { resource ->
            resource.clearSelection()
            true
        } ?: false

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        val owner = selectionTouchOwner
        if (owner != null && isLiveResource(owner.first, owner.second)) return false
        if (owner != null) {
            selectionTouchOwner = null
            selectionViewportGate.clear(owner)
        }
        return super.onInterceptTouchEvent(event)
    }

    internal fun dispose() {
        if (disposed) return
        BiblioLifeOpenTimingDiagnostics.lifecycle("HOST_DISPOSE_BEGIN", instanceId = sessionInstanceId, sessionId = sessionInstanceId, hostId = diagnosticHostId, generation = layoutGeneration.toLong())
        disposed = true
        initialViewportTargetIndex = null
        initialViewportPreloadsReleased = false
        deferredInitialRestoreReadyEvents.clear()
        initialViewportVisualStateRequestId++
        removeCallbacks(initialViewportTimeout)
        clearFreshLocatorObservation()
        if (recyclerView.viewTreeObserver.isAlive) {
            recyclerView.viewTreeObserver.removeOnGlobalLayoutListener(recyclerLayoutListener)
        }
        finishAllReflowWaiters(ContinuousReflowRestoreOutcome.Cancelled)
        geometryBatchReadyWaiters.values.forEach { it.complete(Unit) }
        geometryBatchReadyWaiters.clear()
        reflowEventPort.dispose()
        reflowTargetBarrier.clear()
        reflowDiagnosticTransactions.clear()
        reflowDiagnosticOwners.clear()
        reflowDiagnosticViewportBaselines.clear()
        reportedReflowMeasurements.clear()
        reflowDiagnosticListener = null
        attachedMaterializations.clear()
        selectionTouchOwner = null
        selectionViewportGate.clearAll()
        callbackGate.dispose()
        layoutGeneration = layoutModel.invalidateForReflow()
        // Explicitly releases every real resource before RecyclerView/host teardown.
        resourceWindow.disposeAll()
        recyclerView.adapter = null
        recyclerView.stopScroll()
        removeAllViews()
        pins.clear()
        activeGeometryCssOwner = null
        BiblioLifeOpenTimingDiagnostics.lifecycle("HOST_DISPOSE_END", instanceId = sessionInstanceId, sessionId = sessionInstanceId, hostId = diagnosticHostId, generation = layoutGeneration.toLong())
    }

    /** The resource window remains the sole real-WebView lifetime authority. */
    internal val liveResourceCount: Int get() = resourceWindow.liveIndices().size

    private fun selectInitialViewportTarget(index: Int) {
        if (initialViewportPreloadsReleased || initialViewportTargetIndex == index) return
        initialViewportTargetIndex = index
        // Any pending visual callback for an earlier initial target must not release preloads.
        initialViewportVisualStateRequestId++
        initialViewportRevealed = false
        initialViewportCover.visibility = View.VISIBLE
    }

    private fun reconcileResourceWindow(includePreloads: Boolean = initialViewportPreloadsReleased && proximityPreloadsEnabled) {
        if (disposed || initialViewportFailureReported) return
        val first = layoutManager.findFirstVisibleItemPosition()
        val last = layoutManager.findLastVisibleItemPosition()
        if (first == RecyclerView.NO_POSITION || last == RecyclerView.NO_POSITION) return
        resourceWindow.reconcile(
            if (initialViewportPreloadsReleased) (first..last).toSet()
            else setOf(initialViewportTargetIndex ?: first.also { selectInitialViewportTarget(it) }),
            if (includePreloads && initialViewportPreloadsReleased && proximityPreloadsEnabled) preloadCandidates(first, last) else emptySequence(),
        )
        (first..last).forEach { index ->
            (recyclerView.findViewHolderForAdapterPosition(index) as? ResourceHolder)?.bind(
                resourceWindow.resourceAt(index),
                layoutModel.geometryHeightOrNull(index) ?: ESTIMATED_RESOURCE_HEIGHT_PX.toLong(),
            )
        }
    }

    private fun readingAnchorOffsetPx(): Int = (recyclerView.height * READING_ANCHOR_FRACTION).toInt()

    private fun preloadCandidates(first: Int, last: Int = first): Sequence<Int> = sequence {
        lazyPreloadIndices(first, last, readingOrder.size, initialViewportPreloadsReleased && proximityPreloadsEnabled)
            .forEach { yield(it) }
    }

    private fun createLiveResource(index: Int, generation: Long): ContinuousResourceView {
        val createdLayoutGeneration = layoutGeneration
        val diagnosticOwner = reflowDiagnosticOwners.ownerFor(createdLayoutGeneration)
        val target = ContinuousReflowTarget(index, createdLayoutGeneration, generation)
        if (diagnosticOwner != null && diagnosticOwner.anchorIndex == index) {
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "resource_create",
                    context = diagnosticOwner.context,
                    preferenceGeneration = diagnosticOwner.preferenceGeneration,
                    transactionGeneration = diagnosticOwner.transactionGeneration,
                    layoutGeneration = createdLayoutGeneration,
                    resourceGeneration = generation,
                    readingOrderIndex = index,
                    anchorBeforeY = diagnosticOwner.anchorBeforeY,
                    result = "created",
                ),
            )
        }
        if (initialRestoreAuthority.isPendingIndex(index)) {
            BiblioLifeOpenTimingDiagnostics.targetMaterialized(index)
        }
        return resourceFactory.create(
            context = context,
            publication = publication,
            link = readingOrder[index],
            index = index,
            layoutGeneration = createdLayoutGeneration,
            resourceGeneration = generation,
            sessionInstanceId = sessionInstanceId,
            hostId = diagnosticHostId,
            onMeasurement = ::onMeasurement,
        ).also { resource ->
            activeGeometryCssOwner?.takeIf { it.layoutGeneration == createdLayoutGeneration }?.let { owner ->
                if (owner.revoked) {
                    resource.suppressAmbientCssUntilExplicitUpdate()
                } else {
                    resource.deferCurrentEpochCssUntilBootstrap(
                        preferenceGeneration = owner.preferenceGeneration,
                        transactionGeneration = owner.transactionGeneration,
                    )
                }
            }
            decorationSnapshotProvider?.invoke()?.forEach { (group, snapshot) ->
                resource.replaceDecorations(group, snapshot.first, snapshot.second)
            }
            testBinding.onTargetCreated(target, recyclerView)
            if (diagnosticOwner != null && index == diagnosticOwner.anchorIndex) {
                resource.setReflowDiagnosticLifecycleListener { stage ->
                    emitReflowDiagnostic(
                        EpubContinuousReflowDiagnosticEvent(
                            kind = "resource_$stage",
                            context = diagnosticOwner.context,
                            preferenceGeneration = diagnosticOwner.preferenceGeneration,
                            transactionGeneration = diagnosticOwner.transactionGeneration,
                            layoutGeneration = createdLayoutGeneration,
                            resourceGeneration = generation,
                            readingOrderIndex = index,
                            anchorBeforeY = diagnosticOwner.anchorBeforeY,
                            result = stage,
                        ),
                    )
                }
            }
            resource.onPageReady = {
                if (!disposed && isLiveResource(index, generation)) {
                    if (resource.currentLayoutGeneration != layoutGeneration) {
                        val currentTarget = ContinuousReflowTarget(index, layoutGeneration, generation)
                        resource.applyCssForLayoutGeneration(layoutGeneration) { applied ->
                            if (applied && !disposed && currentTarget.layoutGeneration == layoutGeneration &&
                                isLiveResource(index, generation)
                            ) publishResourceReady(currentTarget)
                            else if (!applied) onReflowTargetFailed(currentTarget)
                        }
                    } else {
                        publishResourceReady(ContinuousReflowTarget(index, layoutGeneration, generation))
                    }
                }
            }
            resource.onPageFailed = {
                if (diagnosticOwner != null && index == diagnosticOwner.anchorIndex) {
                    emitReflowDiagnostic(
                        EpubContinuousReflowDiagnosticEvent(
                            kind = "resource_failed",
                            context = diagnosticOwner.context,
                            preferenceGeneration = diagnosticOwner.preferenceGeneration,
                            transactionGeneration = diagnosticOwner.transactionGeneration,
                            layoutGeneration = layoutGeneration,
                            resourceGeneration = generation,
                            readingOrderIndex = index,
                            anchorBeforeY = diagnosticOwner.anchorBeforeY,
                            result = "failed",
                        ),
                    )
                }
                onReflowTargetFailed(ContinuousReflowTarget(index, layoutGeneration, generation))
            }
        }
    }

    private fun publishResourceReady(target: ContinuousReflowTarget) {
        if (disposed || target.layoutGeneration != layoutGeneration || !isLiveResource(target.index, target.resourceGeneration)) return
        reflowEventPort.trueReady(target)
        if (initialRestoreAuthority.blocksViewportPublication()) {
            Log.d(tag, "CONTINUOUS_INITIAL_RESTORE_VIEWPORT_SUPPRESSED source=resource_ready index=${target.index} generation=${target.resourceGeneration}")
            deferredInitialRestoreReadyEvents.defer(target)
        } else {
            resourceReadyListener?.invoke(target.index, target.resourceGeneration)
        }
    }

    private fun releaseLiveResource(resource: ContinuousResourceView) {
        val target = ContinuousReflowTarget(resource.index, layoutGeneration, resource.generation)
        failGeometryBatchIfRequired(target, "required_resource_released")
        removeAttachedMaterialization(resource)
        failReflowTarget(target, ContinuousReflowRestoreOutcome.Cancelled)
        resourceReleasedListener?.invoke(resource.index, resource.generation)
        (recyclerView.findViewHolderForAdapterPosition(resource.index) as? ResourceHolder)?.unbind(resource)
        resource.dispose()
    }

    private fun onMeasurement(measurement: ResourceLayoutMeasurement) {
        reflowEventPort.measurement(measurement)
    }

    private fun onMeasurementFromPort(measurement: ResourceLayoutMeasurement) {
        val owner = reflowDiagnosticOwners.ownerFor(measurement.layoutGeneration)
        val key = Triple(measurement.index, measurement.layoutGeneration, measurement.resourceGeneration)
        val isAccepted = acceptsMeasurement(measurement)
        val diagnosticResult = if (isAccepted) "accepted" else "rejected"
        val diagnosticMeasurement = (if (isAccepted) measurement.heightPx else Long.MIN_VALUE) to diagnosticResult
        val meaningfulDiagnosticChange = reportedReflowMeasurements[key] != diagnosticMeasurement
        if (owner != null && kotlin.math.abs(measurement.index - owner.anchorIndex) <= 1 && meaningfulDiagnosticChange) {
            reportedReflowMeasurements[key] = diagnosticMeasurement
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "measurement",
                    context = owner.context,
                    preferenceGeneration = owner.preferenceGeneration,
                    transactionGeneration = owner.transactionGeneration,
                    layoutGeneration = measurement.layoutGeneration,
                    resourceGeneration = measurement.resourceGeneration,
                    measurementGeneration = measurement.measurementGeneration,
                    readingOrderIndex = measurement.index,
                    oldHeightPx = resourceWindow.resourceAt(measurement.index)?.currentHeightPx,
                    newHeightPx = measurement.heightPx,
                    anchorBeforeY = owner.anchorBeforeY,
                    result = if (isAccepted) "admitted" else "stale_measurement_ignored",
                ),
            )
        }
        if (!isAccepted) return
        if (shouldDeferGeometryMeasurement(measurement)) {
            freshLocatorObservationBarrier.defer(measurement)
            Log.d(tag, "CONTINUOUS_REFLOW_STAGE geometry_deferred index=${measurement.index} height=${measurement.heightPx}")
            return
        }
        if (collectGeometryBatchMeasurement(measurement)) return
        applyAcceptedMeasurement(measurement)
    }

    private fun collectGeometryBatchMeasurement(measurement: ResourceLayoutMeasurement): Boolean {
        val batch = activeGeometryBatch ?: return false
        if (batch.owner.layoutGeneration != measurement.layoutGeneration) return false
        val result = batch.collect(measurement)
        if (result == ContinuousGeometryBatchCollection.STALE || result == ContinuousGeometryBatchCollection.DUPLICATE) return true
        val diagnosticOwner = reflowDiagnosticOwners.ownerFor(batch.owner.layoutGeneration)
        if (diagnosticOwner != null) {
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "geometry_batch_collect",
                    context = diagnosticOwner.context,
                    preferenceGeneration = batch.owner.preferenceGeneration,
                    transactionGeneration = batch.owner.transactionGeneration,
                    layoutGeneration = batch.owner.layoutGeneration,
                    resourceGeneration = measurement.resourceGeneration,
                    measurementGeneration = measurement.measurementGeneration,
                    readingOrderIndex = measurement.index,
                    oldHeightPx = resourceWindow.resourceAt(measurement.index)?.currentHeightPx,
                    newHeightPx = measurement.heightPx,
                    anchorBeforeY = diagnosticOwner.anchorBeforeY,
                    result = if (result == ContinuousGeometryBatchCollection.DEFERRED) "deferred_irrelevant" else "required",
                ),
            )
        }
        if (result == ContinuousGeometryBatchCollection.READY) {
            emitGeometryBatchEvent("geometry_batch_ready", batch, "count=${batch.requiredResourceGenerations().size}")
            geometryBatchReadyWaiters[batch.owner]?.complete(Unit)
        }
        return true
    }

    private suspend fun awaitGeometryBatchReady(batch: ContinuousGeometryMeasurementBatch): Boolean {
        if (batch.state != ContinuousGeometryBatchState.COLLECTING) return batch.state == ContinuousGeometryBatchState.READY
        val waiter = geometryBatchReadyWaiters.getOrPut(batch.owner) { CompletableDeferred() }
        if (batch.state != ContinuousGeometryBatchState.COLLECTING) waiter.complete(Unit)
        return try {
            // One current-generation live read; no polling and no cached height.
            requestPendingCssMeasurements()
            if (withTimeoutOrNull(1_000L) { waiter.await(); true } != true) {
                failGeometryBatchForMeasurements(batch, "current_css_measurement_unavailable")
                return false
            }
            activeGeometryBatch === batch && batch.state == ContinuousGeometryBatchState.READY
        } finally {
            if (geometryBatchReadyWaiters[batch.owner] === waiter) geometryBatchReadyWaiters.remove(batch.owner)
        }
    }

    private suspend fun restoreUnchangedGeometryIfPossible(
        batch: ContinuousGeometryMeasurementBatch,
        transaction: ContinuousGeometryReflowTransaction,
        target: ContinuousReflowTarget,
        locator: Locator,
        isCurrent: () -> Boolean,
    ): ContinuousReflowRestoreOutcome? {
        val measurements = batch.requiredMeasurementsForCommit()?.plus(batch.optionalMeasurementsForCommit()) ?: return null
        val resources = measurements.map { resourceWindow.withLiveResource(it.index, it.resourceGeneration) { resource -> resource } ?: return null }
        fun unchanged(): Boolean = measurements.indices.all { i ->
            val m = measurements[i]
            resourceWindow.withLiveResource(m.index, m.resourceGeneration) { it === resources[i] } == true &&
                resources[i].canAcknowledgeUnchangedGeometry(m) &&
                layoutModel.geometryHeightOrNull(m.index) == m.heightPx &&
                resources[i].layoutParams?.height?.toLong() == m.heightPx
        }
        fun current(): Boolean = !disposed && isCurrent() && activeGeometryBatch === batch &&
            activeGeometryTransaction === transaction && layoutGeneration == target.layoutGeneration && isTargetAttached(target) && unchanged()
        if (!current()) return null
        val layoutPass = recyclerLayoutPass
        val viewport = captureDiagnosticViewportLayoutSnapshot(target.index)
        val before = resolveLocatorPointGeometry(target.index, target.resourceGeneration, locator) ?: return null
        if (!isCurrent()) return ContinuousReflowRestoreOutcome.Cancelled
        if (!current() || recyclerLayoutPass != layoutPass || captureDiagnosticViewportLayoutSnapshot(target.index) != viewport) return null
        val exact = continuousSemanticAnchorQuality(locator, before, true) == ContinuousSemanticAnchorQuality.EXACT_DOM_POINT
        val delta = continuousAnchorViewportDelta(transaction.anchor.viewportY, before.viewportY)
        val path = continuousReflowPath(true, exact, true, delta)
        if (path == ContinuousReflowPath.FULL_REFLOW) return null
        var finalPoint = before
        if (path == ContinuousReflowPath.ANCHOR_ONLY) {
            if (!batch.beginCommit() || !transaction.tryBeginCommit(batch.owner)) return ContinuousReflowRestoreOutcome.Cancelled
            emitReflowDiagnostic(EpubContinuousReflowDiagnosticEvent(
                kind = "geometry_commit_lock", context = reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.context,
                preferenceGeneration = transaction.preferenceGeneration, transactionGeneration = transaction.generation,
                layoutGeneration = target.layoutGeneration, commitLockHeld = true, result = "acquired_before_anchor_correction",
            ))
            val child = recyclerView.findViewHolderForAdapterPosition(target.index)?.itemView ?: return ContinuousReflowRestoreOutcome.TargetNotReady
            val correction = continuousAnchorCorrectionOffset(layoutManager.getDecoratedTop(child), recyclerView.paddingTop, requireNotNull(delta))
                ?: return ContinuousReflowRestoreOutcome.VisibilityMismatch
            if (!continuousAnchorScrollRequired(delta) || !emitPresentationTransactionEvent(batch, "begin", transaction, "anchor_only")) {
                return ContinuousReflowRestoreOutcome.VisibilityMismatch
            }
            if (!reflowTargetBarrier.markUnchangedGeometry(target, recyclerLayoutPass, ::isTargetAttached) || !transaction.markRestored()) {
                return ContinuousReflowRestoreOutcome.TargetNotReady
            }
            val afterLayoutPass = recyclerLayoutPass
            layoutManager.scrollToPositionWithOffset(target.index, correction)
            transaction.anchorScrollRequested = true
            recyclerView.requestLayout()
            testBinding.onAuthoritativeRestore(target, recyclerView)
            val laidOut = awaitPostRestoreLayout(target, afterLayoutPass)
            if (laidOut != ContinuousReflowRestoreOutcome.Ready) return laidOut
            finalPoint = resolveLocatorPointGeometry(target.index, target.resourceGeneration, locator)
                ?: return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
        }
        val finalDelta = continuousAnchorViewportDelta(transaction.anchor.viewportY, finalPoint.viewportY)
            ?: return ContinuousReflowRestoreOutcome.VisibilityMismatch
        if (!current() || !continuousAnchorViewportMatches(finalDelta) ||
            continuousSemanticAnchorQuality(locator, finalPoint, true) != ContinuousSemanticAnchorQuality.EXACT_DOM_POINT
        ) return ContinuousReflowRestoreOutcome.VisibilityMismatch
        // Canonical publication remains the existing fresh point Locator; the
        // transient DOM token never becomes persistent reading position.
        val finalViewport = captureDiagnosticViewportLayoutSnapshot(target.index)
        val observed = observeRestoredLocator(target, diagnostic = false) ?: return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
        if (!current() || observed.href.removeFragment() != locator.href.removeFragment()) return ContinuousReflowRestoreOutcome.Cancelled
        if (captureDiagnosticViewportLayoutSnapshot(target.index) != finalViewport) {
            return if (path == ContinuousReflowPath.NO_OP) null else ContinuousReflowRestoreOutcome.VisibilityMismatch
        }
        if (path == ContinuousReflowPath.NO_OP &&
            (recyclerLayoutPass != layoutPass || captureDiagnosticViewportLayoutSnapshot(target.index) != viewport ||
                batch.requiredMeasurementsForCommit()?.plus(batch.optionalMeasurementsForCommit()) != measurements)
        ) return null
        if (path == ContinuousReflowPath.NO_OP && !transaction.markRestored()) return ContinuousReflowRestoreOutcome.Cancelled
        // No view setters, adapter notification, layout request or scroll here.
        layoutModel.reportMeasuredHeightsTogether(measurements)
        if (measurements.indices.any { !resources[it].acknowledgeUnchangedGeometry(measurements[it]) } ||
            !batch.acknowledgeUnchangedGeometry() ||
            !reflowTargetBarrier.markUnchangedGeometry(target, recyclerLayoutPass, ::isTargetAttached) ||
            !transaction.markConverged(finalPoint, finalDelta, observed.locations.progression)
        ) return ContinuousReflowRestoreOutcome.SemanticRestoreFailed
        completeReflowTargetIfReady()
        emitReflowPath(path, transaction, target, measurements, resources, delta,
            if (path == ContinuousReflowPath.NO_OP) "same_height_anchor_stable" else "same_height_anchor_moved",
            scrollRequested = transaction.anchorScrollRequested, coherent = true)
        val owner = reflowDiagnosticOwners.ownerFor(target.layoutGeneration)
        emitReflowDiagnostic(EpubContinuousReflowDiagnosticEvent(
            kind = "semantic_anchor_compare", context = owner?.context,
            preferenceGeneration = transaction.preferenceGeneration, transactionGeneration = transaction.generation,
            layoutGeneration = target.layoutGeneration, resourceGeneration = target.resourceGeneration,
            readingOrderIndex = target.index, anchorProgression = locator.locations.progression,
            anchorViewportDeltaPx = finalDelta,
            semanticAnchorFields = buildMap {
                put("identityType", "exact_dom_point"); put("anchorIdentityType", "exact_dom_point")
                finalPoint.anchorIdentityId?.let { put("anchorIdentityId", it) }
                finalPoint.anchorCharacterOffset?.let { put("anchorCharacterOffset", it) }
                put("semanticAnchorQuality", "EXACT_DOM_POINT")
                put("sameResource", true); put("sameDomIdentity", true); put("sameCharacterOffset", true)
                put("semanticAnchorResolved", true); put("semanticAnchorExact", true); put("fallbackUsed", false)
                put("beforeViewportY", transaction.anchor.viewportY)
                put("resolvedBeforeCorrectionViewportY", before.viewportY)
                put("finalViewportY", finalPoint.viewportY); put("finalDeltaPx", finalDelta)
            }, result = "exact_dom_point",
        ))
        emitReflowDiagnostic(EpubContinuousReflowDiagnosticEvent(
            kind = "gesture_baseline_delta", context = owner?.context,
            preferenceGeneration = transaction.preferenceGeneration, transactionGeneration = transaction.generation,
            layoutGeneration = target.layoutGeneration, resourceGeneration = target.resourceGeneration,
            semanticAnchorFields = mapOf("originalTargetViewportYPx" to transaction.anchor.viewportY,
                "actualFinalViewportYPx" to finalPoint.viewportY, "errorFromOriginalBaselinePx" to finalDelta,
                "cumulativeDriftFromGestureStartPx" to finalDelta), result = "exact_dom_point",
        ))
        if (path == ContinuousReflowPath.ANCHOR_ONLY) emitPresentationTransactionEvent(batch, "end", transaction, "anchor_only_committed")
        return ContinuousReflowRestoreOutcome.Restored(target.index, observed)
    }

    private fun emitReflowPath(
        path: ContinuousReflowPath,
        transaction: ContinuousGeometryReflowTransaction,
        target: ContinuousReflowTarget,
        measurements: List<ResourceLayoutMeasurement>,
        resources: List<ContinuousResourceView>,
        deltaPx: Double?,
        reason: String,
        scrollRequested: Boolean,
        coherent: Boolean = false,
    ) {
        val anchorIndex = measurements.indexOfFirst { it.index == target.index }
        val totalDelta = measurements.indices.sumOf { measurements[it].heightPx - resources[it].currentHeightPx }
        val predecessorDelta = measurements.indices.filter { measurements[it].index < target.index }
            .sumOf { measurements[it].heightPx - resources[it].currentHeightPx }
        emitReflowDiagnostic(EpubContinuousReflowDiagnosticEvent(
            kind = "reflow_path", context = reflowDiagnosticOwners.ownerFor(target.layoutGeneration)?.context,
            result = path.diagnosticValue, preferenceGeneration = transaction.preferenceGeneration,
            transactionGeneration = transaction.generation, layoutGeneration = target.layoutGeneration,
            resourceGeneration = target.resourceGeneration, readingOrderIndex = target.index,
            oldHeightPx = resources.getOrNull(anchorIndex)?.currentHeightPx, newHeightPx = measurements.getOrNull(anchorIndex)?.heightPx,
            batchHeightDeltaPx = totalDelta, predecessorHeightDeltaPx = predecessorDelta,
            anchorViewportDeltaPx = deltaPx,
            semanticAnchorFields = mapOf("reason" to reason,
                "geometryMutation" to (path == ContinuousReflowPath.FULL_REFLOW), "scrollRequested" to scrollRequested,
                "postRestoreLayoutPass" to (path != ContinuousReflowPath.NO_OP),
                "fullGeometryBatchApplied" to (path == ContinuousReflowPath.FULL_REFLOW), "coherent" to coherent),
        ))
    }

    private fun prepareGeometryBatchCommit(batch: ContinuousGeometryMeasurementBatch): PreparedGeometryBatchCommit? {
        if (activeGeometryBatch !== batch || batch.owner.layoutGeneration != layoutGeneration) {
            discardGeometryBatch(batch, "stale_before_apply")
            return null
        }
        val requiredMeasurements = batch.requiredMeasurementsForCommit() ?: return null
        val requiredResources = requiredMeasurements.mapNotNull { measurement ->
            resourceWindow.withLiveResource(measurement.index, measurement.resourceGeneration) { resource ->
                resource.takeIf { it.accepts(measurement) }
            }
        }
        if (requiredResources.size != requiredMeasurements.size ||
            requiredMeasurements.any { measurement -> resourceWindow.generationAt(measurement.index) != measurement.resourceGeneration }
        ) {
            failGeometryBatchForMeasurements(batch, "required_resource_changed_before_apply")
            return null
        }
        val optionalPairs = batch.optionalMeasurementsForCommit().mapNotNull { measurement ->
            val resource = resourceWindow.withLiveResource(measurement.index, measurement.resourceGeneration) { it }
                ?: return@mapNotNull null
            if (resource.accepts(measurement)) measurement to resource else null
        }
        val measurements = requiredMeasurements + optionalPairs.map { it.first }
        val resources = requiredResources + optionalPairs.map { it.second }
        val transaction = activeGeometryTransaction?.takeIf {
            it.generation == batch.owner.transactionGeneration && it.matchesCommitOwner(batch.owner)
        }
        if (transaction == null || !batch.beginCommit()) {
            discardGeometryBatch(batch, "commit_owner_mismatch_before_apply")
            return null
        }
        if (!transaction.tryBeginCommit(batch.owner)) {
            failGeometryBatchForMeasurements(batch, "commit_owner_rejected_after_lock")
            return null
        }
        geometryBatchReadyWaiters.remove(batch.owner)
        val prepared = PreparedGeometryBatchCommit(batch, transaction, measurements, resources)
        val anchor = transaction.anchor
        val diagnosticOwner = reflowDiagnosticOwners.ownerFor(batch.owner.layoutGeneration)
        if (diagnosticOwner != null) {
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "geometry_commit_lock",
                    context = diagnosticOwner.context,
                    preferenceGeneration = batch.owner.preferenceGeneration,
                    transactionGeneration = batch.owner.transactionGeneration,
                    layoutGeneration = batch.owner.layoutGeneration,
                    readingOrderIndex = anchor.index,
                    commitLockHeld = true,
                    result = "acquired_before_anchor_preflight",
                ),
            )
        }
        return prepared
    }

    private fun applyReadyGeometryBatch(
        prepared: PreparedGeometryBatchCommit,
        anchorPoint: ContinuousResolvedLocatorPoint,
        pendingOffsetPx: Int,
    ): Boolean {
        val batch = prepared.batch
        val transaction = prepared.transaction
        val measurements = prepared.measurements
        val resources = prepared.resources
        if (disposed || activeGeometryBatch !== batch || activeGeometryTransaction !== transaction ||
            batch.state != ContinuousGeometryBatchState.COMMIT_STARTED ||
            transaction.commitOwner != EpubContinuousGeometryCommitOwner(
                batch.owner.preferenceGeneration ?: transaction.preferenceGeneration,
                batch.owner.transactionGeneration,
                batch.owner.layoutGeneration,
            ) || batch.owner.layoutGeneration != layoutGeneration ||
            !isTargetAttached(batch.anchor) ||
            measurements.indices.any { index ->
                val measurement = measurements[index]
                resourceWindow.withLiveResource(measurement.index, measurement.resourceGeneration) { it } !== resources[index] ||
                    !resources[index].accepts(measurement)
            }
        ) {
            failGeometryBatchForMeasurements(batch, "owner_or_resource_changed_after_anchor_preflight")
            return false
        }

        val anchor = transaction.anchor
        val diagnosticOwner = reflowDiagnosticOwners.ownerFor(batch.owner.layoutGeneration)
        val oldBatchHeightTotalPx = measurements.indices.sumOf { index ->
            resources[index].currentHeightPx
        }
        val newBatchHeightTotalPx = measurements.sumOf { it.heightPx }
        val precedingIndices = measurements.indices.filter { measurements[it].index < anchor.index }
        val predecessorHeightDeltaPx = precedingIndices.sumOf { index ->
            measurements[index].heightPx - resources[index].currentHeightPx
        }
        val anchorDeltaPx = continuousAnchorViewportDelta(transaction.anchor.viewportY, anchorPoint.viewportY)
        val predecessorChanged = precedingIndices.any { measurements[it].heightPx != resources[it].currentHeightPx }
        val scrollRequired = anchorDeltaPx?.let(::continuousAnchorScrollRequired) == true || predecessorChanged
        val reason = when {
            measurements.indices.any { measurements[it].index == anchor.index && measurements[it].heightPx != resources[it].currentHeightPx } -> "resource_height_changed"
            predecessorChanged -> "predecessor_height_changed"
            continuousSemanticAnchorQuality(anchor.locator, anchorPoint, true) != ContinuousSemanticAnchorQuality.EXACT_DOM_POINT -> "exact_anchor_unavailable"
            else -> "geometry_dependency_changed"
        }
        emitReflowPath(ContinuousReflowPath.FULL_REFLOW, transaction, batch.anchor, measurements, resources, anchorDeltaPx, reason, scrollRequired)
        if (diagnosticOwner != null) {
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "geometry_commit_lock",
                    context = diagnosticOwner.context,
                    preferenceGeneration = batch.owner.preferenceGeneration,
                    transactionGeneration = batch.owner.transactionGeneration,
                    layoutGeneration = batch.owner.layoutGeneration,
                    readingOrderIndex = anchor.index,
                    commitLockHeld = true,
                    result = "acquired_before_first_height_mutation",
                ),
            )
            precedingIndices.forEach { index ->
                runCatching {
                    emitReflowDiagnostic(
                        EpubContinuousReflowDiagnosticEvent(
                            kind = "geometry_anchor_dependency",
                            context = diagnosticOwner.context,
                            preferenceGeneration = batch.owner.preferenceGeneration,
                            transactionGeneration = batch.owner.transactionGeneration,
                            layoutGeneration = batch.owner.layoutGeneration,
                            resourceGeneration = measurements[index].resourceGeneration,
                            measurementGeneration = measurements[index].measurementGeneration,
                            readingOrderIndex = measurements[index].index,
                            oldHeightPx = resources[index].currentHeightPx,
                            newHeightPx = measurements[index].heightPx,
                            anchorBeforeY = anchor.localY,
                            batchHeightDeltaPx = measurements[index].heightPx - resources[index].currentHeightPx,
                            result = "required_predecessor",
                        ),
                    )
                }
            }
            emitViewportSnapshot(
                snapshotStage = "before_geometry_commit",
                context = diagnosticOwner.context,
                preferenceGeneration = batch.owner.preferenceGeneration,
                transactionGeneration = batch.owner.transactionGeneration,
                layoutGeneration = batch.owner.layoutGeneration,
                resourceGeneration = anchor.resourceGeneration,
                anchorIndex = anchor.index,
                anchorProgression = anchor.locator.locations.progression,
                anchorPointDocumentYPx = anchorPoint.documentYLayoutPx,
                anchorPointViewportYPx = anchorPoint.viewportY,
                anchorPointAvailable = true,
                anchorPointUnavailableReason = null,
                anchorPointSampleStage = "after_css_before_geometry_commit",
                anchorBeforeLocalYPx = anchor.localY,
                anchorBeforeViewportYPx = anchor.viewportY,
                commitLockHeld = true,
                predecessorMeasurementCount = precedingIndices.size,
                predecessorHeightDeltaPx = predecessorHeightDeltaPx,
                batchHeightDeltaPx = newBatchHeightTotalPx - oldBatchHeightTotalPx,
                result = "before_first_height_mutation",
            )
        }

        emitViewportSnapshot(
            snapshotStage = "before_presentation_commit",
            context = diagnosticOwner?.context,
            preferenceGeneration = batch.owner.preferenceGeneration,
            transactionGeneration = batch.owner.transactionGeneration,
            layoutGeneration = batch.owner.layoutGeneration,
            resourceGeneration = anchor.resourceGeneration,
            anchorIndex = anchor.index,
            anchorProgression = transaction.anchor.locator.locations.progression,
            anchorPointDocumentYPx = anchorPoint.documentYLayoutPx,
            anchorPointViewportYPx = anchorPoint.viewportY,
            anchorPointAvailable = true,
            anchorPointSampleStage = "after_css_before_geometry_commit",
            anchorBeforeLocalYPx = anchor.localY,
            anchorBeforeViewportYPx = anchor.viewportY,
            anchorResourceHref = boundedContinuousDiagnosticResourceHref(transaction.anchor.locator.href.toString()),
            commitLockHeld = true,
            result = "preflight_ready_parent_mutation_pending",
        )

        // The same-point query has already completed. Install all parent geometry
        // and its compensating target offset before RecyclerView can lay out.
        try {
            if (!emitPresentationTransactionEvent(batch, "begin", transaction, "active")) {
                failGeometryBatchForMeasurements(batch, "presentation_transaction_begin_rejected")
                return false
            }
            recyclerView.suppressLayout(true)
            try {
                layoutModel.reportMeasuredHeightsTogether(measurements)
                measurements.forEachIndexed { index, measurement ->
                    val resource = resources[index]
                    resource.commitMeasuredGeometry(measurement)
                    if (index == 0) geometryBatchAfterFirstHeightMutationForTest?.invoke()
                    (recyclerView.findViewHolderForAdapterPosition(measurement.index) as? ResourceHolder)
                        ?.applyMeasuredHeight(resource)
                    adapter.notifyItemChanged(measurement.index)
                }
                emitViewportSnapshot(
                    snapshotStage = "after_geometry_before_anchor",
                    context = diagnosticOwner?.context,
                    preferenceGeneration = batch.owner.preferenceGeneration,
                    transactionGeneration = batch.owner.transactionGeneration,
                    layoutGeneration = batch.owner.layoutGeneration,
                    resourceGeneration = anchor.resourceGeneration,
                    anchorIndex = anchor.index,
                    anchorProgression = transaction.anchor.locator.locations.progression,
                    anchorPointDocumentYPx = anchorPoint.documentYLayoutPx,
                    anchorPointViewportYPx = anchorPoint.viewportY,
                    anchorPointAvailable = true,
                    anchorPointSampleStage = "after_css_before_geometry_commit",
                    anchorBeforeLocalYPx = transaction.anchor.localY,
                    anchorBeforeViewportYPx = transaction.anchor.viewportY,
                    anchorResourceHref = boundedContinuousDiagnosticResourceHref(transaction.anchor.locator.href.toString()),
                    commitLockHeld = true,
                    result = "cached_preflight_point_parent_heights_installed_offset_pending",
                )
                if (scrollRequired) {
                    layoutManager.scrollToPositionWithOffset(anchor.index, pendingOffsetPx)
                    transaction.anchorScrollRequested = true
                }
                emitViewportSnapshot(
                    snapshotStage = "after_anchor_scroll_request",
                    context = diagnosticOwner?.context,
                    preferenceGeneration = batch.owner.preferenceGeneration,
                    transactionGeneration = batch.owner.transactionGeneration,
                    layoutGeneration = batch.owner.layoutGeneration,
                    resourceGeneration = anchor.resourceGeneration,
                    anchorIndex = anchor.index,
                    anchorProgression = transaction.anchor.locator.locations.progression,
                    anchorPointDocumentYPx = null,
                    anchorPointViewportYPx = null,
                    anchorPointAvailable = false,
                    anchorPointUnavailableReason = "post_scroll_point_not_sampled",
                    anchorPointSampleStage = "after_css_before_geometry_commit",
                    anchorBeforeLocalYPx = transaction.anchor.localY,
                    anchorBeforeViewportYPx = transaction.anchor.viewportY,
                    anchorResourceHref = boundedContinuousDiagnosticResourceHref(transaction.anchor.locator.href.toString()),
                    requestedCorrectionOffsetPx = pendingOffsetPx,
                    requestedViewportDeltaPx = continuousAnchorViewportDelta(transaction.anchor.viewportY, anchorPoint.viewportY),
                    scrollRequestIssued = scrollRequired,
                    commitLockHeld = true,
                    result = if (scrollRequired) "correction_requested_before_parent_layout" else "zero_correction_scroll_skipped",
                )
            } finally {
                recyclerView.suppressLayout(false)
            }
            recyclerView.requestLayout()
            if (!batch.markApplied()) {
                failGeometryBatchForMeasurements(batch, "batch_state_changed_after_apply")
                return false
            }
        } catch (error: Throwable) {
            Log.w(tag, "CONTINUOUS_GEOMETRY_BATCH failed after commit start type=${error::class.simpleName}")
            failGeometryBatchForMeasurements(batch, "apply_failed_after_commit_start")
            return false
        }
        try {
        runCatching {
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "geometry_batch_effect",
                    context = diagnosticOwner?.context,
                    preferenceGeneration = batch.owner.preferenceGeneration,
                    transactionGeneration = batch.owner.transactionGeneration,
                    layoutGeneration = batch.owner.layoutGeneration,
                    resourceGeneration = anchor.resourceGeneration,
                    readingOrderIndex = anchor.index,
                    oldHeightPx = oldBatchHeightTotalPx,
                    newHeightPx = newBatchHeightTotalPx,
                    anchorBeforeY = anchor.localY,
                    result = "batch_applied",
                    predecessorMeasurementCount = precedingIndices.size,
                    predecessorHeightDeltaPx = predecessorHeightDeltaPx,
                    batchHeightDeltaPx = newBatchHeightTotalPx - oldBatchHeightTotalPx,
                ),
            )
        }
        emitGeometryBatchEvent("geometry_batch_apply", batch, "resourceCount=${measurements.size}")
        measurements.forEach { measurement ->
            val resource = resourceWindow.resourceAt(measurement.index) ?: return@forEach
            val owner = reflowDiagnosticOwners.ownerFor(batch.owner.layoutGeneration) ?: return@forEach
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "measurement_applied",
                    context = owner.context,
                    preferenceGeneration = batch.owner.preferenceGeneration,
                    transactionGeneration = batch.owner.transactionGeneration,
                    layoutGeneration = batch.owner.layoutGeneration,
                    resourceGeneration = measurement.resourceGeneration,
                    measurementGeneration = measurement.measurementGeneration,
                    readingOrderIndex = measurement.index,
                    oldHeightPx = null,
                    newHeightPx = resource.currentHeightPx,
                    anchorBeforeY = owner.anchorBeforeY,
                    result = "batch_geometry_commit_no_scroll",
                ),
            )
        }
        // Only the semantic target opens the existing attached-layout barrier;
        // the required neighbor measurements have no independent scroll owner.
        onReflowTargetMeasured(batch.anchor)
        } catch (error: Throwable) {
            Log.w(tag, "CONTINUOUS_GEOMETRY_BATCH terminal callback failed type=${error::class.simpleName}")
            failGeometryBatchForMeasurements(batch, "terminal_callback_failed_after_commit_start")
            return false
        }
        return true
    }

    private fun emitPresentationTransactionEvent(
        batch: ContinuousGeometryMeasurementBatch,
        phase: String,
        transaction: ContinuousGeometryReflowTransaction,
        outcome: String,
    ): Boolean {
        if (phase == "begin") {
            if (!transaction.beginPresentationTransaction()) return false
        } else if (!transaction.finishPresentationTransaction()) {
            return false
        }
        val owner = reflowDiagnosticOwners.ownerFor(batch.owner.layoutGeneration)
        emitReflowDiagnostic(
            EpubContinuousReflowDiagnosticEvent(
                kind = "presentation_transaction",
                context = owner?.context,
                preferenceGeneration = batch.owner.preferenceGeneration,
                transactionGeneration = batch.owner.transactionGeneration,
                layoutGeneration = batch.owner.layoutGeneration,
                readingOrderIndex = batch.anchor.index,
                commitLockHeld = true,
                snapshotStage = outcome,
                result = phase,
            ),
        )
        return true
    }

    private fun failGeometryBatchForMeasurements(batch: ContinuousGeometryMeasurementBatch, reason: String) {
        if (activeGeometryBatch !== batch) return
        emitMissingGeometryBatchMeasurements(batch, "geometry_batch_pending", "unmeasured_on_terminal")
        val commitStarted = batch.state in setOf(
            ContinuousGeometryBatchState.COMMIT_STARTED,
            ContinuousGeometryBatchState.APPLIED,
        )
        val failed = if (commitStarted) batch.failAfterCommitStart() else batch.fail()
        if (!failed) return
        geometryBatchReadyWaiters.remove(batch.owner)?.complete(Unit)
        try {
            runCatching {
                emitGeometryBatchEvent(
                    if (commitStarted) "geometry_batch_failed" else "geometry_batch_discarded",
                    batch,
                    if (commitStarted) "FAILED_AFTER_COMMIT_START:$reason" else reason,
                )
            }
        } finally {
            failReflowTarget(batch.anchor, ContinuousReflowRestoreOutcome.TargetNotReady)
        }
    }

    private fun failGeometryBatchIfRequired(target: ContinuousReflowTarget, reason: String) {
        val batch = activeGeometryBatch ?: return
        if (batch.state in setOf(
                ContinuousGeometryBatchState.COLLECTING,
                ContinuousGeometryBatchState.READY,
                ContinuousGeometryBatchState.COMMIT_STARTED,
                ContinuousGeometryBatchState.APPLIED,
            ) &&
            batch.isRequired(target.index, target.resourceGeneration)
        ) {
            emitMissingGeometryBatchMeasurements(batch, "geometry_batch_pending", "unmeasured_on_terminal")
            val commitStarted = batch.state in setOf(
                ContinuousGeometryBatchState.COMMIT_STARTED,
                ContinuousGeometryBatchState.APPLIED,
            )
            val failed = if (commitStarted) batch.failAfterCommitStart() else batch.failRequired(target)
            if (failed) {
                geometryBatchReadyWaiters.remove(batch.owner)?.complete(Unit)
                emitGeometryBatchEvent(
                    if (commitStarted) "geometry_batch_failed" else "geometry_batch_discarded",
                    batch,
                    if (commitStarted) "FAILED_AFTER_COMMIT_START:$reason" else reason,
                )
                failReflowTarget(batch.anchor, ContinuousReflowRestoreOutcome.TargetNotReady)
            }
        }
    }

    private fun discardGeometryBatch(batch: ContinuousGeometryMeasurementBatch, reason: String) {
        if (batch.state in setOf(ContinuousGeometryBatchState.COMMIT_STARTED, ContinuousGeometryBatchState.APPLIED)) {
            if (batch.failAfterCommitStart()) {
                geometryBatchReadyWaiters.remove(batch.owner)?.complete(Unit)
                emitGeometryBatchEvent("geometry_batch_failed", batch, "FAILED_AFTER_COMMIT_START:$reason")
            }
            return
        }
        emitMissingGeometryBatchMeasurements(batch, "geometry_batch_pending", "unmeasured_on_terminal")
        if (batch.discard()) {
            geometryBatchReadyWaiters.remove(batch.owner)?.complete(Unit)
            emitGeometryBatchEvent("geometry_batch_discarded", batch, reason)
        }
    }

    private fun emitGeometryBatchEvent(
        kind: String,
        batch: ContinuousGeometryMeasurementBatch,
        result: String,
    ) {
        val owner = reflowDiagnosticOwners.ownerFor(batch.owner.layoutGeneration) ?: return
        emitReflowDiagnostic(
            EpubContinuousReflowDiagnosticEvent(
                kind = kind,
                context = owner.context,
                preferenceGeneration = batch.owner.preferenceGeneration,
                transactionGeneration = batch.owner.transactionGeneration,
                layoutGeneration = batch.owner.layoutGeneration,
                resourceGeneration = batch.anchor.resourceGeneration,
                readingOrderIndex = batch.anchor.index,
                anchorBeforeY = owner.anchorBeforeY,
                result = result,
            ),
        )
    }

    private fun emitMissingGeometryBatchMeasurements(
        batch: ContinuousGeometryMeasurementBatch,
        kind: String,
        result: String,
    ) {
        if (batch.state in setOf(
                ContinuousGeometryBatchState.COMMITTED,
                ContinuousGeometryBatchState.DISCARDED,
                ContinuousGeometryBatchState.FAILED,
                ContinuousGeometryBatchState.FAILED_AFTER_COMMIT_START,
            )
        ) return
        val owner = reflowDiagnosticOwners.ownerFor(batch.owner.layoutGeneration) ?: return
        batch.missingRequiredResourceGenerations().forEach { (index, resourceGeneration) ->
            val retainedCssObligation = result == "unmeasured_on_terminal" &&
                resourceWindow.withLiveResource(index, resourceGeneration) { it.hasPendingCssGeometry } == true
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = kind,
                    context = owner.context,
                    preferenceGeneration = batch.owner.preferenceGeneration,
                    transactionGeneration = batch.owner.transactionGeneration,
                    layoutGeneration = batch.owner.layoutGeneration,
                    resourceGeneration = resourceGeneration,
                    readingOrderIndex = index,
                    oldHeightPx = resourceWindow.withLiveResource(index, resourceGeneration) { it.currentHeightPx },
                    result = if (retainedCssObligation) "retained_css_geometry_obligation" else result,
                ),
            )
        }
    }

    private fun acceptsMeasurement(measurement: ResourceLayoutMeasurement): Boolean =
        !disposed && callbackGate.accepts(
                measurement.index,
                measurement.resourceGeneration,
                measurement.layoutGeneration,
                layoutGeneration,
                resourceWindow.generationAt(measurement.index),
            ) && resourceWindow.resourceAt(measurement.index)?.accepts(measurement) == true

    private fun applyAcceptedMeasurement(measurement: ResourceLayoutMeasurement) {
        val resource = resourceWindow.resourceAt(measurement.index) ?: return
        val reflowTarget = initialRestoreAuthority.geometryTarget()
            ?.takeIf {
                !initialRestoreAuthority.isRestoreRequested() &&
                    isLiveResource(it.index, it.resourceGeneration)
            }
            ?: reflowDiagnosticTransactions.entries
                .singleOrNull { (target, transaction) ->
                    !transaction.restored && transaction.canRestore(target) &&
                        isLiveResource(target.index, target.resourceGeneration)
                }
                ?.key
            ?: pendingReflowTargetForMeasurement(
                measurement = measurement,
                pendingTargets = reflowTargetWaiters.keys,
                currentLayoutGeneration = layoutGeneration,
                isLiveResource = ::isLiveResource,
            )
        val viewportAnchor = captureViewportLayoutAnchor()
        val readingAnchor = if (reflowTarget == null) captureReadingAnchorLayout() else null
        // A queued LinearLayoutManager offset is consumed only by its next layout.
        // Preserving the old viewport here would overwrite that pending command.
        val pendingInitialPosition = initialRestoreAuthority.isRestoreRequested() &&
            !initialRestoreAuthority.isRestoreCommitted()
        val scrollPlan = if (pendingInitialPosition) ContinuousMeasurementScrollPlan.KeepCurrent else continuousMeasurementScrollPlan(
            reflowTarget = reflowTarget,
            measurementIndex = measurement.index,
            readingAnchor = readingAnchor,
            fallbackAnchor = viewportAnchor,
            currentLayoutGeneration = layoutGeneration,
            isLiveResource = ::isLiveResource,
        )
        val previousHeightPx = resource.currentHeightPx
        resource.commitMeasuredGeometry(measurement)
        layoutModel.reportMeasuredHeight(measurement.index, measurement.heightPx, layoutGeneration)
        val holder = recyclerView.findViewHolderForAdapterPosition(measurement.index) as? ResourceHolder
        holder?.applyMeasuredHeight(resource)
        adapter.notifyItemChanged(measurement.index)
        when (scrollPlan) {
            is ContinuousMeasurementScrollPlan.ReflowTarget -> {
                // The pinned reflow target, not a neighboring provisional holder,
                // owns the viewport until its first measured attached layout opens
                // the transaction barrier. Its later semantic restore remains the
                // only authority for the final reading position.
                layoutManager.scrollToPositionWithOffset(scrollPlan.target.index, readingAnchorOffsetPx())
                recyclerView.requestLayout()
            }
            is ContinuousMeasurementScrollPlan.PreserveAnchor -> {
                layoutManager.scrollToPositionWithOffset(scrollPlan.anchor.index, scrollPlan.anchor.offsetPx)
            }
            ContinuousMeasurementScrollPlan.KeepCurrent -> Unit
        }
        val diagnosticOwner = reflowDiagnosticOwners.ownerFor(measurement.layoutGeneration)
        if (diagnosticOwner != null && kotlin.math.abs(measurement.index - diagnosticOwner.anchorIndex) <= 1) {
            val scrollAnchor = when (scrollPlan) {
                is ContinuousMeasurementScrollPlan.ReflowTarget -> scrollPlan.target.index to readingAnchorOffsetPx()
                is ContinuousMeasurementScrollPlan.PreserveAnchor -> scrollPlan.anchor.index to scrollPlan.anchor.offsetPx
                ContinuousMeasurementScrollPlan.KeepCurrent -> null
            }
            emitReflowDiagnostic(
                EpubContinuousReflowDiagnosticEvent(
                    kind = "measurement_applied",
                    context = diagnosticOwner.context,
                    preferenceGeneration = diagnosticOwner.preferenceGeneration,
                    transactionGeneration = diagnosticOwner.transactionGeneration,
                    layoutGeneration = measurement.layoutGeneration,
                    resourceGeneration = measurement.resourceGeneration,
                    measurementGeneration = measurement.measurementGeneration,
                    readingOrderIndex = measurement.index,
                    oldHeightPx = previousHeightPx,
                    newHeightPx = measurement.heightPx,
                    anchorBeforeIndex = readingAnchor?.index ?: viewportAnchor?.index,
                    anchorBeforeOffsetPx = readingAnchor?.localOffsetPx ?: viewportAnchor?.offsetPx,
                    scrollAnchorIndex = scrollAnchor?.first,
                    scrollAnchorOffsetPx = scrollAnchor?.second,
                    anchorBeforeY = diagnosticOwner.anchorBeforeY,
                    result = when (scrollPlan) {
                        is ContinuousMeasurementScrollPlan.ReflowTarget -> "scroll_to_reflow_target"
                        is ContinuousMeasurementScrollPlan.PreserveAnchor -> "preserved_anchor"
                        ContinuousMeasurementScrollPlan.KeepCurrent -> "keep_current"
                    },
                ),
            )
        }
        holder?.logVisualState("RESOURCE_BOUNDS", resource)
        if (!initialRestorePending) {
            revealInitialViewport(
                "first_real_geometry",
                ContinuousReflowTarget(
                    measurement.index,
                    measurement.layoutGeneration,
                    measurement.resourceGeneration,
                ),
            )
        }
        Log.d(tag, "CONTINUOUS_HOST_RESOURCE_MEASURED index=${measurement.index} height=${measurement.heightPx} generation=$layoutGeneration")
        onReflowTargetMeasured(
            ContinuousReflowTarget(measurement.index, measurement.layoutGeneration, measurement.resourceGeneration),
        )
        // A true-ready callback can arrive before RecyclerView has committed the
        // resource's measured child geometry. The session owns the real anchor
        // lookup, so notify it again only after this generation's geometry is
        // live; no timer or coordinate fallback is involved.
        if (initialRestoreAuthority.blocksViewportPublication()) {
            Log.d(
                tag,
                "CONTINUOUS_INITIAL_RESTORE_VIEWPORT_SUPPRESSED source=measurement index=${measurement.index} " +
                    "generation=${measurement.resourceGeneration}",
            )
        } else {
            viewportChangedListener?.invoke()
        }
    }

    private fun beginFreshLocatorObservation(
        target: ContinuousReflowTarget,
        transaction: ContinuousGeometryReflowTransaction,
    ) {
        freshLocatorObservationBarrier.begin(target, transaction)
        Log.d(tag, "CONTINUOUS_REFLOW_STAGE observe_begin transactionGeneration=${transaction.generation} index=${target.index}")
    }

    private fun shouldDeferGeometryMeasurement(measurement: ResourceLayoutMeasurement): Boolean {
        return freshLocatorObservationBarrier.shouldDefer(measurement) { target, transaction ->
            reflowDiagnosticTransactions[target] === transaction && isTargetAttached(target)
        }
    }

    private fun clearFreshLocatorObservation() {
        freshLocatorObservationBarrier.clear()
    }

    private fun flushDeferredGeometryMeasurements(pending: List<ResourceLayoutMeasurement>) {
        pending.forEach { measurement ->
            if (acceptsMeasurement(measurement)) {
                Log.d(tag, "CONTINUOUS_REFLOW_STAGE geometry_flush index=${measurement.index} height=${measurement.heightPx}")
                applyAcceptedMeasurement(measurement)
            } else {
                Log.d(tag, "CONTINUOUS_REFLOW_STAGE geometry_flush index=${measurement.index} result=stale")
            }
        }
    }

    private fun onReflowTargetFailed(target: ContinuousReflowTarget) {
        failGeometryBatchIfRequired(target, "required_resource_failed")
        if (initialRestoreAuthority.blocksViewportPublication() && !initialRestoreAuthority.isCurrentTarget(target)) {
            Log.d(
                tag,
                "CONTINUOUS_INITIAL_RESTORE_FAILURE_SUPPRESSED source=neighbor index=${target.index} " +
                    "lg=${target.layoutGeneration} rg=${target.resourceGeneration}",
            )
            return
        }
        failReflowTarget(target, ContinuousReflowRestoreOutcome.TargetNotReady)
        reportInitialViewportFailure("resource_not_ready")
    }

    private fun revealInitialViewport(
        reason: String,
        expectedTarget: ContinuousReflowTarget? = null,
    ) {
        if (initialViewportRevealed || disposed) return
        val materialization = expectedTarget?.let { target ->
            attachedMaterializations[target.index]?.takeIf {
                it.target == target &&
                    resourceWindow.withLiveResource(target.index, target.resourceGeneration) { resource -> resource } === it.resource
            }
        }
        initialViewportRevealed = true
        removeCallbacks(initialViewportTimeout)
        initialViewportCover.visibility = View.GONE
        logInitialViewportVisualState("reveal", reason, materialization)
        Log.d(
            tag,
            "CONTINUOUS_COVER_STATE state=revealed reason=$reason lg=$layoutGeneration " +
                "visibility=${initialViewportCover.visibility}",
        )
        materialization?.let { scheduleInitialViewportVisualCommit(reason, it) }
            ?: Log.d(
                tag,
                "CONTINUOUS_INITIAL_VISUAL event=commit_drop reason=target_unavailable lg=$layoutGeneration",
            )
        initialViewportReadyListener?.invoke()
    }

    private fun reportInitialViewportFailure(reason: String) {
        if (disposed || initialViewportRevealed || initialViewportFailureReported) return
        initialViewportFailureReported = true
        removeCallbacks(initialViewportTimeout)
        Log.e(tag, "CONTINUOUS_INITIAL_VIEWPORT_FAILURE reason=$reason lg=$layoutGeneration")
        initialViewportFailureListener?.invoke(reason)
    }

    private fun scheduleInitialViewportVisualCommit(
        reason: String,
        materialization: ContinuousResourceMaterialization,
    ) {
        val target = materialization.target
        val resource = materialization.resource
        val webViewIdentity = resource.webViewIdentity
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.VISUAL_STATE_CALLBACK)) {
            // Unsupported providers retain the existing successful-reveal boundary; no fake T5.
            initialViewportPreloadsReleased = true
            initialViewportTargetIndex = null
            reconcileResourceWindow()
            Log.d(
                tag,
                "CONTINUOUS_INITIAL_VISUAL event=commit_drop reason=visual_state_unsupported " +
                    "lg=${target.layoutGeneration} rg=${target.resourceGeneration} index=${target.index} " +
                    "webViewId=$webViewIdentity",
            )
            return
        }
        val requestId = ++initialViewportVisualStateRequestId
        val scheduled = resource.postVisualStateCallback(requestId) { completedRequestId ->
            val current = attachedMaterializations[target.index]
            if (disposed || initialViewportFailureReported ||
                completedRequestId != initialViewportVisualStateRequestId ||
                initialViewportTargetIndex != target.index || layoutGeneration != target.layoutGeneration ||
                current?.target != target || current.resource !== resource ||
                resource.webViewIdentity != webViewIdentity
            ) {
                Log.d(
                    tag,
                    "CONTINUOUS_INITIAL_VISUAL event=commit_drop reason=stale_or_disposed " +
                        "requestId=$completedRequestId lg=${target.layoutGeneration} rg=${target.resourceGeneration} " +
                        "index=${target.index} webViewId=$webViewIdentity",
                )
                return@postVisualStateCallback
            }
            logInitialViewportVisualState("visual_commit", reason, current, completedRequestId)
            BiblioLifeOpenTimingDiagnostics.visualCommit(target.index)
            initialViewportPreloadsReleased = true
            initialViewportTargetIndex = null
            reconcileResourceWindow()
        }
        if (!scheduled) {
            Log.d(
                tag,
                "CONTINUOUS_INITIAL_VISUAL event=commit_drop reason=resource_disposed " +
                    "requestId=$requestId lg=${target.layoutGeneration} rg=${target.resourceGeneration} " +
                    "index=${target.index} webViewId=$webViewIdentity",
            )
        } else {
            Log.d(
                tag,
                "CONTINUOUS_INITIAL_VISUAL event=commit_scheduled reason=$reason requestId=$requestId " +
                    "lg=${target.layoutGeneration} rg=${target.resourceGeneration} index=${target.index} " +
                    "webViewId=$webViewIdentity",
            )
        }
    }

    private fun logInitialViewportVisualState(
        event: String,
        reason: String,
        materialization: ContinuousResourceMaterialization?,
        requestId: Long? = null,
    ) {
        val target = materialization?.target
        val resource = materialization?.resource
        Log.d(
            tag,
            "CONTINUOUS_INITIAL_VISUAL event=$event reason=$reason requestId=${requestId ?: "none"} " +
                "lg=$layoutGeneration targetIndex=${target?.index ?: "none"} " +
                "targetLg=${target?.layoutGeneration ?: "none"} targetRg=${target?.resourceGeneration ?: "none"} " +
                "targetResourceId=${resource?.let { System.identityHashCode(it) } ?: "none"} " +
                "targetWebViewId=${resource?.webViewIdentity ?: "none"} " +
                viewVisualState("host", this) + " " +
                viewVisualState("cover", initialViewportCover) + " " +
                viewVisualState("targetWebView", resource?.webViewForDiagnostics),
        )
    }

    private fun viewVisualState(label: String, view: View?): String =
        if (view == null) {
            "$label=unavailable"
        } else {
            "$label{attached=${view.isAttachedToWindow},shown=${view.isShown}," +
                "windowToken=${view.windowToken?.let { System.identityHashCode(it) } ?: "none"}," +
                "bounds=${view.left},${view.top},${view.right},${view.bottom}}"
        }

    private inner class ResourceAdapter : RecyclerView.Adapter<ResourceHolder>() {
        override fun getItemCount() = readingOrder.size
        override fun getItemViewType(position: Int) = RESOURCE_VIEW_TYPE
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = ResourceHolder(FrameLayout(parent.context))
        override fun onBindViewHolder(holder: ResourceHolder, position: Int) {
            holder.boundIndex = position
            holder.bind(
                resourceWindow.resourceAt(position),
                layoutModel.geometryHeightOrNull(position) ?: ESTIMATED_RESOURCE_HEIGHT_PX.toLong(),
            )
        }
        override fun onViewAttachedToWindow(holder: ResourceHolder) { super.onViewAttachedToWindow(holder); holder.onAttached(); reconcileResourceWindow() }
        override fun onViewDetachedFromWindow(holder: ResourceHolder) { holder.onDetached(); super.onViewDetachedFromWindow(holder) }
        override fun onViewRecycled(holder: ResourceHolder) { holder.unbind(); super.onViewRecycled(holder) }
        override fun onFailedToRecycleView(holder: ResourceHolder): Boolean = false
    }

    private inner class ResourceHolder(val container: FrameLayout) : RecyclerView.ViewHolder(container) {
        var boundIndex: Int = RecyclerView.NO_POSITION
        private var resource: ContinuousResourceView? = null
        private var attached = false
        private var materialization: ContinuousResourceMaterialization? = null
        fun bind(next: ContinuousResourceView?, placeholderHeightPx: Long) {
            if (resource !== next) {
                unbind()
                resource = next
                next?.let {
                    container.addView(it, FrameLayout.LayoutParams(MATCH_PARENT, it.currentHeightPx.toInt()))
                    logVisualState("REBIND", it)
                }
            }
            if (next == null) {
                container.minimumHeight = placeholderHeightPx.toLayoutHeight()
            } else if (container.minimumHeight != 0 || next.layoutParams?.height != next.currentHeightPx.toLayoutHeight()) {
                // Pin/window reconciliation also rebinds already-current holders.
                // Reassigning identical dimensions here used to request a host
                // layout even when a reflow needed no physical work at all.
                applyMeasuredHeight(next)
            }
            publishAttachedMaterialization()
        }
        fun refreshMaterialization() {
            publishAttachedMaterialization()
        }
        fun applyMeasuredHeight(expected: ContinuousResourceView) {
            if (resource !== expected) return
            container.minimumHeight = 0
            expected.layoutParams = expected.layoutParams.apply {
                height = expected.currentHeightPx.toLayoutHeight()
            }
            container.requestLayout()
        }
        fun unbind(expected: ContinuousResourceView? = null) {
            if (expected != null && resource !== expected) return
            resource?.let {
                removeAttachedMaterialization(it)
                container.minimumHeight = it.currentHeightPx.toLayoutHeight()
                container.removeView(it)
            }
            resource = null
            materialization = null
        }
        fun onAttached() {
            attached = true
            logVisualState("HOLDER_ATTACH")
            publishAttachedMaterialization(fromHolderAttach = true)
        }
        fun onDetached() {
            logVisualState("HOLDER_DETACH")
            attached = false
            unbind()
        }

        private fun publishAttachedMaterialization(fromHolderAttach: Boolean = false) {
            val current = resource ?: return
            if (!attached || !container.isAttachedToWindow || current.parent !== container) return
            val target = ContinuousReflowTarget(current.index, layoutGeneration, current.generation)
            if (resourceWindow.withLiveResource(current.index, current.generation) { it } !== current) return
            val currentMaterialization = materialization
                ?.takeIf { it.target == target && it.resource === current }
                ?: ContinuousResourceMaterialization(target, current).also { materialization = it }
            if (attachedMaterializations[current.index] !== currentMaterialization) {
                attachedMaterializations[current.index]?.let { replaced ->
                    testBinding.onResourceDetached(replaced)
                }
                attachedMaterializations[current.index] = currentMaterialization
                testBinding.onResourceAttached(currentMaterialization)
            }
            if (fromHolderAttach) {
                completeReattachWaiter(currentMaterialization)
            }
        }

        fun logVisualState(event: String, current: ContinuousResourceView? = resource) {
            val webView = current?.getChildAt(0)
            Log.d(
                tag,
                "CONTINUOUS_$event index=${current?.index ?: boundIndex} lg=$layoutGeneration rg=${current?.generation} " +
                    "holderAttached=$attached containerAttached=${container.isAttachedToWindow} " +
                    "resourceParent=${current?.parent?.javaClass?.simpleName} webViewParent=${webView?.parent?.javaClass?.simpleName} " +
                    "webViewId=${webView?.let { System.identityHashCode(it) }} " +
                    "visibility=${current?.visibility} alpha=${current?.alpha} " +
                    "bounds=${current?.left},${current?.top},${current?.right},${current?.bottom}",
            )
        }

        private fun Long.toLayoutHeight(): Int = coerceIn(1L, Int.MAX_VALUE.toLong()).toInt()
    }

    private fun removeAttachedMaterialization(resource: ContinuousResourceView) {
        val materialization = attachedMaterializations[resource.index]
            ?.takeIf { it.resource === resource && it.target.resourceGeneration == resource.generation }
            ?: return
        attachedMaterializations.remove(resource.index)
        testBinding.onResourceDetached(materialization)
    }

    private fun completeReattachWaiter(materialization: ContinuousResourceMaterialization) {
        val waiter = reattachWaiters[materialization.target] ?: return
        if (waiter.resource !== materialization.resource) return
        if (disposed || layoutGeneration != waiter.target.layoutGeneration ||
            attachedMaterializations[waiter.target.index] !== materialization ||
            resourceWindow.withLiveResource(waiter.target.index, waiter.target.resourceGeneration) { it } !== waiter.resource
        ) return
        if (reflowDiagnosticTransactions[waiter.target] !== waiter.transaction ||
            waiter.transaction.generation != waiter.transactionGeneration ||
            !waiter.transaction.canRestore(waiter.target) || !waiter.isTransactionCurrent()
        ) {
            reattachWaiters.remove(waiter.target)?.completion?.complete(ContinuousReflowRestoreOutcome.Cancelled)
            return
        }
        reattachWaiters.remove(waiter.target)?.completion?.complete(ContinuousReflowRestoreOutcome.Ready)
    }

    private fun cancelReattachWaiter(transaction: ContinuousGeometryReflowTransaction) {
        reattachWaiters.entries.toList().forEach { (target, waiter) ->
            if (waiter.transaction === transaction && waiter.transactionGeneration == transaction.generation) {
                reattachWaiters.remove(target)?.completion?.complete(ContinuousReflowRestoreOutcome.Cancelled)
            }
        }
    }

    private data class ReattachWaiter(
        val transaction: ContinuousGeometryReflowTransaction,
        val transactionGeneration: Long,
        val target: ContinuousReflowTarget,
        val resource: ContinuousResourceView,
        val isTransactionCurrent: () -> Boolean,
        val completion: CompletableDeferred<ContinuousReflowRestoreOutcome> = CompletableDeferred(),
    )

    private data class ReattachRegistration(
        val immediateOutcome: ContinuousReflowRestoreOutcome? = null,
        val waiter: ReattachWaiter? = null,
    )

    private fun captureViewportLayoutAnchor(): ContinuousViewportLayoutAnchor? {
        val first = layoutManager.findFirstVisibleItemPosition()
            .takeIf { it != RecyclerView.NO_POSITION }
            ?: return null
        val view = layoutManager.findViewByPosition(first) ?: return null
        return ContinuousViewportLayoutAnchor(first, layoutManager.getDecoratedTop(view))
    }

    private fun captureReadingAnchorLayout(): ContinuousReadingAnchorLayout? {
        if (disposed || recyclerView.height <= 0 || recyclerView.width <= 0) return null
        val viewportY = readingAnchorOffsetPx()
        val child = recyclerView.findChildViewUnder(recyclerView.width / 2f, viewportY.toFloat()) ?: return null
        val index = recyclerView.getChildAdapterPosition(child)
            .takeIf { it != RecyclerView.NO_POSITION }
            ?: return null
        val materialization = attachedMaterializations[index] ?: return null
        val resource = materialization.resource
        if (materialization.target.index != index ||
            materialization.target.layoutGeneration != layoutGeneration ||
            materialization.target.resourceGeneration != resource.generation ||
            resource.parent !== child ||
            !child.isAttachedToWindow ||
            !resource.isAttachedToWindow ||
            resourceWindow.withLiveResource(index, resource.generation) { it } !== resource
        ) return null

        return ContinuousReadingAnchorLayout(
            index = index,
            layoutGeneration = layoutGeneration,
            resourceGeneration = resource.generation,
            viewportY = viewportY,
            localOffsetPx = viewportY - layoutManager.getDecoratedTop(child),
        )
    }

    private companion object {
        const val RESOURCE_VIEW_TYPE = 1
        const val MAX_NON_VISIBLE_PRELOAD_RESOURCES = ContinuousEpubResourceWindow.MAX_NON_VISIBLE_PRELOAD_RESOURCES
        const val LAZY_PRELOAD_RADIUS = 1
        const val ESTIMATED_RESOURCE_HEIGHT_PX = 800
        const val MATCH_PARENT = ViewGroup.LayoutParams.MATCH_PARENT
        const val READING_ANCHOR_FRACTION = 0.25f
        const val INITIAL_VIEWPORT_TIMEOUT_MS = 30_000L
    }
}

/** Pure policy used by the host and deterministic tests; it never expands beyond radius one. */
internal fun lazyPreloadIndices(first: Int, last: Int, size: Int, enabled: Boolean): List<Int> {
    if (!enabled || size <= 0) return emptyList()
    return buildList(2) {
        (first - 1).takeIf { it >= 0 && it < size }?.let(::add)
        (last + 1).takeIf { it >= 0 && it < size }?.let(::add)
    }
}

internal fun continuousAnchorViewportDelta(capturedY: Double, actualY: Double): Double? {
    if (!capturedY.isFinite() || !actualY.isFinite()) return null
    return (actualY - capturedY).takeIf { it.isFinite() }
}

internal fun continuousAnchorViewportMatches(deltaPx: Double): Boolean =
    deltaPx.isFinite() && abs(deltaPx) <= CONTINUOUS_ANCHOR_VIEWPORT_TOLERANCE_PX

internal fun continuousAnchorCorrectionOffset(
    currentDecoratedTop: Int,
    paddingTop: Int,
    viewportDeltaPx: Double,
): Int? {
    if (!viewportDeltaPx.isFinite()) return null
    return currentDecoratedTop - paddingTop - viewportDeltaPx.roundToInt()
}

private const val CONTINUOUS_ANCHOR_VIEWPORT_TOLERANCE_PX = 4.0

internal data class ResourceLayoutMeasurement(
    val index: Int,
    val heightPx: Long,
    val layoutGeneration: Int,
    val resourceGeneration: Long,
    val measurementGeneration: Long,
    val measurementEpoch: Long = 0L,
    val appliedCssToken: Long? = null,
)

/** Holds only current-generation, non-target geometry until fresh semantics commit. */
internal class ContinuousFreshLocatorObservationBarrier {
    private var observation: FreshLocatorObservation? = null
    private val pendingMeasurements = mutableMapOf<Int, ResourceLayoutMeasurement>()

    fun begin(target: ContinuousReflowTarget, transaction: ContinuousGeometryReflowTransaction) {
        check(observation == null) { "Only one fresh Locator observation may be active" }
        observation = FreshLocatorObservation(target, transaction)
    }

    fun shouldDefer(
        measurement: ResourceLayoutMeasurement,
        isTargetStillProtected: (ContinuousReflowTarget, ContinuousGeometryReflowTransaction) -> Boolean,
    ): Boolean {
        val active = observation ?: return false
        return measurement.index != active.target.index &&
            measurement.layoutGeneration == active.target.layoutGeneration &&
            active.transaction.restored && !active.transaction.terminal &&
            isTargetStillProtected(active.target, active.transaction)
    }

    fun defer(measurement: ResourceLayoutMeasurement) {
        pendingMeasurements[measurement.index] = measurement
    }

    fun pendingIndices(): Set<Int> = pendingMeasurements.keys.toSet()

    fun finish(transaction: ContinuousGeometryReflowTransaction): List<ResourceLayoutMeasurement> {
        if (observation?.transaction !== transaction) return emptyList()
        observation = null
        return pendingMeasurements.values.toList().also { pendingMeasurements.clear() }
    }

    fun clear() {
        observation = null
        pendingMeasurements.clear()
    }

    private data class FreshLocatorObservation(
        val target: ContinuousReflowTarget,
        val transaction: ContinuousGeometryReflowTransaction,
    )
}
internal data class ContinuousReflowTarget(
    val index: Int,
    val layoutGeneration: Int,
    val resourceGeneration: Long,
)

internal fun pendingReflowTargetForMeasurement(
    measurement: ResourceLayoutMeasurement,
    pendingTargets: Set<ContinuousReflowTarget>,
    currentLayoutGeneration: Int,
    isLiveResource: (index: Int, resourceGeneration: Long) -> Boolean,
): ContinuousReflowTarget? {
    val target = ContinuousReflowTarget(
        index = measurement.index,
        layoutGeneration = measurement.layoutGeneration,
        resourceGeneration = measurement.resourceGeneration,
    )
    return target.takeIf {
        it in pendingTargets &&
            it.layoutGeneration == currentLayoutGeneration &&
            isLiveResource(it.index, it.resourceGeneration)
    }
}

/** Generation-bound TRUE_READY + first-valid-measurement contract for a reflow target. */
internal class ContinuousReflowTargetBarrier {
    private val ready = mutableSetOf<ContinuousReflowTarget>()
    private val measured = mutableSetOf<ContinuousReflowTarget>()
    private val measurementLayoutPass = mutableMapOf<ContinuousReflowTarget, Long>()
    private val attachedLayout = mutableSetOf<ContinuousReflowTarget>()

    fun markReady(target: ContinuousReflowTarget) { ready += target }
    fun markMeasured(target: ContinuousReflowTarget, layoutPass: Long = 0L) {
        measured += target
        // The next RecyclerView pass is the first one allowed to settle this measurement.
        measurementLayoutPass[target] = layoutPass + 1
        attachedLayout -= target
    }
    /** Reuses a verified attached layout only when all parent dimensions are unchanged. */
    fun markUnchangedGeometry(target: ContinuousReflowTarget, layoutPass: Long, isAttached: (ContinuousReflowTarget) -> Boolean): Boolean {
        if (target !in ready || !isAttached(target)) return false
        measured += target
        measurementLayoutPass[target] = layoutPass
        attachedLayout += target
        return true
    }
    fun markAttachedLayouts(layoutPass: Long = Long.MAX_VALUE, isAttached: (ContinuousReflowTarget) -> Boolean) {
        (ready + measured).filter { target ->
            layoutPass >= (measurementLayoutPass[target] ?: Long.MAX_VALUE) && isAttached(target)
        }.forEach { attachedLayout += it }
    }
    fun isReady(target: ContinuousReflowTarget): Boolean =
        target in ready && target in measured && target in attachedLayout
    fun invalidate(target: ContinuousReflowTarget) {
        ready -= target
        measured -= target
        measurementLayoutPass -= target
        attachedLayout -= target
    }
    fun clear() {
        ready.clear()
        measured.clear()
        measurementLayoutPass.clear()
        attachedLayout.clear()
    }
}

internal sealed class ContinuousReflowRestoreOutcome {
    data object Ready : ContinuousReflowRestoreOutcome()
    data class Restored(val readingOrderIndex: Int, val observedLocator: Locator) : ContinuousReflowRestoreOutcome()
    data object TargetNotReady : ContinuousReflowRestoreOutcome()
    data object SemanticRestoreFailed : ContinuousReflowRestoreOutcome()
    data object VisibilityMismatch : ContinuousReflowRestoreOutcome()
    data object Cancelled : ContinuousReflowRestoreOutcome()
}

/**
 * Initial restore owns the parent viewport until its exact materialized target
 * terminalizes. Neighbor WebViews may continue normal preload/bootstrap work,
 * but their callbacks cannot publish a Locator or replace the target geometry.
 */
internal class ContinuousInitialRestoreAuthorityGate {
    private var pendingIndex: Int? = null
    private var target: ContinuousReflowTarget? = null
    private var restoreRequested = false
    private var restoreCommitted = false

    fun begin(index: Int) {
        pendingIndex = index
        target = null
        restoreRequested = false
        restoreCommitted = false
    }

    fun materialize(candidate: ContinuousReflowTarget): Boolean {
        if (pendingIndex != candidate.index) return false
        target = candidate
        return true
    }

    fun geometryTarget(): ContinuousReflowTarget? = target
    fun isPendingIndex(index: Int): Boolean = pendingIndex == index && target == null
    fun isRestoreRequested(): Boolean = restoreRequested
    fun markRestoreRequested(candidate: ContinuousReflowTarget): Boolean {
        if (target != candidate) return false
        restoreRequested = true
        restoreCommitted = false
        return true
    }
    fun isRestoreCommitted(): Boolean = restoreCommitted
    fun markRestoreCommitted(candidate: ContinuousReflowTarget): Boolean {
        if (target != candidate) return false
        restoreCommitted = true
        return true
    }
    fun blocksViewportPublication(): Boolean = pendingIndex != null
    fun isCurrentTarget(candidate: ContinuousReflowTarget): Boolean = target == candidate

    fun finish(candidate: ContinuousReflowTarget?) {
        if (candidate == null || target == candidate) {
            pendingIndex = null
            target = null
            restoreRequested = false
            restoreCommitted = false
        }
    }
}

internal class ContinuousInitialRestoreReadyEvents {
    private val pending = linkedMapOf<Pair<Int, Long>, ContinuousReflowTarget>()

    fun defer(target: ContinuousReflowTarget) {
        pending[target.index to target.resourceGeneration] = target
    }

    fun takeReady(
        restoreGateBlocksPublication: Boolean,
        isCurrent: (ContinuousReflowTarget) -> Boolean,
    ): List<ContinuousReflowTarget> {
        if (restoreGateBlocksPublication) return emptyList()
        val ready = pending.values.filter(isCurrent)
        pending.clear()
        return ready
    }

    fun clear() {
        pending.clear()
    }
}

/** Semantic identity is authoritative; progression only bounds a locator without DOM detail. */
internal fun semanticLocatorsConverge(anchor: Locator, observed: Locator): Boolean {
    if (anchor.href.removeFragment() != observed.href.removeFragment()) return false
    val anchorSelector = anchor.locations["cssSelector"] as? String
    val observedSelector = observed.locations["cssSelector"] as? String
    if (anchorSelector != null || observedSelector != null) {
        // A CSS selector is authoritative only when both locators carry the
        // same representation. A fragment-only request must be checked by
        // its fragment/range semantics, never rejected as CSS inequality.
        if (anchorSelector == null || observedSelector == null) return false
        return anchorSelector == observedSelector
    }
    val anchorText = anchor.text.highlight?.trim()?.takeIf(String::isNotEmpty)
    val observedText = observed.text.highlight?.trim()?.takeIf(String::isNotEmpty)
    if (anchorText != null || observedText != null) return anchorText != null && anchorText == observedText
    val anchorFragment = anchor.locations.fragments.firstOrNull()
    val observedFragment = observed.locations.fragments.firstOrNull()
    if (anchorFragment != null || observedFragment != null) return anchorFragment != null && anchorFragment == observedFragment
    val anchorProgression = anchor.locations.progression ?: return false
    val observedProgression = observed.locations.progression ?: return false
    return abs(anchorProgression - observedProgression) <= 0.02
}

/** Initial Locators without selector or quote must prove their own resolved DOM Range. */
internal fun initialRestoreRequiresRequestedRangeAnchor(
    requested: Locator,
    observed: Locator,
): Boolean {
    val requestedFragment = requested.locations.fragments.firstOrNull()
    val observedFragment = observed.locations.fragments.firstOrNull()
    return requested.href.removeFragment() == observed.href.removeFragment() &&
        (observedFragment == null || observedFragment == requestedFragment) &&
        (requestedFragment != null || requested.locations.progression?.let { it.isFinite() && it in 0.0..1.0 } == true) &&
        requested.locations["cssSelector"] == null &&
        requested.text.highlight.isNullOrBlank()
}

/**
 * The direct requested-Range result is valid only for the exact materialized
 * resource and the unchanged anchor captured after the accepted geometry barrier.
 */
internal fun isInitialRestoreRangeAnchorCurrent(
    target: ContinuousReflowTarget,
    anchor: EpubContinuousLocatorAnchor,
    currentAnchor: EpubContinuousLocatorAnchor?,
    geometryReady: Boolean,
    rangeAtAnchor: Boolean,
): Boolean =
    geometryReady &&
        rangeAtAnchor &&
        anchor.readingOrderIndex == target.index &&
        anchor.resourceGeneration == target.resourceGeneration &&
        anchor.layoutGeneration == target.layoutGeneration &&
        currentAnchor == anchor

/**
 * At scroll origin the first item cannot move below the viewport start.
 * A target above the usual anchor is then already visible at its own local Y.
 */
internal fun isInitialRestorePublicationStartLocator(locations: Locator.Locations, text: Locator.Text): Boolean =
    locations.progression == 0.0 &&
        locations.fragments.isEmpty() &&
        locations["cssSelector"] == null &&
        locations["cfi"] == null &&
        locations["partialCfi"] == null &&
        locations["continuousDomAnchor"] == null &&
        text.highlight.isNullOrBlank()

/** Only progression-only Locators may use the separately proven native top clamp. */
internal fun isInitialRestoreTopBoundaryLocator(locations: Locator.Locations, text: Locator.Text): Boolean =
    locations.progression?.let { it.isFinite() && it in 0.0..1.0 } == true &&
        locations.fragments.isEmpty() &&
        locations["cssSelector"] == null &&
        locations["cfi"] == null &&
        locations["partialCfi"] == null &&
        locations["continuousDomAnchor"] == null &&
        text.highlight.isNullOrBlank()

internal fun initialRestoreStartBoundaryRangeY(
    targetIndex: Int,
    targetDocumentOffset: Double,
    resourceTopPx: Int,
    viewportPaddingTopPx: Int,
    visibleHeightPx: Int,
    viewportAnchorYPx: Double,
    canScrollTowardStart: Boolean,
): Double? = targetDocumentOffset.takeIf {
    targetIndex == 0 &&
        !canScrollTowardStart &&
        resourceTopPx == viewportPaddingTopPx &&
        it.isFinite() && it >= 0.0 && it < visibleHeightPx &&
        resourceTopPx + it < viewportAnchorYPx
}

internal fun isTargetReadingAnchor(
    target: ContinuousReflowTarget,
    anchor: EpubContinuousLocatorAnchor,
): Boolean =
    anchor.readingOrderIndex == target.index &&
        anchor.resourceGeneration == target.resourceGeneration &&
        anchor.layoutGeneration == target.layoutGeneration
internal data class ContinuousViewportLayoutAnchor(val index: Int, val offsetPx: Int)

internal data class ContinuousReadingAnchorLayout(
    val index: Int,
    val layoutGeneration: Int,
    val resourceGeneration: Long,
    val viewportY: Int,
    val localOffsetPx: Int,
)

internal sealed interface ContinuousMeasurementScrollPlan {
    data class ReflowTarget(val target: ContinuousReflowTarget) : ContinuousMeasurementScrollPlan
    data class PreserveAnchor(val anchor: ContinuousViewportLayoutAnchor) : ContinuousMeasurementScrollPlan
    data object KeepCurrent : ContinuousMeasurementScrollPlan
}

internal fun continuousMeasurementScrollPlan(
    reflowTarget: ContinuousReflowTarget?,
    measurementIndex: Int,
    readingAnchor: ContinuousReadingAnchorLayout?,
    fallbackAnchor: ContinuousViewportLayoutAnchor?,
    currentLayoutGeneration: Int,
    isLiveResource: (Int, Long) -> Boolean,
): ContinuousMeasurementScrollPlan {
    if (reflowTarget != null) return ContinuousMeasurementScrollPlan.ReflowTarget(reflowTarget)

    val currentAnchor = readingAnchor?.takeIf {
        it.layoutGeneration == currentLayoutGeneration &&
            isLiveResource(it.index, it.resourceGeneration)
    }
    if (currentAnchor != null) {
        if (measurementIndex > currentAnchor.index) return ContinuousMeasurementScrollPlan.KeepCurrent
        return ContinuousMeasurementScrollPlan.PreserveAnchor(
            ContinuousViewportLayoutAnchor(
                index = currentAnchor.index,
                offsetPx = currentAnchor.viewportY - currentAnchor.localOffsetPx,
            ),
        )
    }

    return preservedContinuousViewportAnchor(measurementIndex, fallbackAnchor)
        ?.let(ContinuousMeasurementScrollPlan::PreserveAnchor)
        ?: ContinuousMeasurementScrollPlan.KeepCurrent
}

internal fun preservedContinuousViewportAnchor(
    updatedResourceIndex: Int,
    anchor: ContinuousViewportLayoutAnchor?,
): ContinuousViewportLayoutAnchor? = anchor?.takeIf { updatedResourceIndex < it.index }

/** Converts the DOM's CSS-pixel scrollHeight into the Android View coordinate system once. */
internal fun continuousCssHeightToLayoutPx(
    cssHeightPx: Long,
    pixelsPerCssPixel: Double,
): Long? {
    if (cssHeightPx <= 0L || !pixelsPerCssPixel.isFinite() || pixelsPerCssPixel <= 0.0) return null
    val scaled = cssHeightPx.toDouble() * pixelsPerCssPixel
    if (!scaled.isFinite() || scaled > Int.MAX_VALUE.toDouble()) return null
    return ceil(scaled).toLong().coerceAtLeast(1L)
}

/** Converts a semantic document-local CSS offset into the parent layout coordinate system. */
internal fun continuousCssOffsetToLayoutPx(
    cssOffsetPx: Double,
    pixelsPerCssPixel: Double,
): Double? {
    if (!cssOffsetPx.isFinite() || cssOffsetPx < 0.0 ||
        !pixelsPerCssPixel.isFinite() || pixelsPerCssPixel <= 0.0
    ) return null
    return (cssOffsetPx * pixelsPerCssPixel).takeIf(Double::isFinite)
}

/**
 * `WebView.evaluateJavascript` serializes JavaScript strings as JSON strings,
 * while JavaScript booleans are returned as the unquoted literals `true` and
 * `false`. Keep this probe boolean so a real Readium runtime is not mistaken
 * for a missing one merely because of callback serialization.
 */
internal const val READIUM_RUNTIME_PROBE =
    "typeof window.readium === 'object' && window.readium !== null && window.readium.isReflowable === true"

internal fun isReadiumRuntimeProbeSuccess(result: String): Boolean = result == "true"

/**
 * The raw, zero-argument calls exported by the resource-local Android bridge.
 *
 * The HTML injector is the producer of these exact method names. Keeping this
 * representation at the JS-interface boundary lets deterministic callers
 * deliver the same external event without gaining any readiness authority.
 */
internal data class ContinuousRawBootstrapBridgeEvent(
    val methodName: String,
    val arguments: List<String> = emptyList(),
)

/**
 * Parses and dispatches the actual Android-JS-interface call into the existing
 * bootstrap handler. It owns neither bootstrap state nor a WebView lifecycle.
 */
internal class ContinuousBootstrapBridgeEventDispatcher(
    private val onScriptLoaded: () -> Unit,
    private val onScriptFailed: () -> Unit,
) {
    fun dispatch(rawEvent: ContinuousRawBootstrapBridgeEvent): Boolean {
        if (rawEvent.arguments.isNotEmpty()) return false
        when (rawEvent.methodName) {
            BOOTSTRAP_SCRIPT_LOADED_METHOD -> onScriptLoaded()
            BOOTSTRAP_SCRIPT_FAILED_METHOD -> onScriptFailed()
            else -> return false
        }
        return true
    }

    companion object {
        const val BOOTSTRAP_SCRIPT_LOADED_METHOD = "onBootstrapScriptLoaded"
        const val BOOTSTRAP_SCRIPT_FAILED_METHOD = "onBootstrapScriptFailed"
    }
}

/** Generation-bound gate for the real Readium bootstrap acknowledgement. */
internal class ContinuousReadiumBootstrapState(
    private val index: Int,
    private val generation: Long,
) {
    private enum class State { LOADING, READY, FAILED, DISPOSED }
    private var state = State.LOADING
    private var documentFinished = false
    private var scriptLoaded = false

    val canRunCommands: Boolean get() = state == State.READY
    val isLoading: Boolean get() = state == State.LOADING
    val shouldVerifyRuntime: Boolean get() = state == State.LOADING && documentFinished && scriptLoaded

    fun onDocumentFinished(index: Int, generation: Long): Boolean =
        accept(index, generation) && run { documentFinished = true; true }

    fun onScriptLoaded(index: Int, generation: Long): Boolean =
        accept(index, generation) && run { scriptLoaded = true; true }

    fun onRuntimeVerified(index: Int, generation: Long, readiumExists: Boolean): Boolean {
        if (!accept(index, generation) || !documentFinished || !scriptLoaded) return false
        state = if (readiumExists) State.READY else State.FAILED
        return true
    }

    fun onScriptFailed(index: Int, generation: Long): Boolean {
        if (!accept(index, generation)) return false
        state = State.FAILED
        return true
    }

    fun dispose() { state = State.DISPOSED }

    private fun accept(index: Int, generation: Long): Boolean =
        state == State.LOADING && this.index == index && this.generation == generation
}
internal data class ContinuousVisibleResourceRange(val firstVisibleIndex: Int, val lastVisibleIndex: Int, val hostScrollOffsetPx: Long)
internal data class ContinuousAnchorLocator(
    val index: Int,
    val resourceGeneration: Long,
    val layoutGeneration: Int,
    val localY: Double,
    val locator: Locator,
    val viewportY: Double = localY,
    val documentYLayoutPx: Double? = null,
    val targetViewportY: Double = viewportY,
)
internal data class ContinuousResolvedLocatorPoint(
    val documentYLayoutPx: Double,
    val viewportY: Double,
    val semanticAnchorExact: Boolean = false,
    val anchorIdentityId: String? = null,
    val anchorCharacterOffset: Int? = null,
)
internal enum class ContinuousResourcePinReason { SELECTION, ACTION_MODE, PENDING_LOCATOR, NAVIGATION_TARGET, GEOMETRY_REFLOW }

internal interface ContinuousResourceViewFactory {
    val diagnosticSessionId: String
    fun create(context: Context, publication: Publication, link: Link, index: Int, layoutGeneration: Int, resourceGeneration: Long, sessionInstanceId: String, hostId: String, onMeasurement: (ResourceLayoutMeasurement) -> Unit): ContinuousResourceView
}

internal class ReadiumServedContinuousResourceFactory(
    private val servedUrl: (Publication, Link) -> String,
    private val configureReadiumWebView: (R2BasicWebView, Publication, Link, Long) -> Unit,
    private val applyReadiumCss: (R2BasicWebView, Int, Long, Long, (Boolean) -> Unit) -> Unit,
    private val sessionInstanceId: String = "unavailable",
) : ContinuousResourceViewFactory {
    override val diagnosticSessionId: String = sessionInstanceId
    override fun create(context: Context, publication: Publication, link: Link, index: Int, layoutGeneration: Int, resourceGeneration: Long, sessionInstanceId: String, hostId: String, onMeasurement: (ResourceLayoutMeasurement) -> Unit) =
        ContinuousResourceView(context, index, layoutGeneration, resourceGeneration, servedUrl(publication, link), configureReadiumWebView, applyReadiumCss, publication, link, onMeasurement, sessionInstanceId, hostId)
}

@SuppressLint("SetJavaScriptEnabled", "AddJavascriptInterface")
internal class ContinuousResourceView(
    context: Context,
    val index: Int,
    layoutGeneration: Int,
    private val resourceGeneration: Long,
    private val url: String,
    private val configure: (R2BasicWebView, Publication, Link, Long) -> Unit,
    private val applyReadiumCss: (R2BasicWebView, Int, Long, Long, (Boolean) -> Unit) -> Unit,
    private val publication: Publication,
    private val link: Link,
    private val onMeasurement: (ResourceLayoutMeasurement) -> Unit,
    private val sessionInstanceId: String,
    private val hostId: String,
    javascriptExecutor: R2JavascriptExecutor? = null,
) : FrameLayout(context) {
    @Volatile private var layoutGeneration = layoutGeneration
    @Volatile private var measurementEpoch = 0L
    @Volatile private var cssAppliedForEpoch = false
    @Volatile private var cssApplyPending = false
    @Volatile private var readiumRuntimeVerified = false
    @Volatile private var bootstrapReadyPublished = false
    private var disposed = false
    private var measurementGeneration = AtomicLong(0)
    internal val reportedMeasurementGenerationForOpen: Long get() = measurementGeneration.get()
    // An unknown-content estimate, never a viewport-sized minimum.
    private var lastHeightPx = ESTIMATED_RESOURCE_HEIGHT_PX
    @Volatile private var lastReportedHeightPx: Long? = null
    private data class PendingEpochMeasurement(val height: Long, val layout: Int, val epoch: Long, val token: Long)
    private var pendingEpochMeasurement: PendingEpochMeasurement? = null
    private val bootstrapState = ContinuousReadiumBootstrapState(index, resourceGeneration)
    private val requestedDecorations = mutableMapOf<String, List<Decoration>>()
    private val decorationTemplates = mutableMapOf<String, HtmlDecorationTemplates>()
    private val measurementDispatcher = ContinuousMeasurementDispatcher()
    private val cssMutationGate = ContinuousCssMutationGate()
    private val appliedLayoutState = ContinuousAppliedLayoutState()
    private var cssStateDiagnosticListener: ((EpubContinuousReflowDiagnosticEvent) -> Unit)? = null
    internal val hasPendingCssGeometry: Boolean get() = appliedLayoutState.snapshot().let { it.pending && it.applied?.preferenceGeneration != null } ||
        (cssOwner?.preferenceGeneration != null && cssMutationGate.hasMutationObligation(currentCssOwnerToken))

    internal fun mustFinishCssGeometry(preferenceGeneration: Long): Boolean =
        (cssOwner?.preferenceGeneration == preferenceGeneration && cssMutationGate.hasMutationObligation(currentCssOwnerToken)) ||
            appliedLayoutState.snapshot().let { it.pending && it.applied?.preferenceGeneration == preferenceGeneration }

    internal fun setCssStateDiagnosticListener(listener: (EpubContinuousReflowDiagnosticEvent) -> Unit) {
        cssStateDiagnosticListener = listener
    }

    internal fun configureTextRenderDiagnostics(locator: Locator?) {
        sampleTextRenderDiagnostics("cancel")
        textRenderDiagnosticOwner = null
        textRenderContext = locator?.let {
            JSONObject().put("locator", JSONObject().put("locations", it.toJSON().optJSONObject("locations") ?: JSONObject())).toString()
        }
    }

    private var textRenderMeasurementToken: Long? = null
    private var textRenderContext: String? = null
    private var textRenderDiagnosticOwner: ContinuousCssMutationOwner? = null

    internal fun receiveTextRenderDiagnostic(token: Long, payload: String) {
        val owner = textRenderDiagnosticOwner?.takeIf { it.token == token } ?: return
        val fields = continuousTextRenderDiagnosticFields(payload) ?: return
        measurementDispatcher.dispatch {
            // A completed generation can report its queued read-only sample after
            // ambient handoff, but never after replacement/cancellation/new layout.
            if (disposed || textRenderDiagnosticOwner != owner || layoutGeneration != owner.layoutGeneration ||
                resourceGeneration != owner.resourceGeneration) return@dispatch
            cssStateDiagnosticListener?.invoke(EpubContinuousReflowDiagnosticEvent(
                kind = fields["kind"] as String, context = null,
                preferenceGeneration = owner.preferenceGeneration, transactionGeneration = owner.transactionGeneration,
                layoutGeneration = owner.layoutGeneration, resourceGeneration = owner.resourceGeneration,
                readingOrderIndex = index, result = fields["result"] as? String,
                snapshotStage = fields["snapshotStage"] as? String,
                semanticAnchorFields = fields - setOf("kind", "result", "snapshotStage"),
            ))
        }
    }

    private fun sampleTextRenderDiagnostics(stage: String, token: Long = currentCssOwnerToken) {
        if (textRenderContext == null || disposed) return
        try {
            webView.runJavaScript("if(readium.textRenderDiagnostic){readium.textRenderDiagnostic('$stage',$token);}")
        } catch (_: RuntimeException) {
            // Read-only sampling must not turn an accepted measurement into failure.
        }
    }

    private fun emitCssState(result: String, owner: ContinuousCssMutationOwner, fields: Map<String, Any> = emptyMap()) {
        val event = EpubContinuousReflowDiagnosticEvent(
            kind = "css_generation_state", context = null, result = result,
            preferenceGeneration = owner.preferenceGeneration, transactionGeneration = owner.transactionGeneration,
            layoutGeneration = owner.layoutGeneration, resourceGeneration = owner.resourceGeneration,
            readingOrderIndex = index,
            semanticAnchorFields = fields + mapOf("cssGeneration" to owner.token),
        )
        measurementDispatcher.dispatch { cssStateDiagnosticListener?.invoke(event) }
    }

    internal fun recordAppliedCss(ownerToken: Long) {
        val physicalOwner = cssOwner?.takeIf { it.token == ownerToken && cssMutationGate.isCurrent(ownerToken) } ?: return
        val before = appliedLayoutState.snapshot()
        // Pure style-only requests retain the existing lightweight path. An
        // ambient reapply must nevertheless retain any outstanding layout debt.
        if (physicalOwner.transactionGeneration == null && !before.pending) {
            cssMutationGate.geometryCommitted(ownerToken)
            return
        }
        val owner = if (physicalOwner.preferenceGeneration == null && before.pending) {
            physicalOwner.copy(preferenceGeneration = before.applied?.preferenceGeneration,
                transactionGeneration = before.applied?.transactionGeneration)
        } else physicalOwner
        if (before.applied == owner) return
        val transferred = appliedLayoutState.applied(owner)
        lastReportedHeightPx = null
        if (transferred != null) emitCssState("ownership_transferred", owner, buildMap {
            transferred.preferenceGeneration?.let { put("fromPreferenceGeneration", it) }
            owner.preferenceGeneration?.let { put("toPreferenceGeneration", it) }
            put("reason", "newer_css_applied")
        })
        emitCssState("applied", owner)
    }

    internal fun requestCurrentCssMeasurement() {
        val owner = cssOwner ?: return
        if (disposed || !cssMutationGate.isCurrent(owner.token)) return
        val script = """(function(){
            var gate=window.BiblioLifeContinuousMeasurement;
            if(!gate || !gate.beginCssApply(${owner.token})){return null;}
            try {
                var root=document.documentElement,body=document.body;
                if(!body){return null;}
                return Math.ceil(Math.max(1,body.scrollHeight,body.offsetHeight,
                    body.getBoundingClientRect().bottom-root.getBoundingClientRect().top));
            } finally {gate.endCssApply(${owner.token});}
        })()""".trimIndent()
        webView.executeJavascript(script) { raw ->
            raw.toLongOrNull()?.takeIf { it > 0 }?.let {
                receiveMeasurement(it, owner.layoutGeneration, owner.measurementEpoch, owner.token)
            }
        }
    }

    internal fun commitMeasuredGeometry(measurement: ResourceLayoutMeasurement) {
        if (!accepts(measurement)) return
        applyMeasuredHeight(measurement.heightPx)
        if (appliedLayoutState.commit(measurement)) {
            cssMutationGate.geometryCommitted(currentCssOwnerToken)
            appliedLayoutState.snapshot().applied?.let { emitCssState("geometry_committed", it, mapOf("committedHeightPx" to measurement.heightPx)) }
        }
    }

    internal fun canAcknowledgeUnchangedGeometry(measurement: ResourceLayoutMeasurement): Boolean =
        accepts(measurement) && measurement.appliedCssToken != null && currentHeightPx == measurement.heightPx &&
            appliedLayoutState.snapshot().let { it.applied?.token == measurement.appliedCssToken && it.measuredHeightPx == measurement.heightPx }

    internal fun acknowledgeUnchangedGeometry(measurement: ResourceLayoutMeasurement): Boolean {
        if (!canAcknowledgeUnchangedGeometry(measurement) || !appliedLayoutState.commit(measurement)) return false
        cssMutationGate.geometryCommitted(currentCssOwnerToken)
        appliedLayoutState.snapshot().applied?.let {
            emitCssState("geometry_committed", it, mapOf("committedHeightPx" to measurement.heightPx))
        }
        return true
    }

    internal fun emitCssConsistency() {
        val state = appliedLayoutState.snapshot()
        val applied = state.applied ?: return
        if (applied.preferenceGeneration == null) return
        cssStateDiagnosticListener?.invoke(EpubContinuousReflowDiagnosticEvent(
            kind = "reflow_consistency", context = null, result = if (!state.pending && state.committedHeightPx == currentHeightPx) "coherent" else "pending_geometry",
            preferenceGeneration = applied.preferenceGeneration, layoutGeneration = applied.layoutGeneration,
            resourceGeneration = resourceGeneration, readingOrderIndex = index,
            semanticAnchorFields = buildMap {
                put("activeCssPreferenceGeneration", applied.preferenceGeneration)
                put("activeCssLayoutGeneration", applied.layoutGeneration)
                state.committed?.preferenceGeneration?.let { put("committedGeometryPreferenceGeneration", it) }
                state.committed?.layoutGeneration?.let { put("committedGeometryLayoutGeneration", it) }
                put("cssHeightMeasurementKnown", state.measuredHeightPx != null)
                state.measuredHeightPx?.let { put("webViewHeightPx", it) }
                put("parentResourceHeightPx", currentHeightPx)
                put("coherent", !state.pending && state.committedHeightPx == currentHeightPx)
            },
        ))
    }
    @Volatile private var cssOwner: ContinuousCssMutationOwner? = null
    private data class DeferredBootstrapCss(
        val owner: ContinuousCssMutationOwner,
        val onApplied: (Boolean) -> Unit,
    )
    private var deferredBootstrapCss: DeferredBootstrapCss? = null
    // Distinguish revoked deferred work from an ordinary first bootstrap,
    // which is the only case allowed to apply ambient CSS.
    private var deferredBootstrapCssRevoked = false
    val currentHeightPx: Long get() = lastHeightPx
    val generation: Long get() = resourceGeneration
    val canFindLocator: Boolean get() = !disposed && bootstrapState.canRunCommands
    internal val isBootstrapPending: Boolean get() = !disposed && bootstrapState.isLoading
    private val webView = if (javascriptExecutor == null) R2BasicWebView(context) else R2BasicWebView(context, javascriptExecutor = javascriptExecutor)
    internal val webViewIdentity: Int get() = System.identityHashCode(webView)
    internal val webViewForDiagnostics: View get() = webView
    private val bootstrapBridgeDispatcher = ContinuousBootstrapBridgeEventDispatcher(
        onScriptLoaded = ::onBootstrapScriptLoaded,
        onScriptFailed = ::onBootstrapScriptFailed,
    )
    internal var onPageReady: (() -> Unit)? = null
    internal var onPageFailed: (() -> Unit)? = null
    private var reflowDiagnosticLifecycleListener: ((String) -> Unit)? = null
    private var reflowDiagnosticAttached = false
    internal val currentLayoutGeneration: Int get() = layoutGeneration
    internal val currentMeasurementEpoch: Long get() = measurementEpoch
    internal val cssAppliedForCurrentEpoch: Boolean get() = cssAppliedForEpoch
    internal val cssApplicationPending: Boolean get() = cssApplyPending
    internal val currentCssOwnerToken: Long get() = cssOwner?.token ?: Long.MIN_VALUE

    internal fun setReflowDiagnosticLifecycleListener(listener: ((String) -> Unit)?) {
        reflowDiagnosticLifecycleListener = listener
    }

    init {
        BiblioLifeOpenTimingDiagnostics.lifecycle("WEBVIEW_CREATE", instanceId = sessionInstanceId, sessionId = sessionInstanceId, hostId = hostId, generation = layoutGeneration.toLong(), resourceGeneration = resourceGeneration, index = index, webViewId = webViewIdentity)
        webView.settings.javaScriptEnabled = true
        configure(webView, publication, link, resourceGeneration)
        webView.addJavascriptInterface(MeasurementBridge(), "BiblioLifeContinuousMeasurement")
        webView.addJavascriptInterface(ReadiumBootstrapBridge(), "BiblioLifeContinuousReadium")
        webView.addJavascriptInterface(PageLifecycleDiagnosticsBridge(), "BiblioLifePageLifecycleDiagnostics")
        webView.webViewClient = object : WebViewClientCompat() {
            override fun onPageStarted(view: WebView, startedUrl: String, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, startedUrl, favicon)
                BiblioLifeOpenTimingDiagnostics.internal("W1_NAVIGATION_START", index, webViewIdentity)
            }
            override fun onPageFinished(view: WebView, finishedUrl: String) {
                super.onPageFinished(view, finishedUrl)
                bootstrapState.onDocumentFinished(index, resourceGeneration)
                BiblioLifeOpenTimingDiagnostics.internal("W2_DOCUMENT_AVAILABLE", index, webViewIdentity)
                BiblioLifeOpenTimingDiagnostics.pageLifecycle("R3_ON_PAGE_FINISHED", index, webViewIdentity)
                completeReadiumBootstrapIfReady()
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = (view as? R2BasicWebView)?.shouldOverrideUrlLoading(request) ?: false
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                BiblioLifeOpenTimingDiagnostics.subresourceRequest(index, webViewIdentity, request.url, request.isForMainFrame)
                if (request.isForMainFrame) {
                    return BiblioLifeOpenTimingDiagnostics.interceptMainDocument(index, webViewIdentity) {
                        (view as? R2BasicWebView)?.shouldInterceptRequest(view, request)
                    }
                }
                return (view as? R2BasicWebView)?.shouldInterceptRequest(view, request)
            }
            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                super.onReceivedHttpError(view, request, response)
                if (!request.isForMainFrame) BiblioLifeOpenTimingDiagnostics.requestFailure(index, webViewIdentity, "http", request.url, response.statusCode)
            }
        }
        addView(webView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        BiblioLifeOpenTimingDiagnostics.internal("W0_LOAD_CALL_ENTER", index, webViewIdentity)
        webView.loadUrl(url)
        BiblioLifeOpenTimingDiagnostics.targetLoadBegin(index)
    }

    private inner class PageLifecycleDiagnosticsBridge {
        @JavascriptInterface fun domContentLoaded() {
            BiblioLifeOpenTimingDiagnostics.pageLifecycle("R1_DOM_CONTENT_LOADED", index, webViewIdentity)
        }
        @JavascriptInterface fun windowLoad() {
            BiblioLifeOpenTimingDiagnostics.pageLifecycle("R2_WINDOW_LOAD", index, webViewIdentity)
        }
        @JavascriptInterface fun parserMarker(label: String, timeMs: Double) {
            BiblioLifeOpenTimingDiagnostics.parserMarker(index, webViewIdentity, label, timeMs)
        }
        @JavascriptInterface fun resourceTiming(type: String, path: String, startMs: Double, durationMs: Double, local: Boolean) {
            BiblioLifeOpenTimingDiagnostics.resourceTiming(index, webViewIdentity, type, path, startMs, durationMs, local)
        }
    }

    fun accepts(measurement: ResourceLayoutMeasurement) = !disposed && cssAppliedForEpoch && measurement.index == index && measurement.layoutGeneration == layoutGeneration && measurement.resourceGeneration == resourceGeneration && measurement.measurementEpoch == measurementEpoch && measurement.measurementGeneration >= measurementGeneration.get() &&
        (measurement.appliedCssToken == null || measurement.appliedCssToken == appliedLayoutState.snapshot().applied?.token)

    internal fun applyCssForLayoutGeneration(
        nextLayoutGeneration: Int,
        preferenceGeneration: Long? = null,
        transactionGeneration: Long? = null,
        onApplied: (Boolean) -> Unit,
    ) {
        if (disposed || nextLayoutGeneration <= layoutGeneration) {
            onApplied(false)
            return
        }
        layoutGeneration = nextLayoutGeneration
        measurementEpoch += 1
        cssAppliedForEpoch = false
        cssApplyPending = false
        lastReportedHeightPx = null
        deferredBootstrapCssRevoked = false
        applyCurrentEpochCss(preferenceGeneration, transactionGeneration, onApplied)
    }

    internal fun deferCssUntilBootstrap(
        nextLayoutGeneration: Int,
        preferenceGeneration: Long?,
        transactionGeneration: Long?,
        onApplied: (Boolean) -> Unit,
    ): Boolean {
        if (disposed || !bootstrapState.isLoading || nextLayoutGeneration <= layoutGeneration) return false
        layoutGeneration = nextLayoutGeneration
        measurementEpoch += 1
        cssAppliedForEpoch = false
        cssApplyPending = false
        lastReportedHeightPx = null
        val owner = ContinuousCssMutationOwner(
            token = ContinuousCssMutationTokenSource.next(),
            preferenceGeneration = preferenceGeneration,
            transactionGeneration = transactionGeneration,
            layoutGeneration = layoutGeneration,
            resourceGeneration = resourceGeneration,
            measurementEpoch = measurementEpoch,
        )
        cssOwner = owner
        cssMutationGate.activate(owner.token)
        deferredBootstrapCss = DeferredBootstrapCss(owner, onApplied)
        deferredBootstrapCssRevoked = false
        return true
    }

    /** Seeds a newly created WebView with the active transaction's current epoch. */
    internal fun deferCurrentEpochCssUntilBootstrap(
        preferenceGeneration: Long?,
        transactionGeneration: Long?,
    ): Boolean {
        if (disposed || !bootstrapState.isLoading) return false
        val owner = ContinuousCssMutationOwner(
            token = ContinuousCssMutationTokenSource.next(),
            preferenceGeneration = preferenceGeneration,
            transactionGeneration = transactionGeneration,
            layoutGeneration = layoutGeneration,
            resourceGeneration = resourceGeneration,
            measurementEpoch = measurementEpoch,
        )
        cssOwner = owner
        cssMutationGate.activate(owner.token)
        deferredBootstrapCss = DeferredBootstrapCss(owner) { }
        deferredBootstrapCssRevoked = false
        return true
    }

    /** Suppresses ambient bootstrap CSS after an active owner was revoked. */
    internal fun suppressAmbientCssUntilExplicitUpdate() {
        if (!disposed && bootstrapState.isLoading && deferredBootstrapCss == null) {
            deferredBootstrapCssRevoked = true
        }
    }

    /** A newer non-geometric preference request may resume ambient bootstrap. */
    internal fun allowAmbientCssForNewPreference() {
        if (!disposed && deferredBootstrapCss == null) deferredBootstrapCssRevoked = false
    }

    private fun applyCurrentEpochCss(
        preferenceGeneration: Long? = null,
        transactionGeneration: Long? = null,
        onApplied: (Boolean) -> Unit,
        ownerOverride: ContinuousCssMutationOwner? = null,
    ) {
        val expectedLayoutGeneration = layoutGeneration
        val expectedMeasurementEpoch = measurementEpoch
        val owner = ownerOverride ?: ContinuousCssMutationOwner(
            token = ContinuousCssMutationTokenSource.next(),
            preferenceGeneration = preferenceGeneration,
            transactionGeneration = transactionGeneration,
            layoutGeneration = expectedLayoutGeneration,
            resourceGeneration = resourceGeneration,
            measurementEpoch = expectedMeasurementEpoch,
        )
        if (ownerOverride == null) {
            cssOwner = owner
            cssMutationGate.activate(owner.token)
        } else if (cssOwner?.token != owner.token || !cssMutationGate.isCurrent(owner.token) ||
            owner.layoutGeneration != expectedLayoutGeneration ||
            owner.resourceGeneration != resourceGeneration ||
            owner.measurementEpoch != expectedMeasurementEpoch
        ) {
            return
        }
        cssAppliedForEpoch = false
        cssApplyPending = true
        webView.continuousTextRenderDiagnosticContext = textRenderContext.takeIf {
            owner.preferenceGeneration != null && owner.transactionGeneration != null
        }
        if (webView.continuousTextRenderDiagnosticContext != null) textRenderDiagnosticOwner = owner
        applyReadiumCss(webView, index, resourceGeneration, owner.token) { cssApplied ->
            if (disposed || !cssMutationGate.isCurrent(owner.token) ||
                layoutGeneration != expectedLayoutGeneration || measurementEpoch != expectedMeasurementEpoch
            ) {
                return@applyReadiumCss
            }
            if (!cssApplied) {
                cssApplyPending = false
                onApplied(false)
                return@applyReadiumCss
            }
            recordAppliedCss(owner.token)
                installResizeObserver(expectedLayoutGeneration, expectedMeasurementEpoch, owner.token) { observerInstalled ->
                if (disposed || !cssMutationGate.isCurrent(owner.token) ||
                    layoutGeneration != expectedLayoutGeneration || measurementEpoch != expectedMeasurementEpoch
                ) {
                    return@installResizeObserver
                }
                cssApplyPending = false
                cssAppliedForEpoch = observerInstalled
                onApplied(observerInstalled)
                val pending = pendingEpochMeasurement
                pendingEpochMeasurement = null
                if (observerInstalled && pending != null) {
                    receiveMeasurement(pending.height, pending.layout, pending.epoch, pending.token)
                }
                if (observerInstalled && readiumRuntimeVerified) publishBootstrapReadyOnce()
            }
        }
        webView.continuousTextRenderDiagnosticContext = null
    }

    private fun publishBootstrapReadyOnce() {
        if (disposed || !bootstrapState.canRunCommands || bootstrapReadyPublished) return
        bootstrapReadyPublished = true
        requestedDecorations.keys.forEach { group ->
            applyDecorations(group, decorationTemplates[group] ?: HtmlDecorationTemplates.defaultTemplates())
        }
        Log.d("BiblioLifeContinuous", "CONTINUOUS_RESOURCE_TRUE_READY index=$index generation=$resourceGeneration")
        BiblioLifeOpenTimingDiagnostics.internal("W6_TRUE_READY_EMIT", index, webViewIdentity)
        BiblioLifeOpenTimingDiagnostics.trueReady(index)
        onPageReady?.invoke()
    }
    /**
     * Delivers one raw Android-JS-interface invocation to this exact resource.
     * Runtime reaches this through [ReadiumBootstrapBridge]; callers receive no
     * alternate ready/Locator path.
     */
    internal fun dispatchBootstrapBridgeEvent(rawEvent: ContinuousRawBootstrapBridgeEvent): Boolean {
        if (disposed) return false
        return bootstrapBridgeDispatcher.dispatch(rawEvent)
    }
    internal fun postVisualStateCallback(requestId: Long, callback: (Long) -> Unit): Boolean {
        if (disposed || !WebViewFeature.isFeatureSupported(WebViewFeature.VISUAL_STATE_CALLBACK)) return false
        WebViewCompat.postVisualStateCallback(webView, requestId, callback)
        return true
    }
    suspend fun findFirstVisibleLocator(): Locator? = if (disposed || !bootstrapState.canRunCommands) null else webView.findFirstVisibleLocator()
    suspend fun findLocatorAtPoint(x: Double, y: Double, diagnostic: Boolean = true): Locator? =
        if (disposed || !bootstrapState.canRunCommands) null else webView.findLocatorAtPoint(x, y, diagnostic)

    suspend fun captureContinuousReadingAnchor(x: Double, y: Double): Locator? =
        if (disposed || !bootstrapState.canRunCommands) null else webView.captureContinuousReadingAnchor(x, y)
    suspend fun resolveLocatorVerticalOffset(locator: Locator, diagnosticOperation: String? = null): Double? =
        if (disposed || !bootstrapState.canRunCommands) null else webView.locatorVerticalOffset(locator, diagnosticOperation)
            ?.let { cssOffsetPx ->
                continuousCssOffsetToLayoutPx(
                    cssOffsetPx = cssOffsetPx,
                    pixelsPerCssPixel = resources.displayMetrics.density.toDouble(),
                )
            }
    suspend fun continuousLocatorPointGeometry(locator: Locator): ContinuousLocatorPointGeometry? =
        if (disposed || !bootstrapState.canRunCommands) null else webView.continuousLocatorPointGeometry(locator)
    suspend fun isLocatorRangeAtVerticalAnchor(locator: Locator, nativeY: Double, onDiagnostic: ((Map<String, Any?>) -> Unit)? = null): Boolean =
        !disposed && bootstrapState.canRunCommands && webView.isLocatorRangeAtVerticalAnchor(locator, nativeY, onDiagnostic)
    suspend fun locatorsShareMeaningfulBlock(anchor: Locator, observed: Locator): Boolean =
        !disposed && bootstrapState.canRunCommands && webView.locatorsShareMeaningfulBlock(anchor, observed)
    suspend fun currentSelection(): Selection? =
        if (disposed || !bootstrapState.canRunCommands) null else publication.locatorFromLink(link)?.let { webView.currentSelection(it) }
    fun clearSelection() { if (!disposed && bootstrapState.canRunCommands) webView.clearNativeSelection() }
    suspend fun applyCurrentReadiumCss(
        preferenceGeneration: Long? = null,
        deferAmbientHandoff: Boolean = false,
    ): Boolean {
        if (disposed || !bootstrapState.canRunCommands) return false
        val owner = ContinuousCssMutationOwner(
            token = ContinuousCssMutationTokenSource.next(),
            preferenceGeneration = preferenceGeneration,
            transactionGeneration = null,
            layoutGeneration = layoutGeneration,
            resourceGeneration = resourceGeneration,
            measurementEpoch = measurementEpoch,
        )
        cssOwner = owner
        cssMutationGate.activate(owner.token)
        val applied = suspendCancellableCoroutine<Boolean> { continuation ->
            applyReadiumCss(webView, index, resourceGeneration, owner.token) { result ->
                if (disposed || !cssMutationGate.isCurrent(owner.token)) {
                    if (continuation.isActive) continuation.resume(false)
                    return@applyReadiumCss
                }
                if (result && !deferAmbientHandoff) handoffCurrentCssOwnerToAmbient(owner.token)
                if (continuation.isActive) continuation.resume(result)
            }
            continuation.invokeOnCancellation { revokeCssMutationOwnerToken(owner.token) }
        }
        if (!applied) revokeCssMutationOwnerToken(owner.token)
        return applied
    }

    internal fun revokeCssMutationOwnerForPreference(preferenceGeneration: Long): CompletableDeferred<Unit>? {
        val owner = cssOwner ?: return null
        if (owner.preferenceGeneration != preferenceGeneration) return null
        sampleTextRenderDiagnostics("cancel", owner.token)
        textRenderDiagnosticOwner = null
        if (deferredBootstrapCss?.owner?.token == owner.token) {
            deferredBootstrapCss = null
            deferredBootstrapCssRevoked = true
        }
        cssOwner = null
        return cssMutationGate.revoke(owner.token)
    }

    internal fun revokeCssMutationOwnerToken(expectedToken: Long): CompletableDeferred<Unit>? {
        val owner = cssOwner ?: return null
        if (owner.token != expectedToken) return null
        sampleTextRenderDiagnostics("cancel", owner.token)
        textRenderDiagnosticOwner = null
        if (deferredBootstrapCss?.owner?.token == expectedToken) {
            deferredBootstrapCss = null
            deferredBootstrapCssRevoked = true
        }
        cssOwner = null
        return cssMutationGate.revoke(expectedToken)
    }

    internal fun revokeCurrentCssMutationOwner(): CompletableDeferred<Unit>? {
        val owner = cssOwner ?: return null
        return revokeCssMutationOwnerToken(owner.token)
    }

    private fun handoffCurrentCssOwnerToAmbient(expectedToken: Long) {
        val previous = cssOwner ?: return
        if (previous.token != expectedToken || !cssMutationGate.isCurrent(expectedToken)) return
        val ambient = ContinuousCssMutationOwner(
            token = ContinuousCssMutationTokenSource.next(),
            preferenceGeneration = null,
            transactionGeneration = null,
            layoutGeneration = layoutGeneration,
            resourceGeneration = resourceGeneration,
            measurementEpoch = measurementEpoch,
        )
        cssOwner = ambient
        cssMutationGate.activate(ambient.token)
        installResizeObserver(layoutGeneration, measurementEpoch, ambient.token) { }
    }
    fun replaceDecorations(group: String, decorations: List<Decoration>, templates: HtmlDecorationTemplates) {
        if (disposed) return
        requestedDecorations[group] = decorations.filter { it.locator.href == link.url() }
        decorationTemplates[group] = templates
        if (bootstrapState.canRunCommands) applyDecorations(group, templates)
    }
    fun applyMeasuredHeight(heightPx: Long) { if (!disposed) { lastHeightPx = heightPx; layoutParams = layoutParams.apply { height = heightPx.coerceAtMost(Int.MAX_VALUE.toLong()).toInt() }; requestLayout() } }
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!reflowDiagnosticAttached) {
            reflowDiagnosticAttached = true
            runCatching { reflowDiagnosticLifecycleListener?.invoke("attached") }
        }
        logResourceVisualState("attached")
    }

    override fun onDetachedFromWindow() {
        if (reflowDiagnosticAttached) {
            reflowDiagnosticAttached = false
            runCatching { reflowDiagnosticLifecycleListener?.invoke("detached") }
        }
        logResourceVisualState("detached")
        super.onDetachedFromWindow()
    }

    fun dispose() {
        if (!disposed) {
            appliedLayoutState.snapshot().takeIf { it.pending }?.applied?.let { emitCssState("abandoned_reader_closed", it) }
            revokeCurrentCssMutationOwner()
            logResourceVisualState("destroy")
            disposed = true
            bootstrapState.dispose()
            webView.removeJavascriptInterface("BiblioLifeContinuousMeasurement")
            webView.removeJavascriptInterface("BiblioLifeContinuousReadium")
            webView.removeJavascriptInterface("BiblioLifePageLifecycleDiagnostics")
            webView.stopLoading()
            BiblioLifeOpenTimingDiagnostics.lifecycle("WEBVIEW_STOP_LOADING_RETURN", instanceId = sessionInstanceId, sessionId = sessionInstanceId, hostId = hostId, generation = layoutGeneration.toLong(), resourceGeneration = resourceGeneration, index = index, webViewId = webViewIdentity)
            BiblioLifeOpenTimingDiagnostics.lifecycle("WEBVIEW_DESTROY_BEGIN", instanceId = sessionInstanceId, sessionId = sessionInstanceId, hostId = hostId, generation = layoutGeneration.toLong(), resourceGeneration = resourceGeneration, index = index, webViewId = webViewIdentity)
            webView.destroy()
            BiblioLifeOpenTimingDiagnostics.lifecycle("WEBVIEW_DESTROY_RETURN", instanceId = sessionInstanceId, sessionId = sessionInstanceId, hostId = hostId, generation = layoutGeneration.toLong(), resourceGeneration = resourceGeneration, index = index, webViewId = webViewIdentity)
        }
    }

    private fun logResourceVisualState(event: String) {
        Log.d(
            "BiblioLifeContinuous",
            "CONTINUOUS_VISUAL_STATE event=$event index=$index lg=$layoutGeneration rg=$resourceGeneration " +
                "resourceParent=${parent?.javaClass?.simpleName} webViewParent=${webView.parent?.javaClass?.simpleName} " +
                "webViewId=${System.identityHashCode(webView)} visibility=$visibility alpha=$alpha " +
                "bounds=$left,$top,$right,$bottom",
        )
    }

    /**
     * The HTML injector invokes this bridge from the actual script element's
     * load/error handlers. `onPageFinished` alone is not a Readium readiness
     * signal: Android may deliver it before the intercepted asset callback.
     */
    private fun completeReadiumBootstrapIfReady() {
        if (disposed || !bootstrapState.shouldVerifyRuntime) return
        webView.executeJavascript(
            READIUM_RUNTIME_PROBE,
        ) { result ->
            if (disposed || !bootstrapState.shouldVerifyRuntime) return@executeJavascript
            val runtimeReady = isReadiumRuntimeProbeSuccess(result)
            if (!bootstrapState.onRuntimeVerified(index, resourceGeneration, runtimeReady)) return@executeJavascript
            if (!runtimeReady) {
                cssOwner?.token?.let(::revokeCssMutationOwnerToken)
                Log.e("BiblioLifeContinuous", "CONTINUOUS_READIUM_BOOTSTRAP_FAILED index=$index generation=$resourceGeneration reason=runtime_missing")
                onPageFailed?.invoke()
                return@executeJavascript
            }
            BiblioLifeOpenTimingDiagnostics.internal("W4_READIUM_RUNTIME_VERIFIED", index, webViewIdentity)
            readiumRuntimeVerified = true
            webView.setScrollMode(ContinuousPresentation.scrollMode)
            val pendingDeferred = deferredBootstrapCss
            val deferred = pendingDeferred?.takeIf { pending ->
                pending.owner.resourceGeneration == resourceGeneration &&
                    pending.owner.layoutGeneration == layoutGeneration &&
                    pending.owner.measurementEpoch == measurementEpoch &&
                    cssOwner?.token == pending.owner.token && cssMutationGate.isCurrent(pending.owner.token)
            }
            deferredBootstrapCss = null
            val revokedDeferredIntent = deferredBootstrapCssRevoked ||
                (pendingDeferred != null && deferred == null)
            if (deferred == null && revokedDeferredIntent) {
                // The runtime probe may outlive a revoked preference request.
                // Do not reinterpret that terminal request as ambient bootstrap CSS.
                return@executeJavascript
            }
            deferredBootstrapCssRevoked = false
            applyCurrentEpochCss(
                preferenceGeneration = deferred?.owner?.preferenceGeneration,
                transactionGeneration = deferred?.owner?.transactionGeneration,
                onApplied = { applied ->
                deferred?.onApplied?.invoke(applied)
                if (disposed || !bootstrapState.canRunCommands) return@applyCurrentEpochCss
                if (!applied) {
                    Log.e("BiblioLifeContinuous", "CONTINUOUS_READIUM_BOOTSTRAP_FAILED index=$index generation=$resourceGeneration reason=css_measurement")
                    onPageFailed?.invoke()
                    return@applyCurrentEpochCss
                }
                publishBootstrapReadyOnce()
                },
                ownerOverride = deferred?.owner,
            )
        }
    }

    private fun onBootstrapScriptLoaded() {
        post {
            if (disposed || !bootstrapState.onScriptLoaded(index, resourceGeneration)) return@post
            completeReadiumBootstrapIfReady()
        }
    }

    private fun onBootstrapScriptFailed() {
        post {
            if (disposed || !bootstrapState.onScriptFailed(index, resourceGeneration)) return@post
            cssOwner?.token?.let(::revokeCssMutationOwnerToken)
            Log.e("BiblioLifeContinuous", "CONTINUOUS_READIUM_BOOTSTRAP_FAILED index=$index generation=$resourceGeneration reason=script_load")
            onPageFailed?.invoke()
        }
    }

    private inner class ReadiumBootstrapBridge {
        @JavascriptInterface fun onBootstrapScriptLoaded() {
            dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(
                    ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD,
                ),
            )
        }

        @JavascriptInterface fun onBootstrapScriptFailed() {
            dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(
                    ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_FAILED_METHOD,
                ),
            )
        }
    }

    private fun applyDecorations(group: String, templates: HtmlDecorationTemplates = HtmlDecorationTemplates.defaultTemplates()) {
        val decorations = requestedDecorations[group] ?: emptyList()
        val templateJson = templates.toJSON().toString().replace("\\n", " ")
        webView.runJavaScript("readium.registerDecorationTemplates($templateJson);")
        webView.runJavaScript("requestAnimationFrame(function () { readium.getDecorations('$group').clear(); });")
        val script = decorations.map { DecorationChange.Added(it) }.javascriptForGroup(group, templates)
        if (script != null) webView.runJavaScript(script)
    }

    private fun installResizeObserver(
        reportLayoutGeneration: Int,
        reportMeasurementEpoch: Long,
        ownerToken: Long,
        onInstalled: (Boolean) -> Unit,
    ) {
        val script = """javascript:(function(){
            var gate=window.BiblioLifeContinuousMeasurement;
            if(!gate || !gate.beginCssApply($ownerToken)){return false;}
            try {
            var previous=window.__biblioLifeContinuousResizeObserver;
            if(previous){previous.disconnect();}
            var root=document.documentElement;
            var body=document.body;
            var send=function(){
                if(!body){return;}
                var rootTop=root.getBoundingClientRect().top;
                var bodyBottom=body.getBoundingClientRect().bottom-rootTop;
                var h=Math.ceil(Math.max(1,body.scrollHeight,body.offsetHeight,bodyBottom));
                BiblioLifeContinuousMeasurement.report(h,$reportLayoutGeneration,$reportMeasurementEpoch,$ownerToken);
                return h;
            };
            var observer=new ResizeObserver(send);
            window.__biblioLifeContinuousResizeObserver=observer;
            observer.observe(root);
            if(body){observer.observe(body);}
            // The reflow target must publish its actual initial geometry before
            // an unrelated resource measurement can replace its attached holder.
            // This is a one-shot observation of the existing DOM state, not a retry.
            var initialHeight=send();
            requestAnimationFrame(send);
            return {installed:true,height:initialHeight};
            } finally { gate.endCssApply($ownerToken); }
        })()""".trimIndent()
        webView.executeJavascript(script) { result ->
            if (disposed || !cssMutationGate.isCurrent(ownerToken) ||
                layoutGeneration != reportLayoutGeneration || measurementEpoch != reportMeasurementEpoch
            ) return@executeJavascript
            val acknowledgement = javascriptResultObject(result)
            val installed = acknowledgement?.optBoolean("installed", false) ?: result.toBoolean()
            onInstalled(installed)
            // Independent of observer scheduling: acknowledge a forced live
            // layout read only AFTER native accepts reports for this epoch.
            val height = acknowledgement?.optLong("height", -1L) ?: -1L
            if (installed && height > 0) receiveMeasurement(height, reportLayoutGeneration, reportMeasurementEpoch, ownerToken)
        }
    }
    private inner class MeasurementBridge {
        @JavascriptInterface fun textRenderDiagnostic(token: Long, payload: String) {
            receiveTextRenderDiagnostic(token, payload)
        }
        @JavascriptInterface fun beginCssApply(token: Long): Boolean = cssMutationGate.begin(token)
        @JavascriptInterface fun beginCssMutation(token: Long): Boolean = cssMutationGate.beginMutation(token)
        @JavascriptInterface fun cssApplied(token: Long) = recordAppliedCss(token)
        @JavascriptInterface fun endCssApply(token: Long) = cssMutationGate.end(token)
        @JavascriptInterface fun report(cssHeightPx: Long, reportedLayoutGeneration: Int, reportedMeasurementEpoch: Long, ownerToken: Long) {
            receiveMeasurement(cssHeightPx, reportedLayoutGeneration, reportedMeasurementEpoch, ownerToken)
        }
    }

    /** Production-used origin guard; captured epoch prevents queued old JS reports reviving. */
    internal fun receiveMeasurement(
        cssHeightPx: Long,
        reportedLayoutGeneration: Int,
        reportedMeasurementEpoch: Long,
        ownerToken: Long = currentCssOwnerToken,
    ) {
        if (!cssMutationGate.isCurrent(ownerToken) || reportedLayoutGeneration != layoutGeneration || reportedMeasurementEpoch != measurementEpoch) return
        measurementDispatcher.dispatch {
            if (disposed || !cssMutationGate.isCurrent(ownerToken) || reportedLayoutGeneration != layoutGeneration ||
                reportedMeasurementEpoch != measurementEpoch
            ) return@dispatch
            if (!cssAppliedForEpoch) {
                // Observer reports may beat its evaluateJavascript ACK onto
                // Main. Retain only this epoch's latest sample until armed.
                pendingEpochMeasurement = PendingEpochMeasurement(cssHeightPx, reportedLayoutGeneration, reportedMeasurementEpoch, ownerToken)
                return@dispatch
            }
            val heightPx = continuousCssHeightToLayoutPx(
                cssHeightPx = cssHeightPx,
                pixelsPerCssPixel = resources.displayMetrics.density.toDouble(),
            ) ?: return@dispatch
            val previousReportedHeightPx = lastReportedHeightPx
            if (previousReportedHeightPx == null || abs(heightPx - previousReportedHeightPx) > 1) {
                lastReportedHeightPx = heightPx
                if (appliedLayoutState.measured(reportedLayoutGeneration, resourceGeneration, reportedMeasurementEpoch, heightPx)) {
                    appliedLayoutState.snapshot().applied?.let { owner ->
                        emitCssState("measurement_ack", owner, mapOf(
                            "measurementResult" to if (abs(heightPx - currentHeightPx) <= 1) "same_height" else "changed",
                            "heightPx" to heightPx,
                            "measurementGeneration" to measurementGeneration.get() + 1,
                        ))
                    }
                    if (textRenderMeasurementToken != ownerToken) {
                        textRenderMeasurementToken = ownerToken
                        sampleTextRenderDiagnostics("after_measurement", ownerToken)
                    }
                }
                onMeasurement(
                    ResourceLayoutMeasurement(
                        index,
                        heightPx,
                        reportedLayoutGeneration,
                        resourceGeneration,
                        measurementGeneration.incrementAndGet(),
                        reportedMeasurementEpoch,
                        appliedLayoutState.snapshot().applied?.token,
                    ),
                )
            }
        }
    }

    internal suspend fun handoffCssMutationOwner(
        preferenceGeneration: Long?,
        transactionGeneration: Long?,
    ) {
        val previous = cssOwner ?: return
        if ((transactionGeneration != null && previous.transactionGeneration != transactionGeneration) ||
            (transactionGeneration == null && previous.preferenceGeneration != preferenceGeneration) ||
            previous.layoutGeneration != layoutGeneration || previous.measurementEpoch != measurementEpoch
        ) return
        val deferred = deferredBootstrapCss?.takeIf { it.owner.token == previous.token }
        val ambient = ContinuousCssMutationOwner(
            token = ContinuousCssMutationTokenSource.next(),
            preferenceGeneration = null,
            transactionGeneration = null,
            layoutGeneration = layoutGeneration,
            resourceGeneration = resourceGeneration,
            measurementEpoch = measurementEpoch,
        )
        cssOwner = ambient
        cssMutationGate.activate(ambient.token)
        if (deferred != null && !canFindLocator) {
            // Bootstrap may finish after the transaction commits. Transfer its
            // CSS intent to ambient ownership and discard the terminal P callback.
            deferredBootstrapCss = deferred.copy(owner = ambient, onApplied = { })
            deferredBootstrapCssRevoked = false
            return
        }
        deferredBootstrapCss = null
        deferredBootstrapCssRevoked = false
        if (canFindLocator && (cssApplyPending || !cssAppliedForEpoch)) {
            // A resource may have consumed its deferred slot and started CSS,
            // then received terminal ownership while the observer ACK is still
            // in flight. The old ACK is fenced by the token change, so reapply
            // under ambient ownership instead of waiting on that stale callback.
            applyCurrentEpochCss(
                preferenceGeneration = null,
                transactionGeneration = null,
                onApplied = { },
                ownerOverride = ambient,
            )
        } else if (canFindLocator) {
            installResizeObserver(layoutGeneration, measurementEpoch, ambient.token) { }
        }
    }
    private companion object { const val ESTIMATED_RESOURCE_HEIGHT_PX = 800L }
}
