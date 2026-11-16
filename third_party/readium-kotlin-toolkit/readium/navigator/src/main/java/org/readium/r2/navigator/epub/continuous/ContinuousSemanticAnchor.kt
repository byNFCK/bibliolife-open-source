package org.readium.r2.navigator.epub.continuous

import org.readium.r2.shared.publication.Locator

internal enum class ContinuousSemanticAnchorQuality {
    EXACT_DOM_POINT, PROGRESSION_FALLBACK, UNRESOLVED
}

/** Resource identity plus the JS-proven retained Text node and UTF-16 offset. */
internal fun continuousSemanticAnchorQuality(
    locator: Locator,
    point: ContinuousResolvedLocatorPoint?,
    sameResource: Boolean,
): ContinuousSemanticAnchorQuality {
    if (point == null || !sameResource) return ContinuousSemanticAnchorQuality.UNRESOLVED
    val identity = locator.locations["continuousDomAnchor"] as? Map<*, *>
    val id = identity?.get("id") as? String
    val offset = (identity?.get("charOffset") as? Number)?.toInt()
    return if (id != null && offset != null && point.semanticAnchorExact &&
        point.anchorIdentityId == id && point.anchorCharacterOffset == offset
    ) ContinuousSemanticAnchorQuality.EXACT_DOM_POINT
    else ContinuousSemanticAnchorQuality.PROGRESSION_FALLBACK
}
