package app.bibliolife.reader.readium

import org.readium.r2.shared.publication.Locator

/**
 * Search data crossing the gateway/controller boundary. Only the gateway has
 * to construct Readium [Locator] instances; the controller is JVM-testable.
 */
internal data class EpubSearchHit(
    val href: String,
    val title: String?,
    val before: String?,
    val highlight: String?,
    val after: String?,
    val position: Int?,
    val progression: Double?,
    val locator: Locator? = null,
) {
    companion object {
        fun from(locator: Locator) = EpubSearchHit(
            href = locator.href.toString(),
            title = locator.title,
            before = locator.text.before,
            highlight = locator.text.highlight,
            after = locator.text.after,
            position = locator.locations.position,
            progression = locator.locations.totalProgression,
            locator = locator,
        )
    }
}

data class EpubSearchResult(
    /** Stable only for the currently active query generation. */
    val id: String,
    val href: String,
    val title: String?,
    val before: String?,
    val highlight: String?,
    val after: String?,
    val position: Int?,
    val progression: Double?,
)

/** Kept inside the session; UI receives [EpubSearchResult] but never this target. */
internal data class EpubSearchNavigationTarget(
    val hit: EpubSearchHit,
    val result: EpubSearchResult,
    val locator: Locator?,
)

sealed interface EpubSearchState {
    data object Idle : EpubSearchState
    data class Loading(val query: String, val token: Long) : EpubSearchState
    data class Results(val query: String, val token: Long, val results: List<EpubSearchResult>, val loadingMore: Boolean, val hasMore: Boolean) : EpubSearchState
    data class Empty(val query: String, val token: Long) : EpubSearchState
    data class Error(val query: String, val token: Long, val error: EpubSearchError) : EpubSearchState
}

enum class EpubSearchError {
    Generic,
    Unsupported,
    Cancelled,
    PublicationUnavailable,
    Disposed,
}

internal object EpubSearchResultMapper {
    fun map(hit: EpubSearchHit, id: String): EpubSearchNavigationTarget {
        val result = EpubSearchResult(
            id = id,
            href = hit.href,
            title = hit.title?.trim()?.takeIf(String::isNotEmpty),
            before = hit.before,
            highlight = hit.highlight,
            after = hit.after,
            position = hit.position?.takeIf { it >= 1 },
            progression = hit.progression?.takeIf { it in 0.0..1.0 },
        )
        return EpubSearchNavigationTarget(hit, result, hit.locator)
    }

    fun identity(hit: EpubSearchHit): String {
        return listOf(
            hit.href,
            hit.locator?.locations?.fragments?.joinToString("/").orEmpty(),
            hit.locator?.locations?.progression?.let(::normalized),
            hit.position,
            hit.progression?.let(::normalized),
            hit.highlight.orEmpty(), hit.before.orEmpty(), hit.after.orEmpty(),
        ).joinToString("|")
    }

    private fun normalized(value: Double): String = "%.6f".format(java.util.Locale.ROOT, value)
}

internal sealed interface EpubSearchNavigationOutcome {
    data object Completed : EpubSearchNavigationOutcome
    data object NavigatorNotReady : EpubSearchNavigationOutcome
    data object UnknownResultId : EpubSearchNavigationOutcome
    data object ObsoleteResultId : EpubSearchNavigationOutcome
    data object Failed : EpubSearchNavigationOutcome
}

/** Small, production-used boundary that keeps ID resolution separate from ordinary navigation. */
internal class EpubSearchNavigationCoordinator(
    private val resolve: (String) -> EpubSearchController.TargetResolution,
    private val navigate: (EpubSearchNavigationTarget, Boolean) -> EpubSearchNavigationOutcome,
) {
    fun goTo(resultId: String, animated: Boolean): EpubSearchNavigationOutcome = when (val target = resolve(resultId)) {
        is EpubSearchController.TargetResolution.Current -> navigate(target.target, animated)
        EpubSearchController.TargetResolution.Obsolete -> EpubSearchNavigationOutcome.ObsoleteResultId
        EpubSearchController.TargetResolution.Unknown -> EpubSearchNavigationOutcome.UnknownResultId
    }
}
