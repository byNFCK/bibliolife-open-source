package app.bibliolife.reader.readium

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.readium.r2.navigator.DecorableNavigator
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.continuous.EpubContinuousRendition
import org.readium.r2.shared.publication.Locator

/** Stable native groups. A group is replaced atomically and never shares state with another group. */
enum class ReadiumDecorationGroup(val nativeName: String) {
    PERSISTENT_HIGHLIGHTS(ReaderAnnotationDecorationMapper.GROUP),
    SEARCH_RESULT("search-result"),
}

/** UI-independent style data. Native Readium Decoration objects are created only by the gateway. */
sealed class ReadiumDecorationStyle {
    data class Highlight(val tint: Int, val active: Boolean = false) : ReadiumDecorationStyle()
    data class Underline(val tint: Int, val active: Boolean = false) : ReadiumDecorationStyle()
}

/** Normalized decoration input. The Readium Locator remains the target of truth. */
data class ReadiumDecorationSpec(
    val id: String,
    /** Null is only used by transport-invalid test inputs; production mappers reject it. */
    val locator: Locator?,
    val style: ReadiumDecorationStyle,
)

internal fun ReadiumDecorationSpec.toNativeDecoration(): Decoration? = locator?.let { target ->
    Decoration(
        id = id,
        locator = target,
        style = when (val value = style) {
            is ReadiumDecorationStyle.Highlight -> Decoration.Style.Highlight(value.tint, value.active)
            is ReadiumDecorationStyle.Underline -> Decoration.Style.Underline(value.tint, value.active)
        },
        extras = emptyMap(),
    )
}

internal interface ReadiumDecorationGateway {
    suspend fun replace(group: String, decorations: List<ReadiumDecorationSpec>)
}

internal class ReadiumNavigatorDecorationGateway(
    private val navigator: () -> DecorableNavigator?,
) : ReadiumDecorationGateway {
    override suspend fun replace(group: String, decorations: List<ReadiumDecorationSpec>) {
        navigator()?.applyDecorations(decorations.mapNotNull(ReadiumDecorationSpec::toNativeDecoration), group)
            ?: error("navigator_not_ready")
    }
}

/** Continuous delegates only the real Readium operation; session state stays shared. */
internal class ReadiumContinuousDecorationGateway(
    private val renditionProvider: () -> EpubContinuousRendition?,
) : ReadiumDecorationGateway {
    override suspend fun replace(group: String, decorations: List<ReadiumDecorationSpec>) {
        val rendition = renditionProvider() ?: error("navigator_not_ready")
        rendition.applyDecorations(decorations.mapNotNull(ReadiumDecorationSpec::toNativeDecoration), group)
    }
}

/**
 * Latest-wins replacement coordinator for ordinary navigator decorations.
 *
 * There is at most one native call and one pending snapshot per group. A
 * pending request is never started until the previous native call returns, so
 * calls for one group cannot overlap. Completion checks the request generation
 * and disposed flag before changing applied state.
 */
internal class ReadiumDecorationCoordinator(
    private val scope: CoroutineScope,
    private val gateway: ReadiumDecorationGateway,
    private val onStateChanged: (ReadiumDecorationGroup, Snapshot) -> Unit = { _, _ -> },
) {
    data class Snapshot(
        val requested: List<ReadiumDecorationSpec>,
        val applied: List<ReadiumDecorationSpec>,
        val generation: Long,
        val isApplying: Boolean,
        val isReady: Boolean,
        val selectionProtected: Boolean,
        val hasApplied: Boolean,
    )

    sealed class Result {
        data object Applied : Result()
        data object Queued : Result()
        data object Unchanged : Result()
        data object Superseded : Result()
        data object Failed : Result()
        data object NavigatorNotReady : Result()
        data object SessionDisposed : Result()
    }

    private data class Request(
        val generation: Long,
        val snapshot: List<ReadiumDecorationSpec>,
        val complete: (Result) -> Unit,
    )

    private class GroupState {
        var ready = false
        var selectionProtected = false
        var generation = 0L
        var requested: List<ReadiumDecorationSpec> = emptyList()
        var applied: List<ReadiumDecorationSpec> = emptyList()
        var hasApplied = false
        var running: Request? = null
        var pending: Request? = null
        var job: Job? = null
    }

    private val groups = ReadiumDecorationGroup.entries.associateWith { GroupState() }
    private val nativeMutex = Mutex()
    private var disposed = false

    fun snapshot(group: ReadiumDecorationGroup): Snapshot {
        val value = groups.getValue(group)
        return Snapshot(
            requested = value.requested,
            applied = value.applied,
            generation = value.generation,
            isApplying = value.running != null,
            isReady = value.ready,
            selectionProtected = value.selectionProtected,
            hasApplied = value.hasApplied,
        )
    }

    fun onNavigatorReady() {
        if (disposed) return
        groups.values.forEach { it.ready = true }
        groups.keys.forEach { startIfPossible(it) }
        emitAll()
    }

    fun setSelectionProtected(protected: Boolean) {
        if (disposed) return
        if (groups.values.all { it.selectionProtected == protected }) return
        groups.values.forEach { it.selectionProtected = protected }
        if (!protected) groups.keys.forEach(::startIfPossible)
        emitAll()
    }

    fun replace(
        group: ReadiumDecorationGroup,
        decorations: List<ReadiumDecorationSpec>,
        onComplete: (Result) -> Unit = {},
    ): Result {
        if (disposed) return Result.SessionDisposed.also(onComplete)
        val state = groups.getValue(group)
        val normalized = decorations
            .asSequence()
            .filter { it.id.isNotBlank() }
            .distinctBy { it.id }
            .toList()
        if (normalized == state.requested && (state.running != null || state.pending != null)) {
            return Result.Unchanged.also(onComplete)
        }
        if (normalized == state.requested && state.hasApplied && state.applied == normalized) {
            return Result.Unchanged.also(onComplete)
        }
        val request = Request(++state.generation, normalized, onComplete)
        state.requested = normalized
        val oldPending = state.pending
        if (oldPending != null) oldPending.complete(Result.Superseded)
        state.pending = request
        emit(group)
        if (!state.ready) return Result.Queued
        startIfPossible(group)
        return if (state.running === request) Result.Queued else Result.Queued
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        groups.values.forEach { state ->
            state.job?.cancel()
            state.job = null
            state.running?.complete(Result.SessionDisposed)
            state.pending?.complete(Result.SessionDisposed)
            state.running = null
            state.pending = null
        }
    }

    private fun startIfPossible(group: ReadiumDecorationGroup) {
        if (disposed) return
        val state = groups.getValue(group)
        if (!state.ready || state.running != null || state.selectionProtected) return
        val request = state.pending ?: return
        state.pending = null
        state.running = request
        emit(group)
        state.job = scope.launch {
            val succeeded = runCatching {
                nativeMutex.withLock {
                    gateway.replace(group.nativeName, request.snapshot)
                }
            }.isSuccess
            if (disposed || state.running?.generation != request.generation) return@launch
            state.running = null
            state.job = null
            if (succeeded && state.generation == request.generation) {
                state.applied = request.snapshot
                state.hasApplied = true
                request.complete(Result.Applied)
            } else if (succeeded) {
                request.complete(Result.Superseded)
            } else {
                request.complete(Result.Failed)
            }
            emit(group)
            startIfPossible(group)
        }
    }

    private fun emit(group: ReadiumDecorationGroup) = onStateChanged(group, snapshot(group))

    private fun emitAll() = groups.keys.forEach(::emit)

    fun requested(group: ReadiumDecorationGroup): List<ReadiumDecorationSpec> =
        groups.getValue(group).requested
}
