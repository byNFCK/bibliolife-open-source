package app.bibliolife.reader.readium

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.readium.r2.navigator.epub.continuous.EpubContinuousResourceReadyEvent

class ContinuousResourceReadySessionRelayTest {
    @Test fun `live true-ready resource reaches the session anchor query exactly once`() {
        val relay = ContinuousResourceReadySessionRelay()
        val rendition = Any()
        var received: EpubContinuousResourceReadyEvent? = null
        var preferenceReadyCount = 0
        val ready = EpubContinuousResourceReadyEvent(readingOrderIndex = 7, resourceGeneration = 2)

        assertTrue(relay.forward(rendition, rendition, ready, { preferenceReadyCount++ }) { received = it })
        assertTrue(received === ready)
        assertTrue(preferenceReadyCount == 1)
    }

    @Test fun `only the first true-ready resource marks one rendition preference-ready`() {
        val relay = ContinuousResourceReadySessionRelay()
        val rendition = Any()
        var preferenceReadyCount = 0
        var locatorQueryCount = 0

        assertTrue(relay.forward(rendition, rendition, EpubContinuousResourceReadyEvent(0, 1), { preferenceReadyCount++ }) { locatorQueryCount++ })
        assertTrue(relay.forward(rendition, rendition, EpubContinuousResourceReadyEvent(1, 4), { preferenceReadyCount++ }) { locatorQueryCount++ })

        assertTrue(preferenceReadyCount == 1)
        assertTrue(locatorQueryCount == 2)
    }

    @Test fun `true-ready resource activates the bounded preference coordinator`() {
        val relay = ContinuousResourceReadySessionRelay()
        val rendition = Any()
        val preferences = ReadiumPreferenceCoordinator<String>()

        assertEquals(ReadiumPreferenceCoordinator.Action.NotReady, preferences.request("dark"))
        assertTrue(
            relay.forward(
                rendition,
                rendition,
                EpubContinuousResourceReadyEvent(0, 1),
                {
                    preferences.onNavigatorReady()
                    preferences.seedInitialApplied("sepia")
                },
            ) {},
        )
        assertEquals("sepia", preferences.snapshot().applied)
        assertTrue(preferences.request("dark") is ReadiumPreferenceCoordinator.Action.Start)
    }

    @Test fun `a replacement rendition owns a fresh preference readiness transition`() {
        val relay = ContinuousResourceReadySessionRelay()
        val first = Any()
        val second = Any()
        var preferenceReadyCount = 0

        assertTrue(relay.forward(first, first, EpubContinuousResourceReadyEvent(0, 1), { preferenceReadyCount++ }) {})
        assertTrue(relay.forward(second, second, EpubContinuousResourceReadyEvent(0, 1), { preferenceReadyCount++ }) {})

        assertTrue(preferenceReadyCount == 2)
    }

    @Test fun `superseded rendition cannot invoke the session anchor query`() {
        val relay = ContinuousResourceReadySessionRelay()
        var queried = false
        var preferencesReady = false

        assertFalse(
            relay.forward(
                Any(),
                Any(),
                EpubContinuousResourceReadyEvent(7, 1),
                { preferencesReady = true },
            ) { queried = true },
        )
        assertFalse(queried)
        assertFalse(preferencesReady)
    }
}
