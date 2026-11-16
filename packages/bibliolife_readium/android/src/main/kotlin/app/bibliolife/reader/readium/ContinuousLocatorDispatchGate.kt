package app.bibliolife.reader.readium

/**
 * Coalesces parent-viewport Locator work without inventing a Locator or
 * retaining a stale resource. One real WebView command may be active and only
 * the newest distinct resource-local target is retained for one follow-up.
 */
internal class ContinuousLocatorDispatchGate<T> {
    private var active: T? = null
    private var pending: T? = null

    /** Returns a target only when the caller must start a worker. */
    fun offer(target: T): T? {
        val running = active
        if (running == null) {
            active = target
            return target
        }
        if (target == running || target == pending) return null
        if (running is OwnedContinuousLocatorRequest &&
            target is OwnedContinuousLocatorRequest &&
            running.owner?.phase == ProgressNavigationOwner.Phase.FINAL &&
            target.owner?.phase != ProgressNavigationOwner.Phase.FINAL
        ) return null
        val pendingOwned = pending as? OwnedContinuousLocatorRequest
        if (pendingOwned != null &&
            target is OwnedContinuousLocatorRequest &&
            pendingOwned.owner?.phase == ProgressNavigationOwner.Phase.FINAL &&
            target.owner?.phase != ProgressNavigationOwner.Phase.FINAL
        ) return null
        pending = target
        return null
    }

    /** Completes [target] and returns at most one newest follow-up target. */
    fun complete(target: T): T? {
        if (active != target) return null
        val next = pending
        pending = null
        active = next
        return next
    }

    fun clear(): List<T> {
        val abandoned = listOfNotNull(active, pending)
        active = null
        pending = null
        return abandoned
    }
}

/** Marker implemented by dispatch requests whose final scrub publication must not be coalesced away. */
internal interface OwnedContinuousLocatorRequest {
    val owner: ProgressNavigationOwner?
    fun reject()
}

/** Samples only actual manual movement; callers still publish the IDLE result unthrottled. */
internal class ContinuousManualScrollThrottle(private val intervalMs: Long = 125L) {
    private var lastSampleMs: Long? = null

    init {
        require(intervalMs > 0)
    }

    fun shouldSample(nowMs: Long): Boolean {
        val previous = lastSampleMs
        if (previous != null && nowMs - previous < intervalMs) return false
        lastSampleMs = nowMs
        return true
    }

    fun reset() {
        lastSampleMs = null
    }
}

internal data class ContinuousManualScrollRequestIdentity(
    val scrollEpoch: Long,
    val navigationGeneration: Long,
    val liveManual: Boolean,
)

/** Fences live manual results across new viewport sessions and programmatic navigation. */
internal class ContinuousManualScrollPublicationGate {
    var active: Boolean = false
        private set
    private var epoch = 0L
    private var navigationGeneration = 0L
    val scrollEpoch: Long get() = epoch

    fun activityChanged(active: Boolean, currentNavigationGeneration: Long): Boolean {
        if (this.active == active) return false
        this.active = active
        epoch++
        if (active) navigationGeneration = currentNavigationGeneration
        return true
    }

    fun manualDragStarted(currentNavigationGeneration: Long) {
        navigationGeneration = currentNavigationGeneration
    }

    fun requestIdentity(
        liveManual: Boolean,
        currentNavigationGeneration: Long,
        navigationInFlight: Boolean,
    ): ContinuousManualScrollRequestIdentity? {
        if (liveManual && (!active || navigationInFlight ||
                currentNavigationGeneration != navigationGeneration)
        ) return null
        return ContinuousManualScrollRequestIdentity(
            scrollEpoch = epoch,
            navigationGeneration = currentNavigationGeneration,
            liveManual = liveManual,
        )
    }

    fun mayPublish(
        identity: ContinuousManualScrollRequestIdentity,
        currentNavigationGeneration: Long,
        navigationInFlight: Boolean,
    ): Boolean {
        if (identity.scrollEpoch != epoch) return false
        if (!identity.liveManual) return true
        return active && !navigationInFlight &&
            identity.navigationGeneration == currentNavigationGeneration &&
            identity.navigationGeneration == navigationGeneration
    }
}

/**
 * Native text selection is not reader navigation. It invalidates only
 * in-flight parent-viewport Locator publication until that exact native
 * selection session ends; ordinary post-selection observation remains live.
 */
internal class ContinuousSelectionLocatorPublicationGate {
    private var activeSessionId: Long? = null
    private var epoch = 0L

    fun begin(sessionId: Long) {
        if (activeSessionId == sessionId) return
        activeSessionId = sessionId
        epoch += 1
    }

    fun end(sessionId: Long) {
        if (activeSessionId != sessionId) return
        activeSessionId = null
        epoch += 1
    }

    fun captureEpoch(): Long = epoch

    fun mayRequest(): Boolean = activeSessionId == null

    fun mayPublish(capturedEpoch: Long): Boolean =
        activeSessionId == null && capturedEpoch == epoch
}
