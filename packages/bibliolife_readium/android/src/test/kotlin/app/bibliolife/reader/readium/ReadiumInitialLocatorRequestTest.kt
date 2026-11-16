package app.bibliolife.reader.readium

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ReadiumInitialLocatorRequestTest {
    @Test
    fun `resolvable partial locator receives publication link metadata`() {
        val request = ReadiumInitialLocatorRequest.parse(
            """{"href":"OEBPS/chapter.xhtml","locations":{"progression":0.4},"text":{"highlight":"target"}}""",
        )

        val locator = ReadiumInitialLocatorRequest.canonicalize(request!!, publication())

        assertNotNull(locator)
        assertEquals("OEBPS/chapter.xhtml", locator!!.href.toString())
        assertEquals(MediaType.HTML, locator.mediaType)
        assertEquals(0.4, locator.locations.progression!!, 0.0)
        assertEquals("target", locator.text.highlight)
    }

    @Test
    fun `already canonical persisted locator keeps its semantic location`() {
        val json = """{"href":"OEBPS/chapter.xhtml","type":"text/html","title":"Chapter","locations":{"progression":0.4,"totalProgression":0.7},"text":{"highlight":"target"}}"""
        val request = ReadiumInitialLocatorRequest.parse(json)!!
        val before = Locator.fromJSON(JSONObject(json))

        val after = ReadiumInitialLocatorRequest.canonicalize(request, publication())

        assertEquals(before, after)
    }

    @Test
    fun `unknown href is rejected without selecting another resource`() {
        val request = ReadiumInitialLocatorRequest.parse(
            """{"href":"missing.xhtml","locations":{"progression":0.4}}""",
        )!!

        assertNull(ReadiumInitialLocatorRequest.canonicalize(request, publication()))
    }

    @Test
    fun `canonicalization preserves progression fragments css selector and text`() {
        val request = ReadiumInitialLocatorRequest.parse(
            """{"href":"OEBPS/chapter.xhtml#href-fragment","locations":{"progression":0.25,"totalProgression":0.6,"fragments":["part-2"],"cssSelector":"#target"},"text":{"before":"before","highlight":"selected","after":"after"}}""",
        )!!

        val locator = ReadiumInitialLocatorRequest.canonicalize(request, publication())!!

        assertEquals(0.25, locator.locations.progression!!, 0.0)
        assertEquals(0.6, locator.locations.totalProgression!!, 0.0)
        assertEquals(listOf("part-2", "href-fragment"), locator.locations.fragments)
        assertEquals("#target", locator.locations["cssSelector"])
        assertEquals("before", locator.text.before)
        assertEquals("selected", locator.text.highlight)
        assertEquals("after", locator.text.after)
    }

    private fun publication(): Publication = Publication(
        Manifest(
            metadata = Metadata(),
            readingOrder = listOf(
                Link(
                    href = Href(Url("OEBPS/chapter.xhtml")!!),
                    mediaType = MediaType.HTML,
                    title = "Chapter",
                ),
            ),
        ),
    )
}
