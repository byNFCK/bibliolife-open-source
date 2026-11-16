package org.readium.r2.navigator

import org.json.JSONArray
import org.json.JSONObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class R2BasicWebViewJavascriptResultTest {
    @Test fun `accepts object callback result`() {
        val result = javascriptObjectJson("{\"href\":\"chapter.xhtml\",\"locations\":{\"progression\":0.5}}")

        assertEquals("{\"href\":\"chapter.xhtml\",\"locations\":{\"progression\":0.5}}", result)
    }

    @Test fun `accepts JSON string callback result`() {
        val result = javascriptObjectJson("\"{\\\"href\\\":\\\"chapter.xhtml\\\",\\\"locations\\\":{\\\"progression\\\":0.5}}\"")

        assertEquals("{\"href\":\"chapter.xhtml\",\"locations\":{\"progression\":0.5}}", result)
    }

    @Test fun `does not fabricate object for null or malformed callback result`() {
        assertNull(javascriptObjectJson("null"))
        assertNull(javascriptObjectJson("not-json"))
    }

    @Test fun `resource-local continuous command supplements only missing DOM progression`() {
        val point = requireNotNull(continuousDomPoint(539.5, 2332.5, 2.625))
        val javascript = continuousLocatorJavascript(point.x, point.y)

        assertEquals(205.52380952380952, point.x)
        assertEquals(888.5714285714286, point.y)
        assertEquals(true, javascript.contains("readium.findLocatorAtPointDiagnostic(${point.x}, ${point.y})"))
        assertEquals(true, javascript.contains("readium.findLocatorAtPoint(${point.x}, ${point.y})"))
        assertEquals(true, javascript.contains("Number.isFinite(existing)"))
        assertEquals(true, javascript.contains("document.elementFromPoint(${point.x}, ${point.y})"))
        assertEquals(true, javascript.contains("document.createTreeWalker(root, NodeFilter.SHOW_TEXT)"))
        assertEquals(true, javascript.contains("nearestDistance"))
        assertEquals(true, javascript.contains("dx * dx + dy * dy"))
        assertEquals(true, javascript.contains("range.setStart(nearestNode, 0)"))
        assertEquals(true, javascript.contains("prefix.toString().length / total"))
        assertEquals(true, javascript.contains("Math.max(0, Math.min(1"))
        assertEquals(true, javascript.contains("Object.assign({}, locator.locations, { progression: progression })"))
        assertEquals(false, javascript.contains("RecyclerView"))
        assertEquals(false, javascript.contains("scrollHeight"))
    }

    @Test fun `diagnostic serializer keeps only bounded schema evidence`() {
        val oversizedText = "t".repeat(160) + "\nsecret-not-permitted"
        val diagnostic =
            JSONObject()
                .put("schema", 1)
                .put(
                    "caret",
                    JSONObject()
                        .put("text", oversizedText)
                        .put("offset", 12)
                        .put("parentSelector", "#pg-machine-header > div"),
                )
                .put(
                    "quote",
                    JSONObject()
                        .put("before", "Title")
                        .put("highlight", "The Time Machine")
                        .put("after", "Author"),
                )
                .put(
                    "ancestors",
                    JSONArray()
                        .put(
                            JSONObject()
                                .put("tag", "div")
                                .put("id", "pg-machine-header")
                                .put("selector", "#pg-machine-header"),
                        ),
                )
                .put("normalizedResourceQuoteOccurrences", 1)
                .put("unexpectedDocumentDump", "secret-not-permitted")

        val payload = requireNotNull(continuousLocatorDiagnosticLogPayload(diagnostic))
        val serialized = JSONObject(payload)

        assertEquals(120, serialized.getJSONObject("caret").getString("text").length)
        assertEquals("The Time Machine", serialized.getJSONObject("quote").getString("highlight"))
        assertEquals(1, serialized.getInt("normalizedResourceQuoteOccurrences"))
        assertEquals(1, serialized.getJSONArray("ancestors").length())
        assertFalse(payload.contains("secret-not-permitted"))
        assertFalse(payload.contains("unexpectedDocumentDump"))
    }

    @Test fun `diagnostic serializer rejects a non-diagnostic locator payload`() {
        assertNull(continuousLocatorDiagnosticLogPayload(JSONObject().put("schema", 2)))
        assertNull(continuousLocatorDiagnosticLogPayload(JSONObject().put("schema", 1)))
    }

    @Test fun `invalid native point conversion is rejected instead of querying a fake location`() {
        assertNull(continuousDomPoint(Double.NaN, 10.0, 3.0))
        assertNull(continuousDomPoint(10.0, -1.0, 3.0))
        assertNull(continuousDomPoint(10.0, 10.0, 0.0))
    }

}
