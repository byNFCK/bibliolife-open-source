@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
package org.readium.r2.navigator.epub.continuous

import android.app.Activity
import android.view.View
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.LinearLayoutManager
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.R2JavascriptExecutor
import org.readium.r2.shared.publication.*
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class ContinuousInitialLocatorRestoreTest {
    @Test fun `saved halfway position is applied before verification`() = runBlocking { restoreCase() }
    @Test fun `late target measurement cannot replace a queued saved-position restore`() = runBlocking {
        restoreCase(changeGeometry = true)
    }
    @Test fun `changed geometry resolves a fresh semantic offset once`() = runBlocking {
        restoreCase(changeGeometry = true, shiftOffset = true)
    }
    @Test fun `second geometry update at the correct settled saved position must verify`() = runBlocking {
        restoreCase(changeGeometry = true, repeatedInvalidation = true)
    }
    @Test fun `nonzero saved Range at first resource top clamp must verify`() = runBlocking {
        restoreCase(topBoundary = true)
    }
    @Test fun `a different resolved Range cannot pass the top boundary proof`() = runBlocking {
        restoreCase(topBoundary = true, rangeMismatch = true)
    }
    @Test fun `an unresolved saved Range cannot pass the top boundary proof`() = runBlocking {
        restoreCase(topBoundary = true, unresolvedRange = true)
    }
    @Test fun `a second geometry update that moves the saved point cannot pass`() = runBlocking {
        restoreCase(changeGeometry = true, repeatedInvalidation = true, offsetMovesAgain = true)
    }
    @Test fun `measurement during offset recalculation defers correctness to the settled viewport`() = runBlocking {
        restoreCase(changeGeometry = true, invalidateOffsetResolution = true)
    }
    @Test fun `geometry changing inside revalidation cannot publish success`() = runBlocking {
        restoreCase(changeGeometry = true, repeatedInvalidation = true, invalidateRevalidation = true)
    }
    @Test fun `zero-height caret cannot pass nonzero boundary verification`() = runBlocking {
        restoreCase(topBoundary = true, rangeHeightOverride = 0.0)
    }
    @Test fun `Range extending outside the viewport cannot pass boundary verification`() = runBlocking {
        restoreCase(topBoundary = true, rangeHeightOverride = 3000.0)
    }
    @Test fun `disposal releases a queued restore without verification`() = runBlocking {
        restoreCase(stop = "dispose")
    }
    @Test fun `cancellation releases initial authority and rejects stale work`() = runBlocking {
        restoreCase(stop = "cancel")
    }
    @Test fun `unknown resource fails without moving the viewport`() = runBlocking {
        restoreCase(invalidLocator = true)
    }
    @Test fun `separate reopened sessions restore the same saved locator`() = runBlocking {
        repeat(3) { restoreCase(changeGeometry = true) }
    }

    @Test fun `opening without a saved locator reaches its measured first viewport`() = runBlocking {
        restoreCase(withoutSavedLocator = true)
    }

    @Test fun `equivalent saved point after subpixel reflow reaches semantic verification`() = runBlocking {
        restoreCase(changeGeometry = true, repeatedInvalidation = true, equivalentOffsetDrift = true)
    }

    @Test fun `short front matter near resource end verifies after 313 266 260 measurement sequence`() = runBlocking {
        restoreCase(changeGeometry = true, repeatedInvalidation = true, shortResource = true)
    }

    @Test fun `short resource genuinely relocated point fails final verification`() = runBlocking {
        restoreCase(changeGeometry = true, repeatedInvalidation = true, shortResource = true, offsetMovesAgain = true)
    }

    @Test fun `publication origin viewport locator survives serialization disposal and fresh reopening`() = runBlocking {
        var persisted: Locator? = null
        restoreCase(publicationStart = true, onObserved = { observed ->
            persisted = requireNotNull(Locator.fromJSON(observed.toJSON()))
        })
        val saved = requireNotNull(persisted)
        assertEquals("chapter0.xhtml", saved.href.toString())
        assertTrue(requireNotNull(saved.locations.progression) > 0.0)
        assertEquals("p.saved", saved.locations["cssSelector"])
        repeat(5) { restoreCase(publicationStart = true, savedOverride = saved) }
    }

    private suspend fun kotlinx.coroutines.CoroutineScope.restoreCase(
        changeGeometry: Boolean = false,
        shiftOffset: Boolean = false,
        repeatedInvalidation: Boolean = false,
        stop: String? = null,
        invalidLocator: Boolean = false,
        withoutSavedLocator: Boolean = false,
        topBoundary: Boolean = false,
        rangeMismatch: Boolean = false,
        unresolvedRange: Boolean = false,
        offsetMovesAgain: Boolean = false,
        invalidateRevalidation: Boolean = false,
        invalidateOffsetResolution: Boolean = false,
        rangeHeightOverride: Double? = null,
        equivalentOffsetDrift: Boolean = false,
        shortResource: Boolean = false,
        publicationStart: Boolean = false,
        savedOverride: Locator? = null,
        onObserved: ((Locator) -> Unit)? = null,
    ) {
        val index = if (withoutSavedLocator || topBoundary || publicationStart) 0 else if (shortResource) 1 else 2
        val viewportHeight = if (topBoundary || shortResource || publicationStart) 2222 else 2216
        val sourceHeight = if (topBoundary) 8723L else if (shortResource) 313L else 98992L
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val links = (0..if (shortResource) 5 else 2).map { Link(Url("chapter$it.xhtml")!!, MediaType.XHTML) }
        val publication = Publication(Manifest(metadata = Metadata(), readingOrder = links))
        val port = ControlledContinuousReflowEventPort().apply { offsetAnswer = if (topBoundary) 231.56250286102295 else if (shortResource) 154.96875715255737 else if (publicationStart) 555.5 else 54500.37780761719 }
        val binding = RobolectricContinuousReflowHostTestBinding()
        val resources = mutableMapOf<Int, ContinuousResourceView>()
        lateinit var host: ContinuousReflowableHostView
        var offsetQueries = 0
        val events = object : ContinuousReflowEventPort by port {
            override suspend fun resolveLocatorVerticalOffset(target: ContinuousReflowTarget, locator: Locator, runtime: suspend () -> Double?): Double? {
                val answer = port.resolveLocatorVerticalOffset(target, locator, runtime)
                offsetQueries++
                if ((invalidateRevalidation && offsetQueries == 3) || (invalidateOffsetResolution && offsetQueries == 2)) {
                    val live = requireNotNull(resources[target.index])
                    port.measurement(ResourceLayoutMeasurement(target.index, live.currentHeightPx + 17,
                        live.currentLayoutGeneration, live.generation, live.reportedMeasurementGenerationForOpen + 3,
                        live.currentMeasurementEpoch))
                }
                return answer
            }
        }
        val executor = R2JavascriptExecutor { _, script, done ->
            done(when {
                script == READIUM_RUNTIME_PROBE -> "true"
                script.contains("__biblioLifeContinuousResizeObserver") -> "true"
                script.contains("readium.isLocatorRangeAtVerticalAnchor(") -> {
                    val numbers = Regex(", ([0-9.Ee+-]+), ([0-9.Ee+-]+)(?:, true)?\\);$").find(script)
                    val queriedY = numbers?.groupValues?.get(1)?.toDoubleOrNull()
                    val density = activity.resources.displayMetrics.density.toDouble()
                    val rangeY = requireNotNull(port.offsetAnswer) / density + if (rangeMismatch) 20.0 else 0.0
                    val matches = !unresolvedRange && queriedY != null && kotlin.math.abs(queriedY - rangeY) <= 1.0 / density
                    if (script.contains(", true);")) {
                        """{"matches":$matches,"rangeResolved":${!unresolvedRange},"semanticRangeResolved":false,"finiteInputs":true,"rangeCollapsed":true,"rangeTopCssPx":$rangeY,"rangeHeightCssPx":${(rangeHeightOverride ?: 47.0)/density},"windowScrollYCssPx":0.0}"""
                    } else matches.toString()
                }
                script.contains("readium.findLocatorAtPoint(") -> {
                    val localY = host.currentLocatorAnchor()?.y ?: 0.0
                    val saved = kotlin.math.abs(localY - requireNotNull(port.offsetAnswer)) < 4.0
                    val selector = if (saved) "p.saved" else "p.start"
                    val progression = (localY / requireNotNull(resources[index]).currentHeightPx).coerceIn(0.0, 1.0)
                    """{"href":"#","type":"application/xhtml+xml","locations":{"cssSelector":"$selector","progression":$progression}}"""
                }
                else -> "null"
            })
        }
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "initial-restore-measurement-test"
            override fun create(context: android.content.Context, publication: Publication, link: Link,
                index: Int, layoutGeneration: Int, resourceGeneration: Long, sessionInstanceId: String,
                hostId: String, onMeasurement: (ResourceLayoutMeasurement) -> Unit): ContinuousResourceView =
                ContinuousResourceView(context, index, layoutGeneration, resourceGeneration,
                    "https://readium_assets/${link.url()}", { _, _, _, _ -> },
                    { _, _, _, _, done -> done(true) }, publication, link, onMeasurement,
                    sessionInstanceId, hostId, javascriptExecutor = executor,
                ).also { resources[index] = it }
        }
        host = ContinuousReflowableHostView(activity, publication, links, factory, events, binding)
        var ready = 0
        host.setInitialViewportReadyListener { ready++ }
        activity.setContentView(FrameLayout(activity).apply { addView(host, FrameLayout.LayoutParams(1080, viewportHeight)) })
        host.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(viewportHeight, View.MeasureSpec.EXACTLY))
        host.layout(0, 0, 1080, viewportHeight)
        host.pinResource(index, ContinuousResourcePinReason.NAVIGATION_TARGET)
        host.prepareTargetResource(index)
        val target = requireNotNull(binding.createdTarget)
        binding.materializeTarget(target, 1080, viewportHeight)
        val resource = requireNotNull(resources[index])
        val web = resource.getChildAt(0) as WebView
        shadowOf(web).webViewClient.onPageFinished(web, "https://readium_assets/chapter2.xhtml")
        resource.dispatchBootstrapBridgeEvent(ContinuousRawBootstrapBridgeEvent(ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD))
        shadowOf(android.os.Looper.getMainLooper()).idle()
        port.trueReady(target)
        assertEquals(0, ready)
        resource.receiveMeasurement(sourceHeight, resource.currentLayoutGeneration, resource.currentMeasurementEpoch)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        binding.materializeTarget(target, 1080, viewportHeight)
        val recycler = privateField(host, "recyclerView") as RecyclerView
        for (i in 0 until recycler.childCount) {
            val child = recycler.getChildAt(i)
            child.layoutParams = child.layoutParams.apply { width = android.view.ViewGroup.LayoutParams.MATCH_PARENT }
        }
        binding.commitRecyclerViewLayout(1080, viewportHeight)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        if (withoutSavedLocator) {
            assertEquals(1, ready)
            assertFalse((privateField(host, "initialRestoreAuthority") as ContinuousInitialRestoreAuthorityGate).blocksViewportPublication())
            host.dispose()
            return
        }
        if (shortResource) {
            (recycler.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(index, 555)
            binding.commitRecyclerViewLayout(1080, viewportHeight)
        }
        val scrolls = mutableListOf<Pair<Int, Int>>()
        host.scrollToPositionCallObserverForTest = { index, offset -> scrolls += index to offset }
        val locator = savedOverride ?: Locator(if (invalidLocator) Url("missing.xhtml")!! else links[index].url(), MediaType.XHTML,
            locations = if (topBoundary) Locator.Locations(progression = 0.033527696793002916, position = 1, totalProgression = 0.01)
                else Locator.Locations(progression = if (shortResource) 0.9381443298969072 else 0.5126353790613718, otherLocations = mapOf("cssSelector" to "p.saved")))
        var injected = false
        var requests = 0
        val stages = mutableListOf<String>()
        val outcomes = mutableListOf<String>()
        var geometryEvidence: Map<*, *>? = null
        val restore = async(start = CoroutineStart.UNDISPATCHED) {
            host.restoreInitialLocator(locator) { stage, result, facts ->
                stages += "$stage:$result:${facts["failureReason"]}"
                (facts["initialLocatorGeometry"] as? Map<*, *>)?.let { geometryEvidence = it }
                (facts["positioningOutcome"] as? String)?.let(outcomes::add)
                if (stage == "viewport_positioning" && facts["positioningOutcome"] == "position_accepted") {
                    requests++
                    if (!injected) {
                        injected = true
                        if (changeGeometry) {
                            if (shiftOffset) port.offsetAnswer = 56000.0
                            if (shortResource) port.offsetAnswer = 150.26562881469727
                            port.measurement(ResourceLayoutMeasurement(index, if (shortResource) 266 else 103349, resource.currentLayoutGeneration,
                                resource.generation, resource.reportedMeasurementGenerationForOpen + 1,
                                resource.currentMeasurementEpoch))
                            assertEquals(if (shortResource) 266L else 103349L, resource.currentHeightPx)
                        }
                    } else if (repeatedInvalidation) {
                        if (shortResource) port.offsetAnswer = 149.67187356948853
                        if (offsetMovesAgain) port.offsetAnswer = 57000.0
                        if (equivalentOffsetDrift) port.offsetAnswer = requireNotNull(port.offsetAnswer) - 1.5
                        port.measurement(ResourceLayoutMeasurement(index, if (shortResource) 260 else 104000, resource.currentLayoutGeneration,
                            resource.generation, resource.reportedMeasurementGenerationForOpen + 2,
                            resource.currentMeasurementEpoch))
                    }
                }
            }
        }
        try {
            yield()
            if (invalidLocator) {
                assertFalse(restore.await())
                assertTrue(stages.any { it.contains("target_not_in_reading_order") })
                assertTrue(scrolls.isEmpty())
                return
            }
            repeat(3) {
                if (!injected) {
                    binding.commitRecyclerViewLayout(1080, viewportHeight)
                    yield()
                    shadowOf(android.os.Looper.getMainLooper()).idle()
                    yield()
                }
            }
            assertTrue("The measurement must occur after the saved-position request; stages=$stages completed=${restore.isCompleted}", injected)
            assertEquals("A measurement must not overwrite the queued offset: $scrolls", if (topBoundary) 323 else if (publicationStart) 0 else if (shortResource) 400 else -53946, scrolls.last().second)
            // A global-layout notification alone cannot consume the pending
            // LinearLayoutManager command or authorize viewport verification.
            port.recyclerLayoutCommitted()
            yield()
            assertFalse(restore.isCompleted)
            assertFalse(outcomes.contains("position_applied"))
            assertFalse(outcomes.contains("position_settled"))
            assertFalse(stages.any { it.startsWith("viewport_verification:") })
            if (stop != null) {
                if (stop == "dispose") {
                    host.dispose()
                    assertFalse(restore.await())
                } else {
                    restore.cancel()
                    restore.join()
                    assertFalse(privateField(host, "initialRestoreAuthority")
                        .let { it as ContinuousInitialRestoreAuthorityGate }.blocksViewportPublication())
                }
                assertTrue((privateField(host, "postRestoreLayoutWaiters") as Map<*, *>).isEmpty())
                port.recyclerLayoutCommitted()
                assertFalse(stages.any { it.startsWith("viewport_verification:") })
                return
            }
            repeat(6) {
                binding.commitRecyclerViewLayout(1080, viewportHeight)
                yield()
                shadowOf(android.os.Looper.getMainLooper()).idle()
                yield()
            }
            assertTrue("Restore did not finish after its controlled layout", restore.isCompleted)
            if (repeatedInvalidation && !offsetMovesAgain && !invalidateRevalidation && !equivalentOffsetDrift && !shortResource) {
                assertEquals("Tail-height changes must leave the saved viewport at its real point", requireNotNull(port.offsetAnswer), requireNotNull(host.currentLocatorAnchor()).y, 2.0)
            }
            if (shortResource) {
                val geometry = requireNotNull(geometryEvidence)
                for ((phase, top, height) in listOf(Triple("beforePositioning", 555, 313), Triple("beforeRecovery", 400, 266), Triple("afterRecovery", 404, 260))) {
                    val sample = requireNotNull(geometry[phase] as? Map<*, *>)
                    assertEquals("$phase top", top, sample["resourceTopPx"])
                    assertEquals("$phase height", height, sample["resourceHeightPx"])
                }
            }
            if (offsetMovesAgain || rangeMismatch || unresolvedRange || invalidateRevalidation || rangeHeightOverride != null) {
                assertFalse("Incorrect or unresolved positions must fail; $stages", restore.await())
                if (offsetMovesAgain) {
                    assertTrue("A genuine mismatch must reach mandatory viewport proof: $stages", stages.any { it.startsWith("viewport_verification:failed") })
                    assertEquals(2, requests)
                }
            } else {
                assertTrue("Saved position must converge in the actual laid-out target; $stages", restore.await())
                assertEquals(if (changeGeometry) 2 else 1, requests)
                assertTrue(outcomes.indexOf("position_requested") < outcomes.indexOf("position_accepted"))
                assertTrue(outcomes.indexOf("position_accepted") < outcomes.indexOf("position_applied"))
                assertTrue(outcomes.lastIndexOf("position_applied") < outcomes.indexOf("position_settled"))
                assertEquals(index, host.currentLocatorAnchor()?.readingOrderIndex)
                onObserved?.invoke(requireNotNull(host.findLocatorAtReadingAnchor(requireNotNull(host.currentLocatorAnchor()))))
                if (publicationStart) {
                    assertFalse(recycler.canScrollVertically(-1))
                    assertEquals(0, requireNotNull(recycler.layoutManager?.findViewByPosition(0)).top)
                }
                if (topBoundary) {
                    assertEquals(555.5, requireNotNull(host.currentLocatorAnchor()).y, 0.01)
                    assertFalse(recycler.canScrollVertically(-1))
                    assertEquals(0, requireNotNull(recycler.layoutManager?.findViewByPosition(0)).top)
                    assertTrue(stages.any { it.contains("viewport_verification:success") })
                } else {
                    assertEquals(requireNotNull(port.offsetAnswer), requireNotNull(host.currentLocatorAnchor()).y, if (equivalentOffsetDrift) 3.0 else 2.0)
                }
            }
        } finally {
            restore.cancel()
            host.dispose()
        }
    }

    private fun privateField(instance: Any, name: String): Any = requireNotNull(
        instance.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(instance)
    )
}
