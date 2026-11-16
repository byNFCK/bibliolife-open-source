package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ContinuousTextRenderDiagnosticsTest {
    @Test fun `metric whitelist drops text html arbitrary keys and nonfinite values`() {
        val fields = continuousTextRenderDiagnosticFields("""{"kind":"webview_text_render_snapshot",
            "fontFamily":"\"Example Font\", serif", "rangeTopPx":12.5,"sameDomIdentity":true,
            "activeFontCheck":"unknown", "text":"SECRET", "html":"<p>SECRET</p>","other":3}""")!!
        assertEquals("\"Example Font\", serif", fields["fontFamily"])
        assertEquals(12.5, fields["rangeTopPx"])
        assertEquals(true, fields["sameDomIdentity"])
        assertEquals("unknown", fields["activeFontCheck"])
        assertFalse(fields.toString().contains("SECRET"))
        assertFalse(fields.containsKey("other"))
        assertNull(continuousTextRenderDiagnosticFields("not json"))
        assertNull(continuousTextRenderDiagnosticFields("""{"kind":"other"}"""))
    }

    @Test fun `diagnostics wrap one synchronous CSS call without async gap`() {
        val script = guardedReadiumCssScript("""{"font-weight":"700","--USER__lineHeight":"1.5"}""", 71, "{\"locator\":{}}")
        assertTrue(script.indexOf("beginCssMutation(71)") < script.indexOf("'before_css'"))
        assertTrue(script.indexOf("'before_css'") < script.indexOf("readium.setCSSProperties"))
        assertTrue(script.indexOf("gate.cssApplied(71)") < script.indexOf("'after_css'"))
        assertEquals(1, Regex("readium.setCSSProperties").findAll(script).count())
        listOf("setTimeout", "requestAnimationFrame", "Promise", "await").forEach { assertFalse(script.contains(it)) }
        assertFalse(guardedReadiumCssScript("{}", 72).contains("textRenderDiagnostic"))
    }
}
