package app.bibliolife.reader.readium

import androidx.annotation.VisibleForTesting
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.readium.r2.navigator.DecorableNavigator
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.shared.publication.Locator

/** Immutable, codec-safe EPUB opening payload for a factory-created PlatformView session. */
internal data class ReadiumPlatformViewOpenConfiguration(
    val instanceId: String,
    val bookId: String,
    val localFilePath: String,
    val initialLocatorJson: String?,
    val initialPreferences: ReaderPreferencesPayload,
    val initialPreferencesAreAuthoritative: Boolean,
    val isNightMode: Boolean,
    val bridgeProtocolVersion: Int = ReadiumPlatformViewBridgeProtocol.VERSION,
    val openAttemptId: Long? = null,
    val initialLocatorSource: String? = null,
) {
    fun validate(): ReadiumPlatformViewCreationException? = when {
        instanceId.isBlank() -> ReadiumPlatformViewCreationException("invalid_instance_id")
        bookId.isBlank() -> ReadiumPlatformViewCreationException("missing_book_id")
        localFilePath.isBlank() -> ReadiumPlatformViewCreationException("missing_file_path")
        bridgeProtocolVersion != ReadiumPlatformViewBridgeProtocol.VERSION ->
            ReadiumPlatformViewCreationException("unsupported_protocol")
        else -> null
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "instanceId" to instanceId,
        "bookId" to bookId,
        "localFilePath" to localFilePath,
        "initialLocatorJson" to initialLocatorJson,
        "initialPreferences" to initialPreferences.toChannelMap(),
        "initialPreferencesAreAuthoritative" to initialPreferencesAreAuthoritative,
        "isNightMode" to isNightMode,
        "bridgeProtocolVersion" to bridgeProtocolVersion,
        "openAttemptId" to openAttemptId,
        "initialLocatorSource" to initialLocatorSource,
    )

    companion object {
        fun parse(value: Any?): kotlin.Result<ReadiumPlatformViewOpenConfiguration> {
            val map = value as? Map<*, *>
                ?: return kotlin.Result.failure(ReadiumPlatformViewCreationException("invalid_open_configuration"))
            fun string(key: String): String? = map[key] as? String
            val instanceId = string("instanceId")
                ?: return kotlin.Result.failure(ReadiumPlatformViewCreationException("missing_instance_id"))
            val bookId = string("bookId")
                ?: return kotlin.Result.failure(ReadiumPlatformViewCreationException("missing_book_id"))
            val localFilePath = string("localFilePath")
                ?: return kotlin.Result.failure(ReadiumPlatformViewCreationException("missing_file_path"))
            val protocolVersion = when (val raw = map["bridgeProtocolVersion"]) {
                null -> ReadiumPlatformViewBridgeProtocol.VERSION
                is Number -> raw.toDouble().takeIf { it.isFinite() && it == it.toInt().toDouble() }?.toInt()
                    ?: return kotlin.Result.failure(ReadiumPlatformViewCreationException("invalid_protocol"))
                else -> return kotlin.Result.failure(ReadiumPlatformViewCreationException("invalid_protocol"))
            }
            val preferences = ReaderPreferencesPayload.fromChannelValue(map["initialPreferences"])
                ?: ReaderPreferencesPayload()
            val configuration = ReadiumPlatformViewOpenConfiguration(
                instanceId = instanceId.trim(),
                bookId = bookId.trim(),
                localFilePath = localFilePath.trim(),
                initialLocatorJson = string("initialLocatorJson")?.takeIf { it.isNotBlank() },
                initialPreferences = preferences,
                initialPreferencesAreAuthoritative = map["initialPreferencesAreAuthoritative"] as? Boolean ?: false,
                isNightMode = map["isNightMode"] as? Boolean ?: false,
                bridgeProtocolVersion = protocolVersion,
                openAttemptId = when (val id = map["openAttemptId"]) {
                    is Int -> id.toLong()
                    is Long -> id
                    else -> null
                }?.takeIf { it > 0 },
                initialLocatorSource = string("initialLocatorSource")
                    ?.takeIf { it == "launch_request" || it == "saved_progress" || it == "none" },
            )
            return configuration.validate()?.let { error ->
                kotlin.Result.failure<ReadiumPlatformViewOpenConfiguration>(error)
            } ?: kotlin.Result.success(configuration)
        }
    }
}

/** A non-visual publication identity suitable for a later bridge. */
internal data class ReadiumPlatformViewPublicationInfo(
    val bookId: String,
    val title: String,
)

/** Host-safe result/error values; raw session result classes never cross the host boundary. */
internal data class ReadiumPlatformViewError(
    val code: String,
    val openFailure: Map<String, Any?>? = null,
)

internal data class ReadiumPlatformViewPreferenceState(
    val requested: EpubPreferences?,
    val applied: EpubPreferences?,
    val generation: Long,
    val isApplying: Boolean,
)

internal data class ReadiumReaderDecorationState(
    val requestedCount: Int,
    val appliedCount: Int,
    val generation: Long,
    val isApplying: Boolean,
    val isReady: Boolean,
    val selectionProtected: Boolean,
    val hasApplied: Boolean,
)

internal sealed class ReadiumPlatformViewNavigationResult {
    data object Completed : ReadiumPlatformViewNavigationResult()
    data object CompletedWithPublicationFailure : ReadiumPlatformViewNavigationResult()
    data object RecoveredTimeout : ReadiumPlatformViewNavigationResult()
    data object BoundaryReached : ReadiumPlatformViewNavigationResult()
    data object NavigatorNotReady : ReadiumPlatformViewNavigationResult()
    data object InvalidLocator : ReadiumPlatformViewNavigationResult()
    data object InvalidProgression : ReadiumPlatformViewNavigationResult()
    data object SessionDisposed : ReadiumPlatformViewNavigationResult()
    data object Cancelled : ReadiumPlatformViewNavigationResult()
    data object TocNotReady : ReadiumPlatformViewNavigationResult()
    data object UnknownTocEntry : ReadiumPlatformViewNavigationResult()
    data object Failed : ReadiumPlatformViewNavigationResult()
    val accepted: Boolean get() = this == Completed || this == CompletedWithPublicationFailure
}

internal sealed class ReadiumPlatformViewSearchNavigationResult {
    data object Completed : ReadiumPlatformViewSearchNavigationResult()
    data object NavigatorNotReady : ReadiumPlatformViewSearchNavigationResult()
    data object SessionDisposed : ReadiumPlatformViewSearchNavigationResult()
    data object UnknownResultId : ReadiumPlatformViewSearchNavigationResult()
    data object ObsoleteResultId : ReadiumPlatformViewSearchNavigationResult()
    data object Failed : ReadiumPlatformViewSearchNavigationResult()
    val accepted: Boolean get() = this == Completed
}

internal enum class ReadiumPlatformViewPreferenceResult { Applied, Unchanged, NavigatorNotReady, SessionDisposed, Cancelled, Failed }

internal enum class ReadiumPlatformViewDecorationResult { Applied, Queued, Unchanged, Superseded, Failed, NavigatorNotReady, SessionDisposed }

/** A narrow port for native presentation concerns; the navigator itself never crosses it. */
internal class ReadiumPlatformViewNavigatorHost(
    private val navigator: EpubNavigatorFragment,
) {
    private var disposed = false
    private val inputListeners = linkedSetOf<InputListener>()
    private val decorationListeners = linkedSetOf<DecorableNavigator.Listener>()

    fun addInputListener(listener: InputListener): Boolean {
        if (disposed || !inputListeners.add(listener)) return false
        navigator.addInputListener(listener)
        return true
    }

    fun removeInputListener(listener: InputListener): Boolean {
        if (disposed || !inputListeners.remove(listener)) return false
        navigator.removeInputListener(listener)
        return true
    }

    fun addDecorationListener(group: String, listener: DecorableNavigator.Listener): Boolean {
        if (disposed) return false
        navigator.addDecorationListener(group, listener)
        decorationListeners += listener
        return true
    }

    fun removeDecorationListener(listener: DecorableNavigator.Listener): Boolean {
        if (disposed || !decorationListeners.remove(listener)) return false
        navigator.removeDecorationListener(listener)
        return true
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        inputListeners.forEach(navigator::removeInputListener)
        decorationListeners.forEach(navigator::removeDecorationListener)
        inputListeners.clear()
        decorationListeners.clear()
    }
}

/** PlatformView-level immutable state; no Publication, navigator, View or Activity escapes. */
internal sealed class ReadiumPlatformViewReaderState {
    data object InitializationStarted : ReadiumPlatformViewReaderState()
    data class PublicationOpened(val info: ReadiumPlatformViewPublicationInfo) : ReadiumPlatformViewReaderState()
    data class NavigatorAttached(val reusedRestoredFragment: Boolean) : ReadiumPlatformViewReaderState()
    data object NavigatorReady : ReadiumPlatformViewReaderState()
    data class InitialLocatorRestored(val navigated: Boolean) : ReadiumPlatformViewReaderState()
    data class PositionChanged(
        val position: ReadiumPositionState,
        val liveManual: Boolean = false,
        val progressOwner: ProgressNavigationOwner? = null,
    ) : ReadiumPlatformViewReaderState()
    data class ManualScrollActivityChanged(val active: Boolean) : ReadiumPlatformViewReaderState()
    data class NavigationStarted(
        val command: ReadiumNavigationCommand,
        val generation: Long,
        val progressOwner: ProgressNavigationOwner? = null,
    ) : ReadiumPlatformViewReaderState()
    data class NavigationCompleted(val command: ReadiumNavigationCommand, val generation: Long) : ReadiumPlatformViewReaderState()
    data class NavigationFailed(val command: ReadiumNavigationCommand, val error: ReadiumPlatformViewError) : ReadiumPlatformViewReaderState()
    data class PreferencesRequested(val preferences: ReadiumPlatformViewPreferenceState) : ReadiumPlatformViewReaderState()
    data class PreferencesApplied(val preferences: ReadiumPlatformViewPreferenceState, val initial: Boolean) : ReadiumPlatformViewReaderState()
    data class PreferencesFailed(val preferences: ReadiumPlatformViewPreferenceState, val error: ReadiumPlatformViewError) : ReadiumPlatformViewReaderState()
    data class Diagnostic(val fields: Map<String, Any?>) : ReadiumPlatformViewReaderState()
    data class TocStateChanged(val toc: ReadiumTocState) : ReadiumPlatformViewReaderState()
    data class CurrentChapterChanged(val chapter: ReadiumChapterState) : ReadiumPlatformViewReaderState()
    data class SearchStateChanged(val search: EpubSearchState) : ReadiumPlatformViewReaderState()
    data class SelectionChanged(val selection: ReadiumSelectionState) : ReadiumPlatformViewReaderState()
    data class DecorationsChanged(
        val group: ReadiumDecorationGroup,
        val decorations: ReadiumReaderDecorationState,
    ) : ReadiumPlatformViewReaderState()
    data object Disposed : ReadiumPlatformViewReaderState()
}

internal interface ReadiumPlatformViewHostListener {
    fun onStateChanged(state: ReadiumPlatformViewReaderState)
    fun onInteraction(interaction: ReadiumReaderInteraction) = Unit
    fun onNavigatorReady(info: ReadiumPlatformViewPublicationInfo, host: ReadiumPlatformViewNavigatorHost) = Unit
    fun onFatalError(error: ReadiumPlatformViewError) = Unit
    fun onRecoverableError(error: ReadiumPlatformViewError) = Unit
}

internal data class ReadiumPlatformViewHostListenerToken(val generation: Long)

/** One active presentation listener with latest-state replay and stale-token rejection. */
internal class ReadiumPlatformViewHostListenerCoordinator {
    private var listener: ReadiumPlatformViewHostListener? = null
    private var bridgeListener: ReadiumPlatformViewHostListener? = null
    private var generation = 0L
    private var bridgeGeneration = 0L
    private var disposed = false
    private var latestState: ReadiumPlatformViewReaderState? = null
    private var latestNavigator: Pair<ReadiumPlatformViewPublicationInfo, ReadiumPlatformViewNavigatorHost>? = null

    fun bind(next: ReadiumPlatformViewHostListener): ReadiumPlatformViewHostListenerToken? {
        if (disposed || listener != null) return null
        val token = ReadiumPlatformViewHostListenerToken(++generation)
        listener = next
        latestState?.let(next::onStateChanged)
        latestNavigator?.let { (info, host) -> next.onNavigatorReady(info, host) }
        return token
    }

    fun bindBridgeListener(next: ReadiumPlatformViewHostListener): ReadiumPlatformViewHostListenerToken? {
        if (disposed || bridgeListener != null) return null
        val token = ReadiumPlatformViewHostListenerToken(++bridgeGeneration)
        bridgeListener = next
        runCatching { latestState?.let(next::onStateChanged) }
        runCatching { latestNavigator?.let { (info, host) -> next.onNavigatorReady(info, host) } }
        return token
    }

    fun unbind(token: ReadiumPlatformViewHostListenerToken): Boolean {
        if (disposed) return false
        if (token.generation == generation && listener != null) {
            listener = null
            generation++
            return true
        }
        if (token.generation == bridgeGeneration && bridgeListener != null) {
            bridgeListener = null
            bridgeGeneration++
            return true
        }
        return false
    }

    fun unbindBridgeListener(token: ReadiumPlatformViewHostListenerToken): Boolean {
        if (disposed || token.generation != bridgeGeneration || bridgeListener == null) return false
        bridgeListener = null
        bridgeGeneration++
        return true
    }

    fun emit(state: ReadiumPlatformViewReaderState) {
        if (disposed) return
        if (state !is ReadiumPlatformViewReaderState.Diagnostic) latestState = state
        runCatching { listener?.onStateChanged(state) }
        runCatching { bridgeListener?.onStateChanged(state) }
    }

    fun emitInteraction(interaction: ReadiumReaderInteraction) {
        if (disposed) return
        runCatching { listener?.onInteraction(interaction) }
        runCatching { bridgeListener?.onInteraction(interaction) }
    }

    fun emitNavigatorReady(info: ReadiumPlatformViewPublicationInfo, host: ReadiumPlatformViewNavigatorHost) {
        if (disposed) return
        latestNavigator = info to host
        runCatching { listener?.onNavigatorReady(info, host) }
        runCatching { bridgeListener?.onNavigatorReady(info, host) }
    }

    fun emitFatal(error: ReadiumPlatformViewError) {
        if (!disposed) {
            runCatching { listener?.onFatalError(error) }
            runCatching { bridgeListener?.onFatalError(error) }
        }
    }

    fun emitRecoverable(error: ReadiumPlatformViewError) {
        if (!disposed) {
            runCatching { listener?.onRecoverableError(error) }
            runCatching { bridgeListener?.onRecoverableError(error) }
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        listener = null
        bridgeListener = null
        latestNavigator?.second?.dispose()
        latestNavigator = null
        latestState = null
        generation++
        bridgeGeneration++
    }
}

/** Session construction seam used by production and deterministic ownership tests. */
internal fun interface ReadiumReaderSessionFactory {
    fun create(
        dependencies: ReadiumPlatformViewDependencies,
        configuration: ReadiumPlatformViewOpenConfiguration,
        navigatorConfiguration: EpubNavigatorFragment.Configuration,
        scope: CoroutineScope,
        listener: ReadiumReaderSession.Listener,
        diagnosticInstanceId: String,
    ): ReadiumReaderSession
}

internal object ProductionReadiumReaderSessionFactory : ReadiumReaderSessionFactory {
    override fun create(
        dependencies: ReadiumPlatformViewDependencies,
        configuration: ReadiumPlatformViewOpenConfiguration,
        navigatorConfiguration: EpubNavigatorFragment.Configuration,
        scope: CoroutineScope,
        listener: ReadiumReaderSession.Listener,
        diagnosticInstanceId: String,
    ): ReadiumReaderSession {
        // This PlatformView is the native EPUB route. Existing FB2/TXT conversion
        // normalizes to EPUB before reaching it; other formats do not enter it.
        val backendResolution = ReadiumEpubBackendResolver().resolve(
            ReadiumEpubBackendRequest(
                requestedMode = if (configuration.initialPreferences.scroll) {
                    ReadiumEpubRequestedMode.SCROLL
                } else {
                    ReadiumEpubRequestedMode.PAGINATED
                },
                publicationType = ReadiumEpubPublicationType.EPUB,
            ),
        )
        Log.i("BiblioLifeReadium", backendResolution.diagnosticMessage())
        return ReadiumReaderSession(
            context = dependencies.applicationContext,
            fragmentManager = dependencies.fragmentManager,
            scope = scope,
            classLoader = dependencies.classLoader,
            file = java.io.File(configuration.localFilePath),
            initialLocatorJson = configuration.initialLocatorJson,
            initialPreferences = configuration.initialPreferences.toEpubPreferences(configuration.isNightMode),
            initialPreferencesAreAuthoritative = configuration.initialPreferencesAreAuthoritative,
            navigatorConfiguration = navigatorConfiguration,
            listener = listener,
            diagnosticInstanceId = diagnosticInstanceId,
            renditionBackend = backendResolution.backend,
            openAttemptId = configuration.openAttemptId,
            initialLocatorSource = configuration.initialLocatorSource,
        )
    }
}

/** Narrow forwarding API; the raw session, Publication and navigator remain private. */
internal interface ReadiumPlatformViewController {
    val isNavigatorReady: Boolean
    fun selectionState(): ReadiumSelectionState
    fun onNativeSelectionSessionStarted(nativeSessionId: Long): Long?
    fun onNativeSelectionSessionEnded(nativeSessionId: Long): Boolean
    fun requestCurrentSelection(
        onComplete: (ReadiumSelectionRequestResult) -> Unit = {},
        refreshAfterInFlight: Boolean = false,
    ): ReadiumSelectionRequestResult
    fun clearSelection(): ReadiumSelectionClearResult
    fun onViewportEpochChanged(epoch: Long)
    fun position(): ReadiumPositionState?
    fun preferences(): ReadiumPlatformViewPreferenceState
    fun currentChapter(): ReadiumChapterState
    fun tocState(): ReadiumTocState
    fun searchState(): EpubSearchState
    fun decorationState(group: ReadiumDecorationGroup): ReadiumReaderDecorationState
    fun next(animated: Boolean = false): ReadiumPlatformViewNavigationResult
    fun previous(animated: Boolean = false): ReadiumPlatformViewNavigationResult
    fun goToProgression(
        progression: Double,
        animated: Boolean = false,
        onComplete: (ReadiumPlatformViewNavigationResult) -> Unit = {},
    )
    fun goToProgression(
        progression: Double,
        animated: Boolean,
        progressOwner: ProgressNavigationOwner?,
        onComplete: (ReadiumPlatformViewNavigationResult) -> Unit,
    ) = goToProgression(progression, animated, onComplete)
    fun goToProgressLocator(locator: Locator, progression: Double, owner: ProgressNavigationOwner,
        readingOrderIndex: Int?, onComplete: (ReadiumPlatformViewNavigationResult) -> Unit,
    ) { onComplete(ReadiumPlatformViewNavigationResult.Failed) }
    fun openProgressScrubSession(sessionId: Long): Boolean = false
    fun invalidateProgressScrubSession(sessionId: Long): Boolean = false
    fun reserveProgressScrubFinal(owner: ProgressNavigationOwner): Boolean = false
    fun supersedeSettingsPreviewsBefore(requestId: Long): Boolean = false
    fun settingsReflowGesture(id: Long, slider: String, action: String, value: Double, onComplete: (Boolean) -> Unit) { onComplete(false) }
    fun search(query: String)
    fun loadNextSearchPage()
    fun retrySearch()
    fun clearSearch()
    fun goToSearchResult(resultId: String, animated: Boolean = false): ReadiumPlatformViewSearchNavigationResult
    fun setPersistentHighlights(decorations: List<ReadiumDecorationSpec>, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit = {})
    fun setSearchDecoration(locator: Locator, tint: Int, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit = {})
    fun clearSearchDecoration(onComplete: (ReadiumPlatformViewDecorationResult) -> Unit = {})
    fun setDecorations(
        group: ReadiumDecorationGroup,
        decorations: List<ReadiumDecorationSpec>,
        onComplete: (ReadiumPlatformViewDecorationResult) -> Unit = {},
    )
    fun upsertDecoration(
        group: ReadiumDecorationGroup,
        decoration: ReadiumDecorationSpec,
        onComplete: (ReadiumPlatformViewDecorationResult) -> Unit = {},
    )
    fun removeDecoration(
        group: ReadiumDecorationGroup,
        id: String,
        onComplete: (ReadiumPlatformViewDecorationResult) -> Unit = {},
    )
    fun clearDecorations(
        group: ReadiumDecorationGroup,
        onComplete: (ReadiumPlatformViewDecorationResult) -> Unit = {},
    )
    fun applyPreferences(preferences: EpubPreferences, onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit)
    fun applyPreferencesPayload(
        preferences: ReaderPreferencesPayload,
        isNightMode: Boolean,
        onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit,
    )
    fun applyPreferencesPayloadWithDiagnostics(
        preferences: ReaderPreferencesPayload,
        isNightMode: Boolean,
        diagnosticContext: ReadiumReflowDiagnosticContext?,
        onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit,
    ) = applyPreferencesPayload(preferences, isNightMode, onComplete)
    fun applySettingsPreviewPayloadWithDiagnostics(
        preferences: ReaderPreferencesPayload,
        isNightMode: Boolean,
        diagnosticContext: ReadiumReflowDiagnosticContext?,
        previewRequestId: Long,
        onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit,
    ) = applyPreferencesPayloadWithDiagnostics(preferences, isNightMode, diagnosticContext, onComplete)
    fun goTo(locator: Locator, animated: Boolean = false): ReadiumPlatformViewNavigationResult
    fun goToTocEntry(entryId: String, animated: Boolean = true): ReadiumPlatformViewNavigationResult
    fun loadProgressTargets(onComplete: (Result<List<ProgressNavigationTarget>>) -> Unit)
}

internal class ReadiumPlatformViewControllerImpl(
    private val sessionProvider: () -> ReadiumReaderSession?,
    private val scope: CoroutineScope,
    private val isDisposed: () -> Boolean,
) : ReadiumPlatformViewController {
    private fun session() = sessionProvider()
    override val isNavigatorReady: Boolean
        get() = session()?.isNavigatorReady() == true

    override fun selectionState() = session()?.selectionState() ?: ReadiumSelectionState(
        status = ReadiumSelectionStatus.DISPOSED,
        sessionId = null,
        nativeSessionId = null,
        generation = 0,
        viewportEpoch = 0,
        selection = null,
        retrievalInFlight = false,
        error = null,
    )

    override fun onNativeSelectionSessionStarted(nativeSessionId: Long) = session()?.onNativeSelectionSessionStarted(nativeSessionId)
    override fun onNativeSelectionSessionEnded(nativeSessionId: Long) = session()?.onNativeSelectionSessionEnded(nativeSessionId) ?: false
    override fun requestCurrentSelection(onComplete: (ReadiumSelectionRequestResult) -> Unit, refreshAfterInFlight: Boolean) =
        session()?.requestCurrentSelection(onComplete, refreshAfterInFlight) ?: ReadiumSelectionRequestResult.Stale
    override fun clearSelection() = session()?.clearSelection() ?: ReadiumSelectionClearResult.Disposed
    override fun onViewportEpochChanged(epoch: Long) { session()?.onViewportEpochChanged(epoch) }
    override fun position() = session()?.position()
    override fun preferences() = session()?.preferences()?.toPlatformState() ?: ReadiumPlatformViewPreferenceState(null, null, 0, false)
    override fun currentChapter() = session()?.currentChapter() ?: ReadiumChapterState.Unknown
    override fun tocState() = session()?.tocState() ?: ReadiumTocState.NotLoaded
    override fun searchState() = session()?.searchState()?.value ?: EpubSearchState.Idle
    override fun decorationState(group: ReadiumDecorationGroup) =
        session()?.decorationState(group)?.toPlatformState()
            ?: ReadiumReaderDecorationState(0, 0, 0, false, false, false, false)
    override fun next(animated: Boolean) =
        session()?.next(animated)?.toPlatformResult() ?: ReadiumPlatformViewNavigationResult.SessionDisposed
    override fun previous(animated: Boolean) =
        session()?.previous(animated)?.toPlatformResult() ?: ReadiumPlatformViewNavigationResult.SessionDisposed
    override fun goToProgression(
        progression: Double,
        animated: Boolean,
        onComplete: (ReadiumPlatformViewNavigationResult) -> Unit,
    ) {
        val active = session()
        if (active == null) {
            onComplete(ReadiumPlatformViewNavigationResult.SessionDisposed)
            return
        }
        scope.launch {
            onComplete(active.goToProgression(progression, animated).toPlatformResult())
        }
    }
    override fun goToProgression(
        progression: Double,
        animated: Boolean,
        progressOwner: ProgressNavigationOwner?,
        onComplete: (ReadiumPlatformViewNavigationResult) -> Unit,
    ) {
        val active = session()
        if (active == null) {
            onComplete(ReadiumPlatformViewNavigationResult.SessionDisposed)
            return
        }
        scope.launch {
            var result: ReadiumPlatformViewNavigationResult = ReadiumPlatformViewNavigationResult.Cancelled
            try {
                result = active.goToProgression(progression, animated, progressOwner).toPlatformResult()
            } catch (_: kotlinx.coroutines.CancellationException) {
                // Cancellation cannot depend on a callback it prevented.
            } catch (_: Exception) {
                result = ReadiumPlatformViewNavigationResult.Failed
            } finally {
                onComplete(result)
            }
        }
    }
    override fun goToProgressLocator(locator: Locator, progression: Double, owner: ProgressNavigationOwner,
        readingOrderIndex: Int?, onComplete: (ReadiumPlatformViewNavigationResult) -> Unit,
    ) {
        val active = session()
        if (active == null) { onComplete(ReadiumPlatformViewNavigationResult.SessionDisposed); return }
        scope.launch {
            var result: ReadiumPlatformViewNavigationResult = ReadiumPlatformViewNavigationResult.Cancelled
            try {
                result = active.goToProgression(progression, false, owner, locator, readingOrderIndex).toPlatformResult()
            } catch (_: kotlinx.coroutines.CancellationException) {
                // Keep the existing one-shot cancellation completion contract.
            } catch (_: Exception) { result = ReadiumPlatformViewNavigationResult.Failed }
            finally { onComplete(result) }
        }
    }
    override fun openProgressScrubSession(sessionId: Long): Boolean =
        session()?.openProgressScrubSession(sessionId) == true
    override fun invalidateProgressScrubSession(sessionId: Long): Boolean =
        session()?.invalidateProgressScrubSession(sessionId) == true

    override fun reserveProgressScrubFinal(owner: ProgressNavigationOwner): Boolean =
        session()?.reserveProgressScrubFinal(owner) == true

    override fun supersedeSettingsPreviewsBefore(requestId: Long): Boolean =
        session()?.supersedeSettingsPreviewsBefore(requestId) == true
    override fun settingsReflowGesture(id: Long, slider: String, action: String, value: Double, onComplete: (Boolean) -> Unit) {
        val current = session()
        if (current == null) onComplete(false) else current.settingsReflowGesture(id, slider, action, value, onComplete)
    }
    override fun search(query: String) { session()?.search(query) }
    override fun loadNextSearchPage() { session()?.loadNextSearchPage() }
    override fun retrySearch() { session()?.retrySearch() }
    override fun clearSearch() { session()?.clearSearch() }
    override fun goToSearchResult(resultId: String, animated: Boolean) =
        session()?.goToSearchResult(resultId, animated)?.toPlatformResult() ?: ReadiumPlatformViewSearchNavigationResult.SessionDisposed
    override fun setPersistentHighlights(decorations: List<ReadiumDecorationSpec>, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) {
        session()?.setPersistentHighlights(decorations) { onComplete(it.toPlatformResult()) } ?: onComplete(ReadiumPlatformViewDecorationResult.SessionDisposed)
    }
    override fun setSearchDecoration(locator: Locator, tint: Int, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) {
        session()?.setSearchDecoration(locator, tint) { onComplete(it.toPlatformResult()) } ?: onComplete(ReadiumPlatformViewDecorationResult.SessionDisposed)
    }
    override fun clearSearchDecoration(onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) {
        session()?.clearSearchDecoration { onComplete(it.toPlatformResult()) } ?: onComplete(ReadiumPlatformViewDecorationResult.SessionDisposed)
    }
    override fun setDecorations(
        group: ReadiumDecorationGroup,
        decorations: List<ReadiumDecorationSpec>,
        onComplete: (ReadiumPlatformViewDecorationResult) -> Unit,
    ) {
        session()?.setDecorations(group, decorations) { onComplete(it.toPlatformResult()) }
            ?: onComplete(ReadiumPlatformViewDecorationResult.SessionDisposed)
    }
    override fun upsertDecoration(
        group: ReadiumDecorationGroup,
        decoration: ReadiumDecorationSpec,
        onComplete: (ReadiumPlatformViewDecorationResult) -> Unit,
    ) {
        session()?.upsertDecoration(group, decoration) { onComplete(it.toPlatformResult()) }
            ?: onComplete(ReadiumPlatformViewDecorationResult.SessionDisposed)
    }
    override fun removeDecoration(
        group: ReadiumDecorationGroup,
        id: String,
        onComplete: (ReadiumPlatformViewDecorationResult) -> Unit,
    ) {
        session()?.removeDecoration(group, id) { onComplete(it.toPlatformResult()) }
            ?: onComplete(ReadiumPlatformViewDecorationResult.SessionDisposed)
    }
    override fun clearDecorations(
        group: ReadiumDecorationGroup,
        onComplete: (ReadiumPlatformViewDecorationResult) -> Unit,
    ) {
        session()?.clearDecorations(group) { onComplete(it.toPlatformResult()) }
            ?: onComplete(ReadiumPlatformViewDecorationResult.SessionDisposed)
    }
    override fun applyPreferences(preferences: EpubPreferences, onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit) {
        session()?.applyPreferences(preferences) { onComplete(it.toPlatformResult()) } ?: onComplete(ReadiumPlatformViewPreferenceResult.SessionDisposed)
    }
    override fun applyPreferencesPayload(
        preferences: ReaderPreferencesPayload,
        isNightMode: Boolean,
        onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit,
    ) = applyPreferencesPayloadWithDiagnostics(preferences, isNightMode, null, onComplete)

    override fun applyPreferencesPayloadWithDiagnostics(
        preferences: ReaderPreferencesPayload,
        isNightMode: Boolean,
        diagnosticContext: ReadiumReflowDiagnosticContext?,
        onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit,
    ) {
        val epubPreferences = preferences.toEpubPreferences(isNightMode)
        session()?.applyPreferencesWithDiagnostics(
            epubPreferences,
            diagnosticContext,
        ) { onComplete(it.toPlatformResult()) }
            ?: onComplete(ReadiumPlatformViewPreferenceResult.SessionDisposed)
    }

    override fun applySettingsPreviewPayloadWithDiagnostics(
        preferences: ReaderPreferencesPayload,
        isNightMode: Boolean,
        diagnosticContext: ReadiumReflowDiagnosticContext?,
        previewRequestId: Long,
        onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit,
    ) {
        val epubPreferences = preferences.toEpubPreferences(isNightMode)
        session()?.applyPreferencesWithDiagnostics(
            epubPreferences,
            diagnosticContext,
            previewRequestId,
        ) { onComplete(it.toPlatformResult()) }
            ?: onComplete(ReadiumPlatformViewPreferenceResult.SessionDisposed)
    }
    override fun goTo(locator: Locator, animated: Boolean) =
        session()?.goTo(locator, animated)?.toPlatformResult() ?: ReadiumPlatformViewNavigationResult.SessionDisposed
    override fun goToTocEntry(entryId: String, animated: Boolean) =
        session()?.goToTocEntry(entryId, animated)?.toPlatformResult() ?: ReadiumPlatformViewNavigationResult.SessionDisposed

    override fun loadProgressTargets(onComplete: (Result<List<ProgressNavigationTarget>>) -> Unit) {
        if (isDisposed()) {
            onComplete(Result.failure(IllegalStateException("session_disposed")))
            return
        }
        val activeSession = session()
        if (activeSession == null) {
            onComplete(Result.failure(IllegalStateException("session_not_ready")))
            return
        }
        scope.launch {
            onComplete(activeSession.progressionTargets())
        }
    }
}

internal fun ReadiumReaderSession.Error.toPlatformError() = ReadiumPlatformViewError(code)
internal fun ReadiumReaderSession.PreferenceState.toPlatformState() = ReadiumPlatformViewPreferenceState(requested, applied, generation, isApplying)
internal fun ReadiumReaderSession.DecorationState.toPlatformState() = ReadiumReaderDecorationState(requestedCount, appliedCount, generation, isApplying, isReady, selectionProtected, hasApplied)
internal fun ReadiumReaderSession.PreferenceResult.toPlatformResult() = when (this) {
    ReadiumReaderSession.PreferenceResult.Applied -> ReadiumPlatformViewPreferenceResult.Applied
    ReadiumReaderSession.PreferenceResult.Unchanged -> ReadiumPlatformViewPreferenceResult.Unchanged
    ReadiumReaderSession.PreferenceResult.NavigatorNotReady -> ReadiumPlatformViewPreferenceResult.NavigatorNotReady
    ReadiumReaderSession.PreferenceResult.SessionDisposed -> ReadiumPlatformViewPreferenceResult.SessionDisposed
    ReadiumReaderSession.PreferenceResult.Cancelled -> ReadiumPlatformViewPreferenceResult.Cancelled
    is ReadiumReaderSession.PreferenceResult.PositionPreservationFailed -> ReadiumPlatformViewPreferenceResult.Failed
    ReadiumReaderSession.PreferenceResult.Failed -> ReadiumPlatformViewPreferenceResult.Failed
}
internal fun ReadiumReaderSession.DecorationResult.toPlatformResult() = when (this) {
    ReadiumReaderSession.DecorationResult.Applied -> ReadiumPlatformViewDecorationResult.Applied
    ReadiumReaderSession.DecorationResult.Queued -> ReadiumPlatformViewDecorationResult.Queued
    ReadiumReaderSession.DecorationResult.Unchanged -> ReadiumPlatformViewDecorationResult.Unchanged
    ReadiumReaderSession.DecorationResult.Superseded -> ReadiumPlatformViewDecorationResult.Superseded
    ReadiumReaderSession.DecorationResult.Failed -> ReadiumPlatformViewDecorationResult.Failed
    ReadiumReaderSession.DecorationResult.NavigatorNotReady -> ReadiumPlatformViewDecorationResult.NavigatorNotReady
    ReadiumReaderSession.DecorationResult.SessionDisposed -> ReadiumPlatformViewDecorationResult.SessionDisposed
}
internal fun ReadiumReaderSession.NavigationResult.toPlatformResult() = when (this) {
    ReadiumReaderSession.NavigationResult.Completed -> ReadiumPlatformViewNavigationResult.Completed
    ReadiumReaderSession.NavigationResult.CompletedWithPublicationFailure -> ReadiumPlatformViewNavigationResult.CompletedWithPublicationFailure
    ReadiumReaderSession.NavigationResult.RecoveredTimeout -> ReadiumPlatformViewNavigationResult.RecoveredTimeout
    ReadiumReaderSession.NavigationResult.BoundaryReached -> ReadiumPlatformViewNavigationResult.BoundaryReached
    ReadiumReaderSession.NavigationResult.NavigatorNotReady -> ReadiumPlatformViewNavigationResult.NavigatorNotReady
    ReadiumReaderSession.NavigationResult.InvalidLocator -> ReadiumPlatformViewNavigationResult.InvalidLocator
    ReadiumReaderSession.NavigationResult.InvalidProgression -> ReadiumPlatformViewNavigationResult.InvalidProgression
    ReadiumReaderSession.NavigationResult.SessionDisposed -> ReadiumPlatformViewNavigationResult.SessionDisposed
    ReadiumReaderSession.NavigationResult.Cancelled -> ReadiumPlatformViewNavigationResult.Cancelled
    ReadiumReaderSession.NavigationResult.TocNotReady -> ReadiumPlatformViewNavigationResult.TocNotReady
    ReadiumReaderSession.NavigationResult.UnknownTocEntry -> ReadiumPlatformViewNavigationResult.UnknownTocEntry
    ReadiumReaderSession.NavigationResult.Failed -> ReadiumPlatformViewNavigationResult.Failed
}
internal fun ReadiumReaderSession.SearchNavigationResult.toPlatformResult() = when (this) {
    ReadiumReaderSession.SearchNavigationResult.Completed -> ReadiumPlatformViewSearchNavigationResult.Completed
    ReadiumReaderSession.SearchNavigationResult.NavigatorNotReady -> ReadiumPlatformViewSearchNavigationResult.NavigatorNotReady
    ReadiumReaderSession.SearchNavigationResult.SessionDisposed -> ReadiumPlatformViewSearchNavigationResult.SessionDisposed
    ReadiumReaderSession.SearchNavigationResult.UnknownResultId -> ReadiumPlatformViewSearchNavigationResult.UnknownResultId
    ReadiumReaderSession.SearchNavigationResult.ObsoleteResultId -> ReadiumPlatformViewSearchNavigationResult.ObsoleteResultId
    ReadiumReaderSession.SearchNavigationResult.Failed -> ReadiumPlatformViewSearchNavigationResult.Failed
}

/** Pure ownership delegate used by JVM tests and by the production PlatformView lifecycle. */
internal class ReadiumPlatformViewSessionOwner<T>(
    private val factory: () -> T,
    private val initialize: (T) -> Unit,
    private val disposeSession: (T, Boolean) -> Unit,
) {
    private var session: T? = null
    private var initialized = false
    private var disposed = false

    fun createOnce(): T? {
        if (disposed) return null
        if (session == null) session = factory()
        return session
    }

    fun initializeOnce() {
        val active = createOnce() ?: return
        if (initialized || disposed) return
        initialized = true
        initialize(active)
    }

    fun disposeOnce(retainPublicationForRestoredNavigator: Boolean = false) {
        if (disposed) return
        disposed = true
        session?.let { disposeSession(it, retainPublicationForRestoredNavigator) }
        session = null
    }

    fun isDisposed(): Boolean = disposed

    @VisibleForTesting
    fun hasSession(): Boolean = session != null
}
