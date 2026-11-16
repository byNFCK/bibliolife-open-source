package org.readium.r2.navigator.epub.continuous

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.navigator.javascriptResultObject

@RunWith(RobolectricTestRunner::class)
class ContinuousResourceLocatorNormalizerTest {
    private fun link(href: String) = Link(Url(href)!!, MediaType.XHTML)

    private fun domLocator(
        href: String = "#",
        cssSelector: String? = ".x-ebookmaker",
        highlight: String? = "resource-local text",
        progression: Double? = 0.4,
    ) = Locator(
        href = Url(href)!!,
        mediaType = MediaType.XHTML,
        locations = Locator.Locations(
            progression = progression,
            otherLocations = cssSelector?.let { mapOf("cssSelector" to it) } ?: emptyMap(),
        ),
        text = Locator.Text(highlight = highlight),
    )

    @Test fun `resource 7 G1 binds fragment DOM locator to its generation-owned reading-order href`() {
        val normalized = requireNotNull(
            ContinuousResourceLocatorNormalizer.normalize(
                resourceLocator = domLocator(),
                readingOrderLink = link("OEBPS/chapter-7.xhtml"),
            ),
        )

        assertEquals("OEBPS/chapter-7.xhtml", normalized.href.toString())
        assertEquals(".x-ebookmaker", normalized.locations["cssSelector"])
        assertEquals("resource-local text", normalized.text.highlight)
        assertEquals(0.4, normalized.locations.progression)
    }

    @Test fun `deep resource 700 binds directly without a reading-order prefix`() {
        val normalized = requireNotNull(
            ContinuousResourceLocatorNormalizer.normalize(
                resourceLocator = domLocator(href = "https://readium_assets/served.xhtml"),
                readingOrderLink = link("OEBPS/chapter-700.xhtml"),
            ),
        )

        assertEquals("OEBPS/chapter-700.xhtml", normalized.href.toString())
    }

    @Test fun `does not invent a locator when the callback has no DOM location`() {
        assertNull(
            ContinuousResourceLocatorNormalizer.normalize(
                resourceLocator = domLocator(cssSelector = null, highlight = null, progression = null),
                readingOrderLink = link("OEBPS/chapter-7.xhtml"),
            ),
        )
    }

    @Test fun `selector and text without semantic progression are rejected`() {
        assertNull(
            ContinuousResourceLocatorNormalizer.normalize(
                resourceLocator = domLocator(progression = null),
                readingOrderLink = link("OEBPS/chapter-7.xhtml"),
            ),
        )
    }

    @Test fun `generation href normalization and JSON round trip retain semantic location`() {
        val normalized = requireNotNull(
            ContinuousResourceLocatorNormalizer.normalize(
                resourceLocator = domLocator(progression = 0.625),
                readingOrderLink = link("OEBPS/chapter-7.xhtml"),
            ),
        )
        val roundTripped = requireNotNull(Locator.fromJSON(normalized.toJSON()))

        assertEquals("OEBPS/chapter-7.xhtml", roundTripped.href.toString())
        assertEquals(0.625, roundTripped.locations.progression)
        assertEquals(".x-ebookmaker", roundTripped.locations["cssSelector"])
        assertEquals("resource-local text", roundTripped.text.highlight)
    }

    @Test fun `enriched WebView callback survives parser normalization and JSON round trip`() {
        val callback = javascriptResultObject(
            """{"href":"#","type":"application/xhtml+xml","locations":{"cssSelector":"p:nth-child(4)","progression":0.375},"text":{"highlight":"semantic text"}}""",
        )
        val parsed = requireNotNull(Locator.fromJSON(callback))
        val normalized = requireNotNull(
            ContinuousResourceLocatorNormalizer.normalize(
                resourceLocator = parsed,
                readingOrderLink = link("OEBPS/chapter-7.xhtml"),
            ),
        )
        val roundTripped = requireNotNull(Locator.fromJSON(normalized.toJSON()))

        assertEquals("OEBPS/chapter-7.xhtml", roundTripped.href.toString())
        assertEquals(0.375, roundTripped.locations.progression)
        assertEquals("p:nth-child(4)", roundTripped.locations["cssSelector"])
        assertEquals("semantic text", roundTripped.text.highlight)
    }
}
