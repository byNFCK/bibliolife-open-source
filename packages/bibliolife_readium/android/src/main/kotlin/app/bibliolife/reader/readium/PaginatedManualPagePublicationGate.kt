package app.bibliolife.reader.readium

/** Fences discrete manual-page samples across settle, cancellation, and navigation. */
internal class PaginatedManualPagePublicationGate {
    private var epoch = 0L
    private var sessionGeneration: Long? = null

    var active: Boolean = false
        private set

    val hasSession: Boolean get() = sessionGeneration != null

    fun activityChanged(active: Boolean, navigationGeneration: Long): Boolean {
        if (this.active == active) return false
        this.active = active
        epoch++
        if (active) sessionGeneration = navigationGeneration
        return true
    }

    fun reset(): Boolean {
        val wasActive = active
        if (!wasActive && sessionGeneration == null) return false
        active = false
        sessionGeneration = null
        epoch++
        return wasActive
    }

    fun request(
        liveManual: Boolean,
        navigationGeneration: Long,
        navigationInFlight: Boolean,
    ): Identity? {
        if (navigationInFlight || sessionGeneration != navigationGeneration) return null
        if (liveManual != active) return null
        return Identity(epoch, navigationGeneration, liveManual)
    }

    fun mayPublish(
        identity: Identity,
        navigationGeneration: Long,
        navigationInFlight: Boolean,
    ): Boolean = identity.epoch == epoch &&
        identity.navigationGeneration == navigationGeneration &&
        identity.navigationGeneration == sessionGeneration &&
        identity.liveManual == active && !navigationInFlight

    class Identity internal constructor(
        val epoch: Long,
        val navigationGeneration: Long,
        val liveManual: Boolean,
    )
}
