@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import android.app.Activity
import android.view.View
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.readium.r2.navigator.R2BasicWebView
import org.readium.r2.navigator.R2JavascriptExecutor
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import java.util.concurrent.atomic.AtomicLong

@RunWith(RobolectricTestRunner::class)
class ContinuousResourceGeometryTest {
    private val context get() = RuntimeEnvironment.getApplication()

    @Test fun `resource reports only new heights per CSS epoch and rejects stale CSS owners`() {
        val reports = mutableListOf<ResourceLayoutMeasurement>()
        val resource = standaloneResource(index = 0, reports::add)
        finishHostBootstrap(resource)
        var applied: Boolean? = null
        resource.applyCssForLayoutGeneration(1) { applied = it }
        assertEquals(true, applied)
        val firstOwner = resource.currentCssOwnerToken
        val firstEpoch = resource.currentMeasurementEpoch

        fun report(cssHeightPx: Long, owner: Long = resource.currentCssOwnerToken) {
            resource.receiveMeasurement(
                cssHeightPx = cssHeightPx,
                reportedLayoutGeneration = resource.currentLayoutGeneration,
                reportedMeasurementEpoch = resource.currentMeasurementEpoch,
                ownerToken = owner,
            )
            shadowOf(android.os.Looper.getMainLooper()).idle()
        }

        report(700L)
        val first = reports.single()
        assertEquals(1L, first.measurementGeneration)
        report(700L)
        assertEquals("Equal reports in one epoch do not supersede the captured measurement", 1L, measurementGeneration(resource))
        assertEquals(1, reports.size)

        report(703L)
        val changed = reports.last()
        assertEquals(2L, changed.measurementGeneration)
        assertFalse("A real height change invalidates the prior prepared measurement", resource.accepts(first))
        assertTrue(resource.accepts(changed))

        applied = null
        resource.applyCssForLayoutGeneration(2) { applied = it }
        assertEquals(true, applied)
        assertTrue(resource.currentMeasurementEpoch > firstEpoch)
        report(703L)
        assertEquals("The first report of a CSS epoch is retained even at the prior epoch's height", 3L, measurementGeneration(resource))
        val current = reports.last()
        report(900L, owner = firstOwner)
        assertEquals("A report from the previous CSS owner is rejected", 3L, measurementGeneration(resource))
        assertEquals(3, reports.size)
        assertTrue(resource.accepts(current))
        resource.dispose()

        val pendingBootstrapResource = standaloneResource(index = 1) { }
        val lastReportedHeight = pendingBootstrapResource.javaClass.getDeclaredField("lastReportedHeightPx").apply { isAccessible = true }
        lastReportedHeight.set(pendingBootstrapResource, 777L)
        assertTrue(pendingBootstrapResource.deferCssUntilBootstrap(1, 1L, 1L) { })
        val staleBootstrapOwner = pendingBootstrapResource.currentCssOwnerToken
        lastReportedHeight.set(pendingBootstrapResource, 888L)
        assertTrue(pendingBootstrapResource.deferCssUntilBootstrap(2, 2L, 2L) { })
        assertNull("Deferred bootstrap CSS also resets the per-epoch report", lastReportedHeight.get(pendingBootstrapResource))
        pendingBootstrapResource.receiveMeasurement(
            cssHeightPx = 900L,
            reportedLayoutGeneration = pendingBootstrapResource.currentLayoutGeneration,
            reportedMeasurementEpoch = pendingBootstrapResource.currentMeasurementEpoch,
            ownerToken = staleBootstrapOwner,
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(0L, measurementGeneration(pendingBootstrapResource))
        pendingBootstrapResource.dispose()
    }

    private fun locator(
        href: String = "chapter.xhtml",
        selector: String? = ".anchor",
        highlight: String? = "semantic text",
        progression: Double? = 0.4,
        fragments: List<String> = emptyList(),
    ) = Locator(
        href = Url(href)!!,
        mediaType = MediaType.XHTML,
        locations = Locator.Locations(
            fragments = fragments,
            progression = progression,
            otherLocations = selector?.let { mapOf("cssSelector" to it) } ?: emptyMap(),
        ),
        text = Locator.Text(highlight = highlight),
    )

    private fun transaction(index: Int = 6) = ContinuousGeometryReflowTransaction(
        generation = 5,
        anchor = ContinuousAnchorLocator(index, 9, 4, 120.0, locator()),
        requestedPreferences = EpubPreferences(fontSize = 1.2),
    )

    private fun reflowTarget(
        index: Int = 6,
        layoutGeneration: Int = 4,
        resourceGeneration: Long = 10,
    ) = ContinuousReflowTarget(index, layoutGeneration, resourceGeneration)

    @Test fun `native selection blocks parent scroll and viewport publication until its exact owner ends`() {
        val gate = ContinuousSelectionViewportGate()
        val owner = 1 to 42L

        gate.activate(owner)

        assertTrue(gate.blocksParentScroll())
        assertTrue(gate.blocksViewportPublication())
        gate.clear(0 to 41L)
        assertTrue(gate.blocksViewportPublication())

        gate.clear(owner)

        assertFalse(gate.blocksParentScroll())
        assertFalse(gate.blocksViewportPublication())
    }

    @Test fun `neighbor ready and viewport cannot overtake an initial restore target`() {
        val gate = ContinuousInitialRestoreAuthorityGate()
        val target = reflowTarget(index = 14, layoutGeneration = 7, resourceGeneration = 31)
        val neighbor = reflowTarget(index = 13, layoutGeneration = 7, resourceGeneration = 19)

        gate.begin(target.index)
        assertTrue(gate.blocksViewportPublication())
        assertFalse(gate.materialize(neighbor))
        assertNull(gate.geometryTarget())
        assertTrue(gate.materialize(target))
        assertEquals(target, gate.geometryTarget())
        assertFalse(gate.isCurrentTarget(neighbor))
        assertTrue(gate.isCurrentTarget(target))
        assertTrue(gate.blocksViewportPublication())
    }

    @Test fun `initial restore target releases only after its own terminal outcome`() {
        val gate = ContinuousInitialRestoreAuthorityGate()
        val target = reflowTarget(index = 14, layoutGeneration = 7, resourceGeneration = 31)
        val stale = target.copy(resourceGeneration = 30)

        gate.begin(target.index)
        assertTrue(gate.materialize(target))
        gate.finish(stale)
        assertTrue(gate.blocksViewportPublication())
        assertEquals(target, gate.geometryTarget())
        gate.finish(target)
        assertFalse(gate.blocksViewportPublication())
        assertNull(gate.geometryTarget())
    }

    @Test fun `initial restore defers resource readiness until gate release and forwards once`() {
        val deferred = ContinuousInitialRestoreReadyEvents()
        val target = reflowTarget(index = 14, layoutGeneration = 7, resourceGeneration = 31)

        deferred.defer(target)
        deferred.defer(target)

        assertTrue(
            deferred.takeReady(restoreGateBlocksPublication = true) { true }.isEmpty(),
        )
        assertEquals(
            listOf(target),
            deferred.takeReady(restoreGateBlocksPublication = false) { it == target },
        )
        assertTrue(
            deferred.takeReady(restoreGateBlocksPublication = false) { true }.isEmpty(),
        )
    }

    @Test fun `post-restore measurement cannot reset the committed target offset`() {
        val gate = ContinuousInitialRestoreAuthorityGate()
        val target = reflowTarget(index = 14, layoutGeneration = 7, resourceGeneration = 31)

        gate.begin(target.index)
        assertTrue(gate.materialize(target))
        assertFalse(gate.isRestoreCommitted())
        assertTrue(gate.markRestoreCommitted(target))
        assertTrue(gate.isRestoreCommitted())
        assertFalse(gate.markRestoreCommitted(target.copy(resourceGeneration = 30)))
    }

    @Test fun `CSS resource height is converted once to Android layout pixels`() {
        assertEquals(6_300L, continuousCssHeightToLayoutPx(2_400, 2.625))
        assertEquals(263L, continuousCssHeightToLayoutPx(100, 2.625))
    }

    @Test fun `fractional layout height rounds up so WebView cannot retain an internal tail`() {
        assertEquals(264L, continuousCssHeightToLayoutPx(101, 2.61))
    }

    @Test fun `semantic CSS offset is converted into the parent layout coordinate system`() {
        assertEquals(630.0, continuousCssOffsetToLayoutPx(240.0, 2.625))
        assertNull(continuousCssOffsetToLayoutPx(-1.0, 2.625))
    }

    @Test fun `initial fragment restore requires its requested range instead of a nested observed child`() {
        val requested = locator(
            href = "chapter.xhtml",
            selector = null,
            highlight = null,
            progression = 0.26023899165166,
            fragments = listOf("CHAPTER_LXI"),
        )
        val observed = locator(
            href = "chapter.xhtml",
            selector = "#img_images_i_486_a.jpg",
            highlight = null,
            progression = 0.04806023899165166,
        )

        assertFalse(semanticLocatorsConverge(requested, observed))
        assertTrue(initialRestoreRequiresRequestedRangeAnchor(requested, observed))
    }

    @Test fun `initial requested range proof rejects a different resource`() {
        val requested = locator(href = "chapter.xhtml", selector = null, highlight = null, fragments = listOf("CHAPTER_LXI"))
        val observed = locator(href = "other.xhtml", selector = "#img_images_i_486_a.jpg", highlight = null)

        assertFalse(initialRestoreRequiresRequestedRangeAnchor(requested, observed))
    }

    @Test fun `initial requested range proof rejects a different observed fragment`() {
        val requested = locator(href = "chapter.xhtml", selector = null, highlight = null, fragments = listOf("CHAPTER_LIX"))
        val observed = locator(href = "chapter.xhtml", selector = null, highlight = null, fragments = listOf("CHAPTER_LX"))

        assertFalse(initialRestoreRequiresRequestedRangeAnchor(requested, observed))
    }

    @Test fun `initial requested range proof keeps selector and text locators strict`() {
        val observed = locator(href = "chapter.xhtml", selector = "#nested-image", highlight = null)

        assertFalse(initialRestoreRequiresRequestedRangeAnchor(locator(fragments = listOf("CHAPTER_LIX")), observed))
        assertFalse(initialRestoreRequiresRequestedRangeAnchor(locator(selector = null, highlight = "quote", fragments = listOf("CHAPTER_LIX")), observed))
    }

    @Test fun `large fragment range only converges at the same current resource anchor`() {
        val target = reflowTarget(index = 14, layoutGeneration = 7, resourceGeneration = 31)
        val anchor = EpubContinuousLocatorAnchor(
            readingOrderIndex = 14,
            resourceGeneration = 31,
            layoutGeneration = 7,
            x = 360.0,
            y = 554.0,
        )

        assertTrue(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor, geometryReady = true, rangeAtAnchor = true))
        assertFalse(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor.copy(resourceGeneration = 32), geometryReady = true, rangeAtAnchor = true))
        assertFalse(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor.copy(readingOrderIndex = 13), geometryReady = true, rangeAtAnchor = true))
        assertFalse(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor.copy(y = 527.0), geometryReady = true, rangeAtAnchor = true))
        assertFalse(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor, geometryReady = false, rangeAtAnchor = true))
        assertFalse(isInitialRestoreRangeAnchorCurrent(target, anchor, anchor, geometryReady = true, rangeAtAnchor = false))
    }

    @Test fun `invalid and overflowing resource heights are rejected`() {
        assertNull(continuousCssHeightToLayoutPx(0, 2.625))
        assertNull(continuousCssHeightToLayoutPx(100, 0.0))
        assertNull(continuousCssHeightToLayoutPx(100, Double.NaN))
        assertNull(continuousCssHeightToLayoutPx(Int.MAX_VALUE.toLong(), 2.0))
    }

    @Test fun `delayed height above viewport preserves first visible resource and offset`() {
        val anchor = ContinuousViewportLayoutAnchor(index = 4, offsetPx = -120)
        assertEquals(anchor, preservedContinuousViewportAnchor(updatedResourceIndex = 3, anchor))
        assertNull(preservedContinuousViewportAnchor(updatedResourceIndex = 4, anchor))
        assertNull(preservedContinuousViewportAnchor(updatedResourceIndex = 5, anchor))
    }

    @Test fun `measurement of reading anchor resource preserves its point through growth and shrink`() {
        val anchor = ContinuousReadingAnchorLayout(
            index = 4,
            layoutGeneration = 7,
            resourceGeneration = 31,
            viewportY = 554,
            localOffsetPx = 454,
        )
        val live = { index: Int, generation: Long -> index == 4 && generation == 31L }

        listOf(156_674L, 800L).forEach { measuredHeight ->
            assertTrue(measuredHeight > 0L)
            val plan = continuousMeasurementScrollPlan(
                reflowTarget = null,
                measurementIndex = 4,
                readingAnchor = anchor,
                fallbackAnchor = ContinuousViewportLayoutAnchor(index = 4, offsetPx = -355),
                currentLayoutGeneration = 7,
                isLiveResource = live,
            )
            assertEquals(
                ContinuousMeasurementScrollPlan.PreserveAnchor(
                    ContinuousViewportLayoutAnchor(index = 4, offsetPx = 100),
                ),
                plan,
            )
            val preserved = (plan as ContinuousMeasurementScrollPlan.PreserveAnchor).anchor
            assertEquals(anchor.viewportY, preserved.offsetPx + anchor.localOffsetPx)
        }
    }

    @Test fun `late previous resource measurement preserves actual next resource reading anchor`() {
        val anchor = ContinuousReadingAnchorLayout(
            index = 5,
            layoutGeneration = 7,
            resourceGeneration = 32,
            viewportY = 554,
            localOffsetPx = 190,
        )

        assertEquals(
            ContinuousMeasurementScrollPlan.PreserveAnchor(
                ContinuousViewportLayoutAnchor(index = 5, offsetPx = 364),
            ),
            continuousMeasurementScrollPlan(
                reflowTarget = null,
                measurementIndex = 4,
                readingAnchor = anchor,
                fallbackAnchor = ContinuousViewportLayoutAnchor(index = 4, offsetPx = -355),
                currentLayoutGeneration = 7,
            ) { index, generation -> index == 5 && generation == 32L },
        )
    }

    @Test fun `measurement after reading anchor does not move viewport and stale anchor falls back safely`() {
        val anchor = ContinuousReadingAnchorLayout(
            index = 5,
            layoutGeneration = 7,
            resourceGeneration = 32,
            viewportY = 554,
            localOffsetPx = 190,
        )

        assertEquals(
            ContinuousMeasurementScrollPlan.KeepCurrent,
            continuousMeasurementScrollPlan(
                reflowTarget = null,
                measurementIndex = 6,
                readingAnchor = anchor,
                fallbackAnchor = ContinuousViewportLayoutAnchor(index = 5, offsetPx = 364),
                currentLayoutGeneration = 7,
            ) { _, _ -> true },
        )
        assertEquals(
            ContinuousMeasurementScrollPlan.PreserveAnchor(
                ContinuousViewportLayoutAnchor(index = 5, offsetPx = 364),
            ),
            continuousMeasurementScrollPlan(
                reflowTarget = null,
                measurementIndex = 4,
                readingAnchor = anchor.copy(layoutGeneration = 6),
                fallbackAnchor = ContinuousViewportLayoutAnchor(index = 5, offsetPx = 364),
                currentLayoutGeneration = 7,
            ) { _, _ -> true },
        )
        assertEquals(
            ContinuousMeasurementScrollPlan.KeepCurrent,
            continuousMeasurementScrollPlan(
                reflowTarget = null,
                measurementIndex = 4,
                readingAnchor = anchor,
                fallbackAnchor = ContinuousViewportLayoutAnchor(index = 4, offsetPx = -355),
                currentLayoutGeneration = 7,
            ) { _, _ -> false },
        )
    }

    @Test fun `authoritative reflow target retains priority over reading anchor preservation`() {
        val target = reflowTarget(index = 6, layoutGeneration = 7, resourceGeneration = 33)
        val anchor = ContinuousReadingAnchorLayout(
            index = 5,
            layoutGeneration = 7,
            resourceGeneration = 32,
            viewportY = 554,
            localOffsetPx = 190,
        )

        assertEquals(
            ContinuousMeasurementScrollPlan.ReflowTarget(target),
            continuousMeasurementScrollPlan(
                reflowTarget = target,
                measurementIndex = 4,
                readingAnchor = anchor,
                fallbackAnchor = ContinuousViewportLayoutAnchor(index = 4, offsetPx = -355),
                currentLayoutGeneration = 7,
            ) { _, _ -> true },
        )
    }

    @Test fun `geometry restore target requires true ready measurement and attached RecyclerView layout`() {
        val barrier = ContinuousReflowTargetBarrier()
        val target = ContinuousReflowTarget(index = 6, layoutGeneration = 4, resourceGeneration = 9)
        barrier.markReady(target)
        assertFalse(barrier.isReady(target))
        barrier.markMeasured(target)
        assertFalse(barrier.isReady(target))
        barrier.markAttachedLayouts { it == target }
        assertTrue(barrier.isReady(target))
    }

    @Test fun `measurement scroll target selects only an exact live pending waiter`() {
        val target = ContinuousReflowTarget(index = 6, layoutGeneration = 4, resourceGeneration = 9)
        val measurement = ResourceLayoutMeasurement(
            index = target.index,
            heightPx = 47_000,
            layoutGeneration = target.layoutGeneration,
            resourceGeneration = target.resourceGeneration,
            measurementGeneration = 1,
        )
        val isLive = { index: Int, generation: Long -> index == target.index && generation == target.resourceGeneration }

        assertEquals(
            target,
            pendingReflowTargetForMeasurement(measurement, setOf(target), currentLayoutGeneration = 4, isLiveResource = isLive),
        )
        assertNull(
            pendingReflowTargetForMeasurement(
                measurement,
                setOf(target.copy(resourceGeneration = 10)),
                currentLayoutGeneration = 4,
                isLiveResource = isLive,
            ),
        )
        assertNull(
            pendingReflowTargetForMeasurement(measurement, setOf(target), currentLayoutGeneration = 5, isLiveResource = isLive),
        )
        assertNull(
            pendingReflowTargetForMeasurement(measurement, setOf(target), currentLayoutGeneration = 4) { _, _ -> false },
        )
    }

    @Test fun `old resource generation cannot satisfy new reflow target`() {
        val barrier = ContinuousReflowTargetBarrier()
        val old = ContinuousReflowTarget(index = 6, layoutGeneration = 4, resourceGeneration = 9)
        val current = old.copy(resourceGeneration = 10)
        barrier.markReady(old)
        barrier.markMeasured(old)
        barrier.markAttachedLayouts { it == old }
        assertTrue(barrier.isReady(old))
        assertFalse(barrier.isReady(current))
    }

    @Test fun `RecyclerView layout before a measurement cannot settle that measurement`() {
        val barrier = ContinuousReflowTargetBarrier()
        val target = ContinuousReflowTarget(index = 6, layoutGeneration = 4, resourceGeneration = 9)
        barrier.markReady(target)
        barrier.markAttachedLayouts(layoutPass = 8) { it == target }
        barrier.markMeasured(target, layoutPass = 8)
        assertFalse(barrier.isReady(target))
        barrier.markAttachedLayouts(layoutPass = 9) { it == target }
        assertTrue(barrier.isReady(target))
    }

    @Test fun `new target measurement requires a new attached layout before range verification`() {
        val barrier = ContinuousReflowTargetBarrier()
        val target = ContinuousReflowTarget(index = 14, layoutGeneration = 7, resourceGeneration = 31)
        barrier.markReady(target)
        barrier.markMeasured(target, layoutPass = 10)
        barrier.markAttachedLayouts(layoutPass = 11) { it == target }
        assertTrue(barrier.isReady(target))

        barrier.markMeasured(target, layoutPass = 11)
        assertFalse(barrier.isReady(target))
        barrier.markAttachedLayouts(layoutPass = 12) { it == target }
        assertTrue(barrier.isReady(target))
    }

    @Test fun `position-only initial restore requires exact range proof despite enriched observed locator`() {
        val requested = locator(selector = null, highlight = null, progression = 0.6363636363636364)
        val observed = locator(selector = ":root > :nth-child(2) > :nth-child(127)", progression = 0.6362407657699357)
        assertFalse(semanticLocatorsConverge(requested, observed))
        assertTrue(initialRestoreRequiresRequestedRangeAnchor(requested, observed))
        assertFalse(initialRestoreRequiresRequestedRangeAnchor(requested, locator(href = "other.xhtml")))
        assertFalse(initialRestoreRequiresRequestedRangeAnchor(locator(), observed))
        assertFalse(initialRestoreRequiresRequestedRangeAnchor(locator(selector = null, highlight = null, progression = null), observed))
    }
    @Test fun `semantic convergence requires the same semantic anchor`() {
        assertTrue(semanticLocatorsConverge(locator(), locator(progression = 0.41)))
        assertFalse(semanticLocatorsConverge(locator(), locator(selector = ".other")))
        assertFalse(semanticLocatorsConverge(locator(), locator(href = "other.xhtml")))
    }

    @Test fun `fragment expected and CSS-only observed do not compare CSS representations`() {
        val expected = locator(selector = null, highlight = null, fragments = listOf("pgepubid00497"))
        val observed = locator(selector = "#img_images_i_463.jpg", highlight = null, fragments = emptyList())

        assertFalse(semanticLocatorsConverge(expected, observed))
        assertTrue(initialRestoreRequiresRequestedRangeAnchor(expected, observed))
    }

    @Test fun `unrelated measurement is coalesced until fresh locator observation completes`() {
        val transaction = transaction(index = 16)
        val target = reflowTarget(index = 16, layoutGeneration = 1, resourceGeneration = 2)
        assertTrue(transaction.markMaterialized(target))
        assertTrue(transaction.markRestored())
        val barrier = ContinuousFreshLocatorObservationBarrier()
        barrier.begin(target, transaction)
        val first = ResourceLayoutMeasurement(index = 15, heightPx = 47_000, layoutGeneration = 1, resourceGeneration = 1, measurementGeneration = 1)
        val latest = first.copy(heightPx = 47_715, measurementGeneration = 2)

        assertTrue(barrier.shouldDefer(first) { actual, owner -> actual == target && owner === transaction })
        barrier.defer(first)
        barrier.defer(latest)

        assertEquals(listOf(latest), barrier.finish(transaction))
        assertFalse(barrier.shouldDefer(latest) { _, _ -> true })
    }

    @Test fun `cancelled fresh locator observation releases deferred geometry without leaking the barrier`() {
        val transaction = transaction(index = 16)
        val target = reflowTarget(index = 16, layoutGeneration = 1, resourceGeneration = 2)
        assertTrue(transaction.markMaterialized(target))
        assertTrue(transaction.markRestored())
        val barrier = ContinuousFreshLocatorObservationBarrier()
        barrier.begin(target, transaction)
        val deferred = ResourceLayoutMeasurement(index = 15, heightPx = 47_715, layoutGeneration = 1, resourceGeneration = 1, measurementGeneration = 1)
        barrier.defer(deferred)
        transaction.cancel()

        assertEquals(listOf(deferred), barrier.finish(transaction))
        assertFalse(barrier.shouldDefer(deferred) { _, _ -> true })
    }

    @Test fun `transaction permits one restore and isolated completion`() {
        val transaction = transaction()
        val target = ContinuousReflowTarget(6, 4, 10)
        assertTrue(transaction.markMaterialized(target))
        assertTrue(transaction.canRestore(target))
        assertTrue(transaction.markRestored())
        assertFalse(transaction.markRestored())
        assertTrue(transaction.markConverged(ContinuousResolvedLocatorPoint(0.0, 0.0), 0.0, null))
        assertTrue(transaction.complete())
        assertFalse(transaction.markMaterialized(target))
    }

    @Test fun `superseded transaction cancels before it can restore or publish`() {
        val transaction = transaction()
        transaction.markMaterialized(ContinuousReflowTarget(6, 4, 10))
        transaction.cancel()
        assertTrue(transaction.terminal)
        assertFalse(transaction.canRestore(ContinuousReflowTarget(6, 4, 10)))
        assertFalse(transaction.markRestored())
        assertFalse(transaction.complete())
    }

    @Test fun `reflow barrier accepts every ready measure layout order only after attached measured geometry`() {
        val actions = listOf("ready", "measure", "layout")
        val permutations = actions.flatMap { first ->
            (actions - first).flatMap { second ->
                (actions - first - second).map { third -> listOf(first, second, third) }
            }
        }

        permutations.forEach { order ->
            val barrier = ContinuousReflowTargetBarrier()
            val target = reflowTarget()
            var layoutPass = 0L

            order.forEach { action ->
                when (action) {
                    "ready" -> barrier.markReady(target)
                    "measure" -> barrier.markMeasured(target, layoutPass)
                    "layout" -> {
                        layoutPass += 1
                        barrier.markAttachedLayouts(layoutPass) { it == target }
                    }
                }
            }

            if (order.indexOf("layout") > order.indexOf("measure")) {
                assertTrue("order=$order", barrier.isReady(target))
            } else {
                assertFalse("order=$order", barrier.isReady(target))
                layoutPass += 1
                barrier.markAttachedLayouts(layoutPass) { it == target }
                assertTrue("order=$order after fresh layout", barrier.isReady(target))
            }
        }
    }

    @Test fun `stale resource layout and index events cannot satisfy the current reflow target`() {
        val barrier = ContinuousReflowTargetBarrier()
        val current = reflowTarget(index = 6, layoutGeneration = 4, resourceGeneration = 10)
        val staleResource = current.copy(resourceGeneration = 9)
        val staleLayout = current.copy(layoutGeneration = 3)
        val wrongIndex = current.copy(index = 0)

        listOf(staleResource, staleLayout, wrongIndex).forEach { stale ->
            barrier.markReady(stale)
            barrier.markMeasured(stale, layoutPass = 3)
        }
        barrier.markAttachedLayouts(layoutPass = 4) { it != current }

        assertFalse(barrier.isReady(current))
        barrier.markReady(current)
        assertFalse(barrier.isReady(current))
        barrier.markMeasured(current, layoutPass = 4)
        barrier.markAttachedLayouts(layoutPass = 5) { it == current }
        assertTrue(barrier.isReady(current))
    }

    @Test fun `transaction authority keeps anchor index six from restoring stale or index zero targets`() {
        val transaction = transaction()
        val indexZero = reflowTarget(index = 0)
        val current = reflowTarget(index = 6, layoutGeneration = 4, resourceGeneration = 10)
        val staleResource = current.copy(resourceGeneration = 9)
        val staleLayout = current.copy(layoutGeneration = 3)

        assertFalse(transaction.markMaterialized(indexZero))
        assertSame(ContinuousGeometryReflowTransaction.State.CAPTURED, transaction.state)
        assertTrue(transaction.markMaterialized(current))
        assertFalse(transaction.restored)
        assertFalse(transaction.canRestore(indexZero))
        assertFalse(transaction.canRestore(staleResource))
        assertFalse(transaction.canRestore(staleLayout))
        assertTrue(transaction.canRestore(current))
    }

    @Test fun `transaction cannot publish before restore convergence and completion advance in order`() {
        val transaction = transaction()
        val current = reflowTarget(index = 6, layoutGeneration = 4, resourceGeneration = 10)

        assertFalse(transaction.complete())
        assertFalse(transaction.markConverged(ContinuousResolvedLocatorPoint(0.0, 0.0), 0.0, null))
        assertTrue(transaction.markMaterialized(current))
        assertFalse(transaction.complete())
        assertFalse(transaction.converged)
        assertTrue(transaction.markRestored())
        assertFalse(transaction.complete())
        assertTrue(transaction.markConverged(ContinuousResolvedLocatorPoint(0.0, 0.0), 0.0, null))
        assertTrue(transaction.complete())
        assertTrue(transaction.terminal)
    }

    @Test fun `semantic convergence rejects wrong resource and stale locator identity before publication`() {
        val anchor = locator(href = "chapter.xhtml", selector = ".anchor", highlight = "semantic text", progression = 0.40)

        assertTrue(semanticLocatorsConverge(anchor, locator(progression = 0.42)))
        assertFalse(semanticLocatorsConverge(anchor, locator(href = "other.xhtml")))
        assertFalse(semanticLocatorsConverge(anchor, locator(selector = ".later")))
        assertFalse(
            semanticLocatorsConverge(
                locator(selector = null, highlight = "semantic text", progression = 0.40),
                locator(selector = null, highlight = "stale text", progression = 0.40),
            ),
        )
        assertFalse(semanticLocatorsConverge(locator(selector = null, highlight = null, progression = 0.40), locator(selector = null, highlight = null, progression = 0.43)))
        assertFalse(semanticLocatorsConverge(locator(selector = null, highlight = null, progression = null), locator(selector = null, highlight = null, progression = null)))
    }

    @Test fun `explicit six to zero target remains a direct failure not an implicit prefix fallback`() {
        val transaction = transaction()

        assertFalse(transaction.markMaterialized(reflowTarget(index = 0, layoutGeneration = 4, resourceGeneration = 1)))
        assertFalse(transaction.canRestore(reflowTarget(index = 0, layoutGeneration = 4, resourceGeneration = 1)))
        assertSame(ContinuousGeometryReflowTransaction.State.CAPTURED, transaction.state)
    }

    @Test fun `batch host holds first height and emits no correction until grouped heights commit`() =
        verifyGeometryBatchWithSemanticAnchor(false)

    @Test fun `exact DOM anchor uses protected presentation with one correction and exact diagnostics`() =
        verifyGeometryBatchWithSemanticAnchor(true)

    @Test fun `unresolved DOM anchor finishes explicit fallback without claiming exact preservation`() =
        verifyGeometryBatchWithSemanticAnchor(true, degraded = true)

    @Test fun `late exact DOM result cannot mutate a superseded transaction`() =
        verifyGeometryBatchWithSemanticAnchor(true, staleAfterQuery = true)

    @Test fun `missing current CSS measurement fails bounded and retains physical obligation`() =
        verifyGeometryBatchWithSemanticAnchor(true, missingMeasurement = true)

    @Test fun `same current resource height with changed predecessor still uses full reflow`() =
        verifyGeometryBatchWithSemanticAnchor(true, sameHeightAnchor = true)

    private fun verifyGeometryBatchWithSemanticAnchor(exactDom: Boolean, degraded: Boolean = false, staleAfterQuery: Boolean = false, missingMeasurement: Boolean = false, sameHeightAnchor: Boolean = false) = runBlocking {
        val readingOrder = listOf(hostLink(0), hostLink(1), hostLink(2))
        val port = ControlledContinuousReflowEventPort().apply {
            offsetAnswer = 30.0
            pointGeometryAnswer = ContinuousLocatorPointGeometry(documentYCssPx = 30.0, viewportTopCssPx = 30.0,
                semanticAnchorExact = exactDom && !degraded, anchorIdentityId = if (exactDom) "7" else null,
                anchorCharacterOffset = if (exactDom) 12 else null)
        }
        val binding = RobolectricContinuousReflowHostTestBinding()
        val resources = mutableMapOf<Int, ContinuousResourceView>()
        val measurementCallbacks = mutableMapOf<Int, (ResourceLayoutMeasurement) -> Unit>()
        val executor = HostBatchJavascriptExecutor()
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "test-geometry-batch"

            override fun create(
                context: android.content.Context,
                publication: Publication,
                link: Link,
                index: Int,
                layoutGeneration: Int,
                resourceGeneration: Long,
                sessionInstanceId: String,
                hostId: String,
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
            ).also {
                resources[index] = it
                measurementCallbacks[index] = onMeasurement
            }
        }
        val host = ContinuousReflowableHostView(
            context = context,
            publication = Publication(Manifest(metadata = Metadata(), readingOrder = readingOrder)),
            readingOrder = readingOrder,
            resourceFactory = factory,
            reflowEventPort = port,
            testBinding = binding,
        )
        val pointQueryEntered = CompletableDeferred<Unit>()
        val pointQueryRelease = CompletableDeferred<Unit>()
        host.beforeLocatorPointGeometryForTest = {
            pointQueryEntered.complete(Unit)
            pointQueryRelease.await()
        }
        host.pinResource(0, ContinuousResourcePinReason.GEOMETRY_REFLOW)
        host.pinResource(1, ContinuousResourcePinReason.GEOMETRY_REFLOW)
        host.prepareTargetResource(0)
        host.prepareTargetResource(1)
        val initialTarget = requireNotNull(resources[0]).let { ContinuousReflowTarget(0, it.currentLayoutGeneration, it.generation) }
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setContentView(FrameLayout(activity).apply { addView(host, FrameLayout.LayoutParams(1080, 1_000)) })
        (privateHostField(host, "recyclerView") as RecyclerView).setPadding(0, 16, 0, 0)
        host.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(1_000, View.MeasureSpec.EXACTLY),
        )
        host.layout(0, 0, 1080, 1_000)
        binding.materializeTarget(initialTarget, width = 1080, height = 1_000)

        val initialResources = listOf(0, 1).map { index ->
            val target = ContinuousReflowTarget(index, 0, requireNotNull(resources[index]).generation)
            val materialization = requireNotNull(binding.attachedMaterialization(target))
            val resource = materialization.resource
            finishHostBootstrap(resource)
            resource
        }
        assertTrue(initialResources.all { it.cssAppliedForCurrentEpoch && it.canFindLocator })
        val oldAnchorHeight = 710L
        val unmeasuredPredecessorHeight = initialResources[0].currentHeightPx
        port.measurement(
            ResourceLayoutMeasurement(
                index = 1,
                heightPx = oldAnchorHeight,
                layoutGeneration = initialResources[1].currentLayoutGeneration,
                resourceGeneration = initialResources[1].generation,
                measurementGeneration = 1_001L,
                measurementEpoch = initialResources[1].currentMeasurementEpoch,
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        binding.commitRecyclerViewLayout(width = 1080, height = 1_000)
        assertEquals(listOf(unmeasuredPredecessorHeight, oldAnchorHeight), initialResources.map { it.currentHeightPx })
        assertEquals(null, (privateHostField(host, "layoutModel") as ContinuousReflowableHostModel).geometryHeightOrNull(0))
        assertTrue(initialResources.all { it.parent != null && it.isAttachedToWindow })

        val recyclerView = privateHostField(host, "recyclerView") as RecyclerView
        fun ensureHolderMatchParentWidth(child: View) {
            val params = child.layoutParams as RecyclerView.LayoutParams
            if (params.width != android.view.ViewGroup.LayoutParams.MATCH_PARENT) {
                params.width = android.view.ViewGroup.LayoutParams.MATCH_PARENT
                child.requestLayout()
            }
        }
        val holderWidthFixture = object : RecyclerView.OnChildAttachStateChangeListener {
            override fun onChildViewAttachedToWindow(view: View) = ensureHolderMatchParentWidth(view)
            override fun onChildViewDetachedFromWindow(view: View) = Unit
        }
        recyclerView.addOnChildAttachStateChangeListener(holderWidthFixture)
        for (childIndex in 0 until recyclerView.childCount) {
            ensureHolderMatchParentWidth(recyclerView.getChildAt(childIndex))
        }
        fun materializeHolderWidthsForViewportQueries() {
            for (childIndex in 0 until recyclerView.childCount) {
                val child = recyclerView.getChildAt(childIndex)
                val top = child.top
                val height = child.height
                val params = child.layoutParams as RecyclerView.LayoutParams
                params.width = android.view.ViewGroup.LayoutParams.MATCH_PARENT
                child.layoutParams = params
                child.measure(
                    View.MeasureSpec.makeMeasureSpec(recyclerView.width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
                )
                child.layout(child.left, top, child.left + recyclerView.width, top + height)
            }
        }
        val readingAnchorY = (recyclerView.height * 0.25f).toInt()
        val pointOffsetPx = (30.0 * context.resources.displayMetrics.density).toInt()
        (privateHostField(host, "layoutManager") as LinearLayoutManager).scrollToPositionWithOffset(
            1,
            readingAnchorY - pointOffsetPx - recyclerView.paddingTop,
        )
        binding.commitRecyclerViewLayout(width = 1080, height = 1_000)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        val anchorLayoutParams = requireNotNull(recyclerView.findViewHolderForAdapterPosition(1)).itemView
            .layoutParams as RecyclerView.LayoutParams
        anchorLayoutParams.width = android.view.ViewGroup.LayoutParams.MATCH_PARENT
        anchorLayoutParams.height = oldAnchorHeight.toInt()
        binding.commitRecyclerViewLayout(width = 1080, height = 1_000)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        materializeHolderWidthsForViewportQueries()
        resources[2]?.let { trailingResource ->
            finishHostBootstrap(trailingResource)
            port.trueReady(
                ContinuousReflowTarget(
                    index = 2,
                    layoutGeneration = trailingResource.currentLayoutGeneration,
                    resourceGeneration = trailingResource.generation,
                ),
            )
        }
        val anchorChild = recyclerView.findChildViewUnder(recyclerView.width / 2f, readingAnchorY.toFloat())
        assertEquals(1, anchorChild?.let(recyclerView::getChildAdapterPosition))
        assertEquals(1080, anchorChild?.width)

        host.beginGeometryReflowPinLease()
        val targetResource = initialResources[1]
        val requestedLocator = hostLocator(1).let { locator ->
            if (!exactDom) locator else locator.copy(locations = locator.locations.copy(
                otherLocations = locator.locations.otherLocations + mapOf(
                    "continuousDomAnchor" to mapOf("id" to "7", "charOffset" to 12),
                ),
            ))
        }
        val recyclerLocation = IntArray(2)
        val resourceLocation = IntArray(2)
        recyclerView.getLocationOnScreen(recyclerLocation)
        targetResource.getLocationOnScreen(resourceLocation)
        val capturedViewportY = resourceLocation[1] - recyclerLocation[1] +
            30.0 * context.resources.displayMetrics.density
        val transaction = ContinuousGeometryReflowTransaction(
            generation = 81,
            preferenceGeneration = 81,
            anchor = ContinuousAnchorLocator(
                index = 1,
                resourceGeneration = targetResource.generation,
                layoutGeneration = targetResource.currentLayoutGeneration,
                localY = 250.0,
                locator = requestedLocator,
                viewportY = capturedViewportY,
                targetViewportY = if (exactDom) capturedViewportY - 17.0 else capturedViewportY,
                documentYLayoutPx = 30.0 * context.resources.displayMetrics.density,
            ),
            requestedPreferences = EpubPreferences(fontSize = 1.25),
        )
        val diagnosticContext: EpubContinuousReflowDiagnosticContext? = null
        val diagnosticEvents = mutableListOf<EpubContinuousReflowDiagnosticEvent>()
        host.setReflowDiagnosticListener(diagnosticEvents::add)
        host.emitViewportSnapshot(
            snapshotStage = "before_reflow",
            context = diagnosticContext,
            preferenceGeneration = 81,
            transactionGeneration = transaction.generation,
            layoutGeneration = transaction.anchor.layoutGeneration,
            resourceGeneration = transaction.anchor.resourceGeneration,
            anchorIndex = transaction.anchor.index,
            anchorProgression = transaction.anchor.locator.locations.progression,
            anchorPointDocumentYPx = transaction.anchor.documentYLayoutPx,
            anchorPointViewportYPx = transaction.anchor.viewportY,
            anchorPointAvailable = true,
            anchorPointSampleStage = "after_css_before_geometry_commit",
            anchorBeforeLocalYPx = transaction.anchor.localY,
            anchorBeforeViewportYPx = transaction.anchor.viewportY,
            anchorResourceHref = boundedContinuousDiagnosticResourceHref(transaction.anchor.locator.href.toString()),
            result = "captured",
        )
        host.applyInPlaceLayoutGeneration(
            transaction,
            diagnosticContext = diagnosticContext,
            preferenceGeneration = 81,
        )
        assertTrue(diagnosticEvents.any {
            it.kind == "geometry_batch_created" && it.result == "created"
        })
        val requiredAtSnapshot = diagnosticEvents.filter {
            it.kind == "geometry_batch_required" && it.result == "required_at_snapshot"
        }.associate { it.readingOrderIndex!! to it.resourceGeneration!! }
        assertEquals(
            mapOf(0 to initialResources[0].generation, 1 to initialResources[1].generation),
            requiredAtSnapshot,
        )
        val nextGeneration = targetResource.currentLayoutGeneration
        assertTrue(initialResources.all { it.currentLayoutGeneration == nextGeneration && it.cssAppliedForCurrentEpoch })
        initialResources.forEachIndexed { index, resource ->
            port.trueReady(ContinuousReflowTarget(index, nextGeneration, resource.generation))
        }

        val actualScrollCalls = mutableListOf<Pair<Int, Int>>()
        host.scrollToPositionCallObserverForTest = { index, offset -> actualScrollCalls.add(index to offset) }
        var currentTransaction = true
        val restore = async(start = CoroutineStart.UNDISPATCHED) {
            host.restoreAfterGeometryReflow(requestedLocator, transaction) { currentTransaction }
        }
        yield()
        assertTrue("The attached batch anchor must bypass the preparation scroll", actualScrollCalls.isEmpty())
        assertEquals(
            setOf(0, 1),
            diagnosticEvents.filter {
                it.kind == "reflow_wait" && it.result == "required_measurement_pending"
            }.map { it.readingOrderIndex }.toSet(),
        )

        if (missingMeasurement) {
            assertTrue(targetResource.mustFinishCssGeometry(81))
            assertEquals(ContinuousReflowRestoreOutcome.TargetNotReady, restore.await())
            assertTrue(host.hasPendingCssGeometry())
            assertTrue(targetResource.hasPendingCssGeometry)
            assertTrue(actualScrollCalls.isEmpty())
            assertEquals(oldAnchorHeight, targetResource.currentHeightPx)
            assertTrue(diagnosticEvents.any { it.kind == "geometry_batch_pending" && it.result == "retained_css_geometry_obligation" })
            recyclerView.removeOnChildAttachStateChangeListener(holderWidthFixture)
            host.dispose()
            return@runBlocking
        }
        val hostModel = privateHostField(host, "layoutModel") as ContinuousReflowableHostModel
        val predecessor = initialResources[0]
        val anchorCssHeightPx = if (sameHeightAnchor) oldAnchorHeight else 760L
        val anchorMeasuredHeightPx = requireNotNull(
            continuousCssHeightToLayoutPx(anchorCssHeightPx, context.resources.displayMetrics.density.toDouble()),
        )
        targetResource.receiveMeasurement(
            cssHeightPx = anchorCssHeightPx,
            reportedLayoutGeneration = nextGeneration,
            reportedMeasurementEpoch = targetResource.currentMeasurementEpoch,
            ownerToken = targetResource.currentCssOwnerToken,
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals(1L, measurementGeneration(targetResource))
        assertEquals(listOf(unmeasuredPredecessorHeight, oldAnchorHeight), initialResources.map { it.currentHeightPx })
        assertEquals(null, hostModel.measuredHeightOrNull(1))
        assertEquals(oldAnchorHeight, hostModel.geometryHeightOrNull(1))
        assertTrue("An attached unmeasured predecessor keeps the batch open", actualScrollCalls.isEmpty())

        predecessor.receiveMeasurement(530, nextGeneration, predecessor.currentMeasurementEpoch, predecessor.currentCssOwnerToken)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals("Preflight must complete before applying the ready geometry batch", listOf(unmeasuredPredecessorHeight, oldAnchorHeight), initialResources.map { it.currentHeightPx })
        assertEquals(null, hostModel.measuredHeightOrNull(0))
        assertEquals(null, hostModel.measuredHeightOrNull(1))
        pointQueryEntered.await()
        assertEquals(ContinuousGeometryBatchState.COMMIT_STARTED, privateHostField(host, "activeGeometryBatch").let {
            it.javaClass.getDeclaredField("state").apply { isAccessible = true }.get(it)
        })
        assertEquals("No parent height is changed while the semantic preflight is pending", listOf(unmeasuredPredecessorHeight, oldAnchorHeight), initialResources.map { it.currentHeightPx })
        assertTrue("No scroll offset is installed before the preflight query completes", actualScrollCalls.isEmpty())

        targetResource.receiveMeasurement(
            cssHeightPx = anchorCssHeightPx,
            reportedLayoutGeneration = nextGeneration,
            reportedMeasurementEpoch = targetResource.currentMeasurementEpoch,
            ownerToken = targetResource.currentCssOwnerToken,
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals("A duplicate in-epoch height must not supersede the prepared anchor measurement", 1L, measurementGeneration(targetResource))
        assertFalse(diagnosticEvents.any {
            it.kind == "geometry_batch_collect" && it.readingOrderIndex == 1 && it.measurementGeneration == 2L
        })

        host.pinResource(2, ContinuousResourcePinReason.GEOMETRY_REFLOW)
        host.prepareTargetResource(2)
        val optionalResource = requireNotNull(resources[2])
        finishHostBootstrap(optionalResource)
        measurementCallbacks.getValue(2)(
            ResourceLayoutMeasurement(
                index = 2,
                heightPx = 730,
                layoutGeneration = nextGeneration,
                resourceGeneration = optionalResource.generation,
                measurementGeneration = 2_002,
                measurementEpoch = optionalResource.currentMeasurementEpoch,
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals("The late current-generation report is staged during the query", 800L, optionalResource.currentHeightPx)
        assertEquals(null, hostModel.geometryHeightOrNull(2))
        assertFalse(diagnosticEvents.any { it.kind == "measurement_applied" && it.readingOrderIndex == 2 })
        host.beforeLocatorPointGeometryForTest = null
        if (staleAfterQuery) currentTransaction = false
        pointQueryRelease.complete(Unit)
        yield()
        shadowOf(android.os.Looper.getMainLooper()).idle()
        if (staleAfterQuery) {
            assertTrue(restore.isCompleted)
            assertEquals(ContinuousReflowRestoreOutcome.TargetNotReady, restore.await())
            assertTrue("Late exact DOM answer cannot scroll", actualScrollCalls.isEmpty())
            assertEquals(listOf(unmeasuredPredecessorHeight, oldAnchorHeight), initialResources.map { it.currentHeightPx })
            assertFalse(diagnosticEvents.any { it.kind == "semantic_anchor_compare" })
            recyclerView.removeOnChildAttachStateChangeListener(holderWidthFixture)
            host.scrollToPositionCallObserverForTest = null
            host.dispose()
            return@runBlocking
        }
        assertEquals("The batch installs the semantic target offset exactly once", 1, actualScrollCalls.size)
        assertEquals(1, actualScrollCalls.single().first)
        assertTrue(diagnosticEvents.any {
            it.kind == "viewport_snapshot" && it.snapshotStage == "before_reflow" && it.context == null
        })
        val beforeReflowSnapshot = diagnosticEvents.single {
            it.kind == "viewport_snapshot" && it.snapshotStage == "before_reflow"
        }
        assertEquals(targetResource.webViewIdentity, beforeReflowSnapshot.webViewIdentity)
        assertNull(beforeReflowSnapshot.webViewIdentityUnavailableReason)
        val beforeGeometrySnapshot = diagnosticEvents.single {
            it.kind == "viewport_snapshot" && it.snapshotStage == "before_geometry_commit"
        }
        assertEquals(true, beforeGeometrySnapshot.anchorPointAvailable)
        assertEquals("after_css_before_geometry_commit", beforeGeometrySnapshot.anchorPointSampleStage)
        assertEquals(1, beforeGeometrySnapshot.predecessorMeasurementCount)
        assertEquals(530L - unmeasuredPredecessorHeight, beforeGeometrySnapshot.predecessorHeightDeltaPx)
        val predecessorDiagnostic = diagnosticEvents.single { it.kind == "geometry_anchor_dependency" }
        assertEquals(0, predecessorDiagnostic.readingOrderIndex)
        assertEquals(unmeasuredPredecessorHeight, predecessorDiagnostic.oldHeightPx)
        assertEquals(530L, predecessorDiagnostic.newHeightPx)
        assertEquals(530L - unmeasuredPredecessorHeight, predecessorDiagnostic.batchHeightDeltaPx)
        val batchEffect = diagnosticEvents.single { it.kind == "geometry_batch_effect" }
        assertEquals(oldAnchorHeight + unmeasuredPredecessorHeight, batchEffect.oldHeightPx)
        assertEquals(530L + anchorMeasuredHeightPx, batchEffect.newHeightPx)
        assertEquals(530L + anchorMeasuredHeightPx - oldAnchorHeight - unmeasuredPredecessorHeight, batchEffect.batchHeightDeltaPx)
        assertTrue(diagnosticEvents.any {
            it.kind == "geometry_commit_lock" && it.commitLockHeld == true &&
                it.result == "acquired_before_first_height_mutation"
        })

        binding.commitRecyclerViewLayout(width = 1080, height = 1_000)
        materializeHolderWidthsForViewportQueries()
        yield()
        shadowOf(android.os.Looper.getMainLooper()).idle()
        yield()
        assertEquals(1, binding.restoreCount)
        assertEquals("Only the preflight-compensated offset is issued", 1, actualScrollCalls.size)
        assertTrue(diagnosticEvents.any {
            it.kind == "viewport_snapshot" && it.snapshotStage == "before_geometry_commit" &&
                it.anchorPointAvailable == true
        })
        val afterGeometrySnapshot = diagnosticEvents.single {
            it.kind == "viewport_snapshot" && it.snapshotStage == "after_geometry_before_anchor"
        }
        assertEquals("after_css_before_geometry_commit", afterGeometrySnapshot.anchorPointSampleStage)
        assertEquals("cached_preflight_point_parent_heights_installed_offset_pending", afterGeometrySnapshot.result)
        val scrollRequestSnapshot = diagnosticEvents.single {
            it.kind == "viewport_snapshot" && it.snapshotStage == "after_anchor_scroll_request"
        }
        assertEquals(true, scrollRequestSnapshot.scrollRequestIssued)
        assertEquals("post_scroll_point_not_sampled", scrollRequestSnapshot.anchorPointUnavailableReason)
        assertEquals(false, scrollRequestSnapshot.anchorPointAvailable)
        assertTrue(scrollRequestSnapshot.requestedCorrectionOffsetPx != null)
        binding.commitRecyclerViewLayout(width = 1080, height = 1_000)
        materializeHolderWidthsForViewportQueries()
        yield()
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertFalse("A good preflight compensation must not issue a second scroll", diagnosticEvents.any { it.kind == "viewport_scroll" })
        assertTrue("restore has ended before diagnostic assertions", restore.isCompleted)
        val restoreOutcome = restore.await()
        assertTrue(
            "Fresh verification snapshot missing: events=${diagnosticEvents.map { it.kind to it.snapshotStage }}, " +
                "restoreCompleted=${restore.isCompleted}, locatorRequests=${port.locatorRequests}, " +
                "restoreOutcome=$restoreOutcome, capturedViewportY=$capturedViewportY, " +
                "resourceScreenTop=${resourceLocation[1] - recyclerLocation[1]}, " +
                "currentAnchor=${host.currentLocatorAnchor()}, " +
                "targetAttached=${targetResource.isAttachedToWindow}, " +
                "scrollSample=${diagnosticEvents.singleOrNull { it.kind == "viewport_scroll" }}",
            diagnosticEvents.any {
            it.kind == "viewport_snapshot" && it.snapshotStage == "after_anchor_verified"
        })
        val verifiedSnapshot = diagnosticEvents.single {
            it.kind == "viewport_snapshot" && it.snapshotStage == "after_anchor_verified"
        }
        assertFalse("Current physical CSS must have matching parent geometry before final success", targetResource.hasPendingCssGeometry)
        assertEquals(!degraded, verifiedSnapshot.anchorSemanticMatch)
        if (sameHeightAnchor) {
            val path = diagnosticEvents.single { it.kind == "reflow_path" }
            assertEquals("full_reflow", path.result)
            assertEquals("predecessor_height_changed", path.semanticAnchorFields["reason"])
        }
        if (exactDom) {
            val semantic = diagnosticEvents.single { it.kind == "semantic_anchor_compare" }
            assertEquals(if (degraded) "PROGRESSION_FALLBACK" else "EXACT_DOM_POINT", semantic.semanticAnchorFields["semanticAnchorQuality"])
            assertEquals(!degraded, semantic.semanticAnchorFields["sameDomIdentity"])
            assertEquals(!degraded, semantic.semanticAnchorFields["sameCharacterOffset"])
            assertEquals(degraded, semantic.semanticAnchorFields["fallbackUsed"])
            assertEquals(12, semantic.semanticAnchorFields["anchorCharacterOffset"])
            assertEquals(17.0, semantic.semanticAnchorFields["pointToTargetOffsetPx"])
            assertEquals(capturedViewportY - 17.0, semantic.semanticAnchorFields["anchorTargetViewportY"])
        }
        assertEquals(true, verifiedSnapshot.anchorPointAvailable)
        assertTrue(host.hasCommittedCssGeometry(transaction))
        assertTrue(diagnosticEvents.any { it.kind == "viewport_delta" })

        assertTrue(transaction.complete())
        host.finishFreshLocatorObservation(transaction)
        assertEquals(730L, optionalResource.currentHeightPx)
        assertTrue(diagnosticEvents.any {
            it.kind == "presentation_transaction" && it.result == "begin"
        })
        assertTrue(diagnosticEvents.any {
            it.kind == "presentation_transaction" && it.result == "end" && it.snapshotStage == "committed"
        })
        val afterPresentation = diagnosticEvents.single {
            it.kind == "viewport_snapshot" && it.snapshotStage == "after_presentation_commit"
        }
        assertEquals(!degraded, afterPresentation.anchorSemanticMatch)
        assertEquals(true, afterPresentation.anchorPointAvailable)
        assertTrue(kotlin.math.abs(requireNotNull(afterPresentation.anchorViewportDeltaPx)) <= 4.0)
        host.emitAfterReflowCommitSnapshot(transaction, diagnosticContext)
        assertEquals(1, diagnosticEvents.count {
            it.kind == "viewport_snapshot" && it.snapshotStage == "after_reflow_commit"
        })
        val presentationEndIndex = diagnosticEvents.indexOfFirst {
            it.kind == "presentation_transaction" && it.result == "end"
        }
        val verifiedIndex = diagnosticEvents.indexOfFirst { it.kind == "anchor_restore_verified" }
        assertTrue("Presentation ends only after semantic and viewport verification", verifiedIndex in 0 until presentationEndIndex)
        val committedIndex = diagnosticEvents.indexOfFirst {
            it.kind == "geometry_batch_committed"
        }
        assertTrue("Geometry batch commits after the presentation transaction closes", presentationEndIndex in 0 until committedIndex)
        restore.cancelAndJoin()
        transaction.commitOwner?.let(host::acknowledgeGeometryCommit)
        assertTrue(diagnosticEvents.any {
            it.kind == "geometry_commit_lock" && it.commitLockHeld == false &&
                it.result == "released_on_session_ack"
        })
        recyclerView.removeOnChildAttachStateChangeListener(holderWidthFixture)
        host.scrollToPositionCallObserverForTest = null
        host.dispose()
    }

    @Test fun `height mutation exception fails locked batch and releases restore waiter`() = runBlocking {
        val readingOrder = listOf(hostLink(0))
        val port = ControlledContinuousReflowEventPort().apply {
            pointGeometryAnswer = ContinuousLocatorPointGeometry(documentYCssPx = 180.0, viewportTopCssPx = 180.0)
        }
        val binding = RobolectricContinuousReflowHostTestBinding()
        val resources = mutableMapOf<Int, ContinuousResourceView>()
        val factory = object : ContinuousResourceViewFactory {
            override val diagnosticSessionId = "test-geometry-batch-post-lock-failure"
            override fun create(
                context: android.content.Context,
                publication: Publication,
                link: Link,
                index: Int,
                layoutGeneration: Int,
                resourceGeneration: Long,
                sessionInstanceId: String,
                hostId: String,
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
                javascriptExecutor = HostBatchJavascriptExecutor(),
            ).also { resources[index] = it }
        }
        val host = ContinuousReflowableHostView(
            context = context,
            publication = Publication(Manifest(metadata = Metadata(), readingOrder = readingOrder)),
            readingOrder = readingOrder,
            resourceFactory = factory,
            reflowEventPort = port,
            testBinding = binding,
        )
        val diagnosticEvents = mutableListOf<EpubContinuousReflowDiagnosticEvent>()
        host.setReflowDiagnosticListener(diagnosticEvents::add)
        host.pinResource(0, ContinuousResourcePinReason.GEOMETRY_REFLOW)
        host.prepareTargetResource(0)
        val resource = requireNotNull(resources[0])
        val initialTarget = ContinuousReflowTarget(0, resource.currentLayoutGeneration, resource.generation)
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setContentView(FrameLayout(activity).apply { addView(host, FrameLayout.LayoutParams(1080, 1_000)) })
        host.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(1_000, View.MeasureSpec.EXACTLY),
        )
        host.layout(0, 0, 1080, 1_000)
        binding.materializeTarget(initialTarget, width = 1080, height = 1_000)
        finishHostBootstrap(resource)

        host.beginGeometryReflowPinLease()
        val transaction = ContinuousGeometryReflowTransaction(
            generation = 91,
            preferenceGeneration = 91,
            anchor = ContinuousAnchorLocator(
                index = 0,
                resourceGeneration = resource.generation,
                layoutGeneration = resource.currentLayoutGeneration,
                localY = 180.0,
                locator = hostLocator(0),
            ),
            requestedPreferences = EpubPreferences(fontSize = 1.2),
        )
        host.applyInPlaceLayoutGeneration(transaction, preferenceGeneration = 91)
        val currentTarget = ContinuousReflowTarget(0, resource.currentLayoutGeneration, resource.generation)
        port.trueReady(currentTarget)
        host.geometryBatchAfterFirstHeightMutationForTest = { throw IllegalStateException("injected post-write failure") }
        val restore = async(start = CoroutineStart.UNDISPATCHED) {
            host.restoreAfterGeometryReflow(transaction.anchor.locator, transaction) { true }
        }
        port.measurement(
            ResourceLayoutMeasurement(
                index = 0,
                heightPx = 540,
                layoutGeneration = resource.currentLayoutGeneration,
                resourceGeneration = resource.generation,
                measurementGeneration = 91,
                measurementEpoch = resource.currentMeasurementEpoch,
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()

        val restoreOutcome = restore.await()
        assertEquals(
            "height=${resource.currentHeightPx}, outcome=$restoreOutcome, batch=${(privateHostField(host, "activeGeometryBatch") as ContinuousGeometryMeasurementBatch).state}, diagnostics=${diagnosticEvents.map { it.kind to it.result}}",
            540L,
            resource.currentHeightPx,
        )
        assertTrue(transaction.commitOwner != null)
        assertEquals(
            ContinuousGeometryBatchState.FAILED_AFTER_COMMIT_START,
            privateHostField(host, "activeGeometryBatch").let { it as ContinuousGeometryMeasurementBatch }.state,
        )
        assertEquals(ContinuousReflowRestoreOutcome.TargetNotReady, restoreOutcome)

        host.geometryBatchAfterFirstHeightMutationForTest = null
        host.finishFreshLocatorObservation(transaction)
        assertFalse(
            "Finishing an already failed batch must not re-report its cleared required snapshot as unmeasured",
            diagnosticEvents.any { it.kind == "geometry_batch_pending" && it.result == "unmeasured_on_terminal" },
        )
        host.dispose()
    }

    private fun standaloneResource(
        index: Int,
        onMeasurement: (ResourceLayoutMeasurement) -> Unit,
    ) = ContinuousResourceView(
        context = context,
        index = index,
        layoutGeneration = 0,
        resourceGeneration = index.toLong() + 1,
        url = "https://readium_assets/chapter-$index.xhtml",
        configure = { _, _, _, _ -> },
        applyReadiumCss = { _, _, _, _, done -> done(true) },
        publication = Publication(Manifest(metadata = Metadata(), readingOrder = listOf(hostLink(index)))),
        link = hostLink(index),
        onMeasurement = onMeasurement,
        sessionInstanceId = "test-resource-measurement-epoch",
        hostId = "test-resource-measurement-epoch",
        javascriptExecutor = HostBatchJavascriptExecutor(),
    )

    private fun measurementGeneration(resource: ContinuousResourceView): Long =
        (requireNotNull(resource.javaClass.getDeclaredField("measurementGeneration").apply { isAccessible = true }.get(resource)) as AtomicLong).get()

    private fun hostLink(index: Int) = Link(Url("OEBPS/chapter-$index.xhtml")!!, MediaType.XHTML)

    private fun hostLocator(index: Int) = Locator(
        href = Url("OEBPS/chapter-$index.xhtml")!!,
        mediaType = MediaType.XHTML,
        locations = Locator.Locations(progression = 0.4, otherLocations = mapOf("cssSelector" to ".anchor")),
        text = Locator.Text(highlight = "semantic text"),
    )

    private class HostBatchJavascriptExecutor : R2JavascriptExecutor {
        override fun evaluate(webView: R2BasicWebView, javascript: String, callback: (String) -> Unit) {
            callback(
                when {
                    javascript == READIUM_RUNTIME_PROBE -> "true"
                    javascript.contains("__biblioLifeContinuousResizeObserver") -> "true"
                    javascript.contains("readium.findLocatorAtPoint(") ->
                        """{"href":"#","type":"application/xhtml+xml","locations":{"cssSelector":".anchor","progression":0.4},"text":{"highlight":"semantic text"}}"""
                    else -> "null"
                },
            )
        }
    }

    private fun finishHostBootstrap(resource: ContinuousResourceView) {
        val webView = resource.getChildAt(0) as WebView
        shadowOf(webView).webViewClient.onPageFinished(webView, "https://readium_assets/finished.xhtml")
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(
            resource.dispatchBootstrapBridgeEvent(
                ContinuousRawBootstrapBridgeEvent(ContinuousBootstrapBridgeEventDispatcher.BOOTSTRAP_SCRIPT_LOADED_METHOD),
            ),
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()
    }

    private fun privateHostField(host: Any, name: String): Any =
        requireNotNull(host.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(host))
}
