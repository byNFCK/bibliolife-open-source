package app.bibliolife.reader.readium

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
import androidx.lifecycle.Lifecycle
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.navigator.OverflowableNavigator
import org.readium.r2.navigator.SelectableNavigator
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.continuous.ContinuousEpubRendition
import org.readium.r2.navigator.epub.continuous.ContinuousNavigationOutcome
import org.readium.r2.navigator.epub.continuous.ContinuousNavigationResult
import org.readium.r2.navigator.epub.continuous.ContinuousViewportVerification
import org.readium.r2.navigator.epub.continuous.EpubContinuousRendition
import org.readium.r2.navigator.epub.continuous.EpubContinuousPreferenceResult
import org.readium.r2.navigator.epub.continuous.EpubContinuousGeometryCommitOwner
import org.readium.r2.navigator.epub.continuous.EpubContinuousLocatorAnchor
import org.readium.r2.navigator.epub.continuous.EpubContinuousHostBinding
import org.readium.r2.navigator.epub.continuous.EpubContinuousSelectionEvent
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.publication.services.positionsByReadingOrder
import org.readium.r2.shared.publication.services.locateProgression
import java.util.concurrent.ConcurrentHashMap

internal fun shouldPublishContinuousNavigationLocator(
    resultRecorded: Boolean,
    accepted: Boolean,
    verification: ContinuousViewportVerification,
): Boolean = resultRecorded && (accepted || verification == ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT)

internal fun continuousViewportPositionPublicationFields(
    preferenceGeneration: Long,
    readingOrderIndex: Int?,
    logicalPosition: Int?,
    progression: Double?,
    viewport: org.readium.r2.navigator.epub.continuous.EpubContinuousViewportLayoutSnapshot?,
    verifiedAnchor: org.readium.r2.navigator.epub.continuous.EpubContinuousReflowDiagnosticEvent?,
): Map<String, Any?> = buildMap {
    put("level", "debug")
    put("kind", "viewport_position_publication")
    put("snapshotStage", "after_reflow_commit")
    put("viewportSampleStage", "after_reflow_commit")
    put("result", "published")
    put("source", "reflow_committed")
    put("preferenceGeneration", preferenceGeneration)
    readingOrderIndex?.let { put("readingOrderIndex", it) }
    logicalPosition?.let { put("logicalPosition", it) }
    progression?.takeIf { it.isFinite() }?.let { put("positionProgression", it) }
    viewport?.firstVisibleIndex?.let { put("viewportFirstVisibleIndex", it) }
    viewport?.firstVisibleTopPx?.let { put("viewportFirstVisibleTopPx", it) }
    viewport?.heightPx?.let { put("viewportHeightPx", it) }
    viewport?.paddingTopPx?.let { put("viewportPaddingTopPx", it) }
    viewport?.paddingBottomPx?.let { put("viewportPaddingBottomPx", it) }
    viewport?.anchorIndex?.let { put("viewportAnchorIndex", it) }
    viewport?.anchorTopPx?.let { put("viewportAnchorTopPx", it) }
    viewport?.anchorBottomPx?.let { put("viewportAnchorBottomPx", it) }
    viewport?.webViewIdentity?.let { put("webViewIdentity", it) }
    viewport?.webViewIdentityUnavailableReason?.let { put("webViewIdentityUnavailableReason", it) }
    if (viewport == null) put("viewportSnapshotUnavailableReason", "not_on_main_or_viewport_unavailable")
    verifiedAnchor?.let { sample ->
        sample.preferenceGeneration?.let { put("preferenceGeneration", it) }
        sample.transactionGeneration?.let { put("transactionGeneration", it) }
        sample.layoutGeneration?.let { put("layoutGeneration", it) }
        sample.resourceGeneration?.let { put("resourceGeneration", it) }
        sample.anchorResourceHref?.let { put("anchorResourceHref", it) }
        sample.anchorResourceHrefUnavailableReason?.let { put("anchorResourceHrefUnavailableReason", it) }
        sample.webViewIdentity?.let { put("webViewIdentity", it) }
        sample.webViewIdentityUnavailableReason?.let { put("webViewIdentityUnavailableReason", it) }
        sample.anchorPointDocumentYPx?.let { put("anchorPointDocumentYPx", it) }
        sample.anchorPointViewportYPx?.let { put("anchorPointViewportYPx", it) }
        put("anchorPointAvailable", sample.anchorPointAvailable == true)
        put("anchorPointSampleStage", sample.anchorPointSampleStage ?: "unavailable")
        if (sample.anchorPointAvailable != true) {
            put("anchorPointUnavailableReason", sample.anchorPointUnavailableReason ?: "verified_sample_missing")
        } else {
            put("anchorPointUnavailableReason", "none")
        }
        sample.anchorBeforeLocalYPx?.let { put("anchorBeforeLocalYPx", it) }
        sample.anchorBeforeViewportYPx?.let { put("anchorBeforeViewportYPx", it) }
        sample.anchorViewportDeltaPx?.let { put("anchorViewportDeltaPx", it) }
        sample.anchorViewportTolerancePx?.let { put("anchorViewportTolerancePx", it) }
        sample.anchorSemanticMatch?.let { put("anchorSemanticMatch", it) }
        sample.commitLockHeld?.let { put("commitLockHeld", it) }
        sample.requestedCorrectionOffsetPx?.let { put("requestedCorrectionOffsetPx", it) }
        sample.requestedViewportDeltaPx?.let { put("requestedViewportDeltaPx", it) }
        sample.scrollRequestIssued?.let { put("scrollRequestIssued", it) }
        sample.predecessorMeasurementCount?.let { put("predecessorMeasurementCount", it) }
        sample.predecessorHeightDeltaPx?.let { put("predecessorHeightDeltaPx", it) }
        sample.anchorProgression?.let { put("anchorProgression", it) }
        sample.observedReadingOrderIndex?.let { put("observedReadingOrderIndex", it) }
        sample.observedProgression?.let { put("observedProgression", it) }
        sample.semanticProgressionDelta?.let { put("semanticProgressionDelta", it) }
        sample.targetViewportYPx?.let { put("targetViewportYPx", it) }
        sample.actualViewportYPx?.let { put("actualViewportYPx", it) }
        sample.anchorViewportDeltaPx?.let { put("anchorViewportDeltaPx", it) }
        sample.anchorViewportTolerancePx?.let { put("anchorViewportTolerancePx", it) }
        sample.anchorSemanticMatch?.let { put("anchorSemanticMatch", it) }
    } ?: put("anchorPointUnavailableReason", "no_matching_verified_sample")
}

internal data class ReadiumPreviewDispatchDiagnostic(
    val intervalSincePreviousMs: Double?,
    val activeApply: Boolean,
    val pendingLatest: Boolean,
)

internal class ReadiumPreviewDispatchClock(
    private val elapsedRealtimeMs: () -> Long,
) {
    private var previousElapsedRealtimeMs: Long? = null

    fun intervalSincePreviousMs(): Double? {
        val now = elapsedRealtimeMs()
        val previous = previousElapsedRealtimeMs
        previousElapsedRealtimeMs = now
        return previous?.let { (now - it).coerceAtLeast(0L).toDouble() }
    }
}

internal fun readiumPreviewDispatchDiagnostic(
    action: ReadiumPreferenceCoordinator.Action<*>,
    intervalSincePreviousMs: Double?,
): ReadiumPreviewDispatchDiagnostic? = when (action) {
    is ReadiumPreferenceCoordinator.Action.Start ->
        ReadiumPreviewDispatchDiagnostic(intervalSincePreviousMs, activeApply = true, pendingLatest = false)
    is ReadiumPreferenceCoordinator.Action.Queued ->
        ReadiumPreviewDispatchDiagnostic(intervalSincePreviousMs, activeApply = true, pendingLatest = true)
    else -> null
}

/**
 * Owns the non-visual Readium bootstrap for one reader host.
 *
 * The host keeps its UI and interaction callbacks, while this session owns the
 * publication-opening job, fragment lookup/creation and one-time locator
 * restoration. It has no UI dependency and is owned directly by the PlatformView.
 */
class ReadiumReaderSession(
    context: Context,
    private val fragmentManager: FragmentManager,
    private val scope: CoroutineScope,
    private val classLoader: ClassLoader,
    private val file: File,
    private val initialLocatorJson: String?,
    private val initialPreferences: EpubPreferences,
    private val initialPreferencesAreAuthoritative: Boolean,
    private val navigatorConfiguration: EpubNavigatorFragment.Configuration,
    private val listener: Listener,
    private val renditionBackend: ReadiumEpubRenditionBackend,
    private val diagnosticInstanceId: String = "unavailable",
    private val publicationLoader: (suspend (File) -> PublicationLoader.Result)? = null,
    private val openAttemptId: Long? = null,
    initialLocatorSource: String? = null,
) {
    interface Listener {
        fun onStateChanged(state: State)
        fun onResolvedNativeSelection(selection: ReadiumSelectionState) = Unit
        /** Continuous taps are already resource-generation checked by the rendition. */
        fun onContinuousContentTap(): Boolean = false
        /** Persistent highlight activation from a live continuous resource. */
        fun onContinuousPersistentHighlightActivated(
            decorationId: String,
            group: String,
            rect: android.graphics.RectF,
            tint: Int?,
            selectedText: String,
        ): Boolean = false
        fun onNavigatorReady(publication: Publication, navigator: EpubNavigatorFragment)
        fun onPositionChanged(position: ReadiumPositionState) = Unit
        fun onFatalError(error: Error)
        fun onFatalError(error: Error, openFailure: Map<String, Any?>?) = onFatalError(error)
        fun onRecoverableError(error: Error) = Unit
    }

    sealed class State {
        data object InitializationStarted : State()
        data class PublicationOpened(val publication: Publication) : State()
        /** Explicit C-1 holding state; C-2 attaches the real navigator rendition. */
        data object ContinuousRenditionPending : State()
        /** C-2 owns a real Navigator continuous rendition in the supplied native host. */
        data object ContinuousRenditionAttached : State()
        data class NavigatorAttached(val reusedRestoredFragment: Boolean) : State()
        data object NavigatorReady : State()
        data class InitialLocatorRestored(val navigated: Boolean) : State()
        data class PositionChanged(
            val position: ReadiumPositionState,
            val liveManual: Boolean = false,
            val progressOwner: ProgressNavigationOwner? = null,
        ) : State()
        data class ManualScrollActivityChanged(val active: Boolean) : State()
        data class NavigationStarted(
            val command: ReadiumNavigationCommand,
            val generation: Long,
            val progressOwner: ProgressNavigationOwner? = null,
        ) : State()
        data class NavigationCompleted(val command: ReadiumNavigationCommand, val generation: Long) : State()
        data class NavigationFailed(val command: ReadiumNavigationCommand, val error: Error) : State()
        data class PreferencesRequested(val preferences: PreferenceState) : State()
        data class PreferencesApplied(val preferences: PreferenceState, val initial: Boolean) : State()
        data class PreferencesFailed(val preferences: PreferenceState, val error: Error) : State()
        data class Diagnostic(val fields: Map<String, Any?>) : State()
        data class TocStateChanged(val toc: ReadiumTocState) : State()
        data class CurrentChapterChanged(val chapter: ReadiumChapterState) : State()
        data class SearchStateChanged(val search: EpubSearchState) : State()
        data class SelectionChanged(val selection: ReadiumSelectionState) : State()
        data class DecorationsChanged(
            val group: ReadiumDecorationGroup,
            val decorations: DecorationState,
        ) : State()
        data object Disposed : State()
    }

    data class DecorationState(
        val requestedCount: Int,
        val appliedCount: Int,
        val generation: Long,
        val isApplying: Boolean,
        val isReady: Boolean,
        val selectionProtected: Boolean,
        val hasApplied: Boolean,
    )

    /** The requested and successfully applied Readium values are distinct. */
    data class PreferenceState(
        val requested: EpubPreferences?,
        val applied: EpubPreferences?,
        val generation: Long,
        val isApplying: Boolean,
    )

    sealed class NavigationResult {
        data object Completed : NavigationResult()
        // Navigation committed; publication is an independent unsuccessful result.
        data object CompletedWithPublicationFailure : NavigationResult()
        data object RecoveredTimeout : NavigationResult()
        data object BoundaryReached : NavigationResult()
        data object NavigatorNotReady : NavigationResult()
        data object InvalidLocator : NavigationResult()
        data object InvalidProgression : NavigationResult()
        data object SessionDisposed : NavigationResult()
        data object Cancelled : NavigationResult()
        data object TocNotReady : NavigationResult()
        data object UnknownTocEntry : NavigationResult()
        data object Failed : NavigationResult()

        val accepted: Boolean get() = this == Completed || this == CompletedWithPublicationFailure
    }

    sealed class PreferenceResult {
        data object Applied : PreferenceResult()
        data object Unchanged : PreferenceResult()
        data object NavigatorNotReady : PreferenceResult()
        data object SessionDisposed : PreferenceResult()
        data object Cancelled : PreferenceResult()
        data class PositionPreservationFailed(val reason: String) : PreferenceResult()
        data object Failed : PreferenceResult()
    }

    sealed class SearchNavigationResult {
        data object Completed : SearchNavigationResult()
        data object NavigatorNotReady : SearchNavigationResult()
        data object SessionDisposed : SearchNavigationResult()
        data object UnknownResultId : SearchNavigationResult()
        data object ObsoleteResultId : SearchNavigationResult()
        data object Failed : SearchNavigationResult()

        val accepted: Boolean get() = this == Completed
    }

    sealed class DecorationResult {
        data object Applied : DecorationResult()
        data object Queued : DecorationResult()
        data object Unchanged : DecorationResult()
        data object Superseded : DecorationResult()
        data object Failed : DecorationResult()
        data object NavigatorNotReady : DecorationResult()
        data object SessionDisposed : DecorationResult()
    }

    sealed class Error(val code: String) {
        data object MissingLocalFile : Error("file_not_found")
        data object UnsupportedPublication : Error("unsupported_format")
        data class PublicationOpeningFailed(val openingCode: String) : Error(openingCode)
        data object InvalidInitialLocator : Error("invalid_initial_locator")
        data class NavigatorCreationFailed(val cause: Throwable) : Error("navigator_creation_failed")
        data class FragmentAttachmentFailed(val cause: Throwable? = null) : Error("navigator_attachment_failed")
        data object InvalidHostContainer : Error("invalid_host_container")
        data object IncompatibleRestoredNavigator : Error("incompatible_restored_navigator")
        data class InitialLocatorRestorationFailed(val cause: Throwable? = null) : Error("initial_locator_restoration_failed")
        data class InitialViewportReadinessFailed(val reason: String) : Error("initial_viewport_readiness_failed")
        data object NavigatorNotReady : Error("navigator_not_ready")
        data object InvalidLocator : Error("invalid_locator")
        data object InvalidProgression : Error("invalid_progression")
        data object NavigationCancelled : Error("navigation_cancelled")
        data class NavigationFailed(val cause: Throwable? = null) : Error("navigation_failed")
        data class PreferenceApplicationFailed(val cause: Throwable? = null) : Error("preferences_apply_failed")
        data class PreferencePositionPreservationFailed(val reason: String) : Error("preferences_position_preservation_failed")
        data object PreferenceApplicationCancelled : Error("preferences_apply_cancelled")
        data class DecorationApplicationFailed(val group: String) : Error("decorations_apply_failed")
        data class TocLoadingFailed(val cause: Throwable? = null) : Error("toc_loading_failed")
        data object CommandAfterDisposal : Error("session_disposed")
    }

    private val state = ReadiumReaderSessionState()
    private val application: android.app.Application =
        context.applicationContext as android.app.Application
    private var initializationJob: Job? = null
    private val applicationContext = context.applicationContext
    private var openDiagnosticStage = "native_session"
    private var openDiagnosticComponent = "android_reader_session"
    private var openingReady = false
    private val initialRestoreDiagnostic = openAttemptId?.let {
        ReadiumInitialLocatorDiagnostics(it, initialLocatorSource, SystemClock::elapsedRealtime, ::emitOpenDiagnostic)
    }
    private var publication: Publication? = null
    private var navigator: EpubNavigatorFragment? = null
    private var continuousRendition: EpubContinuousRendition? = null
    private val continuousResourceReadyRelay = ContinuousResourceReadySessionRelay()
    private var continuousLocatorJob: Job? = null
    private val continuousLocatorDispatchGate = ContinuousLocatorDispatchGate<ContinuousLocatorDispatchRequest>()
    private val continuousSelectionLocatorPublicationGate = ContinuousSelectionLocatorPublicationGate()
    private val continuousManualScrollThrottle = ContinuousManualScrollThrottle()
    private val continuousManualScrollPublicationGate = ContinuousManualScrollPublicationGate()
    private val continuousPositionPublicationGate = ContinuousPositionPublicationGate()
    private var continuousPreferencePublicationGeneration = 0L
    private var lastDiagnosticViewportPreferenceGeneration: Long? = null
    private val paginatedManualPagePublicationGate = PaginatedManualPagePublicationGate()
    private var manualScrollFinalPendingContext: ContinuousPositionContext? = null
    private var continuousReflowPublicationGate: ContinuousReflowPublicationGate? = null
    private var latestPosition: ReadiumPositionState? = null
    private var latestPositionFingerprint: ReadiumPositionFingerprint? = null
    private var latestPositionWasLiveManual = false
    // A DOM point Locator's href is resource-local/served data. Retain the
    // anchor's immutable reading-order identity so a positions-cache completion
    // can canonicalize the same Locator without guessing from that href.
    private var latestContinuousReadingOrderIndex: Int? = null
    private var presentationState: ReadiumPresentationState = ReadiumPresentationState.Unknown
    private var pendingProgressSeek: Double? = null
    private val recoveredProgressPublicationFence = RecoveredProgressPublicationFence()
    private val progressScrubOwnership = ProgressScrubOwnership()
    private val ownedPaginatedNavigations = ConcurrentHashMap<String, OwnedPaginatedNavigation>()
    private var layoutGeneration = 0L
    private var pendingPagination: PendingPagination? = null
    private var positionsCache: ReadiumPositionsCache? = null
    private var initialLocator: Locator? = null
    private var restoredNavigator = false
    private var fragmentLifecycleCallbacks: FragmentManager.FragmentLifecycleCallbacks? = null
    private var locatorObservationJob: Job? = null
    private var positionsLoadJob: Job? = null
    private var tocLoadJob: Job? = null
    private var searchStateObservationJob: Job? = null
    private var tocIndex: ReadiumTocIndex<Link>? = null
    private val mutableSearchState = MutableStateFlow<EpubSearchState>(EpubSearchState.Idle)
    private var searchOwner: ReadiumSearchSessionOwner? = null
    private val searchNavigationCoordinator = EpubSearchNavigationCoordinator(
        resolve = { id -> searchOwner?.targetFor(id) ?: EpubSearchController.TargetResolution.Unknown },
        navigate = { target, animated ->
            val locator = target.locator
            if (locator == null) {
                EpubSearchNavigationOutcome.Failed
            } else {
                when (goTo(locator, animated)) {
                    NavigationResult.Completed -> {
                        // Result navigation owns the temporary SEARCH_RESULT
                        // decoration; persistent highlights remain untouched.
                        setSearchDecoration(locator, tint = 0x66FFEB3B)
                        EpubSearchNavigationOutcome.Completed
                    }
                    NavigationResult.NavigatorNotReady -> EpubSearchNavigationOutcome.NavigatorNotReady
                    else -> EpubSearchNavigationOutcome.Failed
                }
            }
        },
    )
    private val navigationMutex = Mutex()
    private val preferenceCoordinator = ReadiumPreferenceCoordinator<EpubPreferences>()
    private val preferenceCallbacks = mutableMapOf<Long, (PreferenceResult) -> Unit>()
    private val preferencePreviewRequestIds = mutableMapOf<Long, Long>()
    private var supersededSettingsPreviewRequestId = 0L
    private val diagnosticPreviewDispatchClock = ReadiumPreviewDispatchClock { SystemClock.elapsedRealtime() }
    private var latestVerifiedViewportSnapshot: org.readium.r2.navigator.epub.continuous.EpubContinuousReflowDiagnosticEvent? = null
    private val decorationCoordinator = ReadiumDecorationCoordinator(
        scope = scope,
        gateway = if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
            ReadiumContinuousDecorationGateway { continuousRendition }
        } else {
            ReadiumNavigatorDecorationGateway { navigator }
        },
        onStateChanged = { group, snapshot ->
            if (state.isActive()) listener.onStateChanged(
                State.DecorationsChanged(group, snapshot.toDecorationState()),
            )
        },
    )
    private val selectionCoordinator = ReadiumSelectionCoordinator(
        scope = scope,
        gateway = if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
            ReadiumContinuousSelectionGateway { continuousRendition }
        } else {
            ReadiumNavigatorSelectionGateway { navigator as? SelectableNavigator }
        },
        onStateChanged = { selection ->
            decorationCoordinator.setSelectionProtected(selection.sessionActive)
            if (state.isActive()) listener.onStateChanged(State.SelectionChanged(selection))
        },
        onResolvedSelection = { selection ->
            if (state.isActive()) listener.onResolvedNativeSelection(selection)
        },
    )

    internal fun initialize(containerId: Int, nativeRenditionHost: ReadiumNativeRenditionHost? = null) {
        if (containerId <= 0) {
            fail(Error.InvalidHostContainer)
            return
        }
        if (!state.start()) {
            if (state.phase == ReadiumReaderSessionState.Phase.DISPOSED) {
                listener.onRecoverableError(Error.CommandAfterDisposal)
            }
            return
        }
        openStage("readium_initialization", "started", "readium_initial_locator", mapOf("readiumInitializationReached" to true))
        listener.onStateChanged(State.InitializationStarted)
        if (searchStateObservationJob == null) {
            searchStateObservationJob = scope.launch {
                mutableSearchState.collect { search ->
                    if (state.phase != ReadiumReaderSessionState.Phase.DISPOSED) {
                        listener.onStateChanged(State.SearchStateChanged(search))
                    }
                }
            }
        }
        val hasInitialLocator = !initialLocatorJson.isNullOrBlank()
        initialRestoreDiagnostic?.stage("initial_locator_parse", if (hasInitialLocator) "started" else "skipped")
        val parsedLocator = runCatching {
            ReadiumInitialLocatorRequest.parse(initialLocatorJson)
        }
        val initialLocatorRequest = parsedLocator.getOrNull() ?: run {
            if (hasInitialLocator) {
                val cause = parsedLocator.exceptionOrNull()
                initialRestoreDiagnostic?.finish(
                    "failed", cause, if (cause is org.json.JSONException) "invalid_locator_json" else "invalid_locator_href",
                )
                fail(Error.InvalidInitialLocator, cause = parsedLocator.exceptionOrNull())
                return
            }
            null
        }
        if (initialLocatorRequest != null) {
            initialRestoreDiagnostic?.stage("initial_locator_parse", "success", mapOf(
                "requestedResourceProgression" to initialLocatorRequest.json.optJSONObject("locations")
                    ?.optDouble("progression")?.takeIf(Double::isFinite),
            ))
        } else {
            initialRestoreDiagnostic?.finish("skipped", reason = "no_initial_locator")
        }
        openStage("readium_initialization", "success", "readium_initial_locator")
        openStage("readium_services", "started", "readium_services")
        initializationJob = scope.launch {
            when (val result = withContext(Dispatchers.IO) { loadPublicationForOpen() }) {
                is PublicationLoader.Result.Failure -> {
                    if (state.isActive()) fail(errorFor(result.code), diagnostic = result.diagnostic)
                }
                is PublicationLoader.Result.Success -> {
                    if (!state.isActive()) {
                        closeQuietly(result.publication)
                        return@launch
                    }
                    openStage("initial_locator_resolution", "started", "readium_initial_locator")
                    val canonicalInitialLocator = initialLocatorRequest?.let {
                        initialRestoreDiagnostic?.stage("locator_canonicalization", "started")
                        try {
                            ReadiumInitialLocatorRequest.canonicalize(
                                it,
                                result.publication,
                                onMatch = { facts -> initialRestoreDiagnostic?.record(facts) },
                                onConversionFailure = { cause ->
                                    initialRestoreDiagnostic?.finish("failed", cause, "locator_conversion_failed")
                                },
                            )
                        } catch (cause: Exception) {
                            initialRestoreDiagnostic?.finish("failed", cause)
                            throw cause
                        }
                    }
                    if (initialLocatorRequest != null && canonicalInitialLocator == null) {
                        initialRestoreDiagnostic?.finish("failed", reason = "locator_conversion_failed")
                        closeQuietly(result.publication)
                        fail(Error.InvalidInitialLocator)
                        return@launch
                    }
                    if (canonicalInitialLocator != null) {
                        initialRestoreDiagnostic?.stage("locator_canonicalization", "success")
                    }
                    openStage("initial_locator_resolution", "success", "readium_initial_locator")
                    initialLocator = canonicalInitialLocator
                    publication = result.publication
                    positionsCache = createPositionsCache(result.publication)
                    searchOwner = ReadiumSearchSessionOwner(
                        scope = scope,
                        gateway = ReadiumSearchGateway(result.publication),
                        state = mutableSearchState,
                    )
                    if (!state.publicationOpened()) {
                        closeQuietly(result.publication)
                        return@launch
                    }
                    listener.onStateChanged(State.PublicationOpened(result.publication))
                    openStage("navigator_initialization", "started", "android_readium_navigator")
                    loadToc(result.publication)
                    when (renditionBackend.bootstrapAction()) {
                        ReadiumEpubRenditionBootstrapAction.AttachLegacyNavigator -> attachNavigator(containerId)
                        ReadiumEpubRenditionBootstrapAction.EnterContinuousPending -> {
                            if (state.continuousRenditionPending()) {
                                val rendition = nativeRenditionHost?.takeIf { it.isValid(it.generation) }?.containerOrNull()?.let { container ->
                                    ContinuousEpubRendition.create(
                                        application = application,
                                        publication = result.publication,
                                        configuration = navigatorConfiguration,
                                        sessionInstanceId = diagnosticInstanceId,
                                        initialPreferences = initialPreferences,
                                    ).also { rendition ->
                                        continuousRendition = rendition
                                        rendition.setSelectionSessionListener(::onContinuousSelectionSessionChanged)
                                        rendition.setReflowDiagnosticListener(::onContinuousReflowDiagnostic)
                                        rendition.setContentTapListener { listener.onContinuousContentTap() }
                                        rendition.setDecorationActivationListener { event ->
                                            listener.onContinuousPersistentHighlightActivated(
                                                decorationId = event.decorationId,
                                                group = event.group,
                                                rect = event.rect,
                                                tint = event.tint,
                                                selectedText = event.selectedText,
                                            )
                                        }
                                        // A resource becomes queryable only after its own Readium
                                        // bootstrap has completed. Re-run the real 25% anchor query
                                        // at that boundary, because an earlier RecyclerView callback
                                        // may have observed the resource before it was Locator-ready.
                                        rendition.setResourceReadyListener { event ->
                                            onContinuousResourceReady(rendition, event)
                                        }
                                        rendition.setInitialViewportListeners(
                                            onReady = { onContinuousInitialViewportReady(rendition) },
                                            onFailure = { reason -> onContinuousInitialViewportFailed(rendition, reason) },
                                        )
                                        rendition.attach(EpubContinuousHostBinding(container, nativeRenditionHost.generation))
                                        rendition.setViewportChangedListener {
                                            requestContinuousLocatorUpdate(ContinuousPositionSource.HOST_VIEWPORT)
                                        }
                                        rendition.setManualDragStartedListener {
                                            recoveredProgressPublicationFence.manualDragStarted()
                                            state.invalidateContinuousNavigationAuthority()
                                            progressScrubOwnership.invalidate()
                                            continuousManualScrollPublicationGate.manualDragStarted(state.navigationGeneration)
                                        }
                                        rendition.setManualScrollActivityChangedListener { active ->
                                            if (!state.isActive() || continuousRendition !== rendition ||
                                                !continuousManualScrollPublicationGate.activityChanged(active, state.navigationGeneration)
                                            ) return@setManualScrollActivityChangedListener
                                            if (active) {
                                                continuousManualScrollThrottle.reset()
                                                manualScrollFinalPendingContext = null
                                            } else {
                                                manualScrollFinalPendingContext = continuousRendition?.let(::continuousPositionContext)
                                            }
                                            listener.onStateChanged(State.ManualScrollActivityChanged(active))
                                        }
                                        rendition.setManualScrollProgressListener {
                                            if (continuousManualScrollPublicationGate.active && !state.navigationInFlight &&
                                                continuousManualScrollThrottle.shouldSample(SystemClock.uptimeMillis())
                                            ) {
                                                requestContinuousLocatorUpdate(ContinuousPositionSource.MANUAL_LIVE, liveManual = true)
                                            }
                                        }
                                        decorationCoordinator.onNavigatorReady()
                                    }
                                }
                                listener.onStateChanged(
                                    if (rendition == null) State.ContinuousRenditionPending
                                    else State.ContinuousRenditionAttached,
                                )
                                if (rendition != null && state.continuousRenditionReady()) {
                                    restoreContinuousInitialLocator(rendition)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private suspend fun loadPublicationForOpen(): PublicationLoader.Result {
        val injectedLoader = publicationLoader
        if (injectedLoader != null) return injectedLoader(file)
        val services = try {
            ReadiumServices(applicationContext)
        } catch (error: Exception) {
            if (error !is kotlinx.coroutines.CancellationException) {
                emitOpenDiagnosticFromIo(ReadiumOpenDiagnostics.stage(
                    "readium_services", "failed", "readium_services",
                    ReadiumOpenDiagnostics.exception(error) + ("errorCode" to "readium_services_exception"),
                ))
            }
            throw error
        }
        emitOpenDiagnosticFromIo(ReadiumOpenDiagnostics.stage("readium_services", "success", "readium_services"))
        return PublicationLoader(services).open(file, ::emitOpenDiagnosticFromIo)
    }

    private fun emitOpenDiagnosticFromIo(fields: Map<String, Any?>) {
        // The production session scope uses Main.immediate, like the existing
        // IO continuation. These lightweight events never wait on Flutter.
        scope.launch {
            if (state.isActive()) emitOpenDiagnostic(fields)
        }
    }

    /** Updates only the experimental continuous host; legacy Fragment hosting is unchanged. */
    internal fun updateNativeRenditionHost(host: ReadiumNativeRenditionHost?) {
        if (!state.isActive() || renditionBackend != ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) return
        val valid = host?.takeIf { it.isValid(it.generation) } ?: return
        val container = valid.containerOrNull() ?: return
        continuousRendition?.attach(EpubContinuousHostBinding(container, valid.generation))
    }

    internal fun detachNativeRenditionHost(generation: Long) {
        if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
            continuousRendition?.detach(generation)
        }
    }

    fun publication(): Publication? = publication

    fun navigator(): EpubNavigatorFragment? = navigator

    /** The session-owned native selection state. Hosts must not cache an authoritative copy. */
    fun selectionState(): ReadiumSelectionState = selectionCoordinator.snapshot()

    fun onNativeSelectionSessionStarted(nativeSessionId: Long): Long? =
        selectionCoordinator.onNativeSelectionSessionStarted(nativeSessionId)

    fun onNativeSelectionSessionEnded(nativeSessionId: Long): Boolean =
        selectionCoordinator.onNativeSelectionSessionEnded(nativeSessionId)

    /**
     * Continuous resource callbacks already carry exact WebView identity and
     * generation. The rendition validates/pins them before this coordinator
     * sees the normal native session lifecycle.
     */
    private fun onContinuousSelectionSessionChanged(event: EpubContinuousSelectionEvent) {
        if (!state.isActive() || renditionBackend != ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) return
        if (!event.active) {
            continuousSelectionLocatorPublicationGate.end(event.nativeSessionId)
            selectionCoordinator.onNativeSelectionSessionEnded(event.nativeSessionId)
            return
        }
        continuousSelectionLocatorPublicationGate.begin(event.nativeSessionId)
        // A pre-selection WebView response cannot be allowed to publish after
        // native ActionMode has claimed the resource-local selection. Keep the
        // dispatch gate intact: its running request must complete before a
        // post-selection viewport request can become the newest successor.
        if (selectionCoordinator.onNativeSelectionSessionStarted(event.nativeSessionId) == null) return
        scope.launch {
            // The native selection callback precedes stable serialization.
            // Reuse the existing coordinator's single-flight/retry policy.
            yield()
            if (state.isActive()) selectionCoordinator.requestCurrentSelection(refreshAfterInFlight = true)
        }
    }

    fun requestCurrentSelection(
        onComplete: (ReadiumSelectionRequestResult) -> Unit = {},
        refreshAfterInFlight: Boolean = false,
    ): ReadiumSelectionRequestResult = selectionCoordinator.requestCurrentSelection(onComplete, refreshAfterInFlight)

    fun clearSelection(): ReadiumSelectionClearResult = selectionCoordinator.clearSelection()

    /** Invalidates pending reads when the visible publication resource/viewport changes. */
    fun onViewportEpochChanged(epoch: Long) = selectionCoordinator.onViewportEpochChanged(epoch)

    fun position(): ReadiumPositionState? = latestPosition

    /** True only after the active navigator has been attached and is still usable. */
    fun isNavigatorReady(): Boolean = navigator != null && state.phase != ReadiumReaderSessionState.Phase.DISPOSED

    /** Session-owned canonical positions for the native progress UI. */
    internal suspend fun progressionTargets(): Result<List<ProgressNavigationTarget>> =
        positionsCache?.get()?.map { it.navigationTargets }
            ?: Result.failure(IllegalStateException("publication_not_ready"))

    fun preferences(): PreferenceState = preferenceCoordinator.snapshot().toPreferenceState()

    fun tocState(): ReadiumTocState = state.tocState

    fun currentChapter(): ReadiumChapterState = state.currentChapter

    /** Presentation hosts may observe this, but only the session mutates it. */
    fun searchState(): StateFlow<EpubSearchState> = mutableSearchState

    /** Trims only leading/trailing whitespace; internal and Unicode whitespace are preserved. */
    fun search(query: String) {
        if (state.phase == ReadiumReaderSessionState.Phase.DISPOSED) return
        clearSearchDecoration()
        val owner = searchOwner
        if (owner == null) {
            mutableSearchState.value = EpubSearchState.Error(query.trim(), -1, EpubSearchError.PublicationUnavailable)
        } else {
            owner.search(query)
        }
    }

    fun loadNextSearchPage() {
        if (state.phase != ReadiumReaderSessionState.Phase.DISPOSED) searchOwner?.loadNextPage()
    }

    fun retrySearch() {
        if (state.phase != ReadiumReaderSessionState.Phase.DISPOSED) searchOwner?.retry()
    }

    fun clearSearch() {
        if (state.phase == ReadiumReaderSessionState.Phase.DISPOSED) return
        clearSearchDecoration()
        searchOwner?.clear() ?: run { mutableSearchState.value = EpubSearchState.Idle }
    }
    fun cancelSearch() = clearSearch()

    /** Replaces the persistent highlight group from a repository snapshot. */
    fun setPersistentHighlights(
        decorations: List<ReadiumDecorationSpec>,
        onComplete: (DecorationResult) -> Unit = {},
    ) = requestDecorations(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, decorations, onComplete)

    fun setDecorations(
        group: ReadiumDecorationGroup,
        decorations: List<ReadiumDecorationSpec>,
        onComplete: (DecorationResult) -> Unit = {},
    ) = requestDecorations(group, decorations, onComplete)

    fun upsertDecoration(
        group: ReadiumDecorationGroup,
        decoration: ReadiumDecorationSpec,
        onComplete: (DecorationResult) -> Unit = {},
    ) = setDecorations(
        group,
        decorationCoordinator.requested(group)
            .filterNot { it.id == decoration.id }
            .plus(decoration),
        onComplete,
    )

    fun removeDecoration(
        group: ReadiumDecorationGroup,
        id: String,
        onComplete: (DecorationResult) -> Unit = {},
    ) = setDecorations(
        group,
        decorationCoordinator.requested(group).filterNot { it.id == id },
        onComplete,
    )

    fun clearDecorations(
        group: ReadiumDecorationGroup,
        onComplete: (DecorationResult) -> Unit = {},
    ) = setDecorations(group, emptyList(), onComplete)

    /** Replaces the short-lived search result group without touching highlights. */
    fun setSearchDecoration(
        locator: Locator,
        tint: Int,
        onComplete: (DecorationResult) -> Unit = {},
    ) = requestDecorations(
        ReadiumDecorationGroup.SEARCH_RESULT,
        listOf(ReadiumDecorationSpec("search-result", locator, ReadiumDecorationStyle.Highlight(tint, active = true))),
        onComplete,
    )

    fun clearSearchDecoration(onComplete: (DecorationResult) -> Unit = {}) =
        clearDecorations(ReadiumDecorationGroup.SEARCH_RESULT, onComplete)

    /** Keeps ordinary decoration work out of an active text-selection gesture. */
    fun setSelectionDecorationProtection(active: Boolean) = decorationCoordinator.setSelectionProtected(active)

    fun decorationState(group: ReadiumDecorationGroup): DecorationState =
        decorationCoordinator.snapshot(group).toDecorationState()

    /** Resolves only a session-held result ID, then uses ordinary serialized navigation. */
    fun goToSearchResult(resultId: String, animated: Boolean = false): SearchNavigationResult {
        if (state.phase == ReadiumReaderSessionState.Phase.DISPOSED) return SearchNavigationResult.SessionDisposed
        if (searchOwner == null) return SearchNavigationResult.NavigatorNotReady
        return when (searchNavigationCoordinator.goTo(resultId, animated)) {
            EpubSearchNavigationOutcome.Completed -> SearchNavigationResult.Completed
            EpubSearchNavigationOutcome.NavigatorNotReady -> SearchNavigationResult.NavigatorNotReady
            EpubSearchNavigationOutcome.ObsoleteResultId -> SearchNavigationResult.ObsoleteResultId
            EpubSearchNavigationOutcome.UnknownResultId -> SearchNavigationResult.UnknownResultId
            EpubSearchNavigationOutcome.Failed -> SearchNavigationResult.Failed
        }
    }

    /**
     * Applies a complete effective [EpubPreferences] request through the
     * navigator. The session serializes calls and retains only the newest
     * queued request, so a stale success can never replace the latest state.
     */
    fun applyPreferences(
        preferences: EpubPreferences,
        onComplete: (PreferenceResult) -> Unit,
    ) = applyPreferencesWithDiagnostics(preferences, null, null, onComplete)

    internal fun applyPreferencesWithDiagnostics(
        preferences: EpubPreferences,
        diagnosticContext: ReadiumReflowDiagnosticContext?,
        previewRequestId: Long? = null,
        onComplete: (PreferenceResult) -> Unit,
    ) {
        if (previewRequestId != null && previewRequestId <= 0) {
            onComplete(PreferenceResult.Failed)
            return
        }
        if (previewRequestId != null && previewRequestId < supersededSettingsPreviewRequestId) {
            onComplete(PreferenceResult.Cancelled)
            return
        }
        when (val action = preferenceCoordinator.request(preferences, diagnosticContext,
            forceApply = continuousRendition?.hasPendingCssGeometry() == true)) {
            is ReadiumPreferenceCoordinator.Action.Start -> {
                if (action.request.diagnosticContext != null) {
                    readiumPreviewDispatchDiagnostic(
                        action,
                        diagnosticPreviewDispatchClock.intervalSincePreviousMs(),
                    )?.let { diagnostic ->
                        emitPreferenceDiagnostic(
                            action.request,
                            "preview_dispatch",
                            "started",
                            dispatchStage = "native_session_received",
                            intervalSincePreviousMs = diagnostic.intervalSincePreviousMs,
                            activeApply = diagnostic.activeApply,
                            pendingLatest = diagnostic.pendingLatest,
                        )
                    }
                }
                emitPreferenceDiagnostic(action.request, "preference_received", "start")
                Log.d(
                    TAG,
                    "PREFERENCE_REQUEST generation=${action.request.generation} value=${action.request.value.preferenceFontFamily()}",
                )
                invalidateRenderedPagination(action.request.generation)
                previewRequestId?.let { preferencePreviewRequestIds[action.request.generation] = it }
                preferenceCallbacks[action.request.generation] = onComplete
                listener.onStateChanged(State.PreferencesRequested(this.preferences()))
                applyPreferenceRequest(action.request)
            }
            is ReadiumPreferenceCoordinator.Action.Queued -> {
                if (action.request.diagnosticContext != null) {
                    readiumPreviewDispatchDiagnostic(
                        action,
                        diagnosticPreviewDispatchClock.intervalSincePreviousMs(),
                    )?.let { diagnostic ->
                        emitPreferenceDiagnostic(
                            action.request,
                            "preview_dispatch",
                            "queued_latest",
                            dispatchStage = "native_session_received",
                            intervalSincePreviousMs = diagnostic.intervalSincePreviousMs,
                            activeApply = diagnostic.activeApply,
                            pendingLatest = diagnostic.pendingLatest,
                        )
                    }
                }
                emitPreferenceDiagnostic(action.request, "preference_received", "queued")
                val supersededGeneration = action.supersededPendingRequest?.generation
                    ?: preferenceCoordinator.snapshot().generation.let { latestGeneration ->
                        // The queued request is the latest generation; the in-flight one is older.
                        latestGeneration - 1
                    }
                Log.d(
                    TAG,
                    "PREFERENCE_REQUEST generation=${action.request.generation} value=${action.request.value.preferenceFontFamily()}",
                )
                Log.d(
                    TAG,
                    "PREFERENCE_SUPERSEDE old=$supersededGeneration new=${action.request.generation}",
                )
                invalidateRenderedPagination(action.request.generation)
                continuousRendition?.supersedeGeometryReflow()
                action.supersededPendingRequest?.let { superseded ->
                    preferencePreviewRequestIds.remove(superseded.generation)
                    preferenceCallbacks.remove(superseded.generation)?.invoke(PreferenceResult.Cancelled)
                }
                previewRequestId?.let { preferencePreviewRequestIds[action.request.generation] = it }
                preferenceCallbacks[action.request.generation] = onComplete
                listener.onStateChanged(State.PreferencesRequested(this.preferences()))
            }
            ReadiumPreferenceCoordinator.Action.Unchanged -> onComplete(PreferenceResult.Unchanged)
            ReadiumPreferenceCoordinator.Action.NotReady -> onComplete(PreferenceResult.NavigatorNotReady)
            ReadiumPreferenceCoordinator.Action.Disposed -> onComplete(PreferenceResult.SessionDisposed)
        }
    }

    fun supersedeSettingsPreviewsBefore(requestId: Long): Boolean {
        if (requestId <= 0 || state.phase == ReadiumReaderSessionState.Phase.DISPOSED) return false
        if (requestId > supersededSettingsPreviewRequestId) {
            supersededSettingsPreviewRequestId = requestId
        }
        continuousRendition?.supersedeSettingsPreviewsBefore(supersededSettingsPreviewRequestId)
        return true
    }

    fun settingsReflowGesture(id: Long, slider: String, action: String, value: Double, onComplete: (Boolean) -> Unit) {
        val rendition = continuousRendition
        if (rendition == null || state.phase == ReadiumReaderSessionState.Phase.DISPOSED) { onComplete(false); return }
        scope.launch {
            val accepted = runCatching { rendition.settingsReflowGesture(id, slider, action, value) }.getOrDefault(false)
            onComplete(accepted && continuousRendition === rendition && state.phase != ReadiumReaderSessionState.Phase.DISPOSED)
        }
    }

    fun next(animated: Boolean = false): NavigationResult =
        executeNavigation(ReadiumNavigationCommand.NEXT, boundaryWhenRejected = true) { activeNavigator ->
            (activeNavigator as OverflowableNavigator).goForward(animated)
        }

    fun previous(animated: Boolean = false): NavigationResult =
        executeNavigation(ReadiumNavigationCommand.PREVIOUS, boundaryWhenRejected = true) { activeNavigator ->
            (activeNavigator as OverflowableNavigator).goBackward(animated)
        }

    fun goTo(locator: Locator, animated: Boolean = false): NavigationResult {
        if (locator.href.toString().isBlank()) return NavigationResult.InvalidLocator
        if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
            return executeContinuousLocatorNavigation(locator)
        }
        return executeNavigation(ReadiumNavigationCommand.LOCATOR) { activeNavigator ->
            activeNavigator.go(locator, animated)
        }
    }

    fun goTo(link: Link, animated: Boolean = false): NavigationResult {
        val locator = publication?.locatorFromLink(link) ?: return NavigationResult.InvalidLocator
        return goTo(locator, animated)
    }

    /** Resolves a session-owned stable TOC ID, then reuses the ordinary navigation path. */
    fun goToTocEntry(entryId: String, animated: Boolean = true): NavigationResult {
        if (state.phase == ReadiumReaderSessionState.Phase.DISPOSED) return NavigationResult.SessionDisposed
        val index = tocIndex ?: return NavigationResult.TocNotReady
        val link = index.targets[entryId] ?: return NavigationResult.UnknownTocEntry
        return goTo(link, animated)
    }

    fun openProgressScrubSession(sessionId: Long): Boolean {
        val opened = progressScrubOwnership.open(sessionId)
        if (opened) navigator?.invalidateProgressNavigation()
        return opened
    }

    fun reserveProgressScrubFinal(owner: ProgressNavigationOwner): Boolean =
        owner.phase == ProgressNavigationOwner.Phase.FINAL &&
            progressScrubOwnership.reserve(owner)

    fun invalidateProgressScrubSession(sessionId: Long): Boolean {
        val invalidated = progressScrubOwnership.invalidate(sessionId)
        if (invalidated) navigator?.invalidateProgressNavigation()
        return invalidated
    }

    /** Seeks by continuous progression; logical positions remain metadata only. */
    suspend fun goToProgression(
        progression: Double,
        animated: Boolean = false,
        progressOwner: ProgressNavigationOwner? = null,
        canonicalTarget: Locator? = null,
        canonicalReadingOrderIndex: Int? = null,
    ): NavigationResult {
        val startedMs = SystemClock.elapsedRealtime()
        val result = try {
            goToProgressionInternal(progression, animated, progressOwner, canonicalTarget, canonicalReadingOrderIndex)
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            progressDiagnostic(progressOwner, "progress_navigation_terminal", mapOf(
                "result" to "cancelled", "sideEffectsApplied" to false, "reason" to "task_cancelled",
            ))
            throw cancelled
        } catch (_: Exception) {
            NavigationResult.Failed
        }
        val current = progressOwner == null || progressScrubOwnership.isLatestRequest(progressOwner)
        progressDiagnostic(progressOwner, "progress_native_navigation", mapOf(
            "result" to if (result == NavigationResult.RecoveredTimeout) "recovered_timeout" else if (!current) "rejected_stale" else if (result.accepted) "accepted" else "failed",
            "navigationElapsedMs" to (SystemClock.elapsedRealtime() - startedMs),
        ))
        progressDiagnostic(progressOwner, "progress_navigation_terminal", mapOf(
            "result" to if (result == NavigationResult.RecoveredTimeout) "recovered_timeout" else if (!current || result == NavigationResult.Cancelled) "superseded" else if (result.accepted) "committed" else "failed",
            "sideEffectsApplied" to (current && result.accepted),
            "sideEffectsScope" to if (result == NavigationResult.RecoveredTimeout) "scheduler_ownership" else "navigation",
            "nextPendingPreviewId" to progressOwner?.let { progressScrubOwnership.pendingAfter(it)?.requestId },
            "nextPendingIsFinal" to progressOwner?.let { progressScrubOwnership.pendingAfter(it)?.phase == ProgressNavigationOwner.Phase.FINAL },
            "reason" to result.javaClass.simpleName,
        ))
        return result
    }

    private suspend fun goToProgressionInternal(
        progression: Double,
        animated: Boolean = false,
        progressOwner: ProgressNavigationOwner? = null,
        canonicalTarget: Locator? = null,
        canonicalReadingOrderIndex: Int? = null,
    ): NavigationResult {
        if (canonicalTarget != null && progressOwner?.phase != ProgressNavigationOwner.Phase.FINAL) return NavigationResult.InvalidLocator
        if (progressOwner != null) {
            if (!progressScrubOwnership.reserve(progressOwner)) {
                progressDiagnostic(progressOwner, "progress_native_navigation", mapOf("result" to "rejected_stale"))
                return NavigationResult.Cancelled
            }
        } else {
            progressScrubOwnership.invalidate()
            navigator?.invalidateProgressNavigation()
        }
        val normalized = normalizeRequestedProgression(progression) ?: run {
            progressDiagnostic(progressOwner, "progress_invalid_progression_decision", mapOf(
                "stage" to "before_navigation", "requestedNormalizedProgress" to progression.takeIf { it.isFinite() },
                "viewportAlreadyVerified" to false, "authorityStillCurrent" to true,
                "validationDomain" to "NORMALIZED", "valueBeingValidated" to progression.takeIf { it.isFinite() },
                "validationResult" to "invalid", "terminalMutationAttempted" to true,
            ))
            progressDiagnostic(progressOwner, "progress_terminal_transition", mapOf(
                "fromState" to "REQUESTED", "toState" to "FAILED", "reason" to "InvalidProgression",
                "viewportVerified" to false, "authorityStillCurrent" to true,
            ))
            return NavigationResult.InvalidProgression
        }
        progressLog("READIUM_PROGRESS_SEEK_NATIVE_RECEIVED target=$normalized")
        if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
            return goToContinuousProgression(normalized, progressOwner, canonicalTarget, canonicalReadingOrderIndex)
        }
        return navigationMutex.withLock {
            if (progressOwner != null && !progressScrubOwnership.isCurrent(progressOwner)) {
                return@withLock NavigationResult.Cancelled
            }
            when (val gate = state.beginNavigation()) {
                ReadiumNavigationGate.Disposed -> NavigationResult.SessionDisposed
                ReadiumNavigationGate.NotReady -> NavigationResult.NavigatorNotReady
                ReadiumNavigationGate.Busy -> NavigationResult.Cancelled
                is ReadiumNavigationGate.Granted -> {
                    try {
                    cancelManualPaginatedSessionForNavigation()
                    listener.onStateChanged(
                        State.NavigationStarted(
                            ReadiumNavigationCommand.PROGRESSION,
                            gate.generation,
                            progressOwner,
                        ),
                    )
                    val target: ReadiumProgressionTarget? = withContext(Dispatchers.IO) {
                        if (canonicalTarget != null) return@withContext PublicationProgressionTarget(normalized, canonicalTarget)
                        val openedPublication = publication ?: return@withContext null
                        if (openedPublication.readingOrder.size == 1) {
                            val rendered = (presentationState as? ReadiumPresentationState.Paginated)
                                ?.page
                                ?.takeIf { it.publicationScoped }
                            if (rendered != null) {
                                renderedPageTarget(normalized, rendered.count)
                            } else {
                                openedPublication.locatorFromLink(openedPublication.readingOrder.single())
                                    ?.withContinuousProgression(normalized)
                                    ?.let { ResourceProgressionTarget(normalized, it) }
                            }
                        } else {
                            openedPublication.locateProgression(normalized)
                                ?.let { PublicationProgressionTarget(normalized, it) }
                        }
                    }
                    progressLog("READIUM_PROGRESS_SEEK_STRATEGY strategy=${target?.javaClass?.simpleName ?: "unavailable"}")
                    val locator = when (target) {
                        is ResourceProgressionTarget -> target.locator
                        is PublicationProgressionTarget -> target.locator
                        else -> null
                    }
                    if (locator != null) {
                        progressLog(
                            "READIUM_PROGRESS_SEEK_LOCATOR hasHref=${locator.href.toString().isNotBlank()} " +
                                "hasResourceProgression=${locator.locations.progression != null} " +
                                "resourceProgression=${locator.locations.progression} " +
                                "hasTotalProgression=${locator.locations.totalProgression != null} " +
                                "totalProgression=${locator.locations.totalProgression}",
                        )
                    }
                    progressTargetDiagnostic(progressOwner, normalized, locator)
                    val result = if (target == null) {
                        NavigationResult.InvalidProgression
                    } else if (progressOwner != null) {
                        pendingProgressSeek = normalized
                        executeOwnedPaginatedNavigation(gate, target, progressOwner)
                    } else {
                        pendingProgressSeek = normalized
                        progressLog("READIUM_PROGRESS_SEEK_NAVIGATOR_CALL")
                        executeLockedNavigation(
                            gate = gate,
                            command = ReadiumNavigationCommand.PROGRESSION,
                            action = { activeNavigator ->
                                when (target) {
                                    is RenderedPageTarget -> activeNavigator.goToRenderedPage(target.pageIndex, animated)
                                    is ResourceProgressionTarget -> activeNavigator.go(target.locator, animated)
                                    is PublicationProgressionTarget -> activeNavigator.go(target.locator, animated)
                                }
                            },
                        )
                    }
                    progressLog("READIUM_PROGRESS_SEEK_NAVIGATOR_RESULT success=${result == NavigationResult.Completed}")
                    if (result != NavigationResult.Completed) pendingProgressSeek = null
                    if (target == null) completeNavigation(gate, ReadiumNavigationCommand.PROGRESSION, Error.InvalidProgression)
                    result
                    } finally {
                        if (progressOwner != null && state.completeNavigation(gate.generation)) {
                            progressScrubOwnership.finish(progressOwner, false)
                        }
                    }
                }
            }
        }
    }

    private suspend fun goToContinuousProgression(
        normalized: Double,
        progressOwner: ProgressNavigationOwner?,
        canonicalTarget: Locator? = null,
        canonicalReadingOrderIndex: Int? = null,
    ): NavigationResult = navigationMutex.withLock {
        if (progressOwner != null && !progressScrubOwnership.isCurrent(progressOwner)) {
            return@withLock NavigationResult.Cancelled
        }
        when (val gate = state.beginNavigation()) {
            ReadiumNavigationGate.Disposed -> NavigationResult.SessionDisposed
            ReadiumNavigationGate.NotReady -> NavigationResult.NavigatorNotReady
            ReadiumNavigationGate.Busy -> NavigationResult.Cancelled
            is ReadiumNavigationGate.Granted -> {
                var lease: ProgressNavigationLease? = null
                var terminalResult = "failed"
                try {
                listener.onStateChanged(
                    State.NavigationStarted(
                        ReadiumNavigationCommand.PROGRESSION,
                        gate.generation,
                        progressOwner,
                    ),
                )
                val positions = positionsCache?.get()?.getOrNull()
                val locator = canonicalTarget ?: positions?.continuousPositionMap?.targetFor(normalized)
                val targetReadingOrderIndex = canonicalReadingOrderIndex ?: locator?.let { target ->
                    positions?.positionsByReadingOrder?.indexOfFirst { resource ->
                        resource.any { it.href.toString() == target.href.toString() }
                    }?.takeIf { it >= 0 }
                }
                progressTargetDiagnostic(progressOwner, normalized, locator, targetReadingOrderIndex)
                if (progressOwner != null) {
                    lease = ProgressNavigationLease(progressOwner, gate.generation) { kind, fields ->
                        progressDiagnostic(progressOwner, kind, fields)
                    }
                    progressDiagnostic(progressOwner, "progress_navigation_ownership", mapOf(
                        "result" to "acquired", "reason" to "native_requested",
                    ))
                }
                val progressNavigationStartedMs = SystemClock.elapsedRealtime()
                if (progressOwner?.phase != ProgressNavigationOwner.Phase.PREVIEW &&
                    locator != null && targetReadingOrderIndex != null
                ) {
                    state.recordContinuousCanonicalTarget(
                        generation = gate.generation,
                        href = locator.href.toString(),
                        readingOrderIndex = targetReadingOrderIndex,
                        position = locator.locations.position,
                        totalProgression = locator.locations.totalProgression,
                    )
                    progressDiagnostic(progressOwner, "progress_a11_state", mapOf("a11State" to "requested_pending"))
                }
                val navigation = locator?.let {
                    runCatching {
                        suspend fun navigate(): ContinuousNavigationResult = (continuousRendition?.goWithOutcome(it, gate.generation) {
                            state.isActive() && state.navigationGeneration == gate.generation &&
                                (progressOwner == null || progressScrubOwnership.isCurrent(progressOwner))
                        }
                            ?: ContinuousNavigationResult(
                                gate.generation,
                                ContinuousNavigationOutcome.FAILED_BEFORE_POSITION,
                            )).also { outcome ->
                                if (progressNavigationCompletion(outcome, true,
                                    state.isCurrentContinuousNavigation(gate.generation) &&
                                        (progressOwner == null || progressScrubOwnership.isCurrent(progressOwner))) ==
                                    ProgressNavigationCompletion.COMMITTED) lease?.markVerified()
                            }
                        val activeLease = lease
                        if (activeLease != null) activeLease.awaitVerification { navigate() } else navigate()
                    }.onFailure { error ->
                        if (error is kotlinx.coroutines.CancellationException) throw error
                        if (progressOwner?.phase != ProgressNavigationOwner.Phase.PREVIEW) {
                            listener.onRecoverableError(Error.NavigationFailed(error))
                        }
                    }
                        .getOrElse {
                            ContinuousNavigationResult(
                                gate.generation,
                                ContinuousNavigationOutcome.FAILED_BEFORE_POSITION,
                            )
                        }
                }
                if (lease?.timedOut == true) {
                    terminalResult = "recovered_timeout"
                    return@withLock NavigationResult.RecoveredTimeout
                }
                val resultRecorded = navigation?.let {
                    state.recordContinuousNavigationResult(it, gate.generation)
                } == true
                fun authorityCurrent() = state.isCurrentContinuousNavigation(gate.generation) &&
                    (progressOwner == null || progressScrubOwnership.isCurrent(progressOwner))
                fun completion() = progressNavigationCompletion(
                    if (resultRecorded) state.latestContinuousNavigationResult else navigation,
                    resultRecorded, authorityCurrent(),
                )
                val verifiedTarget = completion() == ProgressNavigationCompletion.COMMITTED
                progressDiagnosticTarget?.takeIf { it.owner == progressOwner }?.verificationResult =
                    progressVerificationDiagnosticFields(navigation?.finalViewportVerification, normalized, targetReadingOrderIndex,
                        resultRecorded && authorityCurrent())["result"] as? String
                progressDiagnostic(progressOwner, "progress_navigation_verified",
                    progressVerificationDiagnosticFields(
                        navigation?.finalViewportVerification, normalized, targetReadingOrderIndex,
                        resultRecorded && authorityCurrent(),
                    ) + mapOf("navigationElapsedMs" to (SystemClock.elapsedRealtime() - progressNavigationStartedMs),
                        "a11State" to if (progressOwner?.phase == ProgressNavigationOwner.Phase.FINAL && verifiedTarget) "verified" else "none"))
                progressDiagnostic(progressOwner, "progress_invalid_progression_decision", mapOf(
                    "stage" to "after_a10", "requestedNormalizedProgress" to normalized,
                    "requestedResourceProgression" to locator?.locations?.progression,
                    "requestedTotalProgression" to locator?.locations?.totalProgression,
                    "observedResourceProgression" to navigation?.finalViewportVerification?.finalVisibleProgression,
                    "observedTotalProgression" to null,
                    "viewportAlreadyVerified" to verifiedTarget, "authorityStillCurrent" to authorityCurrent(),
                    "valueBeingValidated" to navigation?.outcome?.name, "validationDomain" to "OTHER",
                    "validationResult" to if (verifiedTarget) "a10_authoritative" else "not_verified",
                    "terminalMutationAttempted" to (completion() == ProgressNavigationCompletion.FAILED),
                ))
                if (verifiedTarget) {
                    pendingProgressSeek = normalized
                    progressDiagnostic(progressOwner, "progress_viewport_snapshot",
                        progressVerificationDiagnosticFields(navigation?.finalViewportVerification, normalized,
                            targetReadingOrderIndex, authorityCurrent()) + mapOf(
                            "stage" to "after_navigation", "snapshotSource" to "a10_verified_viewport",
                        ))
                }
                // Request a real visible Locator after verification, including
                // verified targets whose separate navigation outcome was not accepted.
                val finalPublication = if (verifiedTarget && authorityCurrent()) {
                    requestContinuousLocatorUpdate(
                        ContinuousPositionSource.VERIFIED_NAVIGATION,
                        progressOwner = progressOwner,
                    )
                } else null
                val publicationFailed = progressOwner?.phase == ProgressNavigationOwner.Phase.FINAL &&
                    verifiedTarget && kotlinx.coroutines.withTimeoutOrNull(PROGRESS_NAVIGATION_WATCHDOG_MS) {
                        finalPublication?.await() == true
                    } != true
                if (publicationFailed) finalPublication?.complete(false)
                val terminal = completion() // Drag/supersession during publication is still authoritative.
                terminalResult = terminal.name.lowercase()
                if (publicationFailed && terminal == ProgressNavigationCompletion.COMMITTED) {
                    progressDiagnostic(progressOwner, "progress_position_publication", mapOf(
                        "result" to "failed", "reason" to "settled_publication_unavailable", "source" to "final_navigation",
                        "stage" to "final_publication_wait",
                    ))
                    progressDiagnostic(progressOwner, "progress_invalid_progression_decision", mapOf(
                        "stage" to "after_publication", "viewportAlreadyVerified" to true,
                        "authorityStillCurrent" to true, "validationDomain" to "CANONICAL",
                        "valueBeingValidated" to "publication_failed", "validationResult" to "separate_publication_failure",
                        "terminalMutationAttempted" to false,
                    ))
                }
                progressDiagnostic(progressOwner, "progress_terminal_transition", mapOf(
                    "fromState" to if (verifiedTarget) "VERIFIED" else "NAVIGATING",
                    "toState" to terminal.name, "viewportVerified" to verifiedTarget,
                    "authorityStillCurrent" to authorityCurrent(),
                    "reason" to when (terminal) {
                        ProgressNavigationCompletion.COMMITTED -> "verified_target_viewport"
                        ProgressNavigationCompletion.SUPERSEDED -> "authority_invalidated"
                        ProgressNavigationCompletion.FAILED -> if (verifiedTarget) "explicit_viewport_invalidation" else "target_not_verified"
                    },
                ))
                if (terminal == ProgressNavigationCompletion.SUPERSEDED) {
                    state.completeNavigation(gate.generation)
                    return@withLock NavigationResult.Cancelled
                }
                val completed = completeNavigation(
                    gate,
                    ReadiumNavigationCommand.PROGRESSION,
                    if (terminal == ProgressNavigationCompletion.COMMITTED) null else Error.InvalidProgression,
                )
                if (publicationFailed && completed == NavigationResult.Completed)
                    NavigationResult.CompletedWithPublicationFailure else completed
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    terminalResult = "cancelled"
                    throw cancelled
                } finally {
                    val ownedLease = lease
                    if (ownedLease != null) finishProgressNavigation(ownedLease, terminalResult)
                    else {
                        state.completeNavigation(gate.generation)
                        if (progressOwner != null) progressScrubOwnership.finish(progressOwner, false)
                    }
                }
            }
        }
    }

    private fun finishProgressNavigation(lease: ProgressNavigationLease, terminalResult: String) {
        lease.finish(terminalResult) {
            if (terminalResult == "recovered_timeout" && state.isCurrentContinuousNavigation(lease.generation)) {
                recoveredProgressPublicationFence.recover(lease.generation)
            }
            val cleared = state.completeNavigation(lease.generation) ||
                (state.navigationGeneration == lease.generation && !state.navigationInFlight)
            val pending = progressScrubOwnership.pendingAfter(lease.owner)
            progressScrubOwnership.finish(lease.owner, terminalResult == "committed")
            progressDiagnostic(lease.owner, "progress_navigation_ownership", mapOf(
                "result" to "released", "terminalResult" to terminalResult,
                "activeSlotCleared" to cleared, "reason" to "terminal_finally",
                "nextPendingPreviewId" to pending?.requestId,
                "nextPendingIsFinal" to (pending?.phase == ProgressNavigationOwner.Phase.FINAL),
            ))
            if (pending != null) progressDiagnostic(pending, "progress_pending_dispatch", mapOf(
                "reason" to if (pending.phase == ProgressNavigationOwner.Phase.FINAL) "active_terminal_final_priority" else "active_terminal_latest",
                "oldPreviewId" to lease.owner.requestId, "nextPreviewId" to pending.requestId,
                "nextIsFinal" to (pending.phase == ProgressNavigationOwner.Phase.FINAL),
            ))
        }
    }

    private data class OwnedPaginatedNavigation(
        val owner: ProgressNavigationOwner,
        val generation: Long,
        val completion: CompletableDeferred<Boolean>,
    )

    private suspend fun executeOwnedPaginatedNavigation(
        gate: ReadiumNavigationGate.Granted,
        target: ReadiumProgressionTarget,
        owner: ProgressNavigationOwner,
    ): NavigationResult {
        val lease = ProgressNavigationLease(owner, gate.generation) { kind, fields -> progressDiagnostic(owner, kind, fields) }
        var terminalResult = "failed"
        progressDiagnostic(owner, "progress_navigation_ownership", mapOf("result" to "acquired", "reason" to "native_requested"))
        try {
        cancelManualPaginatedSessionForNavigation()
        val activeNavigator = navigator
            ?: return completeNavigation(gate, ReadiumNavigationCommand.PROGRESSION, Error.NavigatorNotReady)
        if (!progressScrubOwnership.isCurrent(owner)) {
            terminalResult = "superseded"
            completeNavigation(gate, ReadiumNavigationCommand.PROGRESSION)
            return NavigationResult.Cancelled
        }

        listener.onStateChanged(
            State.NavigationStarted(
                ReadiumNavigationCommand.PROGRESSION,
                gate.generation,
                owner,
            ),
        )
        val pending = OwnedPaginatedNavigation(owner, gate.generation, CompletableDeferred())
        ownedPaginatedNavigations[owner.token] = pending
        val origin = EpubNavigatorFragment.ProgressNavigationOrigin(
            token = owner.token,
            isCurrent = {
                state.isActive() && state.navigationGeneration == gate.generation &&
                    progressScrubOwnership.isCurrent(owner)
            },
            onStale = { pending.completion.complete(false) },
        )
        val accepted = runCatching {
            when (target) {
                is RenderedPageTarget -> activeNavigator.goToRenderedPage(target.pageIndex, false, origin)
                is ResourceProgressionTarget -> activeNavigator.go(target.locator, false, origin)
                is PublicationProgressionTarget -> activeNavigator.go(target.locator, false, origin)
            }
        }.onFailure {
            if (owner.phase == ProgressNavigationOwner.Phase.FINAL) {
                listener.onRecoverableError(Error.NavigationFailed(it))
            }
        }
            .getOrDefault(false)
        if (!accepted) pending.completion.complete(false)

        val published = try {
            lease.awaitVerification {
                pending.completion.await().also { if (it && progressScrubOwnership.isCurrent(owner)) lease.markVerified() }
            }
        } finally {
            ownedPaginatedNavigations.remove(owner.token, pending)
        }
        if (lease.timedOut) {
            terminalResult = "recovered_timeout"
            return NavigationResult.RecoveredTimeout
        }
        completeNavigation(gate, ReadiumNavigationCommand.PROGRESSION)
        return if (published == true && progressScrubOwnership.isCurrent(owner)) {
            terminalResult = "committed"
            NavigationResult.Completed
        } else {
            terminalResult = "superseded"
            NavigationResult.Cancelled
        }
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            terminalResult = "cancelled"
            throw cancelled
        } finally {
            finishProgressNavigation(lease, terminalResult)
        }
    }

    private fun completeOwnedPaginatedNavigation(owner: ProgressNavigationOwner, published: Boolean) {
        ownedPaginatedNavigations[owner.token]?.completion?.complete(published)
    }

    /**
     * Cancels bootstrap work and listener registration. Keep the publication
     * alive across a configuration change because the restored navigator still
     * owns it; normal finishing closes it here.
     */
    fun dispose(retainPublicationForRestoredNavigator: Boolean = false) {
        if (!state.dispose()) return
        progressScrubOwnership.invalidate()
        navigator?.invalidateProgressNavigation()
        ownedPaginatedNavigations.values.forEach { it.completion.complete(false) }
        ownedPaginatedNavigations.clear()
        initializationJob?.cancel()
        initializationJob = null
        locatorObservationJob?.cancel()
        locatorObservationJob = null
        positionsLoadJob?.cancel()
        positionsLoadJob = null
        tocLoadJob?.cancel()
        tocLoadJob = null
        searchStateObservationJob?.cancel()
        searchStateObservationJob = null
        tocIndex = null
        searchOwner?.close()
        searchOwner = null
        preferenceCoordinator.dispose().forEach { request ->
            preferenceCallbacks.remove(request.generation)?.invoke(PreferenceResult.Cancelled)
        }
        preferencePreviewRequestIds.clear()
        continuousReflowPublicationGate = null
        selectionCoordinator.dispose()
        decorationCoordinator.dispose()
        fragmentLifecycleCallbacks?.let(fragmentManager::unregisterFragmentLifecycleCallbacks)
        fragmentLifecycleCallbacks = null
        if (!retainPublicationForRestoredNavigator) {
            removeNavigatorFragment()
        }
        continuousRendition?.dispose()
        continuousRendition = null
        continuousLocatorJob?.cancel()
        continuousLocatorJob = null
        continuousLocatorDispatchGate.clear()
        if (!retainPublicationForRestoredNavigator) {
            publication?.let(::closeQuietly)
            publication = null
            positionsCache = null
        }
        navigator = null
        latestPosition = null
        latestPositionFingerprint = null
        latestContinuousReadingOrderIndex = null
        listener.onStateChanged(State.Disposed)
    }

    /**
     * A normal route finish must remove its navigator fragment. Keeping the
     * fragment tagged in the activity would make the next PlatformView treat
     * it as a restored navigator attached to the old host container, leaving
     * the new host with no WebView. Configuration-change restoration is the
     * only path that intentionally retains the fragment.
     */
    private fun removeNavigatorFragment() {
        val activeNavigator = navigator ?: return
        if (!activeNavigator.isAdded || fragmentManager.isDestroyed) return
        runCatching {
            fragmentManager.beginTransaction()
                .remove(activeNavigator)
                .commitNowAllowingStateLoss()
        }.onFailure { error ->
            Log.w(TAG, "Failed to remove navigator fragment during route disposal", error)
        }
    }

    private fun attachNavigator(containerId: Int) {
        if (!state.isActive()) return
        if (containerId <= 0) {
            fail(Error.InvalidHostContainer)
            return
        }
        val openedPublication = publication ?: return fail(Error.PublicationOpeningFailed("publication_missing"))
        registerFragmentLifecycleCallbacks()
        val existingByTag = fragmentManager.findFragmentByTag(NAVIGATOR_TAG)
        if (existingByTag != null && existingByTag !is EpubNavigatorFragment) {
            fail(Error.IncompatibleRestoredNavigator)
            return
        }
        val existing = existingByTag as? EpubNavigatorFragment
        val attached = if (existing != null) {
            if (existing.id != containerId) {
                fail(Error.IncompatibleRestoredNavigator)
                return
            }
            restoredNavigator = true
            existing
        } else {
            if (fragmentManager.isStateSaved) {
                fail(Error.FragmentAttachmentFailed())
                return
            }
            runCatching {
                val factory = EpubNavigatorFactory(openedPublication, EpubNavigatorFactory.Configuration())
                fragmentManager.fragmentFactory = factory.createFragmentFactory(
                    initialLocator = null,
                    initialPreferences = initialPreferences,
                    paginationListener = paginationListener,
                    configuration = navigatorConfiguration,
                )
                val fragment = fragmentManager.fragmentFactory.instantiate(
                    classLoader,
                    EpubNavigatorFragment::class.java.name,
                ) as EpubNavigatorFragment
                fragmentManager.beginTransaction().add(containerId, fragment, NAVIGATOR_TAG).commitNow()
                fragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                    ?: error("Navigator fragment was not attached")
            }.getOrElse { error ->
                fail(Error.NavigatorCreationFailed(error))
                return
            }
        }
        navigator = attached
        attached.paginationListener = paginationListener
        if (!state.navigatorAttached(restoredNavigator)) return
        listener.onStateChanged(State.NavigatorAttached(restoredNavigator))
        if (attached.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
            onNavigatorViewReady(attached)
        }
    }

    private fun registerFragmentLifecycleCallbacks() {
        if (fragmentLifecycleCallbacks != null) return
        fragmentLifecycleCallbacks = object : FragmentManager.FragmentLifecycleCallbacks() {
            override fun onFragmentStarted(
                manager: FragmentManager,
                fragment: Fragment,
            ) {
                if (fragment === navigator || fragment.tag == NAVIGATOR_TAG) {
                    (fragment as? EpubNavigatorFragment)?.let(::onNavigatorViewReady)
                }
            }
        }.also { callbacks ->
            fragmentManager.registerFragmentLifecycleCallbacks(callbacks, false)
        }
    }

    private fun onNavigatorViewReady(readyNavigator: EpubNavigatorFragment) {
        if (readyNavigator !== navigator || !state.navigatorReady()) return
        listener.onStateChanged(State.NavigatorReady)
        val locator = initialLocator
        val navigated = if (locator == null || restoredNavigator) {
            if (restoredNavigator) {
                initialRestoreDiagnostic?.finish("skipped", reason = "navigator_already_restored")
            }
            false
        } else {
            initialRestoreDiagnostic?.stage("native_navigation_request", "started")
            executeInitialLocatorNavigation(readyNavigator, locator).also { restoration ->
                if (restoration.getOrDefault(false)) {
                    initialRestoreDiagnostic?.finish("success")
                } else {
                    initialRestoreDiagnostic?.finish(
                        "failed", restoration.exceptionOrNull(),
                        "navigator_navigation_rejected".takeIf { restoration.isSuccess },
                    )
                }
            }
                .onFailure { listener.onRecoverableError(Error.InitialLocatorRestorationFailed(it)) }
                .getOrDefault(false)
        }
        if (locator != null && !restoredNavigator && !navigated) {
            listener.onRecoverableError(Error.InitialLocatorRestorationFailed())
        }
        reportOpenReady()
        if (state.initialLocatorRestored()) {
            listener.onStateChanged(State.InitialLocatorRestored(navigated))
        }
        decorationCoordinator.onNavigatorReady()
        preferenceCoordinator.onNavigatorReady()
        if (restoredNavigator) {
            // A restored fragment already owns its navigator preferences. Only an
            // explicit host payload may replace them; an Activity default never does.
            if (initialPreferencesAreAuthoritative) {
                applyPreferences(initialPreferences) { result ->
                    if (result == PreferenceResult.Failed) {
                        listener.onRecoverableError(Error.PreferenceApplicationFailed())
                    }
                }
            } else {
                preferenceCoordinator.seedInitialRequested(initialPreferences)
                listener.onStateChanged(State.PreferencesRequested(preferences()))
            }
        } else {
            // The factory consumed this value while creating the fragment; do not
            // submit it a second time after readiness.
            preferenceCoordinator.seedInitialApplied(initialPreferences)
            listener.onStateChanged(State.PreferencesApplied(preferences(), initial = true))
        }
        startLocatorObservation(readyNavigator)
        publication?.let { listener.onNavigatorReady(it, readyNavigator) }
    }

    private fun applyPreferenceRequest(request: ReadiumPreferenceCoordinator.Request<EpubPreferences>) {
        scope.launch {
            var geometryCommitOwner: EpubContinuousGeometryCommitOwner? = null
            var commitRendition: EpubContinuousRendition? = null
            var nextAfterCommitRelease: ReadiumPreferenceCoordinator.Request<EpubPreferences>? = null
            var coordinatorCompleted = false
            try {
            val activeNavigator = navigator
            val activeContinuousRendition = continuousRendition
            commitRendition = activeContinuousRendition
            val geometryReflow = renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL &&
                activeContinuousRendition?.requiresGeometryReflow(request.value) == true
            if (geometryReflow && activeContinuousRendition != null) {
                continuousReflowPublicationGate = ContinuousReflowPublicationGate(
                    rendition = activeContinuousRendition,
                    preferenceGeneration = request.generation,
                )
                Log.d(
                    TAG,
                    "CONTINUOUS_REFLOW_GATE acquire preferenceGeneration=${request.generation} result=acquired",
                )
            }
            var preservationFailure: Error? = null
            var cancelled = false
            val failure = if (!state.isActive()) {
                Error.NavigatorNotReady
            } else if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
                when (val result = activeContinuousRendition?.applyPreferencesWithDiagnostics(
                    request.value,
                    request.generation,
                    request.diagnosticContext?.let { context ->
                        org.readium.r2.navigator.epub.continuous.EpubContinuousReflowDiagnosticContext(
                            gestureId = context.gestureId,
                            slider = context.slider,
                            applyId = context.applyId,
                            normalizedValue = context.normalizedValue,
                        )
                    },
                    preferencePreviewRequestIds[request.generation],
                    holdGeometryCommitUntilSessionAcknowledged = true,
                )) {
                    EpubContinuousPreferenceResult.Applied -> null
                    is EpubContinuousPreferenceResult.ReflowCommitted -> {
                        geometryCommitOwner = result.commitOwner
                        val commitFailure = commitContinuousReflowPosition(
                            activeContinuousRendition,
                            request.generation,
                            result,
                        )
                        preservationFailure = if (commitFailure != null && result.commitOwner != null) {
                            reflowFailure("failed_after_commit_start")
                        } else commitFailure
                        emitPreferenceDiagnostic(
                            request,
                            "reflow_terminal",
                            when {
                                commitFailure == null -> "committed"
                                result.commitOwner != null -> "failed_after_commit_start"
                                else -> "failed"
                            },
                        )
                        commitFailure
                    }
                    is EpubContinuousPreferenceResult.FailedAfterCommitStart -> {
                        geometryCommitOwner = result.commitOwner
                        reflowFailure("failed_after_commit_start").also { preservationFailure = it }
                    }
                    EpubContinuousPreferenceResult.CaptureUnavailable -> reflowFailure("capture_unavailable").also { preservationFailure = it }
                    EpubContinuousPreferenceResult.TargetNotReady -> reflowFailure("target_not_ready").also { preservationFailure = it }
                    EpubContinuousPreferenceResult.SemanticRestoreFailed -> reflowFailure("semantic_restore_failed").also { preservationFailure = it }
                    EpubContinuousPreferenceResult.VisibilityMismatch -> reflowFailure("visibility_mismatch").also { preservationFailure = it }
                    EpubContinuousPreferenceResult.Cancelled -> {
                        cancelled = true
                        Error.PreferenceApplicationCancelled
                    }
                    null -> Error.NavigatorNotReady
                }
            } else if (activeNavigator == null) {
                Error.NavigatorNotReady
            } else {
                runCatching { activeNavigator.submitPreferences(request.value) }
                    .exceptionOrNull()
                    ?.let { cause ->
                        Log.w(
                            "BiblioLifeReadium",
                            "PREFERENCES_APPLY_FAILED type=${cause::class.simpleName}",
                        )
                        Error.PreferenceApplicationFailed(cause)
                    }
            }
            preferencePreviewRequestIds.remove(request.generation)
            val completion = if (cancelled) {
                preferenceCoordinator.cancel(request.generation)
            } else {
                preferenceCoordinator.complete(
                    request.generation,
                    failure == null,
                    committedDuringSupersession = geometryCommitOwner != null,
                )
            }
            coordinatorCompleted = true
            when (completion) {
                is ReadiumPreferenceCoordinator.Completion.Processed -> {
                    nextAfterCommitRelease = completion.next
                    val continuousPreferencesApplied =
                        completion.outcome == ReadiumPreferenceCoordinator.Outcome.APPLIED &&
                            renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL
                    if (continuousPreferencesApplied) {
                        continuousPreferencePublicationGeneration = completion.request.generation
                    }
                    val result = when (completion.outcome) {
                        ReadiumPreferenceCoordinator.Outcome.APPLIED -> PreferenceResult.Applied
                        ReadiumPreferenceCoordinator.Outcome.SUPERSEDED -> PreferenceResult.Cancelled
                        ReadiumPreferenceCoordinator.Outcome.FAILED -> preservationFailure?.let {
                            PreferenceResult.PositionPreservationFailed(it.code)
                        } ?: PreferenceResult.Failed
                    }
                    Log.d(
                        TAG,
                        "PREFERENCE_COMPLETE generation=${completion.request.generation} result=${result.preferenceDiagnosticResult()}",
                    )
                    emitPreferenceDiagnostic(
                        completion.request,
                        "preference_terminal",
                        when (completion.outcome) {
                            ReadiumPreferenceCoordinator.Outcome.APPLIED -> "applied"
                            ReadiumPreferenceCoordinator.Outcome.SUPERSEDED -> "superseded"
                            ReadiumPreferenceCoordinator.Outcome.FAILED -> "failed"
                        },
                    )
                    preferenceCallbacks.remove(completion.request.generation)?.invoke(result)
                    when (completion.outcome) {
                        ReadiumPreferenceCoordinator.Outcome.APPLIED ->
                            listener.onStateChanged(State.PreferencesApplied(preferences(), initial = false)).also {
                                applyPendingPagination(completion.request.generation)
                            }
                        ReadiumPreferenceCoordinator.Outcome.SUPERSEDED -> Unit
                        ReadiumPreferenceCoordinator.Outcome.FAILED -> {
                            val error = failure ?: Error.PreferenceApplicationFailed()
                            listener.onStateChanged(State.PreferencesFailed(preferences(), error))
                            listener.onRecoverableError(error)
                        }
                    }
                    releaseContinuousReflowPublicationGate(activeContinuousRendition, request.generation)
                    if (continuousPreferencesApplied && completion.next == null) {
                        requestContinuousLocatorUpdate(ContinuousPositionSource.PREFERENCES_APPLIED)
                    }
                }
                ReadiumPreferenceCoordinator.Completion.Stale ->
                    releaseContinuousReflowPublicationGate(activeContinuousRendition, request.generation).also {
                        emitPreferenceDiagnostic(request, "preference_terminal", "stale")
                        Log.d(TAG, "PREFERENCE_COMPLETE generation=${request.generation} result=stale")
                    }
            }
            } catch (error: Throwable) {
                val owner = geometryCommitOwner
                    ?: commitRendition?.geometryCommitOwner(request.generation)
                if (owner == null) throw error
                geometryCommitOwner = owner
                Log.w(TAG, "CONTINUOUS_REFLOW_GATE failure_after_commit_start type=${error::class.simpleName}")
                if (!coordinatorCompleted) {
                    preferencePreviewRequestIds.remove(request.generation)
                    val completion = preferenceCoordinator.complete(
                        request.generation,
                        succeeded = false,
                        committedDuringSupersession = true,
                    )
                    coordinatorCompleted = true
                    if (completion is ReadiumPreferenceCoordinator.Completion.Processed) {
                        nextAfterCommitRelease = completion.next
                        val failure = reflowFailure("failed_after_commit_start")
                        emitPreferenceDiagnostic(completion.request, "reflow_terminal", "failed_after_commit_start")
                        emitPreferenceDiagnostic(completion.request, "preference_terminal", "failed_after_commit_start")
                        preferenceCallbacks.remove(completion.request.generation)?.invoke(
                            PreferenceResult.PositionPreservationFailed(failure.code),
                        )
                        listener.onStateChanged(State.PreferencesFailed(preferences(), failure))
                        listener.onRecoverableError(failure)
                        releaseContinuousReflowPublicationGate(commitRendition, request.generation)
                    }
                }
            } finally {
                runCatching {
                    releaseContinuousReflowPublicationGate(commitRendition, request.generation)
                }
                val owner = geometryCommitOwner
                val released = if (owner == null) {
                    true
                } else {
                    releaseCommitOwnerBeforeStartingNext(
                        releaseOwner = { commitRendition?.acknowledgeGeometryCommit(owner) == true },
                        isOwnerHeld = { commitRendition?.geometryCommitOwner(request.generation) == owner },
                        startNext = { nextAfterCommitRelease?.let(::applyPreferenceRequest) },
                    )
                }
                if (owner == null) {
                    nextAfterCommitRelease?.let(::applyPreferenceRequest)
                } else if (!released) {
                    Log.w(TAG, "CONTINUOUS_REFLOW_GATE next_waiting_for_owner_release preferenceGeneration=${request.generation}")
                }
            }
        }
    }

    private fun EpubPreferences.preferenceFontFamily(): String = fontFamily?.name ?: "original"

    private fun onContinuousReflowDiagnostic(
        event: org.readium.r2.navigator.epub.continuous.EpubContinuousReflowDiagnosticEvent,
    ) {
        if (event.kind == "viewport_snapshot" &&
            event.snapshotStage == "after_anchor_verified" &&
            event.preferenceGeneration != null
        ) {
            latestVerifiedViewportSnapshot = event
        }
        val fields = buildMap<String, Any?> {
            put("level", "debug")
            put("kind", event.kind)
            put("result", event.result)
            event.preferenceGeneration?.let { put("preferenceGeneration", it) }
            event.transactionGeneration?.let { put("transactionGeneration", it) }
            event.layoutGeneration?.let { put("layoutGeneration", it) }
            event.resourceGeneration?.let { put("resourceGeneration", it) }
            event.measurementGeneration?.let { put("measurementGeneration", it) }
            event.readingOrderIndex?.let { put("readingOrderIndex", it) }
            event.oldHeightPx?.let { put("oldHeightPx", it) }
            event.newHeightPx?.let { put("newHeightPx", it) }
            event.anchorBeforeIndex?.let { put("anchorBeforeIndex", it) }
            event.anchorBeforeOffsetPx?.let { put("anchorBeforeOffsetPx", it) }
            event.scrollAnchorIndex?.let { put("scrollAnchorIndex", it) }
            putAll(event.semanticAnchorFields)
            event.scrollAnchorOffsetPx?.let { put("scrollAnchorOffsetPx", it) }
            event.anchorBeforeY?.let { put("anchorBeforeY", it) }
            if (event.anchorBeforeY != null) {
                event.anchorBeforeYCoordinateSpace?.let { put("anchorBeforeYCoordinateSpace", it) }
            }
            event.anchorAfterY?.let { put("anchorAfterY", it) }
            event.targetViewportYPx?.let { put("targetViewportYPx", it) }
            event.actualViewportYPx?.let { put("actualViewportYPx", it) }
            event.observedReadingOrderIndex?.let { put("observedReadingOrderIndex", it) }
            event.observedProgression?.let { put("observedProgression", it) }
            event.semanticProgressionDelta?.let { put("semanticProgressionDelta", it) }
            event.viewportScrollReason?.let { put("viewportScrollReason", it) }
            event.viewportFirstVisibleIndexBefore?.let { put("viewportFirstVisibleIndexBefore", it) }
            event.viewportFirstVisibleIndexAfter?.let { put("viewportFirstVisibleIndexAfter", it) }
            event.viewportFirstVisibleTopBeforePx?.let { put("viewportFirstVisibleTopBeforePx", it) }
            event.viewportFirstVisibleTopAfterPx?.let { put("viewportFirstVisibleTopAfterPx", it) }
            event.viewportFirstVisibleTopDeltaPx?.let { put("viewportFirstVisibleTopDeltaPx", it) }
            event.snapshotStage?.let { put("snapshotStage", it) }
            event.viewportSampleStage?.let { put("viewportSampleStage", it) }
            event.anchorPointSampleStage?.let { put("anchorPointSampleStage", it) }
            event.viewportFirstVisibleIndex?.let { put("viewportFirstVisibleIndex", it) }
            event.viewportFirstVisibleTopPx?.let { put("viewportFirstVisibleTopPx", it) }
            event.viewportHeightPx?.let { put("viewportHeightPx", it) }
            event.viewportPaddingTopPx?.let { put("viewportPaddingTopPx", it) }
            event.viewportPaddingBottomPx?.let { put("viewportPaddingBottomPx", it) }
            event.viewportAnchorIndex?.let { put("viewportAnchorIndex", it) }
            event.viewportAnchorTopPx?.let { put("viewportAnchorTopPx", it) }
            event.viewportAnchorBottomPx?.let { put("viewportAnchorBottomPx", it) }
            event.webViewIdentity?.let { put("webViewIdentity", it) }
            event.webViewIdentityUnavailableReason?.let { put("webViewIdentityUnavailableReason", it) }
            event.anchorResourceHref?.let { put("anchorResourceHref", it) }
            event.anchorResourceHrefUnavailableReason?.let { put("anchorResourceHrefUnavailableReason", it) }
            event.anchorProgression?.let { put("anchorProgression", it) }
            event.anchorBeforeLocalYPx?.let { put("anchorBeforeLocalYPx", it) }
            event.anchorBeforeViewportYPx?.let { put("anchorBeforeViewportYPx", it) }
            event.anchorPointDocumentYPx?.let { put("anchorPointDocumentYPx", it) }
            event.anchorPointViewportYPx?.let { put("anchorPointViewportYPx", it) }
            event.anchorPointAvailable?.let { put("anchorPointAvailable", it) }
            event.anchorPointUnavailableReason?.let { put("anchorPointUnavailableReason", it) }
            event.anchorViewportDeltaPx?.let { put("anchorViewportDeltaPx", it) }
            event.anchorViewportTolerancePx?.let { put("anchorViewportTolerancePx", it) }
            event.anchorSemanticMatch?.let { put("anchorSemanticMatch", it) }
            event.requestedCorrectionOffsetPx?.let { put("requestedCorrectionOffsetPx", it) }
            event.requestedViewportDeltaPx?.let { put("requestedViewportDeltaPx", it) }
            event.scrollRequestIssued?.let { put("scrollRequestIssued", it) }
            event.commitLockHeld?.let { put("commitLockHeld", it) }
            event.predecessorMeasurementCount?.let { put("predecessorMeasurementCount", it) }
            event.predecessorHeightDeltaPx?.let { put("predecessorHeightDeltaPx", it) }
            event.batchHeightDeltaPx?.let { put("batchHeightDeltaPx", it) }
            event.context?.let { context ->
                put("gestureId", context.gestureId)
                put("slider", context.slider)
                put("applyId", context.applyId)
                put("normalizedValue", context.normalizedValue)
            }
        }
        runCatching { listener.onStateChanged(State.Diagnostic(fields)) }
    }

    private fun emitPreferenceDiagnostic(
        request: ReadiumPreferenceCoordinator.Request<EpubPreferences>,
        kind: String,
        result: String,
        dispatchStage: String? = null,
        intervalSincePreviousMs: Double? = null,
        activeApply: Boolean? = null,
        pendingLatest: Boolean? = null,
    ) {
        val fields = buildMap<String, Any?> {
            put("kind", kind)
            put("result", result)
            put("preferenceGeneration", request.generation)
            dispatchStage?.let { put("dispatchStage", it) }
            intervalSincePreviousMs?.let { put("intervalSincePreviousMs", it) }
            activeApply?.let { put("activeApply", it) }
            pendingLatest?.let { put("pendingLatest", it) }
            request.diagnosticContext?.let { context ->
                put("gestureId", context.gestureId)
                put("slider", context.slider)
                put("applyId", context.applyId)
                put("normalizedValue", context.normalizedValue)
            }
        }
        runCatching { listener.onStateChanged(State.Diagnostic(fields)) }
    }

    private fun PreferenceResult.preferenceDiagnosticResult(): String = when (this) {
        PreferenceResult.Applied -> "applied"
        PreferenceResult.Unchanged -> "unchanged"
        PreferenceResult.NavigatorNotReady -> "navigator_not_ready"
        PreferenceResult.SessionDisposed -> "session_disposed"
        PreferenceResult.Cancelled -> "cancelled"
        is PreferenceResult.PositionPreservationFailed -> "position_preservation_failed:$reason"
        PreferenceResult.Failed -> "failed"
    }

    private fun reflowFailure(reason: String): Error =
        Error.PreferencePositionPreservationFailed(reason)

    private fun commitContinuousReflowPosition(
        rendition: EpubContinuousRendition,
        preferenceGeneration: Long,
        result: EpubContinuousPreferenceResult.ReflowCommitted,
    ): Error? {
        val gate = continuousReflowPublicationGate
        if (continuousRendition !== rendition || gate?.rendition !== rendition ||
            gate.preferenceGeneration != preferenceGeneration
        ) {
            Log.d(TAG, "CONTINUOUS_REFLOW_GATE position_commit preferenceGeneration=$preferenceGeneration index=${result.readingOrderIndex} result=stale_transaction")
            return reflowFailure("stale_transaction")
        }
        val positions = positionsCache?.cachedOrNull()
        if (positions == null) {
            Log.d(TAG, "CONTINUOUS_REFLOW_GATE position_commit preferenceGeneration=$preferenceGeneration index=${result.readingOrderIndex} result=canonical_position_unavailable")
            return reflowFailure("canonical_position_unavailable")
        }
        val position = positions.continuousPositionState(
            locator = result.locator,
            readingOrderIndex = result.readingOrderIndex,
            presentation = presentationState,
        )
        if (position == null) {
            Log.d(TAG, "CONTINUOUS_REFLOW_GATE position_commit preferenceGeneration=$preferenceGeneration index=${result.readingOrderIndex} result=canonical_position_unavailable")
            return reflowFailure("canonical_position_unavailable")
        }
        if (position.locator.href != result.locator.href || position.progression == null) {
            Log.d(TAG, "CONTINUOUS_REFLOW_GATE position_commit preferenceGeneration=$preferenceGeneration index=${result.readingOrderIndex} result=canonical_position_unavailable")
            return reflowFailure("canonical_position_unavailable")
        }
        emitPosition(
            position,
            continuousReadingOrderIndex = result.readingOrderIndex,
            continuousPublicationContext = continuousPositionContext(rendition),
            continuousPublicationSource = ContinuousPositionSource.REFLOW_COMMITTED,
            diagnosticPreferenceGeneration = preferenceGeneration,
        )
        Log.d(TAG, "CONTINUOUS_REFLOW_GATE position_commit preferenceGeneration=$preferenceGeneration index=${result.readingOrderIndex} result=committed")
        return null
    }

    private fun releaseContinuousReflowPublicationGate(
        rendition: EpubContinuousRendition?,
        preferenceGeneration: Long,
    ) {
        val gate = continuousReflowPublicationGate ?: return
        if (gate.rendition === rendition && gate.preferenceGeneration == preferenceGeneration) {
            continuousReflowPublicationGate = null
            Log.d(TAG, "CONTINUOUS_REFLOW_GATE release preferenceGeneration=$preferenceGeneration result=released")
        }
    }

    private fun requestDecorations(
        group: ReadiumDecorationGroup,
        decorations: List<ReadiumDecorationSpec>,
        onComplete: (DecorationResult) -> Unit,
    ) {
        decorationCoordinator.replace(group, decorations) { completion ->
            val result = completion.toDecorationResult()
            onComplete(result)
            if (result == DecorationResult.Failed && state.isActive()) {
                listener.onRecoverableError(Error.DecorationApplicationFailed(group.nativeName))
            }
        }
    }

    private fun startLocatorObservation(activeNavigator: EpubNavigatorFragment) {
        if (!state.startLocatorObservation()) return
        val observationGeneration = state.navigationGeneration
        locatorObservationJob = scope.launch {
            activeNavigator.currentLocator.collect { locator ->
                if (!state.isActive() || observationGeneration > state.navigationGeneration) return@collect
                if (renditionBackend != ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL &&
                    paginatedManualPagePublicationGate.hasSession
                ) return@collect
                emitPosition(positionState(locator))
            }
        }
        startPositionsObservation()
    }

    /** Continuous has no Fragment currentLocator flow, but it needs the same Readium position index. */
    private fun startContinuousPositionObservation() {
        if (!state.startLocatorObservation()) return
        startPositionsObservation()
    }

    private fun startPositionsObservation() {
        positionsLoadJob = scope.launch {
            withContext(Dispatchers.IO) { positionsCache?.get() }
            if (!state.isActive()) return@launch
            if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
                requestContinuousLocatorUpdate(ContinuousPositionSource.POSITIONS_READY)
                return@launch
            }
            if (renditionBackend != ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL &&
                (paginatedManualPagePublicationGate.hasSession || latestPositionWasLiveManual)
            ) return@launch
            latestPosition?.locator?.let { locator ->
                emitPosition(
                    positionState(
                        locator = locator,
                        continuousReadingOrderIndex = latestContinuousReadingOrderIndex,
                    ),
                    continuousReadingOrderIndex = latestContinuousReadingOrderIndex,
                )
            }
        }
    }

    /**
     * The rendition already checked that this exact resource generation is
     * live. Keep the event identity until the session boundary so an obsolete
     * rendition cannot start a locator query after a host recreation.
     */
    private fun onContinuousResourceReady(
        rendition: EpubContinuousRendition,
        event: org.readium.r2.navigator.epub.continuous.EpubContinuousResourceReadyEvent,
    ) {
        if (!state.isActive()) return
        continuousResourceReadyRelay.forward(
            activeRendition = continuousRendition,
            sourceRendition = rendition,
            event = event,
            markPreferencesReady = ::onContinuousPreferencesReady,
        ) { readyEvent ->
            Log.d(TAG, "CONTINUOUS_RESOURCE_READY_RECEIVED index=${readyEvent.readingOrderIndex} generation=${readyEvent.resourceGeneration}")
            requestContinuousLocatorUpdate(ContinuousPositionSource.RESOURCE_READY)
        }
    }

    /**
     * Continuous has no Fragment STARTED callback. Its equivalent preference
     * readiness boundary is the first generation-checked resource which has
     * completed the real Readium bootstrap and already consumed the current
     * CSS snapshot. The relay guarantees this runs once per active rendition.
     */
    private fun onContinuousPreferencesReady() {
        preferenceCoordinator.onNavigatorReady()
        // ContinuousEpubRendition was constructed with these preferences and
        // applies them before emitting the resource true-ready event.
        preferenceCoordinator.seedInitialApplied(initialPreferences)
        listener.onStateChanged(State.PreferencesApplied(preferences(), initial = true))
    }

    private fun onContinuousInitialViewportReady(rendition: EpubContinuousRendition) {
        if (!state.isActive() || continuousRendition !== rendition) return
        // Without a saved position, the first real measured viewport is the
        // readiness boundary. Do not report Ready while the native cover still
        // masks content.
        if (initialLocator == null && state.initialLocatorRestored()) {
            listener.onStateChanged(State.InitialLocatorRestored(navigated = false))
            reportOpenReady()
            startContinuousPositionObservation()
        }
        requestContinuousLocatorUpdate(ContinuousPositionSource.INITIAL_VIEWPORT_READY)
    }

    private fun onContinuousInitialViewportFailed(
        rendition: EpubContinuousRendition,
        reason: String,
    ) {
        if (!state.isActive() || continuousRendition !== rendition) return
        Log.e(TAG, "CONTINUOUS_INITIAL_VIEWPORT_FAILURE reason=$reason")
        fail(Error.InitialViewportReadinessFailed(reason))
    }

    private fun requestContinuousLocatorUpdate(
        source: ContinuousPositionSource,
        liveManual: Boolean = false,
        progressOwner: ProgressNavigationOwner? = null,
    ): CompletableDeferred<Boolean>? {
        val finalCompletion = if (progressOwner?.phase == ProgressNavigationOwner.Phase.FINAL) {
            CompletableDeferred<Boolean>()
        } else null
        fun rejectFinal(): CompletableDeferred<Boolean>? {
            finalCompletion?.complete(false)
            return finalCompletion
        }
        if (!recoveredProgressPublicationFence.mayPublish(state.navigationGeneration, source.automatic)) return rejectFinal()
        if (renditionBackend != ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL || !state.isActive()) return rejectFinal()
        if (liveManual != (source == ContinuousPositionSource.MANUAL_LIVE)) return rejectFinal()
        val rendition = continuousRendition ?: return rejectFinal()
        if (continuousReflowPublicationGate?.rendition === rendition) return rejectFinal()
        if (!continuousSelectionLocatorPublicationGate.mayRequest()) {
            Log.d(TAG, "CONTINUOUS_SELECTION_LOCATOR_REQUEST_SUPPRESSED reason=native_selection_active source=${source.name}")
            return rejectFinal()
        }
        val context = continuousPositionContext(rendition)
        if (source in setOf(
                ContinuousPositionSource.VERIFIED_NAVIGATION,
                ContinuousPositionSource.INITIAL_RESTORE,
                ContinuousPositionSource.PREFERENCES_APPLIED,
            ) && manualScrollFinalPendingContext?.matches(context) == false
        ) {
            manualScrollFinalPendingContext = null
        }
        val finalPending = manualScrollFinalPendingContext?.matches(context) == true
        if (!continuousPositionPublicationGate.mayPublish(
                captured = context,
                current = continuousPositionContext(rendition),
                source = source,
                finalPending = finalPending,
            )
        ) return rejectFinal()
        // No work enters the dispatcher until the host can name the exact
        // live bootstrap-ready resource that owns the 25% parent anchor.
        val anchor = rendition.currentLocatorAnchor() ?: return rejectFinal()
        val requestIdentity = continuousManualScrollPublicationGate.requestIdentity(
            liveManual = liveManual,
            currentNavigationGeneration = state.navigationGeneration,
            navigationInFlight = state.navigationInFlight,
        ) ?: return rejectFinal()
        val request = ContinuousLocatorDispatchRequest(
            rendition = rendition,
            anchor = anchor,
            selectionPublicationEpoch = continuousSelectionLocatorPublicationGate.captureEpoch(),
            identity = requestIdentity,
            publicationContext = context,
            publicationSource = source,
            forcePublication = (!liveManual && finalPending) ||
                progressOwner?.phase == ProgressNavigationOwner.Phase.FINAL,
            owner = progressOwner,
            completion = finalCompletion,
        )
        val initial = continuousLocatorDispatchGate.offer(request) ?: return finalCompletion
        continuousLocatorJob = scope.launch {
            try {
                var next: ContinuousLocatorDispatchRequest? = initial
                while (next != null && state.isActive()) {
                    val current = next
                    // A host recreation must not let a request cross rendition
                    // ownership even if the resource index/generation coincides.
                    val renditionCurrent = continuousRendition === current.rendition
                    val selectionCurrent = continuousSelectionLocatorPublicationGate.mayPublish(current.selectionPublicationEpoch)
                    val scrollCurrent = continuousScrollRequestMayPublish(current)
                    if (renditionCurrent && selectionCurrent && scrollCurrent) {
                        Log.d(
                            TAG,
                            "CONTINUOUS_FIND_LOCATOR_ANCHOR_REQUEST source=${current.publicationSource.name} index=${current.anchor.readingOrderIndex} generation=${current.anchor.resourceGeneration}",
                        )
                        val locator = try {
                            current.rendition.findLocatorAtReadingAnchor(current.anchor)
                        } catch (cancelled: kotlinx.coroutines.CancellationException) {
                            throw cancelled
                        } catch (error: Exception) {
                            if (current.progressOwner == null) throw error
                            null
                        }
                        val sessionCurrent = state.isActive()
                        val renditionStillCurrent = continuousRendition === current.rendition
                        val selectionStillCurrent = continuousSelectionLocatorPublicationGate.mayPublish(current.selectionPublicationEpoch)
                        val scrollStillCurrent = continuousScrollRequestMayPublish(current)
                        val accepted = locator != null && sessionCurrent && renditionStillCurrent &&
                            selectionStillCurrent && scrollStillCurrent
                        if (accepted) {
                            Log.d(
                                TAG,
                                "CONTINUOUS_LOCATOR_BRIDGE_EMIT index=${current.anchor.readingOrderIndex} generation=${current.anchor.resourceGeneration} href=${locator.href}",
                            )
                            var positionPublished = false
                            try {
                                emitPosition(
                                    positionState(
                                        locator = requireNotNull(locator),
                                        continuousReadingOrderIndex = current.anchor.readingOrderIndex,
                                    ),
                                    continuousReadingOrderIndex = current.anchor.readingOrderIndex,
                                    liveAuthorization = if (current.liveManual) {
                                        LivePositionAuthorization.Continuous(current.rendition, current.identity)
                                    } else null,
                                    forcePublication = current.forcePublication,
                                    continuousPublicationContext = current.publicationContext,
                                    continuousPublicationSource = current.publicationSource,
                                    progressOwner = current.progressOwner,
                                    onPublished = {
                                        positionPublished = true
                                        current.completion?.complete(
                                            current.progressOwner?.let(progressScrubOwnership::isCurrent) == true,
                                        )
                                    },
                                )
                            } catch (error: Exception) {
                                if (current.progressOwner == null) throw error
                            } finally {
                                if (!positionPublished && current.progressOwner != null) {
                                    current.reject()
                                    progressDiagnostic(current.progressOwner, "progress_position_publication", mapOf(
                                        "result" to "failed", "reason" to "canonicalization_or_publication_failed",
                                        "stage" to "locator_publication",
                                        "source" to if (current.progressOwner?.phase == ProgressNavigationOwner.Phase.FINAL) "final_navigation" else "preview_navigation",
                                    ))
                                }
                            }
                        } else {
                            val stale = current.progressOwner?.let(progressScrubOwnership::isCurrent) == false
                            progressDiagnostic(current.progressOwner, if (stale) "progress_navigation_terminal" else "progress_position_publication", mapOf(
                                "result" to if (stale) "superseded" else "failed",
                                "sideEffectsApplied" to if (stale) false else null, "reason" to "locator_callback_rejected",
                                "resourceGeneration" to current.anchor.resourceGeneration,
                            ))
                            current.reject()
                            Log.w(
                                TAG,
                                "CONTINUOUS_LOCATOR_BRIDGE_DROP reason=${when { locator == null -> "no_locator"; !sessionCurrent -> "session_inactive"; !renditionStillCurrent -> "rendition_stale"; !selectionStillCurrent -> "selection_epoch_stale"; else -> "scroll_epoch_or_navigation_stale" }} index=${current.anchor.readingOrderIndex} generation=${current.anchor.resourceGeneration}",
                            )
                        }
                    }
                    next = continuousLocatorDispatchGate.complete(current)
                }
            } finally {
                continuousLocatorDispatchGate.clear().forEach { requestToReject ->
                    (requestToReject as? OwnedContinuousLocatorRequest)?.reject()
                }
            }
        }
        return finalCompletion
    }

    private fun continuousScrollRequestMayPublish(request: ContinuousLocatorDispatchRequest): Boolean {
        if (!recoveredProgressPublicationFence.mayPublish(request.publicationContext.navigationGeneration,
                request.publicationSource.automatic)) return false
        val owner = request.progressOwner
        if (owner?.phase == ProgressNavigationOwner.Phase.FINAL && request.completion?.isCompleted == true) return false
        if (owner != null && !progressScrubOwnership.isCurrent(owner)) return false
        return continuousManualScrollPublicationGate.mayPublish(
            identity = request.identity,
            currentNavigationGeneration = state.navigationGeneration,
            navigationInFlight = state.navigationInFlight,
        ) && continuousPositionPublicationGate.mayPublish(
            captured = request.publicationContext,
            current = continuousPositionContext(request.rendition),
            source = request.publicationSource,
            finalPending = manualScrollFinalPendingContext?.matches(request.publicationContext) == true,
        )
    }

    private data class ContinuousLocatorDispatchRequest(
        val rendition: EpubContinuousRendition,
        val anchor: EpubContinuousLocatorAnchor,
        val selectionPublicationEpoch: Long,
        val identity: ContinuousManualScrollRequestIdentity,
        val publicationContext: ContinuousPositionContext,
        val publicationSource: ContinuousPositionSource,
        val forcePublication: Boolean,
        override val owner: ProgressNavigationOwner?,
        val completion: CompletableDeferred<Boolean>?,
    ) : OwnedContinuousLocatorRequest {
        val progressOwner: ProgressNavigationOwner? get() = owner
        val liveManual: Boolean get() = identity.liveManual
        override fun reject() { completion?.complete(false) }
    }

    private fun continuousPositionContext(rendition: EpubContinuousRendition) = ContinuousPositionContext(
        rendition = rendition,
        scrollEpoch = continuousManualScrollPublicationGate.scrollEpoch,
        navigationGeneration = state.navigationGeneration,
        preferenceGeneration = continuousPreferencePublicationGeneration,
    )

    private sealed interface LivePositionAuthorization {
        data class Continuous(
            val rendition: EpubContinuousRendition,
            val identity: ContinuousManualScrollRequestIdentity,
        ) : LivePositionAuthorization

        data class Paginated(
            val identity: PaginatedManualPagePublicationGate.Identity,
        ) : LivePositionAuthorization
    }

    private data class ContinuousReflowPublicationGate(
        val rendition: EpubContinuousRendition,
        val preferenceGeneration: Long,
    )

    private fun positionState(
        locator: Locator,
        continuousReadingOrderIndex: Int? = null,
    ): ReadiumPositionState {
        if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
            val positions = positionsCache?.cachedOrNull()
            if (positions == null) {
                Log.w(
                    TAG,
                    "CONTINUOUS_POSITION_UNAVAILABLE reason=positions_cache_unavailable index=$continuousReadingOrderIndex href=${locator.href}",
                )
            } else {
                positions.continuousPositionState(
                    locator = locator,
                    readingOrderIndex = continuousReadingOrderIndex,
                    presentation = presentationState,
                )?.let { position ->
                    return state.applyVerifiedContinuousCanonicalPosition(
                        position = position,
                        readingOrderIndex = continuousReadingOrderIndex,
                    ).copy(readingOrderIndex = continuousReadingOrderIndex)
                }
                Log.w(
                    TAG,
                    "CONTINUOUS_POSITION_UNAVAILABLE reason=no_canonical_position index=$continuousReadingOrderIndex href=${locator.href} progression=${locator.locations.progression}",
                )
            }
            return ReadiumPositionState(
                locator = locator,
                progression = null,
                totalLogicalPositions = positions?.totalLogicalPositions,
                presentation = presentationState,
            )
        }
        val canonicalLocator = locator
        val resourceProgression = normalizeObservedProgression(canonicalLocator.locations.progression)
        val totalProgression = normalizeObservedProgression(canonicalLocator.locations.totalProgression)
        val effectiveProgression = if (publication?.readingOrder?.size == 1) {
            resourceProgression ?: totalProgression
        } else {
            totalProgression
        }
        return ReadiumPositionState(
            locator = canonicalLocator,
            progression = effectiveProgression,
            totalLogicalPositions = positionsCache?.cachedOrNull()?.totalLogicalPositions,
            presentation = presentationState,
        )
    }

    private val paginationListener = object : EpubNavigatorFragment.PaginationListener {
        override fun onManualPageActivityChanged(active: Boolean) {
            if (!state.isActive() || renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) return
            if (active) {
                progressScrubOwnership.invalidate()
                navigator?.invalidateProgressNavigation()
            }
            if (active && state.navigationInFlight) {
                navigator?.cancelManualPaginationForNavigation()
                return
            }
            if (paginatedManualPagePublicationGate.activityChanged(active, state.navigationGeneration)) {
                if (active) {
                    pendingPagination = null
                }
                listener.onStateChanged(State.ManualScrollActivityChanged(active))
            }
        }

        override fun onManualPageSessionCancelled() {
            val wasActive = paginatedManualPagePublicationGate.reset()
            if (pendingPagination?.manualFinal == true) pendingPagination = null
            if (wasActive) {
                listener.onStateChanged(State.ManualScrollActivityChanged(false))
            }
        }

        override fun onManualPageProgressionChanged(locator: Locator) {
            if (!state.isActive() || renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) return
            val identity = paginatedManualPagePublicationGate.request(
                liveManual = true,
                navigationGeneration = state.navigationGeneration,
                navigationInFlight = state.navigationInFlight,
            ) ?: return
            if (!paginatedManualPagePublicationGate.mayPublish(
                    identity,
                    navigationGeneration = state.navigationGeneration,
                    navigationInFlight = state.navigationInFlight,
                ) || preferenceCoordinator.snapshot().isApplying
            ) return

            emitPosition(
                positionState(locator),
                liveAuthorization = LivePositionAuthorization.Paginated(identity),
            )
        }

        override fun onManualPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
            val identity = paginatedManualPagePublicationGate.request(
                liveManual = true,
                navigationGeneration = state.navigationGeneration,
                navigationInFlight = state.navigationInFlight,
            ) ?: return
            if (!state.isActive() || !paginatedManualPagePublicationGate.mayPublish(
                    identity,
                    navigationGeneration = state.navigationGeneration,
                    navigationInFlight = state.navigationInFlight,
                )
            ) return
            val next = paginatedPresentation(pageIndex, totalPages) ?: return
            if (preferenceCoordinator.snapshot().isApplying) return
            presentationState = next
        }

        override fun onManualPageSettled(pageIndex: Int, totalPages: Int, locator: Locator) {
            val identity = paginatedManualPagePublicationGate.request(
                liveManual = false,
                navigationGeneration = state.navigationGeneration,
                navigationInFlight = state.navigationInFlight,
            ) ?: return
            if (!state.isActive() || !paginatedManualPagePublicationGate.mayPublish(
                    identity,
                    navigationGeneration = state.navigationGeneration,
                    navigationInFlight = state.navigationInFlight,
                )
            ) return
            val next = paginatedPresentation(pageIndex, totalPages) ?: return
            if (preferenceCoordinator.snapshot().isApplying) {
                pendingPagination = PendingPagination(
                    generation = layoutGeneration,
                    locator = locator,
                    presentation = next,
                    manualFinal = true,
                )
                return
            }
            presentationState = next
            val position = positionState(locator)
            publishManualPaginatedFinal(position)
        }

        override fun onPageChanged(
            pageIndex: Int,
            totalPages: Int,
            locator: Locator,
            scrollMode: Boolean,
            progressOrigin: org.readium.r2.navigator.epub.EpubNavigatorFragment.ProgressNavigationOrigin?,
        ) {
            if (!state.isActive()) return
            if (progressOrigin != null) {
                val owned = ownedPaginatedNavigations[progressOrigin.token]
                if (owned == null || !progressOrigin.isCurrent() ||
                    !progressScrubOwnership.isCurrent(owned.owner)
                ) {
                    owned?.completion?.complete(false)
                    return
                }
                if (preferenceCoordinator.snapshot().isApplying) {
                    owned.completion.complete(false)
                    return
                }
                val ownedPresentation = if (scrollMode) {
                    ReadiumPresentationState.Scrolling
                } else {
                    paginatedPresentation(pageIndex, totalPages) ?: ReadiumPresentationState.Unknown
                }
                presentationState = ownedPresentation
                pendingProgressSeek = null
                emitPosition(
                    positionState(locator),
                    progressOwner = owned.owner,
                    forcePublication = owned.owner.phase == ProgressNavigationOwner.Phase.FINAL,
                )
                progressDiagnostic(owned.owner, "progress_navigation_verified", mapOf(
                    "result" to if (progressScrubOwnership.isCurrent(owned.owner)) "verified" else "superseded",
                    "verificationSource" to "owned_page_callback",
                ))
                owned.completion.complete(progressScrubOwnership.isCurrent(owned.owner))
                return
            }
            pendingProgressSeek?.let { requested ->
                progressLog(
                    "READIUM_PROGRESS_SEEK_SETTLED requestedProgression=$requested " +
                        "resourceProgression=${locator.locations.progression} " +
                        "totalProgression=${locator.locations.totalProgression} " +
                        "renderedPageIndex=$pageIndex renderedPageCount=$totalPages",
                )
                pendingProgressSeek = null
            }
            val next = if (scrollMode) {
                ReadiumPresentationState.Scrolling
            } else {
                ReadiumRenderedPageState.create(
                    index = pageIndex,
                    count = totalPages,
                    layoutGeneration = layoutGeneration,
                    publicationScoped = publication?.readingOrder?.size == 1,
                )?.let(ReadiumPresentationState::Paginated)
                    ?: ReadiumPresentationState.Unknown
            }
            if (preferenceCoordinator.snapshot().isApplying) {
                pendingPagination = PendingPagination(layoutGeneration, locator, next)
                return
            }
            presentationState = next
            emitPosition(positionState(locator))
        }
    }

    private fun paginatedPresentation(pageIndex: Int, totalPages: Int): ReadiumPresentationState? =
        ReadiumRenderedPageState.create(
            index = pageIndex,
            count = totalPages,
            layoutGeneration = layoutGeneration,
            publicationScoped = publication?.readingOrder?.size == 1,
        )?.let(ReadiumPresentationState::Paginated)

    private fun cancelManualPaginatedSessionForNavigation() {
        navigator?.cancelManualPaginationForNavigation()
        val wasActive = paginatedManualPagePublicationGate.reset()
        if (pendingPagination?.manualFinal == true) pendingPagination = null
        if (wasActive) {
            listener.onStateChanged(State.ManualScrollActivityChanged(false))
        }
    }

    private fun invalidateRenderedPagination(generation: Long) {
        layoutGeneration = maxOf(layoutGeneration + 1, generation)
        pendingPagination = null
        if (presentationState == ReadiumPresentationState.Unknown) return
        presentationState = ReadiumPresentationState.Unknown
        if (renditionBackend != ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL &&
            paginatedManualPagePublicationGate.hasSession
        ) return
        latestPosition?.locator?.let {
            if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
                val rendition = continuousRendition ?: return@let
                emitPosition(
                    positionState(it),
                    continuousPublicationContext = continuousPositionContext(rendition),
                    continuousPublicationSource = ContinuousPositionSource.HOST_VIEWPORT,
                )
            } else {
                emitPosition(positionState(it))
            }
        }
    }

    private fun applyPendingPagination(generation: Long) {
        val pending = pendingPagination?.takeIf { it.generation == generation } ?: return
        pendingPagination = null
        presentationState = pending.presentation
        val position = positionState(pending.locator)
        if (pending.manualFinal) publishManualPaginatedFinal(position) else emitPosition(position)
    }

    private fun publishManualPaginatedFinal(position: ReadiumPositionState) {
        // A final page can equal the prior live sample or the previous checkpoint (snap-back).
        // Force only this authoritative Paginated publication through the native fingerprint.
        val sameAsLatest = position.fingerprint() == latestPositionFingerprint
        if (sameAsLatest) latestPositionFingerprint = null
        emitPosition(position)
        paginatedManualPagePublicationGate.reset()
    }

    private data class PendingPagination(
        val generation: Long,
        val locator: Locator,
        val presentation: ReadiumPresentationState,
        val manualFinal: Boolean = false,
    )

    private fun emitPosition(
        position: ReadiumPositionState,
        continuousReadingOrderIndex: Int? = null,
        liveAuthorization: LivePositionAuthorization? = null,
        forcePublication: Boolean = false,
        continuousPublicationContext: ContinuousPositionContext? = null,
        continuousPublicationSource: ContinuousPositionSource? = null,
        diagnosticPreferenceGeneration: Long? = null,
        progressOwner: ProgressNavigationOwner? = null,
        onPublished: (() -> Unit)? = null,
    ) {
        if (progressOwner != null && !progressScrubOwnership.isCurrent(progressOwner)) {
            progressDiagnostic(progressOwner, "progress_position_publication", progressPositionFields(position) + mapOf("result" to "suppressed_stale", "source" to if (progressOwner.phase == ProgressNavigationOwner.Phase.FINAL) "final_navigation" else "preview_navigation"))
            return
        }
        val liveManual = liveAuthorization != null
        liveAuthorization?.let { authorization ->
            val authorized = when (authorization) {
                is LivePositionAuthorization.Continuous ->
                    renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL &&
                        continuousRendition === authorization.rendition &&
                        authorization.identity.liveManual &&
                        continuousManualScrollPublicationGate.mayPublish(
                            identity = authorization.identity,
                            currentNavigationGeneration = state.navigationGeneration,
                            navigationInFlight = state.navigationInFlight,
                        )
                is LivePositionAuthorization.Paginated ->
                    renditionBackend != ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL &&
                        authorization.identity.liveManual &&
                        paginatedManualPagePublicationGate.mayPublish(
                            identity = authorization.identity,
                            navigationGeneration = state.navigationGeneration,
                            navigationInFlight = state.navigationInFlight,
                        )
            }
            if (!authorized) return
        }
        if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) {
            val capturedContext = continuousPublicationContext ?: return
            val source = continuousPublicationSource ?: return
            if (!recoveredProgressPublicationFence.mayPublish(capturedContext.navigationGeneration, source.automatic)) return
            val rendition = continuousRendition ?: return
            if (!continuousPositionPublicationGate.mayPublish(
                    captured = capturedContext,
                    current = continuousPositionContext(rendition),
                    source = source,
                    finalPending = manualScrollFinalPendingContext?.matches(capturedContext) == true,
                )
            ) return
        }
        if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL &&
            continuousReadingOrderIndex != null
        ) {
            latestContinuousReadingOrderIndex = continuousReadingOrderIndex
        }
        val fingerprint = position.fingerprint()
        val progressPublicationDeduped = fingerprint == latestPositionFingerprint && !forcePublication
        var publicationFields: Map<String, Any?>? = null
        if (progressOwner != null) {
            val target = progressDiagnosticTarget?.takeIf { it.owner == progressOwner }
            val observed = position.progression
            val requested = target?.requested
            val comparison = progressPositionFields(position) + progressViewportFields() + mapOf(
                "requestedNormalizedProgress" to requested, "observedNormalizedProgress" to observed,
                "progressError" to if (requested != null && observed != null) observed - requested else null,
                "sameRequestedResource" to target?.locator?.let { it.href == position.locator.href },
                "requestedProgress" to requested, "observedProgress" to observed,
                "requestedProgression" to target?.locator?.locations?.progression,
                "observedProgression" to position.locator.locations.progression,
                "snapshotSource" to "settled_locator_publication",
            )
            progressDiagnostic(progressOwner, "progress_viewport_snapshot", comparison + mapOf("stage" to "after_navigation"))
            if (progressOwner.phase == ProgressNavigationOwner.Phase.FINAL) {
                progressDiagnostic(progressOwner, "progress_navigation_verified", comparison + mapOf(
                    "stage" to "settled_publication", "requestedReadingOrderIndex" to target?.index,
                    "observedReadingOrderIndex" to continuousReadingOrderIndex,
                    "result" to (target?.verificationResult ?: if (renditionBackend != ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL) "verified" else "failed"),
                ))
            }
            publicationFields = comparison + mapOf(
                "stage" to "locator_publication",
                "source" to if (progressOwner.phase == ProgressNavigationOwner.Phase.FINAL) "final_navigation" else "preview_navigation",
            )
        }
        if (progressPublicationDeduped) {
            // The canonical position is already published. Complete the attempt
            // successfully even though no duplicate PositionChanged is emitted.
            progressDiagnostic(progressOwner, "progress_position_publication",
                publicationFields.orEmpty() + mapOf("result" to "deduped"))
            onPublished?.invoke()
            return
        }
        Log.d(
                "BiblioLifeReadium",
                "READIUM_POSITION_STATE href=${position.locator.href} logicalPosition=${position.locator.locations.position} " +
                    "totalLogicalPositions=${position.totalLogicalPositions} resourceProgression=${position.locator.locations.progression} " +
                    "totalProgression=${position.progression} presentation=${position.presentation}",
        )
        latestPosition = position
        latestPositionFingerprint = fingerprint
        if (forcePublication &&
                continuousPublicationContext != null &&
                manualScrollFinalPendingContext?.matches(continuousPublicationContext) == true &&
                continuousPublicationSource?.automatic == true &&
                continuousPositionPublicationGate.manualFinalPublished(
                    continuousPublicationContext,
                    hasCanonicalProgression = position.progression != null,
                )
        ) {
            manualScrollFinalPendingContext = null
        }
        resolveCurrentChapter(position)
        listener.onStateChanged(State.PositionChanged(position, liveManual, progressOwner))
        val publishedReflowGeneration = diagnosticPreferenceGeneration
            ?.takeIf { continuousPublicationSource == ContinuousPositionSource.REFLOW_COMMITTED }
        val verified = publishedReflowGeneration?.let { generation ->
            latestVerifiedViewportSnapshot?.takeIf { it.preferenceGeneration == generation }
        }
        val viewport = if (publishedReflowGeneration != null) {
            continuousRendition?.diagnosticViewportLayoutSnapshot(verified?.readingOrderIndex)
        } else null
        if (renditionBackend == ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL &&
            publishedReflowGeneration != null &&
            publishedReflowGeneration != lastDiagnosticViewportPreferenceGeneration
        ) {
            lastDiagnosticViewportPreferenceGeneration = publishedReflowGeneration
            runCatching {
                listener.onStateChanged(
                    State.Diagnostic(
                        continuousViewportPositionPublicationFields(
                            preferenceGeneration = publishedReflowGeneration,
                            readingOrderIndex = continuousReadingOrderIndex,
                            logicalPosition = position.locator.locations.position,
                            progression = position.progression,
                            viewport = viewport,
                            verifiedAnchor = verified,
                        ),
                    ),
                )
            }
            latestVerifiedViewportSnapshot = null
        }
        listener.onPositionChanged(position)
        latestPositionWasLiveManual = liveManual
        progressDiagnostic(progressOwner, "progress_position_publication",
            publicationFields.orEmpty() + mapOf("result" to "published"))
        onPublished?.invoke()
    }


    @OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
    private fun createPositionsCache(openedPublication: Publication): ReadiumPositionsCache =
        ReadiumPositionsCache { openedPublication.positionsByReadingOrder() }

    private fun loadToc(openedPublication: Publication) {
        if (!state.startTocLoading()) return
        listener.onStateChanged(State.TocStateChanged(state.tocState))
        tocLoadJob = scope.launch {
            val result = runCatching {
                withContext(Dispatchers.Default) {
                    ReadiumTocNormalizer.normalize(
                        roots = openedPublication.tableOfContents,
                        titleOf = Link::title,
                        hrefOf = { it.href.toString() },
                        childrenOf = Link::children,
                    )
                }
            }
            if (!state.isActive()) return@launch
            result.onSuccess { index ->
                if (!state.tocReady(index.entries)) return@onSuccess
                tocIndex = index
                listener.onStateChanged(State.TocStateChanged(state.tocState))
                latestPosition?.let(::resolveCurrentChapter)
            }.onFailure { error ->
                val tocError = ReadiumTocError.LoadingFailed(error)
                if (state.tocFailed(tocError)) {
                    listener.onStateChanged(State.TocStateChanged(state.tocState))
                    listener.onRecoverableError(Error.TocLoadingFailed(error))
                }
            }
        }
    }

    private fun resolveCurrentChapter(position: ReadiumPositionState) {
        val index = tocIndex ?: return
        val chapter = ReadiumTocNormalizer.resolveChapter(
            index = index,
            href = position.locator.href.toString(),
            fragments = position.locator.locations.fragments,
            current = state.currentChapter,
        )
        if (state.updateCurrentChapter(chapter)) {
            listener.onStateChanged(State.CurrentChapterChanged(chapter))
        }
    }

    private fun executeNavigation(
        command: ReadiumNavigationCommand,
        boundaryWhenRejected: Boolean = false,
        action: (EpubNavigatorFragment) -> Boolean,
    ): NavigationResult {
        progressScrubOwnership.invalidate()
        navigator?.invalidateProgressNavigation()
        if (!navigationMutex.tryLock()) return NavigationResult.Cancelled
        return try {
            when (val gate = state.beginNavigation()) {
                ReadiumNavigationGate.Disposed -> NavigationResult.SessionDisposed
                ReadiumNavigationGate.NotReady -> NavigationResult.NavigatorNotReady
                ReadiumNavigationGate.Busy -> NavigationResult.Cancelled
                is ReadiumNavigationGate.Granted -> executeLockedNavigation(gate, command, action, boundaryWhenRejected)
            }
        } finally {
            navigationMutex.unlock()
        }
    }

    /**
     * The bridge command is synchronous but the real continuous target
     * resolution is suspendable WebView work. Completion is therefore emitted
     * from the same serialized session gate once the direct locator operation
     * actually finishes.
     */
    private fun executeContinuousLocatorNavigation(locator: Locator): NavigationResult {
        progressScrubOwnership.invalidate()
        if (!navigationMutex.tryLock()) return NavigationResult.Cancelled
        val gate = when (val navigationGate = state.beginNavigation()) {
            ReadiumNavigationGate.Disposed -> { navigationMutex.unlock(); return NavigationResult.SessionDisposed }
            ReadiumNavigationGate.NotReady -> { navigationMutex.unlock(); return NavigationResult.NavigatorNotReady }
            ReadiumNavigationGate.Busy -> { navigationMutex.unlock(); return NavigationResult.Cancelled }
            is ReadiumNavigationGate.Granted -> navigationGate
        }
        listener.onStateChanged(State.NavigationStarted(ReadiumNavigationCommand.LOCATOR, gate.generation))
        scope.launch {
            val navigation = runCatching {
                continuousRendition?.goWithOutcome(locator, gate.generation)
                    ?: ContinuousNavigationResult(
                        gate.generation,
                        ContinuousNavigationOutcome.FAILED_BEFORE_POSITION,
                    )
            }.onFailure { listener.onRecoverableError(Error.NavigationFailed(it)) }
                .getOrElse {
                    ContinuousNavigationResult(
                        gate.generation,
                        ContinuousNavigationOutcome.FAILED_BEFORE_POSITION,
                    )
                }
            val resultRecorded = state.recordContinuousNavigationResult(navigation, gate.generation)
            val accepted = resultRecorded && navigation.accepted
            if (
                shouldPublishContinuousNavigationLocator(
                    resultRecorded = resultRecorded,
                    accepted = accepted,
                    verification = navigation.finalViewportVerification.classification,
                )
            ) {
                requestContinuousLocatorUpdate(ContinuousPositionSource.VERIFIED_NAVIGATION)
            }
            completeNavigation(gate, ReadiumNavigationCommand.LOCATOR, if (accepted) null else Error.NavigationFailed())
            navigationMutex.unlock()
        }
        return NavigationResult.Completed
    }

    private fun restoreContinuousInitialLocator(rendition: EpubContinuousRendition) {
        scope.launch {
            val locator = initialLocator
            // No Locator must wait for the host's generation-checked first
            // measured viewport. The callback above publishes the lifecycle
            // transition once content is actually visible.
            if (locator == null) return@launch
            val diagnostic = initialRestoreDiagnostic
            val restoration = runCatching {
                if (diagnostic == null) rendition.restoreInitialLocator(locator)
                else rendition.restoreInitialLocator(locator, diagnostic::stage)
            }
            val navigated = restoration.getOrDefault(false)
            if (!navigated) {
                diagnostic?.finish(
                    "failed", restoration.exceptionOrNull(),
                    "native_restoration_returned_false".takeIf { restoration.isSuccess },
                )
                fail(Error.InitialLocatorRestorationFailed(restoration.exceptionOrNull()))
                return@launch
            }
            diagnostic?.finish("success")
            if (state.initialLocatorRestored()) {
                listener.onStateChanged(State.InitialLocatorRestored(navigated))
                reportOpenReady()
                startContinuousPositionObservation()
            }
            requestContinuousLocatorUpdate(ContinuousPositionSource.INITIAL_RESTORE)
        }
    }

    private fun executeLockedNavigation(
        gate: ReadiumNavigationGate.Granted,
        command: ReadiumNavigationCommand,
        action: (EpubNavigatorFragment) -> Boolean,
        boundaryWhenRejected: Boolean = false,
    ): NavigationResult {
        cancelManualPaginatedSessionForNavigation()
        val activeNavigator = navigator ?: return completeNavigation(gate, command, Error.NavigatorNotReady)
        listener.onStateChanged(State.NavigationStarted(command, gate.generation))
        val accepted = runCatching { action(activeNavigator) }
            .onFailure { listener.onRecoverableError(Error.NavigationFailed(it)) }
            .getOrDefault(false)
        return if (accepted) {
            completeNavigation(gate, command)
            NavigationResult.Completed
        } else {
            completeNavigation(gate, command, if (boundaryWhenRejected) null else Error.NavigationFailed())
            if (boundaryWhenRejected) NavigationResult.BoundaryReached else NavigationResult.Failed
        }
    }

    private fun completeNavigation(
        gate: ReadiumNavigationGate.Granted,
        command: ReadiumNavigationCommand,
        error: Error? = null,
    ): NavigationResult {
        if (!state.completeNavigation(gate.generation)) return NavigationResult.Cancelled
        if (error == null) listener.onStateChanged(State.NavigationCompleted(command, gate.generation))
        else listener.onStateChanged(State.NavigationFailed(command, error))
        return when (error) {
            null -> NavigationResult.Completed
            Error.NavigatorNotReady -> NavigationResult.NavigatorNotReady
            Error.InvalidProgression -> NavigationResult.InvalidProgression
            else -> NavigationResult.Failed
        }
    }

    private fun executeInitialLocatorNavigation(
        activeNavigator: EpubNavigatorFragment,
        locator: Locator,
    ): Result<Boolean> = runCatching { activeNavigator.go(locator, false) }

    private fun errorFor(code: String): Error = when (code) {
        "file_not_found" -> Error.MissingLocalFile
        "unsupported_format" -> Error.UnsupportedPublication
        else -> Error.PublicationOpeningFailed(code)
    }

    private fun openStage(
        stage: String,
        result: String,
        component: String,
        facts: Map<String, Any?> = emptyMap(),
    ) {
        openDiagnosticStage = stage
        openDiagnosticComponent = component
        emitOpenDiagnostic(ReadiumOpenDiagnostics.stage(stage, result, component, facts))
    }

    private fun emitOpenDiagnostic(fields: Map<String, Any?>) {
        runCatching { listener.onStateChanged(State.Diagnostic(fields)) }
    }

    private fun reportOpenReady() {
        if (openingReady) return
        openingReady = true
        openStage("navigator_initialization", "success", "android_readium_navigator")
        openStage("reader_ready", "success", "android_readium_navigator")
    }

    private fun fail(error: Error, cause: Throwable? = null, diagnostic: Map<String, Any?>? = null) {
        if (!state.fail()) return
        val openFailure = if (!openingReady) {
            val original = cause ?: when (error) {
                is Error.NavigatorCreationFailed -> error.cause
                is Error.FragmentAttachmentFailed -> error.cause
                is Error.InitialLocatorRestorationFailed -> error.cause
                else -> null
            }
            val facts = mapOf(
                "errorCode" to error.code,
                "exceptionType" to error.javaClass.simpleName,
                "message" to (error as? Error.InitialViewportReadinessFailed)?.reason
                    ?.takeIf { it.matches(Regex("[a-z][a-z0-9_]{0,63}")) },
            ) + (original?.let(ReadiumOpenDiagnostics::exception) ?: emptyMap())
            val restoration = initialRestoreDiagnostic?.let { restore ->
                if (error is Error.InitialViewportReadinessFailed && initialLocator != null) {
                    restore.finish("failed", reason = error.reason)
                } else {
                    restore.terminal?.takeIf { it["result"] == "failed" }
                }
            }
            val payload = (diagnostic ?: ReadiumOpenDiagnostics.stage(
                openDiagnosticStage, "failed", openDiagnosticComponent, facts,
            )) + if (restoration == null) emptyMap() else mapOf("initialLocatorRestoration" to restoration)
            val correlated = if (openAttemptId == null) payload else payload + ("openAttemptId" to openAttemptId)
            emitOpenDiagnostic(correlated)
            correlated.takeIf { openAttemptId != null }
        } else null
        listener.onFatalError(error, openFailure)
    }

    private fun closeQuietly(openedPublication: Publication) {
        runCatching { openedPublication.close() }
            .onFailure { Log.w(TAG, "PUBLICATION_CLOSE_FAILED", it) }
    }

    // Observer state only: never consulted by navigation or publication fences.
    private data class ProgressDiagnosticTarget(val owner: ProgressNavigationOwner, val requested: Double, val locator: Locator?, val index: Int?, var verificationResult: String? = null)
    private var progressDiagnosticTarget: ProgressDiagnosticTarget? = null
    private val progressDiagnosticGenerations = linkedMapOf<String, Long>()

    private fun progressDiagnostic(owner: ProgressNavigationOwner?, kind: String, fields: Map<String, Any?> = emptyMap()) {
        if (owner == null) return
        runCatching {
            listener.onStateChanged(State.Diagnostic(mapOf(
                "category" to "Reader.Progress", "level" to "debug", "kind" to kind,
                "gestureId" to owner.sessionId, "previewId" to owner.requestId,
                "isFinal" to (owner.phase == ProgressNavigationOwner.Phase.FINAL),
                "navigationGeneration" to progressDiagnosticGenerations[owner.token],
                "currentNavigationGeneration" to state.navigationGeneration,
            ) + fields))
        }
    }

    private fun progressViewportFields(): Map<String, Any?> {
        val viewport = continuousRendition?.diagnosticViewportLayoutSnapshot(null)
        return mapOf(
            "firstVisibleResourceIndex" to viewport?.firstVisibleIndex,
            "firstVisibleTopPx" to viewport?.firstVisibleTopPx,
            "viewportHeightPx" to viewport?.heightPx,
            "resourceGeneration" to continuousRendition?.currentLocatorAnchor()?.resourceGeneration,
        )
    }

    private fun progressPositionFields(position: ReadiumPositionState?): Map<String, Any?> = mapOf(
        "resourceHref" to position?.locator?.href?.toString(),
        "readingOrderIndex" to position?.locator?.let { locator -> publication?.readingOrder?.indexOfFirst { it.href.toString() == locator.href.toString() } },
        "resourceProgression" to position?.locator?.locations?.progression,
        "totalProgression" to position?.progression,
        "logicalPosition" to position?.locator?.locations?.position,
    )

    private fun progressTargetDiagnostic(owner: ProgressNavigationOwner?, normalized: Double, locator: Locator?, index: Int? = null) {
        if (owner == null) return
        progressDiagnosticGenerations[owner.token] = state.navigationGeneration
        while (progressDiagnosticGenerations.size > 4) {
            progressDiagnosticGenerations.remove(progressDiagnosticGenerations.keys.first())
        }
        val resolvedIndex = index ?: locator?.let { target -> publication?.readingOrder?.indexOfFirst { it.href.toString() == target.href.toString() } }
        progressDiagnosticTarget = ProgressDiagnosticTarget(owner, normalized, locator, resolvedIndex)
        progressDiagnostic(owner, "progress_target_resolved", mapOf(
            "normalizedProgress" to normalized, "targetLocatorAvailable" to (locator != null),
            "targetReadingOrderIndex" to resolvedIndex,
            "targetResourceHref" to locator?.href?.toString(),
            "targetProgression" to locator?.locations?.progression,
            "targetTotalProgression" to locator?.locations?.totalProgression,
            "targetPosition" to locator?.locations?.position,
        ))
        progressDiagnostic(owner, "progress_viewport_snapshot", progressPositionFields(latestPosition) + progressViewportFields() + mapOf("stage" to "before_navigation", "snapshotSource" to "latest_published_position"))
        progressDiagnostic(owner, "progress_navigation_start", mapOf(
            "normalizedProgress" to normalized, "targetProgression" to locator?.locations?.progression,
            "activeNavigation" to true, "targetReadingOrderIndex" to resolvedIndex,
        ))
        progressDiagnostic(owner, "progress_native_navigation", mapOf(
            "result" to "requested", "readingOrderIndex" to resolvedIndex,
            "resourceGeneration" to continuousRendition?.currentLocatorAnchor()?.resourceGeneration,
            "locatorProgression" to locator?.locations?.progression,
            "totalProgression" to locator?.locations?.totalProgression,
        ))
    }

    private fun progressLog(message: String) {
        if (Log.isLoggable(PROGRESS_LOG_TAG, Log.DEBUG)) Log.d(TAG, message)
    }

    private fun ReadiumPreferenceCoordinator.Snapshot<EpubPreferences>.toPreferenceState() = PreferenceState(
        requested = requested,
        applied = applied,
        generation = generation,
        isApplying = isApplying,
    )

    private fun ReadiumDecorationCoordinator.Snapshot.toDecorationState() = DecorationState(
        requestedCount = requested.size,
        appliedCount = applied.size,
        generation = generation,
        isApplying = isApplying,
        isReady = isReady,
        selectionProtected = selectionProtected,
        hasApplied = hasApplied,
    )

    private fun ReadiumDecorationCoordinator.Result.toDecorationResult() = when (this) {
        ReadiumDecorationCoordinator.Result.Applied -> DecorationResult.Applied
        ReadiumDecorationCoordinator.Result.Queued -> DecorationResult.Queued
        ReadiumDecorationCoordinator.Result.Unchanged -> DecorationResult.Unchanged
        ReadiumDecorationCoordinator.Result.Superseded -> DecorationResult.Superseded
        ReadiumDecorationCoordinator.Result.Failed -> DecorationResult.Failed
        ReadiumDecorationCoordinator.Result.NavigatorNotReady -> DecorationResult.NavigatorNotReady
        ReadiumDecorationCoordinator.Result.SessionDisposed -> DecorationResult.SessionDisposed
    }

    companion object {
        const val NAVIGATOR_TAG = "BIBLIOLIFE_EPUB_NAVIGATOR"
        private const val TAG = "BiblioLifeReadium"
        private const val PROGRESS_LOG_TAG = "BiblioLifeProgress"
        private const val PROGRESSION_BOUNDARY_EPSILON = 0.000001

        internal fun normalizeObservedProgression(value: Double?): Double? = value
            ?.takeIf { it.isFinite() }
            ?.coerceIn(0.0, 1.0)

        internal fun normalizeRequestedProgression(value: Double): Double? = when {
            !value.isFinite() -> null
            value < -PROGRESSION_BOUNDARY_EPSILON || value > 1.0 + PROGRESSION_BOUNDARY_EPSILON -> null
            else -> value.coerceIn(0.0, 1.0)
        }
    }
}

/** Parses publication-independent locator structure before opening a publication. */
internal data class ReadiumInitialLocatorRequest(
    val json: JSONObject,
    val href: Url,
) {
    companion object {
        fun parse(locatorJson: String?): ReadiumInitialLocatorRequest? {
            if (locatorJson.isNullOrBlank()) return null
            val json = JSONObject(locatorJson)
            val hrefValue = json.opt("href") as? String ?: return null
            if (hrefValue.isBlank()) return null
            val href = Url(hrefValue) ?: return null
            return ReadiumInitialLocatorRequest(json, href)
        }

        fun canonicalize(
            request: ReadiumInitialLocatorRequest,
            publication: Publication,
            onMatch: (Map<String, Any?>) -> Unit = {},
            onConversionFailure: (Throwable) -> Unit = {},
        ): Locator? {
            val link = publication.linkWithHref(request.href) ?: run {
                onMatch(mapOf("requestedHrefMatchesPublication" to false, "failureReason" to "requested_href_not_found"))
                return null
            }
            val requestedIndex = publication.readingOrder.indexOfFirst { it.containsLink(link) }
            if (requestedIndex < 0 &&
                !publication.resources.any { it.containsLink(link) }
            ) {
                onMatch(mapOf("requestedHrefMatchesPublication" to false, "failureReason" to "requested_href_outside_publication"))
                return null
            }
            onMatch(mapOf(
                "requestedHrefMatchesPublication" to true,
                "requestedReadingOrderIndex" to requestedIndex.takeIf { it >= 0 },
            ))

            // locatorFromLink supplies the publication's canonical href and media type. Preserve
            // the incoming semantic location and text objects while replacing those Link fields.
            val canonical = publication.locatorFromLink(link.copy(href = Href(request.href))) ?: return null
            val json = JSONObject(request.json.toString())
                .put("href", canonical.href.toString())
                .put("type", canonical.mediaType.toString())
            canonical.title?.let { json.put("title", it) }

            request.href.fragment?.let { fragment ->
                val locations = json.optJSONObject("locations") ?: JSONObject().also { json.put("locations", it) }
                val fragments = buildList {
                    when (val value = locations.opt("fragments")) {
                        is JSONArray -> for (index in 0 until value.length()) value.optString(index).takeIf(String::isNotBlank)?.let(::add)
                        is String -> value.takeIf(String::isNotBlank)?.let(::add)
                    }
                    locations.optString("fragment").takeIf(String::isNotBlank)?.let(::add)
                    add(fragment)
                }.distinct()
                if (fragments.isNotEmpty()) {
                    locations.put("fragments", JSONArray(fragments))
                    locations.remove("fragment")
                }
            }
            return runCatching { Locator.fromJSON(json) }.onFailure(onConversionFailure).getOrNull()
        }

        private fun Link.containsLink(target: Link): Boolean =
            this == target || alternates.any { it.containsLink(target) } || children.any { it.containsLink(target) }
    }
}
