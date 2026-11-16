package app.bibliolife.reader.readium

import kotlin.math.roundToInt
import org.readium.r2.shared.publication.Locator

/** One canonical, Readium-backed target for a valid logical position. */
internal data class ProgressNavigationTarget(
    val index: Int,
    val totalCount: Int,
    val locator: Locator?,
    val href: String?,
    val logicalPosition: Int,
    val resourceProgression: Double?,
    val totalProgression: Double?,
)

internal data class ProgressLocationSnapshot(
    val href: String?,
    val logicalPosition: Int?,
    val resourceProgression: Double?,
    val totalProgression: Double?,
)

internal data class ProgressPositionCandidate(
    val locator: Locator?,
    val href: String?,
    val logicalPosition: Int?,
    val resourceProgression: Double?,
    val totalProgression: Double?,
)

internal enum class ProgressNavigationConfirmation { Exact, NearestAvailable }

/** Pure mapping logic for discrete, canonical publication positions. */
internal object ProgressNavigationModel {
    const val PROGRESSION_EPSILON = 0.0001
    /**
     * Groups duplicate synthetic positions while retaining publication order. Within a group,
     * the locator with the smallest resource progression wins; equal/missing values retain the
     * first publication-order locator, which represents the earliest known location.
     */
    fun targets(positions: List<Locator>): List<ProgressNavigationTarget> = canonicalTargets(
        positions.map { locator ->
            ProgressPositionCandidate(
                locator = locator,
                href = locator.href.toString(),
                logicalPosition = locator.locations.position,
                resourceProgression = locator.locations.progression,
                totalProgression = locator.locations.totalProgression,
            )
        },
    )

    internal fun canonicalTargets(candidates: List<ProgressPositionCandidate>): List<ProgressNavigationTarget> {
        val grouped = linkedMapOf<Int, MutableList<ProgressPositionCandidate>>()
        candidates.forEach { candidate ->
            val position = candidate.logicalPosition ?: return@forEach
            if (position >= 1) grouped.getOrPut(position) { mutableListOf() }.add(candidate)
        }
        val total = grouped.size
        return grouped.values.mapIndexed { index, candidates ->
            val canonical = candidates.minByOrNull {
                it.resourceProgression ?: Double.POSITIVE_INFINITY
            }!!
            ProgressNavigationTarget(
                index = index,
                totalCount = total,
                locator = canonical.locator,
                href = canonical.href,
                logicalPosition = canonical.logicalPosition!!,
                resourceProgression = canonical.resourceProgression,
                totalProgression = canonical.totalProgression,
            )
        }
    }

    fun sliderValueToIndex(value: Float, itemCount: Int): Int =
        if (itemCount <= 1) 0 else value.roundToInt().coerceIn(0, itemCount - 1)

    fun targetAtSliderValue(targets: List<ProgressNavigationTarget>, value: Float): ProgressNavigationTarget? =
        targets.getOrNull(sliderValueToIndex(value, targets.size))

    /** Human-readable position always comes from the selected Readium target, never its index. */
    fun displayPosition(target: ProgressNavigationTarget): Int = target.logicalPosition

    fun snapshot(locator: Locator?): ProgressLocationSnapshot? = locator?.let {
        ProgressLocationSnapshot(
            href = it.href.toString(),
            logicalPosition = it.locations.position,
            resourceProgression = it.locations.progression,
            totalProgression = it.locations.totalProgression,
        )
    }

    fun currentIndex(targets: List<ProgressNavigationTarget>, location: ProgressLocationSnapshot?): Int {
        if (targets.isEmpty() || location == null) return 0
        location.logicalPosition?.let { position ->
            targets.indexOfFirst { it.logicalPosition == position }.takeIf { it >= 0 }?.let { return it }
        }
        targets.indexOfFirst {
            it.href == location.href && it.resourceProgression == location.resourceProgression
        }.takeIf { it >= 0 }?.let { return it }
        location.totalProgression?.let { progression ->
            return targets.indices.minByOrNull {
                kotlin.math.abs((targets[it].totalProgression ?: progression) - progression)
            } ?: 0
        }
        return targets.indexOfFirst { it.href == location.href }.takeIf { it >= 0 } ?: 0
    }

    fun confirmation(target: ProgressNavigationTarget, confirmed: ProgressLocationSnapshot): ProgressNavigationConfirmation =
        if (confirmed.logicalPosition == target.logicalPosition) {
            ProgressNavigationConfirmation.Exact
        } else {
            ProgressNavigationConfirmation.NearestAvailable
        }

    fun materiallySame(
        first: ProgressLocationSnapshot,
        second: ProgressLocationSnapshot,
        epsilon: Double = PROGRESSION_EPSILON,
    ): Boolean =
        first.logicalPosition == second.logicalPosition &&
            first.href == second.href &&
            approximatelyEqual(first.resourceProgression, second.resourceProgression, epsilon) &&
            approximatelyEqual(first.totalProgression, second.totalProgression, epsilon)

    fun isPreNavigationReplay(
        preNavigation: ProgressLocationSnapshot?,
        emission: ProgressLocationSnapshot,
    ): Boolean = preNavigation != null && materiallySame(preNavigation, emission)

    private fun approximatelyEqual(first: Double?, second: Double?, epsilon: Double): Boolean =
        when {
            first == null || second == null -> first == second
            else -> kotlin.math.abs(first - second) <= epsilon
        }
}
