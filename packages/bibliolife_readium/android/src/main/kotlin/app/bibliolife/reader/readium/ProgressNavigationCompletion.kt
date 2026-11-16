package app.bibliolife.reader.readium

import org.readium.r2.navigator.epub.continuous.ContinuousNavigationResult
import org.readium.r2.navigator.epub.continuous.ContinuousNavigationOutcome
import org.readium.r2.navigator.epub.continuous.ContinuousViewportVerification

internal enum class ProgressNavigationCompletion { COMMITTED, FAILED, SUPERSEDED }

/** A10 is the success boundary; the legacy go() Boolean is not a second veto. */
internal fun progressNavigationCompletion(
    navigation: ContinuousNavigationResult?,
    resultRecorded: Boolean,
    authorityCurrent: Boolean,
): ProgressNavigationCompletion {
    if (!authorityCurrent || (navigation != null && !resultRecorded) ||
        navigation?.outcome == ContinuousNavigationOutcome.SUPERSEDED_AFTER_POSITION ||
        navigation?.finalViewportVerification?.classification == ContinuousViewportVerification.SUPERSEDED
    ) return ProgressNavigationCompletion.SUPERSEDED
    val evidence = navigation?.finalViewportVerification
    return if (resultRecorded && navigation?.outcome != ContinuousNavigationOutcome.FAILED_BEFORE_POSITION &&
        evidence?.classification == ContinuousViewportVerification.VERIFIED_TARGET_VIEWPORT &&
        evidence.sameResource && evidence.targetRangeAtReadingAnchor == true && evidence.authorityStillCurrent
    ) ProgressNavigationCompletion.COMMITTED else ProgressNavigationCompletion.FAILED
}
