@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
package org.readium.r2.navigator.epub.continuous

import android.app.Activity
import android.view.View
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.R2JavascriptExecutor
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.*
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class ContinuousReflowFastPathTest {
    @Test fun `same height and stable exact point commits coherently without layout mutation scroll or lock`() = verify(0.0, 1200, "no_op")
    @Test fun `font weight trace with height 86657 and stable point uses no op`() =
        verify(0.0, 86657, "no_op", oldHeight = 86657, originalPoint = 555.970947)
    @Test fun `same height and moved exact point corrects once without height mutation`() = verify(12.0, 1200, "anchor_only")
    @Test fun `tiny subpixel delta does not request a scroll`() = verify(0.25, 1200, "no_op")
    @Test fun `height changing preference keeps full geometry pipeline`() = verify(12.0, 1450, "full_reflow")
    @Test fun `height changing line height keeps full geometry pipeline`() = verify(12.0, 1450, "full_reflow", lineHeight = true)
    @Test fun `full geometry change with zero correction does not scroll`() = verify(0.0, 1450, "full_reflow")
    @Test fun `full geometry change with tiny correction does not scroll`() = verify(0.25, 1450, "full_reflow")
    @Test fun `full geometry change with meaningful subpixel correction scrolls once`() = verify(0.75, 1450, "full_reflow")
    @Test fun `progression fallback cannot be classified as exact no op`() = verify(0.0, 1200, "full_reflow", exact = false)
    @Test fun `late stale anchor result cannot commit no op ownership`() = verify(0.0, 1200, "no_op", stale = true)

    private fun verify(delta: Double, newHeight: Long, expectedPath: String, exact: Boolean = true, lineHeight: Boolean = false, stale: Boolean = false, oldHeight: Long = 1200, originalPoint: Double = 250.0) = runBlocking {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val link = Link(Url("chapter.xhtml")!!, MediaType.XHTML)
        val publication = Publication(Manifest(metadata = Metadata(), readingOrder = listOf(link)))
        val port = ControlledContinuousReflowEventPort()
        val binding = RobolectricContinuousReflowHostTestBinding()
        lateinit var resource: ContinuousResourceView
        val executor = R2JavascriptExecutor { _, script, done -> done(when {
            script == READIUM_RUNTIME_PROBE -> "true"
            script.contains("__biblioLifeContinuousResizeObserver") -> "true"
            script.contains("readium.findLocatorAtPoint(") -> """{"href":"#","type":"application/xhtml+xml","locations":{"cssSelector":"p","progression":0.4}}"""
            else -> "null"
        }) }
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "fast-path-test"
            override fun create(context: android.content.Context, publication: Publication, link: Link, index: Int,
                layoutGeneration: Int, resourceGeneration: Long, sessionInstanceId: String, hostId: String,
                onMeasurement: (ResourceLayoutMeasurement) -> Unit): ContinuousResourceView = ContinuousResourceView(
                    context, index, layoutGeneration, resourceGeneration, "https://readium_assets/chapter.xhtml",
                    { _, _, _, _ -> }, { _, _, _, _, done -> done(true) }, publication, link,
                    onMeasurement, sessionInstanceId, hostId, javascriptExecutor = executor,
                ).also { resource = it }
        }
        val host = ContinuousReflowableHostView(activity, publication, listOf(link), factory, reflowEventPort = port, testBinding = binding)
        activity.setContentView(FrameLayout(activity).apply { addView(host, FrameLayout.LayoutParams(1080, 1000)) })
        host.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY))
        host.layout(0, 0, 1080, 1000)
        host.pinResource(0, ContinuousResourcePinReason.GEOMETRY_REFLOW)
        host.prepareTargetResource(0)
        val initialTarget = requireNotNull(binding.createdTarget)
        binding.materializeTarget(initialTarget, 1080, 1000)
        val web = resource.getChildAt(0) as WebView
        shadowOf(web).webViewClient.onPageFinished(web, "https://readium_assets/chapter.xhtml")
        resource.dispatchBootstrapBridgeEvent(ContinuousRawBootstrapBridgeEvent(ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD))
        shadowOf(android.os.Looper.getMainLooper()).idle()
        port.trueReady(initialTarget)
        resource.receiveMeasurement(oldHeight, resource.currentLayoutGeneration, resource.currentMeasurementEpoch)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        binding.materializeTarget(initialTarget, 1080, 1000)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        val recycler = privateField(host, "recyclerView") as RecyclerView
        for (i in 0 until recycler.childCount) {
            val child = recycler.getChildAt(i)
            child.layoutParams = child.layoutParams.apply { width = android.view.ViewGroup.LayoutParams.MATCH_PARENT }
        }
        binding.commitRecyclerViewLayout(1080, 1000)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        port.pointGeometryAnswer = ContinuousLocatorPointGeometry(originalPoint, originalPoint, true, "7", 12)
        val locator = Locator(link.url(), MediaType.XHTML, locations = Locator.Locations(progression = 0.4,
            otherLocations = mapOf("cssSelector" to "p", "continuousDomAnchor" to mapOf("id" to "7", "charOffset" to 12))))
        val original = requireNotNull(host.resolveLocatorPointGeometry(0, resource.generation, locator))
        val tx = ContinuousGeometryReflowTransaction(9, 9, ContinuousAnchorLocator(0, resource.generation,
            resource.currentLayoutGeneration, originalPoint, locator, original.viewportY, original.documentYLayoutPx),
            if (lineHeight) EpubPreferences(lineHeight = 1.8) else EpubPreferences(fontWeight = 1.2))
        val events = mutableListOf<EpubContinuousReflowDiagnosticEvent>()
        host.setReflowDiagnosticListener(events::add)
        host.beginGeometryReflowPinLease()
        host.applyInPlaceLayoutGeneration(tx, EpubContinuousReflowDiagnosticContext(42, "fontWeight", 3, 1.2), 9)
        val target = ContinuousReflowTarget(0, resource.currentLayoutGeneration, resource.generation)
        port.trueReady(target)
        resource.receiveMeasurement(newHeight, resource.currentLayoutGeneration, resource.currentMeasurementEpoch)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        port.pointGeometryAnswer = ContinuousLocatorPointGeometry(originalPoint + delta, originalPoint + delta, exact, "7", 12)
        var mutations = 0
        var reads = 0
        var current = true
        var adapterNotifications = 0
        recycler.adapter!!.registerAdapterDataObserver(object : RecyclerView.AdapterDataObserver() {
            override fun onChanged() { adapterNotifications++ }
            override fun onItemRangeChanged(positionStart: Int, itemCount: Int) { adapterNotifications++ }
        })
        host.geometryBatchAfterFirstHeightMutationForTest = { mutations++ }
        host.beforeLocatorPointGeometryForTest = { reads++; if (stale) current = false }
        val scrolls = mutableListOf<Pair<Int, Int>>()
        host.scrollToPositionCallObserverForTest = { i, offset -> scrolls += i to offset }
        val passBefore = privateField(host, "recyclerLayoutPass") as Long
        val result = async(start = CoroutineStart.UNDISPATCHED) { host.restoreAfterGeometryReflow(locator, tx) { current } }
        yield()
        shadowOf(android.os.Looper.getMainLooper()).idle()
        if (expectedPath != "no_op") {
            binding.commitRecyclerViewLayout(1080, 1000)
            yield(); shadowOf(android.os.Looper.getMainLooper()).idle(); yield()
            if (!result.isCompleted) {
                binding.commitRecyclerViewLayout(1080, 1000)
                yield(); shadowOf(android.os.Looper.getMainLooper()).idle(); yield()
            }
        }
        assertTrue("Restore must finish without unrequested layout: ${events.map { it.kind to it.result }}", result.isCompleted)
        val outcome = result.await()
        if (stale) {
            assertEquals(ContinuousReflowRestoreOutcome.Cancelled, outcome)
            assertTrue(resource.hasPendingCssGeometry)
            assertEquals(0, mutations)
            assertTrue(scrolls.isEmpty())
            assertFalse(events.any { it.kind == "reflow_path" })
            host.dispose()
            return@runBlocking
        }
        assertTrue("outcome=$outcome anchor=${host.currentLocatorAnchor()} events=${events.map { it.kind to it.result }}", outcome is ContinuousReflowRestoreOutcome.Restored)
        assertNull((outcome as ContinuousReflowRestoreOutcome.Restored).observedLocator.locations["continuousDomAnchor"])
        val path = events.single { it.kind == "reflow_path" }
        assertEquals(expectedPath, path.result)
        assertEquals(expectedPath == "full_reflow", mutations > 0)
        if (expectedPath == "no_op") {
            assertTrue(scrolls.isEmpty())
            assertEquals(0, binding.restoreCount)
            assertEquals(passBefore, privateField(host, "recyclerLayoutPass"))
            assertEquals(1, reads)
            assertEquals(0, adapterNotifications)
            assertNull(tx.commitOwner)
            assertFalse(events.any { it.kind == "presentation_transaction" || it.kind == "geometry_batch_apply" })
        } else if (expectedPath == "anchor_only") {
            assertEquals(1, scrolls.size)
            assertEquals(1, binding.restoreCount)
            assertEquals(2, reads)
            assertEquals(0, adapterNotifications)
            assertNotNull(tx.commitOwner)
            assertFalse(events.any { it.kind == "geometry_batch_apply" })
        } else {
            assertEquals(1, mutations)
            assertEquals(if (continuousAnchorScrollRequired(delta)) 1 else 0, scrolls.size)
        }
        assertEquals(expectedPath == "full_reflow", path.semanticAnchorFields["geometryMutation"])
        assertEquals(original.viewportY, tx.anchor.viewportY, 0.0)
        assertEquals("7", (tx.anchor.locator.locations["continuousDomAnchor"] as Map<*, *>)["id"])
        assertFalse(resource.hasPendingCssGeometry)
        assertTrue(host.hasCommittedCssGeometry(tx))
        assertTrue(tx.complete())
        host.finishFreshLocatorObservation(tx)
        host.finishGeometryReflowPinLease()
        shadowOf(android.os.Looper.getMainLooper()).idle()
        resource.emitCssConsistency()
        val consistency = events.last { it.kind == "reflow_consistency" }.semanticAnchorFields
        assertEquals(true, consistency["coherent"])
        assertEquals(9L, consistency["activeCssPreferenceGeneration"])
        assertEquals(9L, consistency["committedGeometryPreferenceGeneration"])
        if (expectedPath == "no_op") {
            assertEquals(passBefore, privateField(host, "recyclerLayoutPass"))
            assertEquals(0, adapterNotifications)
        }
        tx.commitOwner?.let(host::acknowledgeGeometryCommit)
        host.dispose()
    }
    private fun privateField(instance: Any, name: String): Any = requireNotNull(instance.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(instance))
}
