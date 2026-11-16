package app.bibliolife.reader.readium

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ContinuousPublicationPositionMapTest {
    private fun entry(href: String, position: Int, progression: Double) = ContinuousPublicationPositionIndex.Entry(
        value = href,
        href = href,
        position = position,
        progression = progression,
        totalProgression = null,
    )

    private val map = ContinuousPublicationPositionIndex(
        listOf(
            List(2) { index -> entry("a.xhtml", index + 1, index.toDouble()) },
            List(10) { index -> entry("b.xhtml", index + 3, index / 9.0) },
            List(3) { index -> entry("c.xhtml", index + 13, index / 2.0) },
        ),
    )

    @Test fun `unequal reading-order position counts drive whole book progression`() {
        val actual = map.progressionFor(
            readingOrderIndex = null,
            href = "b.xhtml",
            position = 7,
            progression = 4.0 / 9.0,
            totalProgression = null,
        )
        assertEquals(6.0 / 14.0, requireNotNull(actual), 0.0001)
        assertNotEquals(4.0 / 9.0 / 3.0 + 1.0 / 3.0, actual)
    }

    @Test fun `progression target is selected from canonical publication positions`() {
        assertEquals("a.xhtml", map.targetFor(0.0))
        assertEquals("b.xhtml", map.targetFor(0.5))
        assertEquals("c.xhtml", map.targetFor(1.0))
        assertEquals("a.xhtml", map.targetFor(-1.0))
        assertEquals("c.xhtml", map.targetFor(2.0))
    }

    @Test fun `point-local semantic progression resolves to the canonical Readium position`() {
        val pointIndex = ContinuousPublicationPositionIndex(
            listOf(
                List(2) { index -> entry("a.xhtml", index + 1, index.toDouble()).copy(totalProgression = index / 14.0) },
                List(10) { index -> entry("b.xhtml", index + 3, index / 9.0).copy(totalProgression = (index + 2) / 14.0) },
                List(3) { index -> entry("c.xhtml", index + 13, index / 2.0).copy(totalProgression = (index + 12) / 14.0) },
            ),
        )

        val resolved = requireNotNull(
            pointIndex.positionFor(
                readingOrderIndex = null,
                href = "b.xhtml",
                progression = 4.0 / 9.0,
            ),
        )

        assertEquals(7, resolved.position)
        assertEquals(6.0 / 14.0, resolved.totalProgression!!, 0.0001)
    }

    @Test fun `generation-bound resource index canonicalizes a served DOM locator without href matching`() {
        val deepIndex = 700
        val positions = List(deepIndex + 1) { index ->
            listOf(
                ContinuousPublicationPositionIndex.Entry(
                    value = index,
                    href = "OEBPS/chapter-$index.xhtml",
                    position = index + 1,
                    progression = 0.0,
                    totalProgression = index.toDouble() / deepIndex,
                ),
            )
        }
        val index = ContinuousPublicationPositionIndex(positions)

        val canonical = requireNotNull(
            index.positionFor(
                readingOrderIndex = deepIndex,
                href = "https://readium_assets/publication/served-dom-resource.xhtml",
                progression = 0.0,
            ),
        )

        assertEquals(deepIndex + 1, canonical.position)
        assertEquals(1.0, canonical.totalProgression!!, 0.0)
    }

    @Test fun `serialized enriched DOM locator reaches canonical session position and Flutter event`() {
        val positionsByReadingOrder = listOf(
            listOf(canonicalLocator("a.xhtml", 1, 0.0, 0.0)),
            listOf(
                canonicalLocator("b.xhtml", 2, 0.0, 0.25),
                canonicalLocator("b.xhtml", 3, 0.5, 0.5),
                canonicalLocator("b.xhtml", 4, 1.0, 0.75),
            ),
            listOf(canonicalLocator("c.xhtml", 5, 0.0, 1.0)),
        )
        val cache = CachedReadiumPositions(
            positions = positionsByReadingOrder.flatten(),
            positionsByReadingOrder = positionsByReadingOrder,
            navigationTargets = emptyList(),
        )
        val serializedEnrichedLocator = """{"href":"b.xhtml","type":"application/xhtml+xml","locations":{"cssSelector":"p:nth-child(8)","progression":0.5},"text":{"highlight":"semantic text"}}"""
        val parsed = requireNotNull(Locator.fromJSON(JSONObject(serializedEnrichedLocator)))

        val state = requireNotNull(
            cache.continuousPositionState(
                locator = parsed,
                readingOrderIndex = 1,
                presentation = ReadiumPresentationState.Scrolling,
            ),
        )
        val event = requireNotNull(
            ReadiumPlatformViewBridgeSerializer.stateEvent(
                protocolVersion = 1,
                instanceId = "reader",
                sequence = 1,
                state = ReadiumPlatformViewReaderState.PositionChanged(state),
            ),
        )
        val payload = event["payload"] as Map<*, *>
        val emittedLocator = requireNotNull(
            Locator.fromJSON(JSONObject(payload["locatorJson"] as String)),
        )

        assertEquals(0.5, state.locator.locations.progression)
        assertEquals(3, state.locator.locations.position)
        assertEquals(0.5, state.locator.locations.totalProgression)
        assertEquals(0.5, state.progression)
        assertEquals(5, state.totalLogicalPositions)
        assertEquals("positionChanged", event["type"])
        assertEquals(0.5, payload["progression"])
        assertEquals(0.5, payload["resourceProgression"])
        assertEquals(3, payload["position"])
        assertEquals(0.5, emittedLocator.locations.progression)
        assertEquals("p:nth-child(8)", emittedLocator.locations["cssSelector"])
        assertEquals("semantic text", emittedLocator.text.highlight)
    }

    @Test fun `missing semantic progression or canonical positions stays unavailable`() {
        val empty = CachedReadiumPositions(emptyList(), emptyList(), emptyList())
        val withoutProgression = Locator(Url("chapter.xhtml")!!, MediaType.XHTML)
        val withProgression = withoutProgression.copyWithLocations(progression = 0.5)

        assertNull(
            empty.continuousPositionState(
                withProgression,
                readingOrderIndex = 0,
                presentation = ReadiumPresentationState.Unknown,
            ),
        )
        val onePosition = CachedReadiumPositions(
            positions = listOf(canonicalLocator("chapter.xhtml", 1, 0.0, 0.0)),
            positionsByReadingOrder = listOf(listOf(canonicalLocator("chapter.xhtml", 1, 0.0, 0.0))),
            navigationTargets = emptyList(),
        )
        assertNull(
            onePosition.continuousPositionState(
                withoutProgression,
                readingOrderIndex = 0,
                presentation = ReadiumPresentationState.Unknown,
            ),
        )
    }

    private fun canonicalLocator(
        href: String,
        position: Int,
        progression: Double,
        totalProgression: Double,
    ) = Locator(
        href = Url(href)!!,
        mediaType = MediaType.XHTML,
        locations = Locator.Locations(
            progression = progression,
            position = position,
            totalProgression = totalProgression,
        ),
    )
}
