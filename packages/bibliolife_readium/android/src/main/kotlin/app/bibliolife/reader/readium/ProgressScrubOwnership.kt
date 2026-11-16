package app.bibliolife.reader.readium

/** Immutable identity carried with a Progress scrub navigation and its publication. */
data class ProgressNavigationOwner(
    val sessionId: Long,
    val requestId: Long,
    val phase: Phase,
) {
    enum class Phase { PREVIEW, FINAL }

    val token: String get() = "$sessionId:$requestId:${phase.name.lowercase()}"
}

/**
 * Reserves ownership before a navigation waits for the navigator mutex. This makes a final
 * request or a newer preview invalidate the old request immediately, including its suspended
 * WebView work and any later locator publication.
 */
internal class ProgressScrubOwnership {
    private var greatestOpenedSessionId: Long = 0
    private var activeSessionId: Long? = null
    private var currentOwner: ProgressNavigationOwner? = null
    private var finalReserved = false
    private var lastReservedRequestId = 0L
    private var lastTerminalRequestId = 0L

    @Synchronized
    fun open(sessionId: Long): Boolean {
        require(sessionId > 0)
        if (sessionId <= greatestOpenedSessionId) return false
        greatestOpenedSessionId = sessionId
        activeSessionId = sessionId
        currentOwner = null
        finalReserved = false
        lastReservedRequestId = 0L
        lastTerminalRequestId = 0L
        return true
    }

    @Synchronized
    fun reserve(owner: ProgressNavigationOwner): Boolean {
        if (owner.sessionId <= 0 || owner.requestId <= 0) return false
        if (activeSessionId != owner.sessionId) return false
        if (owner.requestId <= lastTerminalRequestId) return false
        if (currentOwner == owner) return true
        if (finalReserved) return false
        if (owner.requestId <= lastReservedRequestId) return false
        if (owner.phase == ProgressNavigationOwner.Phase.FINAL) finalReserved = true
        currentOwner = owner
        lastReservedRequestId = owner.requestId
        return true
    }

    @Synchronized
    fun reserveFinal(sessionId: Long, requestId: Long): ProgressNavigationOwner? {
        if (sessionId <= 0 || requestId <= 0 || activeSessionId != sessionId || finalReserved) return null
        if (requestId <= lastReservedRequestId) return null
        return ProgressNavigationOwner(sessionId, requestId, ProgressNavigationOwner.Phase.FINAL).also {
            finalReserved = true
            currentOwner = it
            lastReservedRequestId = requestId
        }
    }

    @Synchronized
    fun isCurrent(owner: ProgressNavigationOwner): Boolean =
        activeSessionId == owner.sessionId && currentOwner == owner

    @Synchronized
    fun finish(owner: ProgressNavigationOwner, keepPublicationAuthority: Boolean) {
        if (activeSessionId != owner.sessionId) return
        lastTerminalRequestId = maxOf(lastTerminalRequestId, owner.requestId)
        if (currentOwner == owner && !keepPublicationAuthority) currentOwner = null
    }

    @Synchronized
    fun pendingAfter(owner: ProgressNavigationOwner): ProgressNavigationOwner? = currentOwner?.takeIf { it != owner }

    /** Diagnostics only: a failed owner is retired without being mislabelled as superseded. */
    @Synchronized
    fun isLatestRequest(owner: ProgressNavigationOwner): Boolean =
        activeSessionId == owner.sessionId && lastReservedRequestId == owner.requestId

    @Synchronized
    fun invalidate(sessionId: Long? = null): Boolean {
        if (sessionId != null && activeSessionId != sessionId) return false
        val wasActive = activeSessionId != null
        activeSessionId = null
        currentOwner = null
        finalReserved = false
        return wasActive
    }
}
