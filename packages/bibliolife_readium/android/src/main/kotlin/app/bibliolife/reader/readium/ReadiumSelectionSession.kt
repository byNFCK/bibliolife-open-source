package app.bibliolife.reader.readium

import android.graphics.RectF
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.readium.r2.navigator.SelectableNavigator
import org.readium.r2.navigator.Selection
import org.readium.r2.navigator.epub.continuous.EpubContinuousRendition
import org.readium.r2.shared.publication.Locator

/** A UI-independent rectangle in navigator coordinates. */
data class ReadiumSelectionRect(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
) {
    fun toRectF(): RectF = RectF(left, top, right, bottom)

    companion object {
        fun from(rect: RectF?): ReadiumSelectionRect? = rect?.let {
            listOf(it.left, it.top, it.right, it.bottom)
                .takeIf { values -> values.all(Float::isFinite) }
                ?.let { values -> ReadiumSelectionRect(values[0], values[1], values[2], values[3]) }
        }
    }
}

/** Native Locator-backed selection data. No DOM, View, ActionMode or menu state is stored here. */
data class ReadiumSelectionSnapshot(
    /** Always non-null for the production native gateway; nullable only for pure state fakes. */
    val locator: Locator?,
    val selectedText: String,
    val textBefore: String?,
    val textAfter: String?,
    val href: String,
    val progression: Double?,
    val totalProgression: Double?,
    val rect: ReadiumSelectionRect?,
) {
    companion object {
        fun fromNative(selection: Selection): ReadiumSelectionSnapshot? {
            val locator = selection.locator
            val selectedText = locator.text.highlight ?: return null
            val href = locator.href.toString()
            if (selectedText.isBlank() || href.isBlank()) return null
            return ReadiumSelectionSnapshot(
                locator = locator,
                selectedText = selectedText,
                textBefore = locator.text.before?.takeIf(String::isNotEmpty),
                textAfter = locator.text.after?.takeIf(String::isNotEmpty),
                href = href,
                progression = locator.locations.progression.validSelectionProgression(),
                totalProgression = locator.locations.totalProgression.validSelectionProgression(),
                rect = ReadiumSelectionRect.from(selection.rect),
            )
        }
    }
}

enum class ReadiumSelectionStatus {
    INACTIVE,
    PENDING,
    ACTIVE,
    CLEARING,
    RETRIEVAL_FAILED,
    DISPOSED,
}

data class ReadiumSelectionState(
    val status: ReadiumSelectionStatus,
    val sessionId: Long?,
    val nativeSessionId: Long?,
    val generation: Long,
    val viewportEpoch: Long,
    val selection: ReadiumSelectionSnapshot?,
    val retrievalInFlight: Boolean,
    val error: Throwable?,
) {
    val sessionActive: Boolean
        get() = status == ReadiumSelectionStatus.PENDING ||
            status == ReadiumSelectionStatus.ACTIVE ||
            status == ReadiumSelectionStatus.CLEARING ||
            status == ReadiumSelectionStatus.RETRIEVAL_FAILED

    val blocksUserNavigation: Boolean
        get() = sessionActive
}

internal interface ReadiumSelectionGateway {
    suspend fun currentSelection(): ReadiumSelectionSnapshot?
    fun clearSelection()
}

internal class ReadiumNavigatorSelectionGateway(
    private val navigatorProvider: () -> SelectableNavigator?,
) : ReadiumSelectionGateway {
    override suspend fun currentSelection(): ReadiumSelectionSnapshot? {
        val navigator = navigatorProvider() ?: throw ReadiumSelectionNavigatorNotReady
        return navigator.currentSelection()?.let(ReadiumSelectionSnapshot::fromNative)
    }

    override fun clearSelection() {
        navigatorProvider()?.clearSelection() ?: throw ReadiumSelectionNavigatorNotReady
    }
}

/**
 * Continuous selection always resolves the exact owner recorded by the
 * rendition. It never guesses from the reading anchor or visible holders.
 */
internal class ReadiumContinuousSelectionGateway(
    private val renditionProvider: () -> EpubContinuousRendition?,
) : ReadiumSelectionGateway {
    override suspend fun currentSelection(): ReadiumSelectionSnapshot? {
        val rendition = renditionProvider() ?: throw ReadiumSelectionNavigatorNotReady
        return rendition.currentSelection()?.let(ReadiumSelectionSnapshot::fromNative)
    }

    override fun clearSelection() {
        renditionProvider()?.clearSelection() ?: throw ReadiumSelectionNavigatorNotReady
    }
}

internal object ReadiumSelectionNavigatorNotReady : IllegalStateException("navigator_not_ready")

/**
 * Starts the one general native selection-resolution pipeline after the DOM session callback.
 * A single bounded retry handles the proven transient empty first serialization; presentation
 * is not involved and can never request another native read.
 */
internal class ReadiumNativeSelectionResolutionHost(
    private val beginSession: (Long) -> Long?,
    private val activeNativeSessionId: () -> Long?,
    private val post: (Runnable) -> Boolean,
    private val requestSelection: (
        onComplete: (ReadiumSelectionRequestResult) -> Unit,
        refreshAfterInFlight: Boolean,
    ) -> ReadiumSelectionRequestResult,
    private val trace: (String) -> Unit = {},
) {
    private var activeSessionId: Long? = null

    fun onNativeSelectionSessionStarted(nativeSessionId: Long) {
        if (activeSessionId == nativeSessionId) return
        if (beginSession(nativeSessionId) == null) return
        activeSessionId = nativeSessionId
        postResolution(nativeSessionId, retryEmpty = true)
    }

    fun onNativeSelectionSessionEnded(nativeSessionId: Long) {
        if (activeSessionId == nativeSessionId) activeSessionId = null
    }

    /** Refreshes the same authoritative snapshot after native handle geometry changes. */
    fun refreshActiveSelection() {
        val nativeSessionId = activeSessionId ?: return
        postResolution(nativeSessionId, retryEmpty = false, refreshAfterInFlight = true)
    }

    private fun postResolution(
        nativeSessionId: Long,
        retryEmpty: Boolean,
        refreshAfterInFlight: Boolean = false,
    ) {
        val posted = post(
            Runnable {
                if (activeSessionId != nativeSessionId || activeNativeSessionId() != nativeSessionId) return@Runnable
                trace(
                    if (refreshAfterInFlight) "READIUM_SELECTION_RESOLUTION_REFRESH"
                    else "READIUM_SELECTION_RESOLUTION_REQUEST retryEmpty=$retryEmpty",
                )
                requestSelection(
                    { result ->
                        if (result == ReadiumSelectionRequestResult.Empty && retryEmpty &&
                            activeSessionId == nativeSessionId
                        ) {
                            postResolution(nativeSessionId, retryEmpty = false)
                        }
                    },
                    refreshAfterInFlight,
                )
            },
        )
        if (!posted) trace("READIUM_SELECTION_RESOLUTION_REQUEST_REJECTED")
    }
}

sealed class ReadiumSelectionRequestResult {
    data class Updated(val selection: ReadiumSelectionSnapshot) : ReadiumSelectionRequestResult()
    data object Empty : ReadiumSelectionRequestResult()
    data object Started : ReadiumSelectionRequestResult()
    data object AlreadyInFlight : ReadiumSelectionRequestResult()
    data object Clearing : ReadiumSelectionRequestResult()
    data object NotActive : ReadiumSelectionRequestResult()
    data object NavigatorNotReady : ReadiumSelectionRequestResult()
    data class Failed(val error: Throwable) : ReadiumSelectionRequestResult()
    data object Stale : ReadiumSelectionRequestResult()
    data object Disposed : ReadiumSelectionRequestResult()
}

sealed class ReadiumSelectionClearResult {
    data object Started : ReadiumSelectionClearResult()
    data object AlreadyClearing : ReadiumSelectionClearResult()
    data object NotActive : ReadiumSelectionClearResult()
    data object NavigatorNotReady : ReadiumSelectionClearResult()
    data class Failed(val error: Throwable) : ReadiumSelectionClearResult()
    data object Disposed : ReadiumSelectionClearResult()
}

/**
 * Owns the native selection lifetime, retrieval generations and clear command.
 * The host only forwards native callbacks and presents the resulting state.
 */
internal class ReadiumSelectionCoordinator(
    private val scope: CoroutineScope,
    private val gateway: ReadiumSelectionGateway,
    private val onStateChanged: (ReadiumSelectionState) -> Unit = {},
    private val onResolvedSelection: (ReadiumSelectionState) -> Unit = {},
) {
    private var state = ReadiumSelectionState(
        status = ReadiumSelectionStatus.INACTIVE,
        sessionId = null,
        nativeSessionId = null,
        generation = 0L,
        viewportEpoch = 0L,
        selection = null,
        retrievalInFlight = false,
        error = null,
    )
    private var nextSessionId = 0L
    private var retrievalToken = 0L
    private var retrievalJob: Job? = null
    private var retrievalPending = false
    private val retrievalCallbacks = mutableListOf<(ReadiumSelectionRequestResult) -> Unit>()
    private val retrievalPendingCallbacks = mutableListOf<(ReadiumSelectionRequestResult) -> Unit>()

    fun snapshot(): ReadiumSelectionState = state

    fun onNativeSelectionSessionStarted(nativeSessionId: Long): Long? {
        if (state.status == ReadiumSelectionStatus.DISPOSED) return null
        if (state.nativeSessionId == nativeSessionId && state.sessionActive) return state.sessionId
        invalidateRetrieval()
        val sessionId = ++nextSessionId
        state = state.copy(
            status = ReadiumSelectionStatus.PENDING,
            sessionId = sessionId,
            nativeSessionId = nativeSessionId,
            generation = state.generation + 1,
            selection = null,
            retrievalInFlight = false,
            error = null,
        )
        publish()
        return sessionId
    }

    fun onNativeSelectionSessionEnded(nativeSessionId: Long): Boolean {
        if (state.status == ReadiumSelectionStatus.DISPOSED || state.nativeSessionId != nativeSessionId) return false
        invalidateRetrieval()
        state = state.copy(
            status = ReadiumSelectionStatus.INACTIVE,
            sessionId = null,
            nativeSessionId = null,
            generation = state.generation + 1,
            selection = null,
            retrievalInFlight = false,
            error = null,
        )
        publish()
        return true
    }

    fun onViewportEpochChanged(epoch: Long) {
        if (state.status == ReadiumSelectionStatus.DISPOSED || state.viewportEpoch == epoch) return
        invalidateRetrieval()
        state = state.copy(viewportEpoch = epoch, generation = state.generation + 1)
        if (state.sessionActive) {
            state = state.copy(
                status = ReadiumSelectionStatus.PENDING,
                selection = null,
                retrievalInFlight = false,
                error = null,
            )
        }
        publish()
    }

    fun requestCurrentSelection(
        onComplete: (ReadiumSelectionRequestResult) -> Unit = {},
        refreshAfterInFlight: Boolean = false,
    ): ReadiumSelectionRequestResult {
        if (state.status == ReadiumSelectionStatus.DISPOSED) {
            onComplete(ReadiumSelectionRequestResult.Disposed)
            return ReadiumSelectionRequestResult.Disposed
        }
        if (!state.sessionActive || state.nativeSessionId == null || state.sessionId == null) {
            onComplete(ReadiumSelectionRequestResult.NotActive)
            return ReadiumSelectionRequestResult.NotActive
        }
        if (state.status == ReadiumSelectionStatus.CLEARING) {
            onComplete(ReadiumSelectionRequestResult.Clearing)
            return ReadiumSelectionRequestResult.Clearing
        }
        if (state.retrievalInFlight) {
            if (refreshAfterInFlight) {
                retrievalPending = true
                retrievalPendingCallbacks += onComplete
            } else {
                retrievalCallbacks += onComplete
            }
            return ReadiumSelectionRequestResult.AlreadyInFlight
        }
        retrievalCallbacks += onComplete
        startRetrieval()
        return ReadiumSelectionRequestResult.Started
    }

    fun clearSelection(): ReadiumSelectionClearResult {
        if (state.status == ReadiumSelectionStatus.DISPOSED) return ReadiumSelectionClearResult.Disposed
        if (!state.sessionActive || state.nativeSessionId == null) return ReadiumSelectionClearResult.NotActive
        if (state.status == ReadiumSelectionStatus.CLEARING) return ReadiumSelectionClearResult.AlreadyClearing
        val previousStatus = state.status
        invalidateRetrieval()
        state = state.copy(
            status = ReadiumSelectionStatus.CLEARING,
            generation = state.generation + 1,
            selection = state.selection,
            retrievalInFlight = false,
            error = null,
        )
        publish()
        return try {
            gateway.clearSelection()
            ReadiumSelectionClearResult.Started
        } catch (error: Throwable) {
            state = state.copy(status = previousStatus, error = error)
            publish()
            if (error === ReadiumSelectionNavigatorNotReady) ReadiumSelectionClearResult.NavigatorNotReady
            else ReadiumSelectionClearResult.Failed(error)
        }
    }

    fun dispose() {
        if (state.status == ReadiumSelectionStatus.DISPOSED) return
        val callbacks = retrievalCallbacks.toList() + retrievalPendingCallbacks.toList()
        retrievalCallbacks.clear()
        retrievalPendingCallbacks.clear()
        state = state.copy(
            status = ReadiumSelectionStatus.DISPOSED,
            sessionId = null,
            nativeSessionId = null,
            selection = null,
            retrievalInFlight = false,
            error = null,
        )
        retrievalToken++
        retrievalJob?.cancel()
        retrievalJob = null
        retrievalPending = false
        callbacks.forEach { it(ReadiumSelectionRequestResult.Disposed) }
        publish()
    }

    private fun startRetrieval() {
        val sessionId = state.sessionId ?: return
        val nativeSessionId = state.nativeSessionId ?: return
        val generation = state.generation
        val viewportEpoch = state.viewportEpoch
        val token = ++retrievalToken
        state = state.copy(status = ReadiumSelectionStatus.PENDING, retrievalInFlight = true, error = null)
        publish()
        retrievalJob = scope.launch {
            val result = runCatching { gateway.currentSelection() }
            val stale = state.status == ReadiumSelectionStatus.DISPOSED ||
                state.sessionId != sessionId || state.nativeSessionId != nativeSessionId ||
                state.generation != generation || state.viewportEpoch != viewportEpoch ||
                retrievalToken != token
            retrievalJob = null
            if (stale) {
                completeCallbacks(ReadiumSelectionRequestResult.Stale)
            } else {
                val value = result.getOrNull()
                val normalized = value?.takeIf { it.selectedText.isNotBlank() && it.href.isNotBlank() }
                when {
                    result.isFailure -> {
                        val error = result.exceptionOrNull() ?: IllegalStateException("selection_read_failed")
                        state = state.copy(status = ReadiumSelectionStatus.RETRIEVAL_FAILED, retrievalInFlight = false, error = error)
                        publish()
                        completeCallbacks(
                            if (error === ReadiumSelectionNavigatorNotReady) ReadiumSelectionRequestResult.NavigatorNotReady
                            else ReadiumSelectionRequestResult.Failed(error),
                        )
                    }
                    normalized == null -> {
                        // An empty response never erases a newer valid snapshot.
                        state = state.copy(
                            status = if (state.selection == null) ReadiumSelectionStatus.PENDING else ReadiumSelectionStatus.ACTIVE,
                            retrievalInFlight = false,
                        )
                        publish()
                        completeCallbacks(ReadiumSelectionRequestResult.Empty)
                    }
                    else -> {
                        state = state.copy(
                            status = ReadiumSelectionStatus.ACTIVE,
                            selection = normalized,
                            retrievalInFlight = false,
                            error = null,
                        )
                        publish()
                        // The presentation consumer receives the exact state produced by this
                        // native serialization. It must never initiate a second selection read.
                        onResolvedSelection(state)
                        completeCallbacks(ReadiumSelectionRequestResult.Updated(normalized))
                    }
                }
            }
            if (retrievalPending && state.sessionActive && state.status != ReadiumSelectionStatus.DISPOSED) {
                retrievalPending = false
                retrievalCallbacks += retrievalPendingCallbacks
                retrievalPendingCallbacks.clear()
                startRetrieval()
            } else {
                retrievalPending = false
                retrievalPendingCallbacks.clear()
            }
        }
    }

    private fun completeCallbacks(result: ReadiumSelectionRequestResult) {
        val callbacks = retrievalCallbacks.toList()
        retrievalCallbacks.clear()
        callbacks.forEach { it(result) }
    }

    private fun invalidateRetrieval() {
        retrievalToken++
        retrievalJob?.cancel()
        retrievalJob = null
        retrievalPending = false
        val callbacks = retrievalCallbacks.toList() + retrievalPendingCallbacks.toList()
        retrievalCallbacks.clear()
        retrievalPendingCallbacks.clear()
        callbacks.forEach { it(ReadiumSelectionRequestResult.Stale) }
    }

    private fun publish() = onStateChanged(state)
}

private fun Double?.validSelectionProgression(): Double? =
    this?.takeIf { it.isFinite() && it in 0.0..1.0 }
