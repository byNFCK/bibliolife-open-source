package app.bibliolife.reader.readium

/** Position sources which can publish again after a completed manual scroll. */
internal enum class ContinuousPositionSource(val automatic: Boolean) {
    MANUAL_LIVE(automatic = false),
    HOST_VIEWPORT(automatic = true),
    RESOURCE_READY(automatic = true),
    INITIAL_VIEWPORT_READY(automatic = true),
    POSITIONS_READY(automatic = true),
    VERIFIED_NAVIGATION(automatic = false),
    INITIAL_RESTORE(automatic = false),
    PREFERENCES_APPLIED(automatic = false),
    REFLOW_COMMITTED(automatic = false),
}

/** Identity of one Continuous publication context. Rendition ownership is referential. */
internal class ContinuousPositionContext(
    val rendition: Any,
    val scrollEpoch: Long,
    val navigationGeneration: Long,
    val preferenceGeneration: Long,
) {
    fun matches(other: ContinuousPositionContext): Boolean =
        rendition === other.rendition &&
            scrollEpoch == other.scrollEpoch &&
            navigationGeneration == other.navigationGeneration &&
            preferenceGeneration == other.preferenceGeneration

    override fun equals(other: Any?): Boolean = other is ContinuousPositionContext && matches(other)

    override fun hashCode(): Int {
        var result = System.identityHashCode(rendition)
        result = 31 * result + scrollEpoch.hashCode()
        result = 31 * result + navigationGeneration.hashCode()
        result = 31 * result + preferenceGeneration.hashCode()
        return result
    }
}

/** Prevents automatic position callbacks from following an accepted manual final. */
internal class ContinuousPositionPublicationGate {
    private var completedManualContext: ContinuousPositionContext? = null

    fun mayPublish(
        captured: ContinuousPositionContext,
        current: ContinuousPositionContext,
        source: ContinuousPositionSource,
        finalPending: Boolean,
    ): Boolean {
        if (!captured.matches(current)) return false
        if (completedManualContext?.matches(current) == false) completedManualContext = null
        if (!source.automatic) return true
        return finalPending || completedManualContext?.matches(current) != true
    }

    fun manualFinalPublished(context: ContinuousPositionContext, hasCanonicalProgression: Boolean): Boolean {
        if (!hasCanonicalProgression) return false
        completedManualContext = context
        return true
    }
}
