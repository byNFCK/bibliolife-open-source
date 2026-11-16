package org.readium.r2.navigator

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.readium.r2.shared.publication.Locator

@RunWith(RobolectricTestRunner::class)
class R2BasicWebViewJavascriptExecutorTest {
    @Test fun `temporary DOM anchor capture and exact geometry cross the real native parser`() = runBlocking {
        val commands = mutableListOf<String>()
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication()) { _, script, callback ->
            commands += script
            callback(if (script.contains("captureContinuousReadingAnchor"))
                """{"href":"#","type":"application/xhtml+xml","locations":{"progression":0.4,"domRange":{"start":{"cssSelector":"p","textNodeIndex":0,"charOffset":12}},"continuousDomAnchor":{"id":"7","charOffset":12}}}"""
            else """{"documentY":900,"viewportTop":556,"semanticAnchorExact":true,"anchorIdentityId":"7","anchorCharacterOffset":12}""")
        }
        val locator = requireNotNull(webView.captureContinuousReadingAnchor(50.0, 120.0))
        val point = requireNotNull(webView.continuousLocatorPointGeometry(locator))
        assertEquals(true, point.semanticAnchorExact)
        assertEquals("7", point.anchorIdentityId)
        assertEquals(12, point.anchorCharacterOffset)
        assertEquals(900.0, point.documentYCssPx)
        assertEquals(2, commands.size)
        assertTrue(commands.first().startsWith("readium.captureContinuousReadingAnchor("))
        assertTrue(commands.last().contains("continuousDomAnchor"))
    }

    private val rawLocator =
        """{"href":"#","type":"application/xhtml+xml","locations":{"cssSelector":"p:nth-child(4)","progression":0.375},"text":{"highlight":"semantic text"}}"""

    @Test fun `runtime executor delegates to the actual WebView boundary`() {
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication())

        webView.runJavaScript("window.biblioLifeExecutorProbe = true;")

        assertEquals(
            "window.biblioLifeExecutorProbe = true;",
            shadowOf(webView).lastEvaluatedJavascript,
        )
    }

    @Test fun `resource-local executor receives production locator command and raw object callback is parsed`() = runBlocking {
        val commands = mutableListOf<String>()
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication()) { _, script, callback ->
            commands += script
            callback(rawLocator)
        }

        val locator = requireNotNull(webView.findLocatorAtPoint(50.0, 120.0))

        assertEquals("#", locator.href.toString())
        assertEquals(0.375, locator.locations.progression)
        assertEquals("p:nth-child(4)", locator.locations["cssSelector"])
        assertEquals("semantic text", locator.text.highlight)
        assertEquals(1, commands.size)
        assertTrue(commands.single().contains("readium.findLocatorAtPoint(50.0, 120.0)"))
        assertTrue(commands.single().contains("Number.isFinite(existing)"))
    }

    @Test fun `JSON-string callback is parsed by the same production locator path`() = runBlocking {
        val jsonStringCallback = "\"" + rawLocator.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication()) { _, _, callback -> callback(jsonStringCallback) }

        val locator = requireNotNull(webView.findLocatorAtPoint(0.0, 0.0))

        assertEquals("#", locator.href.toString())
        assertEquals(0.375, locator.locations.progression)
    }

    @Test fun `malformed raw callback stays bounded and creates no Locator`() = runBlocking {
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication()) { _, _, callback -> callback("not-a-locator") }

        assertNull(webView.findLocatorAtPoint(0.0, 0.0))
    }

    @Test fun `numeric offset callback keeps the production numeric parse`() = runBlocking {
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication()) { _, _, callback -> callback("30305.5") }

        assertEquals(30305.5, webView.locatorVerticalOffset(Locator.fromJSON(org.json.JSONObject(rawLocator))!!))
    }

    @Test fun `progression-only position uses the real offset JavaScript callback`() = runBlocking {
        val commands = mutableListOf<String>()
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication()) { _, script, callback ->
            commands += script
            callback("1777.5")
        }
        val position = Locator.fromJSON(
            org.json.JSONObject("""{"href":"#","type":"application/xhtml+xml","locations":{"progression":0.6}}"""),
        )!!

        assertEquals(1777.5, webView.locatorVerticalOffset(position))
        assertEquals(1, commands.size)
        assertTrue(commands.single().contains("readium.locatorVerticalOffset("))
        assertTrue(commands.single().contains("\"progression\":0.6"))
        assertTrue(!commands.single().contains("scrollHeight"))
    }

    @Test fun `raw null offset callback is classified without fallback`() = runBlocking {
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication()) { _, _, callback -> callback("null") }

        assertNull(webView.locatorVerticalOffset(Locator.fromJSON(org.json.JSONObject(rawLocator))!!))
        assertEquals("null", continuousLocatorOffsetRawClassification("null"))
        assertEquals("quoted-null", continuousLocatorOffsetRawClassification("\"null\""))
    }

    @Test fun `fragment restore verifies its own range at the reading anchor`() = runBlocking {
        val commands = mutableListOf<String>()
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication()) { _, script, callback ->
            commands += script
            callback("true")
        }
        val fragment = Locator.fromJSON(
            org.json.JSONObject("""{"href":"#CHAPTER_LIX","type":"application/xhtml+xml","locations":{"fragments":["CHAPTER_LIX"]}}"""),
        )!!

        assertTrue(webView.isLocatorRangeAtVerticalAnchor(fragment, nativeY = 554.0))
        assertEquals(1, commands.size)
        assertTrue(commands.single().contains("readium.isLocatorRangeAtVerticalAnchor("))
        assertTrue(commands.single().contains("\"CHAPTER_LIX\""))
    }

    @Test fun `missing requested range never passes the reading-anchor proof`() = runBlocking {
        val webView = R2BasicWebView(RuntimeEnvironment.getApplication()) { _, _, callback -> callback("false") }
        val fragment = Locator.fromJSON(
            org.json.JSONObject("""{"href":"#MISSING","type":"application/xhtml+xml","locations":{"fragments":["MISSING"]}}"""),
        )!!

        assertTrue(!webView.isLocatorRangeAtVerticalAnchor(fragment, nativeY = 554.0))
    }
}
