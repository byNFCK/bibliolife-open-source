package org.readium.r2.navigator.epub.continuous

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ContinuousSemanticAnchorTest {
    private fun locator(progression: Double = 0.5) = org.readium.r2.shared.publication.Locator.fromJSON(
        JSONObject("""{"href":"chapter6.xhtml","type":"application/xhtml+xml","locations":{
          "progression":$progression,"continuousDomAnchor":{"id":"7","charOffset":12}}}""")
    )!!

    private val exact = ContinuousResolvedLocatorPoint(900.0, 556.0, true, "7", 12)

    @Test fun exactIdentityDoesNotDependOnProgression() {
        for (progression in listOf(0.0, 0.4, 0.9, 1.0)) {
            assertEquals(ContinuousSemanticAnchorQuality.EXACT_DOM_POINT,
                continuousSemanticAnchorQuality(locator(progression), exact, true))
        }
    }

    @Test fun sameProgressionDifferentNodeIsNotExact() {
        assertEquals(ContinuousSemanticAnchorQuality.PROGRESSION_FALLBACK,
            continuousSemanticAnchorQuality(locator(), exact.copy(anchorIdentityId = "8"), true))
    }

    @Test fun differentCharacterOffsetIsNotExact() {
        assertEquals(ContinuousSemanticAnchorQuality.PROGRESSION_FALLBACK,
            continuousSemanticAnchorQuality(locator(), exact.copy(anchorCharacterOffset = 13), true))
    }

    @Test fun fallbackNeverCountsAsExact() {
        assertEquals(ContinuousSemanticAnchorQuality.PROGRESSION_FALLBACK,
            continuousSemanticAnchorQuality(locator(), exact.copy(semanticAnchorExact = false), true))
    }

    @Test fun neighborResourceCannotSatisfyAnchor() {
        assertEquals(ContinuousSemanticAnchorQuality.UNRESOLVED,
            continuousSemanticAnchorQuality(locator(), exact, false))
    }

    @Test fun missingResultIsUnresolved() {
        assertEquals(ContinuousSemanticAnchorQuality.UNRESOLVED,
            continuousSemanticAnchorQuality(locator(), null, true))
    }
}
