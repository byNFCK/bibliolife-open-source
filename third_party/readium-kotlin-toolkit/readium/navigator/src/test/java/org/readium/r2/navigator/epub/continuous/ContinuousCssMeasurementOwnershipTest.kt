@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
package org.readium.r2.navigator.epub.continuous

import android.os.Looper
import android.webkit.WebView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.R2JavascriptExecutor
import org.readium.r2.shared.publication.*
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RuntimeEnvironment
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class ContinuousCssMeasurementOwnershipTest {
    private class Fixture {
        val reports = mutableListOf<ResourceLayoutMeasurement>()
        val events = mutableListOf<EpubContinuousReflowDiagnosticEvent>()
        val scripts = mutableListOf<String>()
        var holdObserver = false
        var observerHeight: Long? = null
        val pending = mutableListOf<(String) -> Unit>()
        val link = Link(Url("chapter.xhtml")!!, MediaType.XHTML)
        val resource = ContinuousResourceView(
            RuntimeEnvironment.getApplication(), 0, 0, 1, "https://readium_assets/chapter.xhtml",
            { _, _, _, _ -> }, { _, _, _, _, done -> done(true) },
            Publication(Manifest(metadata = Metadata(), readingOrder = listOf(link))), link,
            reports::add, "css-measurement-test", "css-measurement-test",
            javascriptExecutor = R2JavascriptExecutor { _, script, done ->
                scripts += script
                when {
                    script.contains("__biblioLifeContinuousResizeObserver") -> {
                        if (holdObserver) pending += done
                        else done(observerHeight?.let { """{"installed":true,"height":$it}""" } ?: "true")
                    }
                    script == READIUM_RUNTIME_PROBE -> done("true")
                    script.contains("body.getBoundingClientRect().bottom-root") -> done("777")
                    else -> done("null")
                }
            },
        )
        init {
            resource.layoutParams = android.widget.FrameLayout.LayoutParams(1080, 800)
            resource.setCssStateDiagnosticListener(events::add)
            val web = resource.getChildAt(0) as WebView
            shadowOf(web).webViewClient.onPageFinished(web, "https://readium_assets/chapter.xhtml")
            resource.dispatchBootstrapBridgeEvent(ContinuousRawBootstrapBridgeEvent(ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD))
            idle()
        }
        fun idle() = shadowOf(Looper.getMainLooper()).idle()
        fun apply(g: Int) = resource.applyCssForLayoutGeneration(g, g.toLong(), g.toLong()) { }
        fun release(height: Long? = null) {
            val callbacks = pending.toList(); pending.clear()
            callbacks.forEach { it(height?.let { h -> """{"installed":true,"height":$h}""" } ?: "true") }
            idle()
        }
        fun report(height: Long, token: Long = resource.currentCssOwnerToken) {
            resource.receiveMeasurement(height, resource.currentLayoutGeneration, resource.currentMeasurementEpoch, token)
            idle()
        }
    }

    @Test fun `text render measurement sample follows accepted ACK once and stale diagnostic token is rejected`() {
        val f = Fixture()
        f.resource.configureTextRenderDiagnostics(Locator(Url("chapter.xhtml")!!, MediaType.XHTML))
        f.holdObserver = true
        f.apply(1)
        val oldToken = f.resource.currentCssOwnerToken
        f.report(700)
        assertFalse(f.scripts.any { it.contains("'after_measurement'") })
        f.release(700)
        assertEquals(1, f.scripts.count { it.contains("'after_measurement'") })
        f.report(700)
        assertEquals(1, f.scripts.count { it.contains("'after_measurement'") })
        val payload = """{"kind":"webview_text_render_snapshot","snapshotStage":"after_measurement","rangeTopPx":22}"""
        f.resource.receiveTextRenderDiagnostic(oldToken, payload); f.idle()
        assertEquals(1, f.events.count { it.kind == "webview_text_render_snapshot" })
        f.apply(2)
        f.resource.receiveTextRenderDiagnostic(oldToken, payload); f.idle()
        assertEquals(1, f.events.count { it.kind == "webview_text_render_snapshot" })
        f.resource.revokeCurrentCssMutationOwner()
        f.resource.receiveTextRenderDiagnostic(f.resource.currentCssOwnerToken, payload); f.idle()
        assertEquals(1, f.events.count { it.kind == "webview_text_render_snapshot" })
        f.resource.dispose()
    }

    @Test fun `report before observer ACK is retained and acknowledges matching CSS exactly once`() {
        val f = Fixture()
        f.holdObserver = true
        f.apply(1)
        assertTrue(f.resource.mustFinishCssGeometry(1))
        assertFalse(f.resource.cssAppliedForCurrentEpoch)
        f.report(700)
        assertTrue(f.reports.isEmpty())
        f.release(700)
        assertEquals(1, f.reports.size)
        val sample = f.reports.single()
        assertFalse(f.resource.canAcknowledgeUnchangedGeometry(sample.copy(appliedCssToken = sample.appliedCssToken!! + 1)))
        assertFalse(f.resource.canAcknowledgeUnchangedGeometry(sample.copy(layoutGeneration = sample.layoutGeneration + 1)))
        assertEquals(f.resource.currentCssOwnerToken, sample.appliedCssToken)
        f.report(700)
        assertEquals(1, f.reports.size)
        f.resource.commitMeasuredGeometry(sample)
        assertFalse(f.resource.mustFinishCssGeometry(1))
        f.resource.emitCssConsistency()
        assertEquals(true, f.events.last { it.kind == "reflow_consistency" }.semanticAnchorFields["coherent"])
        f.resource.dispose()
    }

    @Test fun `observer ACK carries fresh measurement even when observer report is lost`() {
        val f = Fixture()
        f.observerHeight = 700
        f.apply(1); f.idle()
        assertEquals(1, f.reports.size)
        f.resource.commitMeasuredGeometry(f.reports.last())
        f.apply(2); f.idle()
        assertEquals(2, f.reports.size)
        assertTrue(f.events.any { it.result == "measurement_ack" && it.preferenceGeneration == 2L && it.semanticAnchorFields["measurementResult"] == "same_height" })
        f.resource.commitMeasuredGeometry(f.reports.last())
        assertFalse(f.resource.hasPendingCssGeometry)
        f.resource.dispose()
    }

    @Test fun `latest CSS explicitly replaces obligation and rejects delayed old report`() {
        val f = Fixture()
        f.holdObserver = true
        f.apply(1)
        val old = f.resource.currentCssOwnerToken
        f.apply(2)
        f.report(900, old)
        f.release(700)
        assertEquals(1, f.reports.size)
        assertEquals(2, f.reports.single().layoutGeneration)
        assertTrue(f.events.any { it.result == "ownership_transferred" })
        f.resource.commitMeasuredGeometry(f.reports.single())
        assertFalse(f.resource.hasPendingCssGeometry)
        f.resource.dispose()
    }

    @Test fun `lost report can be replaced by one current CSS measurement request`() {
        val f = Fixture()
        f.apply(1); f.idle()
        assertTrue(f.reports.isEmpty())
        f.resource.requestCurrentCssMeasurement(); f.idle()
        assertEquals(1, f.reports.size)
        f.resource.commitMeasuredGeometry(f.reports.single())
        assertFalse(f.resource.hasPendingCssGeometry)
        f.resource.dispose()
    }
}
