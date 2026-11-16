package app.bibliolife.reader.readium

import org.readium.r2.navigator.epub.continuous.ContinuousNavigationResult

import org.readium.r2.shared.publication.Locator
import org.readium.r2.navigator.epub.continuous.ContinuousViewportVerification

/** Engine-oriented current reading position. No UI formatting belongs here. */
data class ReadiumPositionState(
    val locator: Locator,
    val progression: Double?,
    val totalLogicalPositions: Int? = null,
    val presentation: ReadiumPresentationState = ReadiumPresentationState.Unknown,
    val readingOrderIndex: Int? = null,
)

sealed class ReadiumPresentationState {
    data object Unknown : ReadiumPresentationState()
    data object Scrolling : ReadiumPresentationState()
    data class Paginated(val page: ReadiumRenderedPageState) : ReadiumPresentationState()
}

/** Ephemeral viewport-derived pagination. This must never be persisted in a Locator. */
@ConsistentCopyVisibility
data class ReadiumRenderedPageState private constructor(
    val index: Int,
    val count: Int,
    val progression: Double,
    val layoutGeneration: Long,
    val publicationScoped: Boolean,
) {
    companion object {
        fun create(
            index: Int,
            count: Int,
            layoutGeneration: Long,
            publicationScoped: Boolean,
        ): ReadiumRenderedPageState? {
            if (count < 1 || index !in 0 until count || layoutGeneration < 0) return null
            val progression = if (count == 1) 0.0 else index.toDouble() / (count - 1)
            return ReadiumRenderedPageState(
                index = index,
                count = count,
                progression = progression.coerceIn(0.0, 1.0),
                layoutGeneration = layoutGeneration,
                publicationScoped = publicationScoped,
            )
        }
    }
}

/** Keeps high-frequency deduplication precise enough for same-resource page turns. */
internal data class ReadiumPositionFingerprint(
    val href: String,
    val fragments: List<String>,
    val cssSelector: String?,
    val position: Int?,
    val resourceProgression: Double?,
    val totalProgression: Double?,
    val totalLogicalPositions: Int? = null,
    val presentation: ReadiumPresentationState = ReadiumPresentationState.Unknown,
)

internal fun ReadiumPositionState.fingerprint() = ReadiumPositionFingerprint(
    href = locator.href.toString(),
    fragments = locator.locations.fragments,
    cssSelector = locator.locations["cssSelector"] as? String,
    position = locator.locations.position,
    resourceProgression = locator.locations.progression,
    totalProgression = progression,
    totalLogicalPositions = totalLogicalPositions,
    presentation = presentation,
)

enum class ReadiumNavigationCommand {
    INITIAL_LOCATOR,
    NEXT,
    PREVIOUS,
    LOCATOR,
    PROGRESSION,
}

internal sealed class ReadiumNavigationGate {
    data class Granted(val generation: Long) : ReadiumNavigationGate()
    data object NotReady : ReadiumNavigationGate()
    data object Disposed : ReadiumNavigationGate()
    data object Busy : ReadiumNavigationGate()
}

/**
 * A platform-independent latest-wins coordinator for Readium preferences.
 *
 * It intentionally keeps at most one request running and one replacement
 * request pending. This prevents settings sliders from building an unbounded
 * queue while still ensuring that the newest effective preferences are sent
 * after an earlier navigator call returns.
 */
internal data class ReadiumReflowDiagnosticContext(
    val gestureId: Long,
    val slider: String,
    val applyId: Long,
    val normalizedValue: Double,
)

internal class ReadiumPreferenceCoordinator<T> {
    data class Snapshot<T>(
        val requested: T?,
        val applied: T?,
        val generation: Long,
        val isApplying: Boolean,
    )

    data class Request<T>(
        val generation: Long,
        val value: T,
        val diagnosticContext: ReadiumReflowDiagnosticContext? = null,
    )

    sealed class Action<out T> {
        data class Start<T>(val request: Request<T>) : Action<T>()
        data class Queued<T>(
            val request: Request<T>,
            val supersededPendingRequest: Request<T>?,
        ) : Action<T>()

        data object Unchanged : Action<Nothing>()
        data object NotReady : Action<Nothing>()
        data object Disposed : Action<Nothing>()
    }

    sealed class Completion<out T> {
        data class Processed<T>(
            val request: Request<T>,
            val outcome: Outcome,
            val next: Request<T>?,
        ) : Completion<T>()

        data object Stale : Completion<Nothing>()
    }

    enum class Outcome { APPLIED, SUPERSEDED, FAILED }

    private var ready = false
    private var disposed = false
    private var generation = 0L
    private var requested: T? = null
    private var applied: T? = null
    private var running: Request<T>? = null
    private var pending: Request<T>? = null

    fun onNavigatorReady() {
        if (!disposed) ready = true
    }

    fun seedInitialApplied(value: T) {
        if (disposed) return
        requested = value
        applied = value
    }

    fun seedInitialRequested(value: T) {
        if (!disposed) requested = value
    }

    fun request(
        value: T,
        diagnosticContext: ReadiumReflowDiagnosticContext? = null,
        forceApply: Boolean = false,
    ): Action<T> = when {
        disposed -> Action.Disposed
        !ready -> Action.NotReady
        !forceApply && value == applied && running == null && pending == null -> Action.Unchanged
        !forceApply && value == requested && (running != null || pending != null) -> Action.Unchanged
        running == null -> Request(++generation, value, diagnosticContext).also {
            requested = value
            running = it
        }.let { request -> Action.Start(request) }
        else -> Request(++generation, value, diagnosticContext).let { next ->
            requested = value
            val replaced = pending
            pending = next
            Action.Queued(next, replaced)
        }
    }

    fun complete(
        requestGeneration: Long,
        succeeded: Boolean,
        committedDuringSupersession: Boolean = false,
    ): Completion<T> {
        val completed = running
        if (disposed || completed == null || completed.generation != requestGeneration) {
            return Completion.Stale
        }
        running = null
        val isLatest = completed.generation == generation
        val outcome = when {
            succeeded && (isLatest || committedDuringSupersession) -> {
                applied = completed.value
                Outcome.APPLIED
            }
            succeeded -> Outcome.SUPERSEDED
            else -> Outcome.FAILED
        }
        val next = pending
        pending = null
        running = next
        return Completion.Processed(completed, outcome, next)
    }

    fun cancel(requestGeneration: Long): Completion<T> {
        val completed = running
        if (disposed || completed == null || completed.generation != requestGeneration) {
            return Completion.Stale
        }
        running = null
        val next = pending
        pending = null
        running = next
        return Completion.Processed(completed, Outcome.SUPERSEDED, next)
    }

    fun dispose(): List<Request<T>> {
        if (disposed) return emptyList()
        disposed = true
        ready = false
        val cancelled = listOfNotNull(running, pending)
        running = null
        pending = null
        return cancelled
    }

    fun snapshot() = Snapshot(
        requested = requested,
        applied = applied,
        generation = generation,
        isApplying = running != null,
    )
}

internal fun releaseCommitOwnerBeforeStartingNext(
    releaseOwner: () -> Boolean,
    isOwnerHeld: () -> Boolean,
    startNext: () -> Unit,
): Boolean {
    val acknowledged = try {
        releaseOwner()
    } catch (_: Throwable) {
        false
    }
    val released = acknowledged || !isOwnerHeld()
    if (released) startNext()
    return released
}

/**
 * Small, platform-independent guard for [ReadiumReaderSession].
 *
 * Keeping these one-way transitions separate makes duplicate callbacks from a
 * FragmentManager restore harmless and gives the native module JVM coverage
 * without trying to fake Android fragments or Readium's WebView navigator.
 */
internal class ReadiumReaderSessionState {
    enum class Phase {
        IDLE,
        OPENING_PUBLICATION,
        PUBLICATION_OPENED,
        CONTINUOUS_RENDITION_PENDING,
        NAVIGATOR_ATTACHED,
        NAVIGATOR_READY,
        INITIAL_LOCATOR_RESTORED,
        FAILED,
        DISPOSED,
    }

    var phase: Phase = Phase.IDLE
        private set
    var initialLocatorHandled: Boolean = false
        private set
    var reusedRestoredNavigator: Boolean = false
        private set
    var locatorObservationStarted: Boolean = false
        private set
    var navigationGeneration: Long = 0
        private set
    var navigationInFlight: Boolean = false
        private set
    var latestContinuousNavigationResult: ContinuousNavigationResult? = null
        private set
    private var manualDragInvalidatedNavigationGeneration: Long? = null
    private var continuousCanonicalTarget: ContinuousCanonicalPositionTarget? = null
    var tocState: ReadiumTocState = ReadiumTocState.NotLoaded
        private set
    var currentChapter: ReadiumChapterState = ReadiumChapterState.Unknown
        private set

    fun start(): Boolean = transition(Phase.IDLE, Phase.OPENING_PUBLICATION)

    fun publicationOpened(): Boolean = transition(Phase.OPENING_PUBLICATION, Phase.PUBLICATION_OPENED)

    /** C-1 holds the opened Publication until C-2 attaches the real rendition. */
    fun continuousRenditionPending(): Boolean =
        transition(Phase.PUBLICATION_OPENED, Phase.CONTINUOUS_RENDITION_PENDING)

    fun navigatorAttached(reusedRestoredNavigator: Boolean): Boolean {
        if (phase != Phase.PUBLICATION_OPENED) return false
        this.reusedRestoredNavigator = reusedRestoredNavigator
        return set(Phase.NAVIGATOR_ATTACHED)
    }

    fun navigatorReady(): Boolean =
        phase == Phase.NAVIGATOR_ATTACHED && set(Phase.NAVIGATOR_READY)

    /** The continuous rendition has no Fragment lifecycle but uses the same navigation gates. */
    fun continuousRenditionReady(): Boolean =
        phase == Phase.CONTINUOUS_RENDITION_PENDING && set(Phase.NAVIGATOR_READY)

    fun initialLocatorRestored(): Boolean {
        if (phase != Phase.NAVIGATOR_READY || initialLocatorHandled) return false
        initialLocatorHandled = true
        return set(Phase.INITIAL_LOCATOR_RESTORED)
    }

    fun startLocatorObservation(): Boolean {
        if (phase != Phase.INITIAL_LOCATOR_RESTORED || locatorObservationStarted) return false
        locatorObservationStarted = true
        return true
    }

    fun startTocLoading(): Boolean {
        if (phase == Phase.DISPOSED || tocState !is ReadiumTocState.NotLoaded) return false
        tocState = ReadiumTocState.Loading
        return true
    }

    fun tocReady(entries: List<ReadiumTocEntry>): Boolean {
        if (phase == Phase.DISPOSED || tocState !is ReadiumTocState.Loading) return false
        tocState = if (entries.isEmpty()) ReadiumTocState.Empty else ReadiumTocState.Ready(entries)
        return true
    }

    fun tocFailed(error: ReadiumTocError): Boolean {
        if (phase == Phase.DISPOSED || tocState !is ReadiumTocState.Loading) return false
        tocState = ReadiumTocState.Failed(error)
        return true
    }

    fun updateCurrentChapter(chapter: ReadiumChapterState): Boolean {
        if (phase == Phase.DISPOSED || currentChapter == chapter) return false
        currentChapter = chapter
        return true
    }

    fun beginNavigation(): ReadiumNavigationGate = when {
        phase == Phase.DISPOSED -> ReadiumNavigationGate.Disposed
        phase != Phase.INITIAL_LOCATOR_RESTORED -> ReadiumNavigationGate.NotReady
        navigationInFlight -> ReadiumNavigationGate.Busy
        else -> {
            navigationInFlight = true
            latestContinuousNavigationResult = null
            continuousCanonicalTarget = null
            manualDragInvalidatedNavigationGeneration = null
            ReadiumNavigationGate.Granted(++navigationGeneration)
        }
    }

    /** Retains canonical publication identity only for this exact active seek. */
    fun recordContinuousCanonicalTarget(
        generation: Long,
        href: String,
        readingOrderIndex: Int,
        position: Int?,
        totalProgression: Double?,
    ): Boolean {
        if (phase == Phase.DISPOSED || !navigationInFlight || generation != navigationGeneration ||
            href.isBlank() || readingOrderIndex < 0 || position == null || position < 1 ||
            totalProgression == null || !totalProgression.isFinite() || totalProgression !in 0.0..1.0
        ) return false
        continuousCanonicalTarget = ContinuousCanonicalPositionTarget(
            generation = generation,
            href = href,
            readingOrderIndex = readingOrderIndex,
            position = position,
            totalProgression = totalProgression,
        )
        return true
    }

    /** Applies only publication identity, leaving all visible locator fields intact. */
    fun applyVerifiedContinuousCanonicalPosition(
        position: ReadiumPositionState,
        readingOrderIndex: Int?,
    ): ReadiumPositionState {
        val target = continuousCanonicalTarget ?: return position
        val result = latestContinuousNavigationResult ?: return position
        val verification = result.finalViewportVerification
        if (phase == Phase.DISPOSED || target.generation != navigationGeneration ||
            target.generation != result.transactionId || readingOrderIndex != target.readingOrderIndex ||
            result.outcome == org.readium.r2.navigator.epub.continuous.ContinuousNavigationOutcome.FAILED_BEFORE_POSITION ||
            result.outcome == org.readium.r2.navigator.epub.continuous.ContinuousNavigationOutcome.SUPERSEDED_AFTER_POSITION ||
            verification.classification != ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT ||
            !verification.sameResource || !verification.authorityStillCurrent
        ) return position

        val locator = position.locator.copyWithLocations(
            position = target.position,
            totalProgression = target.totalProgression,
        )
        return position.copy(locator = locator, progression = target.totalProgression)
    }

    /** A RecyclerView drag revokes the current programmatic target immediately. */
    fun invalidateContinuousNavigationAuthority() {
        if (phase == Phase.DISPOSED) return
        manualDragInvalidatedNavigationGeneration = navigationGeneration
        continuousCanonicalTarget = null
        latestContinuousNavigationResult
            ?.takeIf { it.transactionId == navigationGeneration }
            ?.let { result ->
                latestContinuousNavigationResult = result.copy(
                    finalViewportVerification = result.finalViewportVerification.copy(
                        classification = org.readium.r2.navigator.epub.continuous.ContinuousViewportVerification.SUPERSEDED,
                        authorityStillCurrent = false,
                    ),
                )
            }
    }

    fun recordContinuousNavigationResult(
        result: ContinuousNavigationResult,
        expectedGeneration: Long,
    ): Boolean {
        if (phase == Phase.DISPOSED ||
            !navigationInFlight ||
            expectedGeneration != navigationGeneration ||
            manualDragInvalidatedNavigationGeneration == expectedGeneration ||
            result.transactionId != expectedGeneration
        ) return false
        latestContinuousNavigationResult = result
        return true
    }

    fun completeNavigation(generation: Long): Boolean {
        if (phase == Phase.DISPOSED || generation != navigationGeneration || !navigationInFlight) return false
        navigationInFlight = false
        return true
    }

    internal fun isCurrentContinuousNavigation(generation: Long): Boolean =
        isActive() && navigationInFlight && navigationGeneration == generation &&
            manualDragInvalidatedNavigationGeneration != generation

    fun fail(): Boolean {
        if (phase == Phase.DISPOSED || phase == Phase.FAILED) return false
        phase = Phase.FAILED
        return true
    }

    fun dispose(): Boolean {
        if (phase == Phase.DISPOSED) return false
        navigationInFlight = false
        navigationGeneration++
        latestContinuousNavigationResult = null
        continuousCanonicalTarget = null
        manualDragInvalidatedNavigationGeneration = navigationGeneration
        phase = Phase.DISPOSED
        return true
    }

    fun isActive(): Boolean = phase != Phase.DISPOSED && phase != Phase.FAILED

    private fun transition(from: Phase, to: Phase): Boolean =
        phase == from && set(to)

    private fun set(value: Phase): Boolean {
        phase = value
        return true
    }
}

private data class ContinuousCanonicalPositionTarget(
    val generation: Long,
    val href: String,
    val readingOrderIndex: Int,
    val position: Int,
    val totalProgression: Double,
)
