@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.R2BasicWebView
import org.readium.r2.navigator.R2JavascriptExecutor
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import android.webkit.WebView
import android.app.Activity
import android.widget.FrameLayout
import android.view.View
import android.graphics.Color
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.html.HtmlDecorationTemplates
import org.robolectric.Robolectric
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield

@RunWith(RobolectricTestRunner::class)
class ContinuousBootstrapBridgeEventTest {
    @Test fun `store before resource creation seeds only matching href and stale generation is rejected`() {
        val readingOrder = listOf(link(0))
        val created = mutableListOf<ContinuousResourceView>()
        val binding = RobolectricContinuousReflowHostTestBinding()
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "test-decoration-handoff"
            override fun create(
                context: android.content.Context, publication: Publication, link: Link, index: Int,
                layoutGeneration: Int, resourceGeneration: Long, sessionInstanceId: String, hostId: String,
                onMeasurement: (ResourceLayoutMeasurement) -> Unit,
            ) = resource(index, resourceGeneration, RawCallbackJavascriptExecutor { "null" }).also { created += it }
        }
        val host = ContinuousReflowableHostView(context, publication(*readingOrder.toTypedArray()), readingOrder, factory, testBinding = binding)
        val href = Url("OEBPS/chapter-0.xhtml")!!
        val unrelated = Url("OEBPS/chapter-1.xhtml")!!
        val snapshot = listOf(
            Decoration("annotation:target", Locator(href = href, mediaType = MediaType.XHTML, locations = Locator.Locations(progression = 0.1)), Decoration.Style.Highlight(Color.YELLOW, false), emptyMap()),
            Decoration("annotation:unrelated", Locator(href = unrelated, mediaType = MediaType.XHTML, locations = Locator.Locations(progression = 0.2)), Decoration.Style.Highlight(Color.YELLOW, false), emptyMap()),
        )
        host.setDecorationSnapshotProvider { mapOf("persistent" to (snapshot to HtmlDecorationTemplates.defaultTemplates())) }
        host.prepareTargetResource(0)
        val target = requireNotNull(binding.createdTarget)
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setContentView(host)
        host.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY))
        host.layout(0, 0, 1080, 1920)
        binding.materializeTarget(target)
        val current = requireNotNull(created.singleOrNull())
        val field = ContinuousResourceView::class.java.getDeclaredField("requestedDecorations").apply { isAccessible = true }
        @Suppress("UNCHECKED_CAST")
        val requested = field.get(current) as Map<String, List<Decoration>>
        assertEquals(listOf("annotation:target"), requested.getValue("persistent").map { it.id })
        var staleDelivered = false
        assertFalse(host.applyToLiveResource(0, 0L) { staleDelivered = true })
        assertFalse(staleDelivered)
        assertTrue(host.applyToLiveResource(0, 1L) { staleDelivered = true })
        assertTrue(staleDelivered)
        host.dispose()
    }

    @Test fun `lazy preload policy is idle safe bounded and edge aware`() {
        assertEquals(emptyList<Int>(), lazyPreloadIndices(5, 5, 20, enabled = false))
        assertEquals(listOf(4, 6), lazyPreloadIndices(5, 5, 20, enabled = true))
        assertEquals(listOf(1), lazyPreloadIndices(0, 0, 2, enabled = true))
        assertEquals(listOf(18), lazyPreloadIndices(19, 19, 20, enabled = true))
        assertEquals(listOf(8, 11), lazyPreloadIndices(9, 10, 20, enabled = true))
        assertEquals(emptyList<Int>(), lazyPreloadIndices(3, 3, 0, enabled = true))
    }

    @Test fun `initial target preparation and placeholder layouts do not load neighbors`() {
        val readingOrder = (0..720).map(::link)
        val created = mutableListOf<Int>()
        val binding = RobolectricContinuousReflowHostTestBinding()
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "test-initial-target"
            override fun create(
                context: android.content.Context, publication: Publication, link: Link, index: Int,
                layoutGeneration: Int, resourceGeneration: Long, sessionInstanceId: String, hostId: String,
                onMeasurement: (ResourceLayoutMeasurement) -> Unit,
            ) = ContinuousResourceView(
                context = context, index = index, layoutGeneration = layoutGeneration, resourceGeneration = resourceGeneration,
                url = "https://readium_assets/${link.url()}",
                configure = { _, _, _, _ -> }, applyReadiumCss = { _, _, _, _, done -> done(true) },
                publication = publication, link = link, onMeasurement = onMeasurement,
                sessionInstanceId = sessionInstanceId, hostId = hostId,
                javascriptExecutor = RawCallbackJavascriptExecutor { "null" },
            ).also { created += index }
        }
        val host = ContinuousReflowableHostView(context, publication(*readingOrder.toTypedArray()), readingOrder, factory, testBinding = binding)
        host.prepareTargetResource(700)
        val target = requireNotNull(binding.createdTarget)
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setContentView(host)
        host.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY))
        host.layout(0, 0, 1080, 1920)
        binding.materializeTarget(target)
        assertEquals(listOf(700), created)
        assertEquals(1, host.liveResourceCount)
        host.prepareTargetResource(710)
        binding.materializeTarget(requireNotNull(binding.createdTarget))
        assertEquals(listOf(700, 710), created)
        assertEquals(1, host.liveResourceCount)
        host.dispose()
        host.prepareTargetResource(711)
        assertEquals(listOf(700, 710), created)
        assertEquals(0, host.liveResourceCount)
    }

    @Test fun `in-place reflow retains attached WebView and rejects old epoch before accepting fresh same height`() = runBlocking {
        val executors = mutableMapOf<Int, RawCallbackJavascriptExecutor>()
        val deliveredMeasurements = mutableListOf<ResourceLayoutMeasurement>()
        val createdResources = mutableMapOf<Int, ContinuousResourceView>()
        var cssApplications = 0
        var holdCssApplications = false
        var failNextAnchorCssApplication = false
        val heldCssCompletions = mutableListOf<(Boolean) -> Unit>()
        val readingOrder = listOf(link(0), link(1))
        val binding = RobolectricContinuousReflowHostTestBinding()
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "test-in-place-reflow"
            override fun create(
                context: android.content.Context, publication: Publication, link: Link,
                index: Int, layoutGeneration: Int, resourceGeneration: Long,
                sessionInstanceId: String, hostId: String,
                onMeasurement: (ResourceLayoutMeasurement) -> Unit,
            ): ContinuousResourceView {
                val executor = RawCallbackJavascriptExecutor { javascript ->
                    when {
                        javascript == READIUM_RUNTIME_PROBE -> "true"
                        javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                        javascript.contains("continuousLocatorPointGeometry") -> "{\"documentY\":80.0,\"viewportTop\":80.0}"
                        else -> "null"
                    }
                }
                executors[index] = executor
                return ContinuousResourceView(
                context = context,
                index = index,
                layoutGeneration = layoutGeneration,
                resourceGeneration = resourceGeneration,
                url = "https://readium_assets/${link.url()}",
                configure = { _, _, _, _ -> },
                    applyReadiumCss = { _, _, _, _, done ->
                        cssApplications += 1
                        if (holdCssApplications) {
                            heldCssCompletions += done
                        } else if (index == 0 && failNextAnchorCssApplication) {
                            failNextAnchorCssApplication = false
                            done(false)
                        } else {
                            done(true)
                        }
                    },
                publication = publication,
                link = link,
                onMeasurement = { measurement ->
                    deliveredMeasurements += measurement
                    onMeasurement(measurement)
                },
                sessionInstanceId = sessionInstanceId,
                hostId = hostId,
                javascriptExecutor = executor,
                ).also { createdResources[index] = it }
            }
        }
        val host = ContinuousReflowableHostView(
            context = context,
            publication = publication(*readingOrder.toTypedArray()),
            readingOrder = readingOrder,
            resourceFactory = factory,
            testBinding = binding,
        )
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setContentView(FrameLayout(activity).apply {
            addView(host, FrameLayout.LayoutParams(1080, 1800))
        })
        host.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1800, View.MeasureSpec.EXACTLY))
        host.layout(0, 0, 1080, 1800)
        host.prepareTargetResource(0)
        val initialTarget = requireNotNull(binding.createdTarget)
        host.pinResource(0, ContinuousResourcePinReason.SELECTION)
        host.pinResource(1, ContinuousResourcePinReason.SELECTION)
        host.prepareTargetResource(1)
        val neighborTarget = requireNotNull(binding.createdTarget)
        binding.materializeTarget(neighborTarget)
        val measuredNeighbor = requireNotNull(createdResources[1])
        binding.materializeTarget(initialTarget, height = 1800)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        val initialMaterialization = requireNotNull(binding.attachedMaterialization(initialTarget))
        val resource = initialMaterialization.resource
        val webView = resource.webViewForDiagnostics
        finishProductionPageLoad(resource)
        assertTrue(resource.dispatchBootstrapBridgeEvent(ContinuousRawBootstrapBridgeEvent(ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD)))
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(resource.canFindLocator)
        assertTrue(resource.cssAppliedForCurrentEpoch)

        binding.materializeTarget(neighborTarget, height = 1800)
        assertTrue("Measured neighbor bootstrap requires its holder to be attached", measuredNeighbor.isAttachedToWindow)
        val neighborWebView = measuredNeighbor.getChildAt(0) as WebView
        shadowOf(neighborWebView).webViewClient.onPageFinished(neighborWebView, "https://readium_assets/finished.xhtml")
        assertTrue(measuredNeighbor.dispatchBootstrapBridgeEvent(ContinuousRawBootstrapBridgeEvent(ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD)))
        shadowOf(android.os.Looper.getMainLooper()).idle()
        val bootstrapState = privateField(measuredNeighbor, "bootstrapState")
        val bootstrapStatus = privateField(bootstrapState!!, "state")
        assertTrue(
            "neighbor readiness stalled: attached=${measuredNeighbor.isAttachedToWindow}, " +
                "bootstrap=$bootstrapStatus, " +
                "runtime=${privateField(measuredNeighbor, "readiumRuntimeVerified")}, " +
                "css=${measuredNeighbor.cssAppliedForCurrentEpoch}, pending=${measuredNeighbor.cssApplicationPending}, " +
                "commands=${executors[1]?.commands}",
            measuredNeighbor.canFindLocator,
        )
        assertTrue(
            "Measured neighbor detached after bootstrap: live=${host.isLiveResource(1, measuredNeighbor.generation)}, " +
                "range=${host.visibleResourceRange()}, host=${host.width}x${host.height}, " +
                "resourceBounds=${measuredNeighbor.left},${measuredNeighbor.top},${measuredNeighbor.right},${measuredNeighbor.bottom}, " +
                "holder=${binding.attachedMaterialization(neighborTarget)}, detached=${binding.detachedMaterializations.map { it.target.index to it.target.resourceGeneration }}",
            measuredNeighbor.isAttachedToWindow,
        )
        measuredNeighbor.receiveMeasurement(520, measuredNeighbor.currentLayoutGeneration, measuredNeighbor.currentMeasurementEpoch)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(520L, measuredNeighbor.currentHeightPx)

        // The settings transaction snapshots the live window before its first
        // target reconciliation. Once leased, its resources stay live even
        // after their unrelated pin reasons are removed.
        host.beginGeometryReflowPinLease()
        host.unpinResource(0, ContinuousResourcePinReason.SELECTION)
        host.unpinResource(1, ContinuousResourcePinReason.SELECTION)
        val measuredNeighborGeneration = measuredNeighbor.generation
        val measuredNeighborWebView = measuredNeighbor.webViewForDiagnostics
        assertTrue(host.isLiveResource(1, measuredNeighborGeneration))

        resource.receiveMeasurement(420, resource.currentLayoutGeneration, resource.currentMeasurementEpoch)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(420L, resource.currentHeightPx)
        val oldGeneration = resource.currentLayoutGeneration
        val oldEpoch = resource.currentMeasurementEpoch
        val oldResourceGeneration = resource.generation
        val diagnosticEvents = mutableListOf<EpubContinuousReflowDiagnosticEvent>()
        host.setReflowDiagnosticListener(diagnosticEvents::add)
        val reflow = ContinuousGeometryReflowTransaction(
            generation = 17,
            preferenceGeneration = 1,
            anchor = ContinuousAnchorLocator(
                index = 0,
                resourceGeneration = oldResourceGeneration,
                layoutGeneration = oldGeneration,
                localY = 80.0,
                locator = targetLocator(0),
            ),
            requestedPreferences = EpubPreferences(fontSize = 1.2),
        )
        host.applyInPlaceLayoutGeneration(
            reflow,
            EpubContinuousReflowDiagnosticContext(gestureId = 1, slider = "font_size", applyId = 1, normalizedValue = 1.2),
            preferenceGeneration = 1,
        )
        host.prepareTargetResource(0)
        shadowOf(android.os.Looper.getMainLooper()).idle()

        assertEquals(oldResourceGeneration, resource.generation)
        assertEquals(oldGeneration + 1, resource.currentLayoutGeneration)
        assertEquals(oldEpoch + 1, resource.currentMeasurementEpoch)
        assertEquals(4, cssApplications)
        assertEquals(520L, measuredNeighbor.currentHeightPx)
        assertEquals(measuredNeighborGeneration, measuredNeighbor.generation)
        assertSame(measuredNeighborWebView, measuredNeighbor.webViewForDiagnostics)
        assertTrue(measuredNeighbor.isAttachedToWindow)
        assertTrue(host.isLiveResource(1, measuredNeighborGeneration))
        assertSame(webView, resource.webViewForDiagnostics)
        assertTrue(resource.isAttachedToWindow)
        assertTrue(resource.parent != null)
        val firstOwnerToken = resource.currentCssOwnerToken
        assertTrue(diagnosticEvents.none { it.kind == "resource_detached" && it.readingOrderIndex == 0 })
        assertEquals(420L, resource.currentHeightPx)
        assertTrue(diagnosticEvents.any { it.kind == "neighbor_update" && it.readingOrderIndex == 1 })

        measuredNeighbor.receiveMeasurement(
            530,
            measuredNeighbor.currentLayoutGeneration,
            measuredNeighbor.currentMeasurementEpoch,
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals("A visible resource waits for the anchor's grouped measurement", 520L, measuredNeighbor.currentHeightPx)

        val beforeFreshCount = deliveredMeasurements.size
        // Queue a valid current-epoch observation, then deliver a late old-epoch
        // report before the main-thread measurement dispatcher drains.
        resource.receiveMeasurement(420, resource.currentLayoutGeneration, resource.currentMeasurementEpoch)
        resource.receiveMeasurement(421, oldGeneration, oldEpoch)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        val restore = async(start = CoroutineStart.UNDISPATCHED) {
            host.restoreAfterGeometryReflow(reflow.anchor.locator, reflow) { true }
        }
        yield()
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(530L, measuredNeighbor.currentHeightPx)
        assertEquals(beforeFreshCount + 1, deliveredMeasurements.size)
        assertEquals(resource.currentLayoutGeneration, deliveredMeasurements.last().layoutGeneration)
        assertEquals(resource.currentMeasurementEpoch, deliveredMeasurements.last().measurementEpoch)
        assertEquals(420L, deliveredMeasurements.last().heightPx)
        assertEquals(420L, resource.currentHeightPx)
        resource.receiveMeasurement(460, resource.currentLayoutGeneration, resource.currentMeasurementEpoch)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals("An applied batch retains later reports until its transaction terminal", 420L, resource.currentHeightPx)

        val firstAppliedGeneration = resource.currentLayoutGeneration
        val firstAppliedEpoch = resource.currentMeasurementEpoch
        val secondReflow = ContinuousGeometryReflowTransaction(
                generation = 18,
                preferenceGeneration = 2,
                anchor = ContinuousAnchorLocator(
                    index = reflow.anchor.index,
                    resourceGeneration = reflow.anchor.resourceGeneration,
                    layoutGeneration = firstAppliedGeneration,
                    localY = reflow.anchor.localY,
                    locator = reflow.anchor.locator,
                ),
                requestedPreferences = EpubPreferences(fontSize = 1.0),
            )
        host.applyInPlaceLayoutGeneration(
            secondReflow,
            EpubContinuousReflowDiagnosticContext(gestureId = 1, slider = "font_size", applyId = 2, normalizedValue = 1.0),
            preferenceGeneration = 2,
        )
        host.prepareTargetResource(0)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        restore.cancelAndJoin()
        host.finishFreshLocatorObservation(reflow)
        val secondRestore = async(start = CoroutineStart.UNDISPATCHED) {
            host.restoreAfterGeometryReflow(secondReflow.anchor.locator, secondReflow) { true }
        }
        assertEquals(oldResourceGeneration, resource.generation)
        assertEquals(oldGeneration + 2, resource.currentLayoutGeneration)
        assertEquals(oldEpoch + 2, resource.currentMeasurementEpoch)
        assertSame(webView, resource.webViewForDiagnostics)
        assertTrue(resource.isAttachedToWindow)
        assertEquals("Superseding the uncommitted generation preserves its accepted anchor height", 420L, resource.currentHeightPx)
        assertEquals(measuredNeighborGeneration, measuredNeighbor.generation)
        assertSame(measuredNeighborWebView, measuredNeighbor.webViewForDiagnostics)
        assertEquals(530L, measuredNeighbor.currentHeightPx)
        assertTrue(measuredNeighbor.isAttachedToWindow)
        assertEquals(6, cssApplications)
        assertTrue("neighbor was evicted during the next apply", host.isLiveResource(1, measuredNeighborGeneration))
        val beforeSecondFreshCount = deliveredMeasurements.size
        val secondOwnerToken = resource.currentCssOwnerToken
        resource.receiveMeasurement(460, resource.currentLayoutGeneration, resource.currentMeasurementEpoch, secondOwnerToken)
        resource.receiveMeasurement(461, resource.currentLayoutGeneration, resource.currentMeasurementEpoch, firstOwnerToken)
        resource.receiveMeasurement(461, firstAppliedGeneration, firstAppliedEpoch, secondOwnerToken)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(beforeSecondFreshCount + 1, deliveredMeasurements.size)
        assertEquals(resource.currentLayoutGeneration, deliveredMeasurements.last().layoutGeneration)
        assertEquals(resource.currentMeasurementEpoch, deliveredMeasurements.last().measurementEpoch)
        assertEquals(420L, resource.currentHeightPx)
        resource.receiveMeasurement(480, resource.currentLayoutGeneration, resource.currentMeasurementEpoch, secondOwnerToken)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals("The newest anchor report remains staged until the required neighbor arrives", 420L, resource.currentHeightPx)
        val neighborOwnerToken = measuredNeighbor.currentCssOwnerToken
        measuredNeighbor.receiveMeasurement(
            550,
            measuredNeighbor.currentLayoutGeneration,
            measuredNeighbor.currentMeasurementEpoch,
            neighborOwnerToken,
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        yield()
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(480L, resource.currentHeightPx)
        assertEquals(550L, measuredNeighbor.currentHeightPx)

        // Keep real bootstrap readiness intact while making one CSS epoch fail.
        // The subsequent generation must retry CSS on this same WebView rather
        // than waiting for another bootstrap-ready event that cannot be emitted.
        failNextAnchorCssApplication = true
        host.applyInPlaceLayoutGeneration(
            ContinuousGeometryReflowTransaction(
                generation = 19,
                preferenceGeneration = 3,
                anchor = ContinuousAnchorLocator(
                    index = reflow.anchor.index,
                    resourceGeneration = reflow.anchor.resourceGeneration,
                    layoutGeneration = resource.currentLayoutGeneration,
                    localY = reflow.anchor.localY,
                    locator = reflow.anchor.locator,
                ),
                requestedPreferences = EpubPreferences(fontSize = 1.15),
            ),
            EpubContinuousReflowDiagnosticContext(gestureId = 1, slider = "font_size", applyId = 3, normalizedValue = 1.15),
            preferenceGeneration = 3,
        )
        secondRestore.cancelAndJoin()
        host.finishFreshLocatorObservation(secondReflow)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue("CSS failure does not revoke the WebView's bootstrap readiness", resource.canFindLocator)
        assertFalse(resource.cssAppliedForCurrentEpoch)
        assertFalse(resource.cssApplicationPending)

        val cssCountBeforeRetry = cssApplications
        host.applyInPlaceLayoutGeneration(
            ContinuousGeometryReflowTransaction(
                generation = 20,
                preferenceGeneration = 4,
                anchor = ContinuousAnchorLocator(
                    index = reflow.anchor.index,
                    resourceGeneration = reflow.anchor.resourceGeneration,
                    layoutGeneration = resource.currentLayoutGeneration,
                    localY = reflow.anchor.localY,
                    locator = reflow.anchor.locator,
                ),
                requestedPreferences = EpubPreferences(fontSize = 1.05),
            ),
            EpubContinuousReflowDiagnosticContext(gestureId = 1, slider = "font_size", applyId = 4, normalizedValue = 1.05),
            preferenceGeneration = 4,
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(
            "a bootstrapped WebView must retry CSS for the next epoch",
            resource.cssAppliedForCurrentEpoch,
        )
        assertEquals(cssCountBeforeRetry + 2, cssApplications)
        assertTrue(diagnosticEvents.none {
            it.readingOrderIndex == 0 && it.result?.startsWith("deferred_until_bootstrap") == true
        })

        // A terminal revoke must fence an already-dispatched CSS callback and
        // its late measurement, even though the WebView/resource remain live.
        holdCssApplications = true
        val terminalHeight = resource.currentHeightPx
        val terminalNeighborHeight = measuredNeighbor.currentHeightPx
        host.applyInPlaceLayoutGeneration(
            ContinuousGeometryReflowTransaction(
                generation = 21,
                preferenceGeneration = 5,
                anchor = ContinuousAnchorLocator(
                    index = reflow.anchor.index,
                    resourceGeneration = reflow.anchor.resourceGeneration,
                    layoutGeneration = resource.currentLayoutGeneration,
                    localY = reflow.anchor.localY,
                    locator = reflow.anchor.locator,
                ),
                requestedPreferences = EpubPreferences(fontSize = 1.1),
            ),
            EpubContinuousReflowDiagnosticContext(gestureId = 1, slider = "font_size", applyId = 5, normalizedValue = 1.1),
            preferenceGeneration = 5,
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        val terminalAnchorToken = resource.currentCssOwnerToken
        val terminalNeighborToken = measuredNeighbor.currentCssOwnerToken
        assertTrue(heldCssCompletions.isNotEmpty())
        resource.revokeCssMutationOwnerForPreference(5)
        measuredNeighbor.revokeCssMutationOwnerForPreference(5)
        heldCssCompletions.toList().forEach { it(true) }
        resource.receiveMeasurement(
            999,
            resource.currentLayoutGeneration,
            resource.currentMeasurementEpoch,
            terminalAnchorToken,
        )
        measuredNeighbor.receiveMeasurement(
            999,
            measuredNeighbor.currentLayoutGeneration,
            measuredNeighbor.currentMeasurementEpoch,
            terminalNeighborToken,
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(terminalHeight, resource.currentHeightPx)
        assertEquals(terminalNeighborHeight, measuredNeighbor.currentHeightPx)
        assertTrue(diagnosticEvents.none {
            it.preferenceGeneration == 5L && it.kind in setOf("resource_in_place_css", "neighbor_update") && it.result == "applied"
        })
        host.finishGeometryReflowPinLease()
        host.dispose()
    }

    @Test fun `bootstrap applies only the latest deferred reflow owner`() {
        var cssApplications = 0
        val binding = RobolectricContinuousReflowHostTestBinding()
        val executor = RawCallbackJavascriptExecutor { javascript ->
            when {
                javascript == READIUM_RUNTIME_PROBE -> "true"
                javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                else -> "null"
            }
        }
        val readingOrder = listOf(link(0))
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "test-latest-bootstrap-reflow"

            override fun create(
                context: android.content.Context, publication: Publication, link: Link,
                index: Int, layoutGeneration: Int, resourceGeneration: Long,
                sessionInstanceId: String, hostId: String,
                onMeasurement: (ResourceLayoutMeasurement) -> Unit,
            ) = ContinuousResourceView(
                context = context,
                index = index,
                layoutGeneration = layoutGeneration,
                resourceGeneration = resourceGeneration,
                url = "https://readium_assets/${link.url()}",
                configure = { _, _, _, _ -> },
                applyReadiumCss = { _, _, _, _, done ->
                    cssApplications += 1
                    done(true)
                },
                publication = publication,
                link = link,
                onMeasurement = onMeasurement,
                sessionInstanceId = sessionInstanceId,
                hostId = hostId,
                javascriptExecutor = executor,
            )
        }
        val host = ContinuousReflowableHostView(
            context = context,
            publication = publication(*readingOrder.toTypedArray()),
            readingOrder = readingOrder,
            resourceFactory = factory,
            testBinding = binding,
        )
        host.prepareTargetResource(0)
        val target = requireNotNull(binding.createdTarget)
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setContentView(FrameLayout(activity).apply { addView(host, FrameLayout.LayoutParams(1080, 1800)) })
        host.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1800, View.MeasureSpec.EXACTLY))
        host.layout(0, 0, 1080, 1800)
        binding.materializeTarget(target, width = 1080, height = 1800)
        val resource = requireNotNull(binding.attachedMaterialization(target)).resource
        val webView = resource.webViewForDiagnostics
        val events = mutableListOf<EpubContinuousReflowDiagnosticEvent>()
        host.setReflowDiagnosticListener(events::add)

        assertFalse(resource.canFindLocator)
        assertFalse(resource.cssApplicationPending)
        assertEquals(0, cssApplications)
        fun submitReflow(transactionGeneration: Long, preferenceGeneration: Long, fontSize: Double) {
            host.applyInPlaceLayoutGeneration(
                ContinuousGeometryReflowTransaction(
                    generation = transactionGeneration,
                    preferenceGeneration = preferenceGeneration,
                    anchor = ContinuousAnchorLocator(
                        index = 0,
                        resourceGeneration = resource.generation,
                        layoutGeneration = resource.currentLayoutGeneration,
                        localY = 70.0,
                        locator = targetLocator(0),
                    ),
                    requestedPreferences = EpubPreferences(fontSize = fontSize),
                ),
                EpubContinuousReflowDiagnosticContext(
                    gestureId = 8,
                    slider = "font_size",
                    applyId = preferenceGeneration,
                    normalizedValue = fontSize,
                ),
                preferenceGeneration = preferenceGeneration,
            )
        }

        submitReflow(transactionGeneration = 41, preferenceGeneration = 41, fontSize = 1.1)
        assertEquals(0, cssApplications)
        assertFalse(resource.canFindLocator)
        submitReflow(transactionGeneration = 42, preferenceGeneration = 42, fontSize = 1.25)
        assertEquals(0, cssApplications)
        assertFalse(resource.canFindLocator)
        assertEquals(2, events.count { it.result?.startsWith("deferred_until_bootstrap") == true })

        finishProductionPageLoad(resource)
        assertTrue(
            resource.dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(
                    ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD,
                ),
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()

        assertTrue(resource.canFindLocator)
        assertTrue(resource.cssAppliedForCurrentEpoch)
        assertEquals(1, cssApplications)
        assertSame(webView, resource.webViewForDiagnostics)
        val appliedOwner = requireNotNull(privateField(resource, "cssOwner"))
        assertEquals(42L, privateField(appliedOwner, "preferenceGeneration"))
        assertEquals(42L, privateField(appliedOwner, "transactionGeneration"))
        assertTrue(events.any {
            it.kind == "resource_in_place_css" && it.preferenceGeneration == 42L &&
                it.transactionGeneration == 42L && it.result?.startsWith("applied_same_webview") == true
        })
        assertTrue(events.none {
            it.kind == "resource_in_place_css" && it.preferenceGeneration == 41L && it.result == "applied"
        })
        host.dispose()
    }

    @Test fun `revoked deferred CSS never falls back to ambient bootstrap CSS`() {
        var holdRuntimeProbe = false
        val executor = RawCallbackJavascriptExecutor(
            callbackFor = { javascript ->
                when {
                    javascript == READIUM_RUNTIME_PROBE -> "true"
                    javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                    else -> "null"
                }
            },
            shouldHold = { javascript -> holdRuntimeProbe && javascript == READIUM_RUNTIME_PROBE },
        )
        var cssApplications = 0
        var p2CallbackCount = 0
        var p3Applied: Boolean? = null
        var readyCount = 0
        val resource = resource(
            index = 0,
            generation = 104,
            executor = executor,
            applyReadiumCss = { _, _, _, _, done ->
                cssApplications += 1
                done(true)
            },
        ).apply {
            onPageReady = { readyCount += 1 }
        }
        attachToProductionWindow(resource)
        assertTrue(resource.deferCssUntilBootstrap(1, 2, 2) { p2CallbackCount++ })

        holdRuntimeProbe = true
        finishProductionPageLoad(resource)
        assertTrue(
            resource.dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(
                    ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD,
                ),
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(1, executor.heldEvaluationCount)
        assertTrue(resource.revokeCssMutationOwnerForPreference(2) != null)
        executor.releaseHeldEvaluations()
        shadowOf(android.os.Looper.getMainLooper()).idle()

        assertTrue(resource.canFindLocator)
        assertFalse(resource.cssAppliedForCurrentEpoch)
        assertFalse(privateField(resource, "bootstrapReadyPublished") as Boolean)
        assertEquals(0, cssApplications)
        assertEquals(0, p2CallbackCount)
        assertEquals(0, readyCount)

        resource.applyCssForLayoutGeneration(
            nextLayoutGeneration = 2,
            preferenceGeneration = 3,
            transactionGeneration = 3,
        ) { p3Applied = it }
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(1, cssApplications)
        assertEquals(true, p3Applied)
        assertTrue(resource.cssAppliedForCurrentEpoch)
        assertTrue(privateField(resource, "bootstrapReadyPublished") as Boolean)
        assertEquals(1, readyCount)
        val owner = requireNotNull(privateField(resource, "cssOwner"))
        assertEquals(3L, privateField(owner, "preferenceGeneration"))
        assertEquals(3L, privateField(owner, "transactionGeneration"))
        resource.dispose()
    }

    @Test fun `revoked observer acknowledgement cannot publish CSS or bootstrap readiness`() {
        var holdObserverAck = false
        val executor = RawCallbackJavascriptExecutor(
            callbackFor = { javascript ->
                when {
                    javascript == READIUM_RUNTIME_PROBE -> "true"
                    javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                    else -> "null"
                }
            },
            shouldHold = { javascript ->
                holdObserverAck && javascript.contains("__biblioLifeContinuousResizeObserver")
            },
        )
        var cssApplications = 0
        var p2CallbackCount = 0
        var readyCount = 0
        val resource = resource(
            index = 0,
            generation = 105,
            executor = executor,
            applyReadiumCss = { _, _, _, _, done ->
                cssApplications += 1
                done(true)
            },
        ).apply {
            onPageReady = { readyCount += 1 }
        }
        attachToProductionWindow(resource)
        assertTrue(resource.deferCssUntilBootstrap(1, 2, 2) { p2CallbackCount++ })
        finishProductionPageLoad(resource)
        assertTrue(
            resource.dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(
                    ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD,
                ),
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(1, cssApplications)
        assertTrue(resource.cssAppliedForCurrentEpoch)
        assertEquals(1, readyCount)

        holdObserverAck = true
        var p3CallbackCount = 0
        resource.applyCssForLayoutGeneration(2, 3, 3) { p3CallbackCount++ }
        assertEquals(2, cssApplications)
        assertTrue(resource.cssApplicationPending)
        assertFalse(resource.cssAppliedForCurrentEpoch)
        assertEquals(1, executor.heldEvaluationCount)
        assertTrue(resource.revokeCssMutationOwnerForPreference(3) != null)
        executor.releaseHeldEvaluations()
        shadowOf(android.os.Looper.getMainLooper()).idle()

        assertFalse(resource.cssAppliedForCurrentEpoch)
        assertEquals(0, p3CallbackCount)
        assertEquals(1, p2CallbackCount)
        assertEquals(1, readyCount)
        resource.dispose()
    }

    @Test fun `handoff during pending observer acknowledgement reapplies CSS under ambient owner`() = runBlocking {
        var holdObserverAck = false
        val executor = RawCallbackJavascriptExecutor(
            callbackFor = { javascript ->
                when {
                    javascript == READIUM_RUNTIME_PROBE -> "true"
                    javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                    else -> "null"
                }
            },
            shouldHold = { javascript ->
                holdObserverAck && javascript.contains("__biblioLifeContinuousResizeObserver")
            },
        )
        var measurementCount = 0
        var cssApplicationCount = 0
        val resource = resource(
            index = 0,
            generation = 106,
            executor = executor,
            onMeasurement = { measurementCount += 1 },
            applyReadiumCss = { _, _, _, _, done ->
                cssApplicationCount += 1
                done(true)
            },
        )
        attachToProductionWindow(resource)
        finishProductionPageLoad(resource)
        assertTrue(
            resource.dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(
                    ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD,
                ),
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(resource.cssAppliedForCurrentEpoch)
        assertEquals(1, cssApplicationCount)

        holdObserverAck = true
        resource.applyCssForLayoutGeneration(2, 3, 3) { }
        val previewToken = resource.currentCssOwnerToken
        assertTrue(resource.cssApplicationPending)
        assertEquals(1, executor.heldEvaluationCount)

        resource.handoffCssMutationOwner(3, 3)
        val ambientToken = resource.currentCssOwnerToken
        assertTrue(ambientToken != previewToken)
        assertEquals(3, cssApplicationCount)
        assertTrue(resource.cssApplicationPending)
        assertEquals(2, executor.heldEvaluationCount)

        executor.releaseNextHeldEvaluation()
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertFalse(resource.cssAppliedForCurrentEpoch)
        assertTrue(resource.cssApplicationPending)
        resource.receiveMeasurement(1100, resource.currentLayoutGeneration, resource.currentMeasurementEpoch, previewToken)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(0, measurementCount)

        executor.releaseNextHeldEvaluation()
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(resource.cssAppliedForCurrentEpoch)
        assertFalse(resource.cssApplicationPending)
        resource.receiveMeasurement(1200, resource.currentLayoutGeneration, resource.currentMeasurementEpoch, ambientToken)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(1, measurementCount)
        resource.dispose()
    }

    @Test fun `late-created neighbor inherits active owner and revoked bootstrap resumes only on a newer request`() = runBlocking {
        val cssApplications = mutableMapOf<Int, Int>()
        val resources = mutableMapOf<Int, ContinuousResourceView>()
        val readingOrder = listOf(link(0), link(1), link(2))
        val binding = RobolectricContinuousReflowHostTestBinding()
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "test-late-created-reflow-neighbor"

            override fun create(
                context: android.content.Context, publication: Publication, link: Link,
                index: Int, layoutGeneration: Int, resourceGeneration: Long,
                sessionInstanceId: String, hostId: String,
                onMeasurement: (ResourceLayoutMeasurement) -> Unit,
            ): ContinuousResourceView {
                val executor = RawCallbackJavascriptExecutor { javascript ->
                    when {
                        javascript == READIUM_RUNTIME_PROBE -> "true"
                        javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                        else -> "null"
                    }
                }
                return ContinuousResourceView(
                    context = context,
                    index = index,
                    layoutGeneration = layoutGeneration,
                    resourceGeneration = resourceGeneration,
                    url = "https://readium_assets/${link.url()}",
                    configure = { _, _, _, _ -> },
                    applyReadiumCss = { _, cssIndex, _, _, done ->
                        cssApplications[cssIndex] = (cssApplications[cssIndex] ?: 0) + 1
                        done(cssApplications[cssIndex] != 4)
                    },
                    publication = publication,
                    link = link,
                    onMeasurement = onMeasurement,
                    sessionInstanceId = sessionInstanceId,
                    hostId = hostId,
                    javascriptExecutor = executor,
                ).also { resources[index] = it }
            }
        }
        val host = ContinuousReflowableHostView(
            context = context,
            publication = publication(*readingOrder.toTypedArray()),
            readingOrder = readingOrder,
            resourceFactory = factory,
            testBinding = binding,
        )
        host.prepareTargetResource(0)
        val initialTarget = requireNotNull(binding.createdTarget)
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setContentView(FrameLayout(activity).apply { addView(host, FrameLayout.LayoutParams(1080, 1800)) })
        host.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1800, View.MeasureSpec.EXACTLY))
        host.layout(0, 0, 1080, 1800)
        binding.materializeTarget(initialTarget, width = 1080, height = 1800)
        val anchor = requireNotNull(resources[0])
        val anchorWebView = anchor.getChildAt(0) as WebView
        shadowOf(anchorWebView).webViewClient.onPageFinished(anchorWebView, "https://readium_assets/finished.xhtml")
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(anchor.dispatchBootstrapBridgeEvent(ContinuousRawBootstrapBridgeEvent(ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD)))
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(anchor.canFindLocator)
        assertEquals(1, cssApplications[0])

        host.beginGeometryReflowPinLease()
        host.applyInPlaceLayoutGeneration(
            ContinuousGeometryReflowTransaction(
                generation = 71,
                anchor = ContinuousAnchorLocator(
                    index = 0,
                    resourceGeneration = anchor.generation,
                    layoutGeneration = anchor.currentLayoutGeneration,
                    localY = 80.0,
                    locator = targetLocator(0),
                ),
                requestedPreferences = EpubPreferences(fontSize = 1.2),
            ),
            preferenceGeneration = 71,
        )
        assertEquals(2, cssApplications[0])

        // The production pin path creates this resource after
        // applyInPlaceLayoutGeneration has enumerated the live resources.
        assertFalse(resources.containsKey(2))
        host.pinResource(2, ContinuousResourcePinReason.SELECTION)
        val lateTarget = requireNotNull(binding.createdTarget)
        assertEquals(2, lateTarget.index)
        val lateNeighbor = requireNotNull(resources[2])
        val inheritedOwner = requireNotNull(privateField(lateNeighbor, "cssOwner"))
        assertEquals(71L, privateField(inheritedOwner, "preferenceGeneration"))
        assertEquals(71L, privateField(inheritedOwner, "transactionGeneration"))
        assertEquals(0, cssApplications[2] ?: 0)

        host.awaitCssOwnerDrain(host.revokePreferenceCssOwners(71))
        val revokedOwnerToken = lateNeighbor.currentCssOwnerToken
        assertFalse(lateNeighbor.canFindLocator)
        assertFalse(lateNeighbor.cssAppliedForCurrentEpoch)
        assertEquals(0, cssApplications[2] ?: 0)
        lateNeighbor.receiveMeasurement(
            999,
            lateNeighbor.currentLayoutGeneration,
            lateNeighbor.currentMeasurementEpoch,
            revokedOwnerToken,
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(800L, lateNeighbor.currentHeightPx)

        // A newer valid non-geometric preference request explicitly transfers
        // this pending resource out of the revoked P2 bootstrap tombstone.
        host.applyCurrentReadiumCssToLiveResources(preferenceGeneration = 72)
        assertEquals(3, cssApplications[0])
        assertEquals(0, cssApplications[2] ?: 0)
        assertEquals(null, privateField(privateField(lateNeighbor, "cssOwner")!!, "preferenceGeneration"))
        assertFalse(privateField(lateNeighbor, "deferredBootstrapCssRevoked") as Boolean)
        val deferred = privateField(lateNeighbor, "deferredBootstrapCss")!!
        assertEquals(null, privateField(privateField(deferred, "owner")!!, "preferenceGeneration"))

        // A partial CSS-only failure is not promoted to ambient ownership on
        // either the already-ready anchor or the still-loading neighbor.
        host.applyCurrentReadiumCssToLiveResources(preferenceGeneration = 73)
        assertEquals(4, cssApplications[0])
        assertTrue(privateField(host, "activeGeometryCssOwner")?.let { privateField(it, "revoked") as Boolean } == true)
        assertEquals(null, privateField(lateNeighbor, "deferredBootstrapCss"))
        assertTrue(privateField(lateNeighbor, "deferredBootstrapCssRevoked") as Boolean)
        host.dispose()
    }

    @Test fun `late initial CSS completion cannot suppress current epoch bootstrap readiness`() {
        val executor = RawCallbackJavascriptExecutor { javascript ->
            when {
                javascript == READIUM_RUNTIME_PROBE -> "true"
                javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                else -> "null"
            }
        }
        val cssCompletions = mutableListOf<(Boolean) -> Unit>()
        var publishedReadyCount = 0
        val resource = ContinuousResourceView(
            context = context,
            index = 0,
            layoutGeneration = 0,
            resourceGeneration = 44,
            url = "https://readium_assets/OEBPS/chapter-0.xhtml",
            configure = { _, _, _, _ -> },
            applyReadiumCss = { _, _, _, _, complete -> cssCompletions += complete },
            publication = publication(link(0)),
            link = link(0),
            onMeasurement = {},
            sessionInstanceId = "test-bootstrap-race",
            hostId = "test-bootstrap-race",
            javascriptExecutor = executor,
        )
        resource.onPageReady = { publishedReadyCount += 1 }
        attachToProductionWindow(resource)
        finishProductionPageLoad(resource)
        assertTrue(resource.dispatchBootstrapBridgeEvent(ContinuousRawBootstrapBridgeEvent(ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD)))
        shadowOf(android.os.Looper.getMainLooper()).runToEndOfTasks()
        assertEquals(1, cssCompletions.size)

        var reflowApplied: Boolean? = null
        resource.applyCssForLayoutGeneration(1) { reflowApplied = it }
        assertEquals(2, cssCompletions.size)
        cssCompletions[1](true)
        shadowOf(android.os.Looper.getMainLooper()).runToEndOfTasks()
        assertEquals(true, reflowApplied)
        assertTrue(resource.cssAppliedForCurrentEpoch)
        assertEquals(1, publishedReadyCount)

        cssCompletions[0](true)
        shadowOf(android.os.Looper.getMainLooper()).runToEndOfTasks()
        assertEquals(1, publishedReadyCount)
        assertEquals(1, resource.currentLayoutGeneration)
        assertTrue(resource.cssAppliedForCurrentEpoch)
        resource.dispose()
    }
    private val context get() = RuntimeEnvironment.getApplication()
    private fun link(index: Int) = Link(Url("OEBPS/chapter-$index.xhtml")!!, MediaType.XHTML)
    private fun publication(vararg links: Link) = Publication(Manifest(metadata = Metadata(), readingOrder = links.toList()))

    private class RawCallbackJavascriptExecutor(
        private val shouldHold: (String) -> Boolean = { false },
        private val callbackFor: (String) -> String,
    ) : R2JavascriptExecutor {
        val commands = mutableListOf<String>()
        private val heldEvaluations = mutableListOf<() -> Unit>()
        val heldEvaluationCount: Int get() = heldEvaluations.size

        override fun evaluate(webView: R2BasicWebView, javascript: String, callback: (String) -> Unit) {
            commands += javascript
            val completion = { callback(callbackFor(javascript)) }
            if (shouldHold(javascript)) heldEvaluations += completion else completion()
        }

        fun releaseHeldEvaluations() {
            heldEvaluations.toList().also { heldEvaluations.clear() }.forEach { it() }
        }

        fun releaseNextHeldEvaluation() {
            heldEvaluations.removeAt(0).invoke()
        }
    }

    private fun resource(
        index: Int,
        generation: Long,
        executor: R2JavascriptExecutor,
        onMeasurement: (ResourceLayoutMeasurement) -> Unit = {},
        applyReadiumCss: (R2BasicWebView, Int, Long, Long, (Boolean) -> Unit) -> Unit = { _, _, _, _, done -> done(true) },
    ) = ContinuousResourceView(
        context = context,
        index = index,
        layoutGeneration = 0,
        resourceGeneration = generation,
        url = "https://readium_assets/OEBPS/chapter-$index.xhtml",
        configure = { _, _, _, _ -> },
        applyReadiumCss = applyReadiumCss,
        publication = publication(link(index)),
        link = link(index),
        onMeasurement = onMeasurement,
        sessionInstanceId = "test-resource",
        hostId = "test-host",
        javascriptExecutor = executor,
    )

    private fun finishProductionPageLoad(resource: ContinuousResourceView) {
        val webView = resource.getChildAt(0) as WebView
        shadowOf(webView).webViewClient.onPageFinished(webView, "https://readium_assets/finished.xhtml")
        shadowOf(android.os.Looper.getMainLooper()).runToEndOfTasks()
    }

    private fun privateField(instance: Any, name: String): Any? =
        instance.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(instance)

    private fun attachToProductionWindow(resource: ContinuousResourceView): Activity {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setContentView(FrameLayout(activity).apply { addView(resource) })
        shadowOf(android.os.Looper.getMainLooper()).runToEndOfTasks()
        return activity
    }

    private data class HostBarrierHarness(
        val host: ContinuousReflowableHostView,
        val port: ControlledContinuousReflowEventPort,
        val binding: RobolectricContinuousReflowHostTestBinding,
        val createdTargets: MutableList<ContinuousReflowTarget>,
    )

    private enum class HostBarrierEvent { READY, MEASUREMENT, LAYOUT }

    private data class HostBarrierCase(
        val name: String,
        val events: List<HostBarrierEvent>,
        val barrierEventIndex: Int,
    )

    private fun targetLocator(index: Int = 6) = Locator(
        href = Url("OEBPS/chapter-$index.xhtml")!!,
        mediaType = MediaType.XHTML,
        locations = Locator.Locations(progression = 0.4),
    )

    private fun transaction(locator: Locator, generation: Long = 1) = ContinuousGeometryReflowTransaction(
        generation = generation,
        anchor = ContinuousAnchorLocator(
            index = 6,
            resourceGeneration = 0,
            layoutGeneration = 0,
            localY = 120.0,
            locator = locator,
        ),
        requestedPreferences = EpubPreferences(fontSize = 1.2),
    )

    private fun hostBarrierHarness(): HostBarrierHarness {
        val readingOrder = (0..20).map(::link)
        val port = ControlledContinuousReflowEventPort().apply {
            offsetAnswer = 120.0
            pointGeometryAnswer = ContinuousLocatorPointGeometry(
                documentYCssPx = 120.0,
                viewportTopCssPx = 120.0,
            )
        }
        val binding = RobolectricContinuousReflowHostTestBinding()
        val createdTargets = mutableListOf<ContinuousReflowTarget>()
        val executor = RawCallbackJavascriptExecutor { javascript ->
            when {
                javascript == READIUM_RUNTIME_PROBE -> "true"
                javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                else -> "null"
            }
        }
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "test-host-barrier"
            override fun create(
                context: android.content.Context, publication: Publication, link: Link,
                index: Int, layoutGeneration: Int, resourceGeneration: Long,
                sessionInstanceId: String, hostId: String,
                onMeasurement: (ResourceLayoutMeasurement) -> Unit,
            ) = ContinuousResourceView(
                context = context,
                index = index,
                layoutGeneration = layoutGeneration,
                resourceGeneration = resourceGeneration,
                url = "https://readium_assets/${link.url()}",
                configure = { _, _, _, _ -> },
                applyReadiumCss = { _, _, _, _, done -> done(true) },
                publication = publication,
                link = link,
                onMeasurement = onMeasurement,
                sessionInstanceId = sessionInstanceId,
                hostId = hostId,
                javascriptExecutor = executor,
            ).also { createdTargets += ContinuousReflowTarget(index, layoutGeneration, resourceGeneration) }
        }
        return HostBarrierHarness(
            host = ContinuousReflowableHostView(
                context = context,
                publication = publication(*readingOrder.toTypedArray()),
                readingOrder = readingOrder,
                resourceFactory = factory,
                reflowEventPort = port,
                testBinding = binding,
            ),
            port = port,
            binding = binding,
            createdTargets = createdTargets,
        )
    }

    private fun HostBarrierHarness.attachTarget(target: ContinuousReflowTarget) {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setContentView(FrameLayout(activity).apply { addView(host) })
        binding.materializeTarget(target, width = 1080, height = 600)
        val resource = checkNotNull(binding.attachedMaterialization(target)).resource
        // Keep the barrier test's READY event ordering under its explicit test
        // driver while satisfying the production CSS/observer gate for samples.
        resource.onPageReady = {}
        val webView = resource.getChildAt(0) as WebView
        shadowOf(webView).webViewClient.onPageFinished(webView, "https://readium_assets/finished.xhtml")
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(
            resource.dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(
                    ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD,
                ),
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(resource.cssAppliedForCurrentEpoch)
    }

    private fun ControlledContinuousReflowEventPort.deliver(
        event: HostBarrierEvent,
        target: ContinuousReflowTarget,
        measurementGeneration: Long = 1,
    ) {
        when (event) {
            HostBarrierEvent.READY -> trueReady(target)
            HostBarrierEvent.MEASUREMENT -> measurement(
                ResourceLayoutMeasurement(
                    index = target.index,
                    heightPx = 1_200,
                    layoutGeneration = target.layoutGeneration,
                    resourceGeneration = target.resourceGeneration,
                    measurementGeneration = measurementGeneration,
                ),
            )
            HostBarrierEvent.LAYOUT -> recyclerLayoutCommitted()
        }
    }

    @Test fun `raw bootstrap JS bridge event drives the production resource from loading to true ready`() {
        val executor = RawCallbackJavascriptExecutor { javascript ->
            when {
                javascript == READIUM_RUNTIME_PROBE -> "true"
                javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                else -> "null"
            }
        }
        val resource = resource(index = 12, generation = 4, executor = executor)
        attachToProductionWindow(resource)
        var trueReady = 0
        resource.onPageReady = { trueReady += 1 }

        finishProductionPageLoad(resource)
        assertFalse("the real R2BasicWebView resource starts LOADING", resource.canFindLocator)

        assertTrue(
            resource.dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(
                    ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD,
                ),
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).runToEndOfTasks()

        assertTrue("production bootstrap state must reach TRUE_READY", resource.canFindLocator)
        assertEquals(1, trueReady)
        assertTrue(executor.commands.contains(READIUM_RUNTIME_PROBE))
    }

    @Test fun `raw bootstrap events are resource local and reject late G1 plus disposed delivery`() {
        val executor = RawCallbackJavascriptExecutor { if (it == READIUM_RUNTIME_PROBE) "true" else "null" }
        val g1 = resource(index = 700, generation = 1, executor = executor)
        attachToProductionWindow(g1)
        finishProductionPageLoad(g1)
        g1.dispose()
        val g2 = resource(index = 700, generation = 2, executor = executor)
        attachToProductionWindow(g2)
        finishProductionPageLoad(g2)

        val loaded = ContinuousRawBootstrapBridgeEvent(
            ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD,
        )
        assertFalse("late G1 bridge delivery is rejected by its disposed resource", g1.dispatchBootstrapBridgeEvent(loaded))
        assertFalse(g1.canFindLocator)
        assertTrue("the same raw event reaches only G2's production handler", g2.dispatchBootstrapBridgeEvent(loaded))
        shadowOf(android.os.Looper.getMainLooper()).runToEndOfTasks()
        assertTrue(g2.canFindLocator)
        g2.dispose()
        assertFalse("disposed resource rejects raw bridge delivery", g2.dispatchBootstrapBridgeEvent(loaded))
    }

    @Test fun `host barrier restores exactly once across seven ready measurement layout orders`() = runBlocking {
        val cases = listOf(
            HostBarrierCase("A ready measurement layout", listOf(HostBarrierEvent.READY, HostBarrierEvent.MEASUREMENT, HostBarrierEvent.LAYOUT), 2),
            HostBarrierCase("B measurement ready layout", listOf(HostBarrierEvent.MEASUREMENT, HostBarrierEvent.READY, HostBarrierEvent.LAYOUT), 2),
            HostBarrierCase("C measurement layout ready", listOf(HostBarrierEvent.MEASUREMENT, HostBarrierEvent.LAYOUT, HostBarrierEvent.READY), 2),
            HostBarrierCase("D ready layout measurement subsequent layout", listOf(HostBarrierEvent.READY, HostBarrierEvent.LAYOUT, HostBarrierEvent.MEASUREMENT, HostBarrierEvent.LAYOUT), 3),
            HostBarrierCase("E duplicate ready", listOf(HostBarrierEvent.READY, HostBarrierEvent.READY, HostBarrierEvent.MEASUREMENT, HostBarrierEvent.LAYOUT), 3),
            HostBarrierCase("F duplicate measurement", listOf(HostBarrierEvent.READY, HostBarrierEvent.MEASUREMENT, HostBarrierEvent.MEASUREMENT, HostBarrierEvent.LAYOUT), 3),
            HostBarrierCase("G duplicate layout", listOf(HostBarrierEvent.READY, HostBarrierEvent.MEASUREMENT, HostBarrierEvent.LAYOUT, HostBarrierEvent.LAYOUT), 2),
        )

        cases.forEachIndexed { caseIndex, case ->
            val harness = hostBarrierHarness()
            val locator = targetLocator()
            val restore = async(start = CoroutineStart.UNDISPATCHED) {
                harness.host.restoreAfterGeometryReflow(
                    locator = locator,
                    transaction = transaction(locator, generation = caseIndex.toLong() + 1),
                    isTransactionCurrent = { true },
                )
            }
            val target = requireNotNull(harness.createdTargets.singleOrNull { it.index == 6 })
            assertTrue("${case.name}: direct target 6 must be created", harness.createdTargets.any { it.index == 6 })
            assertTrue("${case.name}: direct target must not materialize the 0 to 5 prefix", harness.createdTargets.none { it.index < 6 })
            assertTrue("${case.name}: direct target window must stay bounded", harness.createdTargets.size <= 9)
            harness.attachTarget(target)
            assertEquals("${case.name}: attachment alone is below the barrier", 0, harness.binding.restoreCount)

            case.events.forEachIndexed { eventIndex, event ->
                harness.port.deliver(event, target)
                yield()
                val expected = if (eventIndex < case.barrierEventIndex) 0 else 1
                assertEquals("${case.name}: event[$eventIndex]=$event", expected, harness.binding.restoreCount)
            }

            harness.port.deliver(HostBarrierEvent.READY, target)
            harness.port.deliver(HostBarrierEvent.MEASUREMENT, target, measurementGeneration = 2)
            harness.port.deliver(HostBarrierEvent.LAYOUT, target)
            yield()
            assertEquals("${case.name}: duplicate callbacks must not restore twice", 1, harness.binding.restoreCount)
            restore.cancelAndJoin()
            harness.host.dispose()
        }
    }

    @Test fun `stale resource and layout generation callbacks cannot open the host barrier`() = runBlocking {
        val harness = hostBarrierHarness()
        val locator = targetLocator()
        val restore = async(start = CoroutineStart.UNDISPATCHED) {
            harness.host.restoreAfterGeometryReflow(locator, transaction(locator), isTransactionCurrent = { true })
        }
        val target = requireNotNull(harness.createdTargets.singleOrNull { it.index == 6 })
        harness.attachTarget(target)

        listOf(
            target.copy(resourceGeneration = target.resourceGeneration - 1),
            target.copy(layoutGeneration = target.layoutGeneration - 1),
        ).forEach { stale ->
            harness.port.deliver(HostBarrierEvent.READY, stale)
            harness.port.deliver(HostBarrierEvent.MEASUREMENT, stale)
            harness.port.deliver(HostBarrierEvent.LAYOUT, stale)
            yield()
            assertEquals("stale target=$stale", 0, harness.binding.restoreCount)
        }

        restore.cancelAndJoin()
        harness.host.dispose()
    }

    @Test fun `superseded host transaction cancels at the barrier without restore`() = runBlocking {
        val harness = hostBarrierHarness()
        val locator = targetLocator()
        val transaction = transaction(locator)
        var isCurrent = true
        val restore = async(start = CoroutineStart.UNDISPATCHED) {
            harness.host.restoreAfterGeometryReflow(locator, transaction, isTransactionCurrent = { isCurrent })
        }
        val target = requireNotNull(harness.createdTargets.singleOrNull { it.index == 6 })
        harness.attachTarget(target)
        isCurrent = false

        harness.port.deliver(HostBarrierEvent.READY, target)
        harness.port.deliver(HostBarrierEvent.MEASUREMENT, target)
        harness.port.deliver(HostBarrierEvent.LAYOUT, target)
        yield()

        assertEquals(ContinuousReflowRestoreOutcome.Cancelled, restore.await())
        assertEquals(ContinuousGeometryReflowTransaction.State.CANCELLED, transaction.state)
        assertEquals(0, harness.binding.restoreCount)
        harness.host.dispose()
    }

    @Test fun `supersede wakes an active readiness barrier without restoring stale anchor`() = runBlocking {
        val harness = hostBarrierHarness()
        val locator = targetLocator()
        val transaction = transaction(locator)
        val restore = async(start = CoroutineStart.UNDISPATCHED) {
            harness.host.restoreAfterGeometryReflow(locator, transaction, isTransactionCurrent = { true })
        }
        val target = requireNotNull(harness.createdTargets.singleOrNull { it.index == 6 })
        harness.attachTarget(target)

        harness.host.cancelGeometryReflowWaiters()

        assertEquals(ContinuousReflowRestoreOutcome.Cancelled, restore.await())
        assertEquals(0, harness.binding.restoreCount)
        harness.host.dispose()
    }

    @Test fun `real holder bootstrap locator command and raw callback retain the semantic anchor at resource 700`() = runBlocking {
        val commands = mutableListOf<String>()
        val executor = RawCallbackJavascriptExecutor { javascript ->
            when {
                javascript == READIUM_RUNTIME_PROBE -> "true"
                javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                javascript.contains("readium.findLocatorAtPoint(") ->
                    """{"href":"#","type":"application/xhtml+xml","locations":{"cssSelector":"p:nth-child(4)","progression":0.375},"text":{"highlight":"semantic text"}}"""
                else -> "null"
            }
        }
        val readingOrder = (0..700).map(::link)
        val binding = RobolectricContinuousReflowHostTestBinding()
        val createdIndices = mutableListOf<Int>()
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "test-bootstrap"
            override fun create(
                context: android.content.Context, publication: Publication, link: Link,
                index: Int, layoutGeneration: Int, resourceGeneration: Long,
                sessionInstanceId: String, hostId: String,
                onMeasurement: (ResourceLayoutMeasurement) -> Unit,
            ) = ContinuousResourceView(
                context = context,
                index = index,
                layoutGeneration = layoutGeneration,
                resourceGeneration = resourceGeneration,
                url = "https://readium_assets/${link.url()}",
                configure = { _, _, _, _ -> },
                applyReadiumCss = { _, _, _, _, done -> done(true) },
                publication = publication,
                link = link,
                onMeasurement = onMeasurement,
                sessionInstanceId = sessionInstanceId,
                hostId = hostId,
                javascriptExecutor = executor,
            ).also { createdIndices += index }
        }
        val host = ContinuousReflowableHostView(
            context = context,
            publication = publication(*readingOrder.toTypedArray()),
            readingOrder = readingOrder,
            resourceFactory = factory,
            testBinding = binding,
        )
        Robolectric.buildActivity(Activity::class.java).setup().get().setContentView(
            FrameLayout(context).apply { addView(host) },
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        host.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY),
        )
        host.layout(0, 0, 1080, 600)

        val createdBeforeDirectTarget = createdIndices.size
        host.prepareTargetResource(700)
        val target700 = requireNotNull(binding.createdTarget)
        assertEquals(700, target700.index)
        binding.materializeTarget(target700, height = 600)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        host.prepareTargetResource(700)
        binding.materializeTarget(target700, height = 600)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        val materialization = requireNotNull(binding.attachedMaterialization(target700))
        assertEquals(700, materialization.target.index)
        val directTargetMaterializations = createdIndices.drop(createdBeforeDirectTarget)
        assertTrue(directTargetMaterializations.contains(700))
        assertTrue(
            "direct target materialization is bounded and never expands to the 0..699 prefix",
            directTargetMaterializations.size <= 16,
        )
        finishProductionPageLoad(materialization.resource)
        assertFalse(materialization.resource.canFindLocator)

        assertTrue(
            materialization.resource.dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(
                    ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD,
                ),
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(materialization.resource.canFindLocator)
        binding.materializeTarget(target700, width = 1080, height = 600)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(materialization, binding.attachedMaterialization(target700))

        assertNull(
            "Robolectric does not expose a real attached child through findChildViewUnder(); this JVM seam must not fake a physical hit just to synthesize currentLocatorAnchor()",
            host.currentLocatorAnchor(),
        )
        val locator = requireNotNull(
            ContinuousResourceLocatorNormalizer.normalize(
                resourceLocator = requireNotNull(materialization.resource.findLocatorAtPoint(540.0, 150.0)),
                readingOrderLink = readingOrder[700],
            ),
        )

        assertTrue("the resource-local R2BasicWebView must receive the actual Locator command", executor.commands.any { it.contains("readium.findLocatorAtPoint(") })
        assertEquals("OEBPS/chapter-700.xhtml", locator.href.toString())
        assertEquals(0.375, locator.locations.progression)
        assertEquals("p:nth-child(4)", locator.locations["cssSelector"])
        assertEquals("semantic text", locator.text.highlight)
    }
}
