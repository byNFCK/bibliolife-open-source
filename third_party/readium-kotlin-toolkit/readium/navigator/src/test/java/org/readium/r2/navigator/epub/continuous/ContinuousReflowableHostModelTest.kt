package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContinuousReflowableHostModelTest {
    private val resources = listOf("a.xhtml", "b.xhtml", "c.xhtml")

    // Deterministic resource fixtures for the future native resource-view host.
    private val xhtml = mapOf(
        "a.xhtml" to "<html><body><p>A_END</p></body></html>",
        "b.xhtml" to "<html><body><p>B_START</p><p>B_END</p></body></html>",
        "c.xhtml" to "<html><body><p>C_START</p></body></html>",
    )

    private fun host(vararg heights: Long): ContinuousReflowableHostModel =
        ContinuousReflowableHostModel(resources).also { host ->
            heights.forEachIndexed { index, height -> host.reportMeasuredHeight(index, height) }
        }

    @Test fun `measured XHTML resources stack at their actual heights without viewport gaps`() {
        val host = host(200, 300, 250)
        assertTrue(xhtml.getValue("a.xhtml").contains("A_END"))
        assertTrue(xhtml.getValue("b.xhtml").contains("B_START"))
        assertEquals(0, host.geometryFor(0).startPx)
        assertEquals(200, host.geometryFor(1).startPx)
        assertEquals(500, host.geometryFor(2).startPx)
        assertEquals(750, host.documentHeightPx())
    }

    @Test fun `A end and B start occupy the same continuous viewport`() {
        val host = host(250, 1_200, 350)
        assertEquals(listOf("a.xhtml", "b.xhtml"), host.visibleResources(225, 900).map { it.href })
        assertEquals("a.xhtml", host.activeResource(225, 900).href)
    }

    @Test fun `reading anchor selects B when only a tiny A tail is visible`() {
        val host = host(200, 300, 250)
        val anchor = host.readingAnchor(scrollPx = 195, viewportHeightPx = 300)
        assertEquals("b.xhtml", anchor.resource.href)
        assertEquals(70, anchor.localY)
        assertEquals(0.25, anchor.fraction, 0.0)
    }

    @Test fun `reading anchor maps parent viewport points into A B and C local coordinates`() {
        val host = host(200, 300, 250)
        assertEquals("a.xhtml", host.readingAnchor(0, 200).resource.href)
        assertEquals("b.xhtml", host.readingAnchor(200, 200).resource.href)
        assertEquals("c.xhtml", host.readingAnchor(500, 200).resource.href)
    }

    @Test fun `three short resources share one viewport without artificial page allocation`() {
        val host = host(200, 300, 250)
        assertEquals(resources, host.visibleResources(0, 900).map { it.href })
        assertEquals(750, host.documentHeightPx())
    }

    @Test fun `one global scroll crosses forward and backward without navigation command`() {
        val host = host(250, 1_200, 350)
        val forward = host.scrollBy(225, 100, 900)
        assertEquals(325, forward)
        assertEquals("b.xhtml", host.activeResource(forward, 900).href)
        assertEquals(225, host.scrollBy(forward, -100, 900))
    }

    @Test fun `one parent fling delta crosses A B seam without restarting at item boundary`() {
        val host = host(1_000, 1_000, 1_000)
        val afterFling = host.scrollBy(currentScrollPx = 100, deltaPx = 1_150, viewportHeightPx = 600)
        assertEquals(1_250L, afterFling)
        assertEquals("b.xhtml", host.activeResource(afterFling, 600).href)
    }

    @Test fun `large resource remains one variable height document segment`() {
        val host = host(4_000, 300, 250)
        assertEquals(4_000, host.geometryFor(0).heightPx)
        assertEquals(4_000, host.geometryFor(1).startPx)
        assertEquals(3_650, host.scrollBy(0, 9_999, 900))
    }

    @Test fun `virtualization uses geometry and preserves measured placeholders after recycle`() {
        val host = ContinuousReflowableHostModel((0 until 100).map { "chapter-$it.xhtml" })
        repeat(100) { host.reportMeasuredHeight(it, 400) }
        val plan = host.planVirtualization(scrollPx = 20_000, viewportHeightPx = 900)
        assertTrue(plan.liveIndices.containsAll(setOf(50, 51, 52)))
        assertTrue(plan.liveIndices.size <= 11)
        assertFalse(plan.liveIndices.any { it < 40 })
        val later = host.planVirtualization(scrollPx = 30_000, viewportHeightPx = 900)
        assertTrue(later.recycleIndices.contains(50))
        assertEquals(20_000, host.geometryFor(50).startPx)
    }

    @Test fun `virtualization stays bounded for large reading orders`() {
        listOf(100, 500, 1_000).forEach { count ->
            val host = ContinuousReflowableHostModel((0 until count).map { "chapter-$it.xhtml" })
            repeat(count) { host.reportMeasuredHeight(it, 400) }
            val plan = host.planVirtualization(scrollPx = (count / 2L) * 400, viewportHeightPx = 900)
            assertTrue(plan.liveIndices.size <= 11)
            assertTrue(plan.liveIndices.isNotEmpty())
        }
    }

    @Test fun `target resource can be prepared without making preceding resources live`() {
        val host = ContinuousReflowableHostModel((0 until 100).map { "chapter-$it.xhtml" })
        repeat(100) { host.reportMeasuredHeight(it, 400) }
        val plan = host.planVirtualization(scrollPx = 28_000, viewportHeightPx = 900)
        assertTrue(70 in plan.liveIndices)
        assertFalse((0..60).any { it in plan.liveIndices })
    }

    @Test fun `selection pinned resource cannot recycle`() {
        val host = ContinuousReflowableHostModel((0 until 20).map { "chapter-$it.xhtml" })
        repeat(20) { host.reportMeasuredHeight(it, 400) }
        host.planVirtualization(0, 900)
        host.setSelectionPinned(0, true)
        val plan = host.planVirtualization(5_000, 900)
        assertTrue(plan.liveIndices.contains(0))
        host.setSelectionPinned(0, false)
        assertTrue(host.planVirtualization(5_000, 900).recycleIndices.contains(0))
    }

    @Test fun `layout generation invalidates stale heights and replacement preserves content offset`() {
        val host = host(200, 300, 250)
        assertEquals(600, host.replaceMeasuredHeightAndAdjustScroll(0, 400, 400))
        assertEquals(400, host.geometryFor(1).startPx)
        assertEquals(1, host.invalidateForReflow())
        try {
            host.geometry()
            throw AssertionError("Expected stale geometry to be rejected")
        } catch (_: IllegalArgumentException) {
            // A subsequent renderer must report heights for the new layout generation.
        }
    }

    @Test fun `stale generation updates are rejected and delayed height shifts later offsets`() {
        val host = host(200, 300, 250)
        val nextGeneration = host.invalidateForReflow()
        host.reportMeasuredHeight(0, 240, nextGeneration)
        host.reportMeasuredHeight(1, 330, nextGeneration)
        host.reportMeasuredHeight(2, 250, nextGeneration)
        assertEquals(240, host.geometryFor(1).startPx)
        assertEquals(570, host.geometryFor(2).startPx)
        try {
            host.reportMeasuredHeight(1, 300, generation = nextGeneration - 1)
            throw AssertionError("Expected stale measurement to be rejected")
        } catch (_: IllegalArgumentException) {
            // A stale WebView must not overwrite current reflow geometry.
        }
    }

    @Test fun `provisional 800 estimates are replaced by measured heights without a residual gap`() {
        val host = host(800, 800, 800)
        host.reportMeasuredHeight(0, 200)
        host.reportMeasuredHeight(1, 300)
        host.reportMeasuredHeight(2, 250)
        assertEquals(200, host.geometryFor(1).startPx)
        assertEquals(500, host.geometryFor(2).startPx)
        assertEquals(750, host.documentHeightPx())
        host.reportMeasuredHeight(1, 450)
        assertEquals(650, host.geometryFor(2).startPx)
        assertEquals(900, host.documentHeightPx())
    }

    @Test fun `measured placeholder survives holder recycling and is cleared by reflow generation`() {
        val host = host(200, 300, 250)
        assertEquals(200L, host.measuredHeightOrNull(0))
        assertEquals(300L, host.measuredHeightOrNull(1))
        host.invalidateForReflow()
        assertEquals(null, host.measuredHeightOrNull(0))
    }

    @Test fun `in-place reflow keeps prior height only as geometry until fresh measurement`() {
        val host = host(200, 300, 250)
        val nextGeneration = host.beginInPlaceReflow()

        assertEquals(1, nextGeneration)
        assertEquals(null, host.measuredHeightOrNull(0))
        assertEquals(200L, host.geometryHeightOrNull(0))
        assertEquals(null, host.measuredHeightOrNull(1))
        assertEquals(300L, host.geometryHeightOrNull(1))

        host.reportMeasuredHeight(0, 200, nextGeneration)

        assertEquals(200L, host.measuredHeightOrNull(0))
        assertEquals(200L, host.geometryHeightOrNull(0))
    }

    @Test fun `geometry batch retains prior accepted heights across rapid generations`() {
        val host = host(240, 360, 180)
        host.beginInPlaceReflow()
        host.beginInPlaceReflow()

        assertEquals(null, host.measuredHeightOrNull(0))
        assertEquals(240L, host.geometryHeightOrNull(0))
        assertEquals(360L, host.geometryHeightOrNull(1))
    }

    @Test fun `geometry batch waits for all required measurements and grouped model update is atomic`() {
        val host = host(240, 360, 180)
        val generation = host.beginInPlaceReflow()
        val batch = geometryBatch(generation, mapOf(0 to 10L, 1 to 11L))

        assertEquals(ContinuousGeometryBatchCollection.REQUIRED, batch.collect(measurement(0, 420, generation, 10, 1)))
        assertEquals(null, batch.requiredMeasurementsForCommit())
        assertEquals(ContinuousGeometryBatchCollection.READY, batch.collect(measurement(1, 510, generation, 11, 1)))
        val required = batch.requiredMeasurementsForCommit()!!
        host.reportMeasuredHeightsTogether(required)
        assertEquals(420L, host.measuredHeightOrNull(0))
        assertEquals(510L, host.measuredHeightOrNull(1))
        assertEquals(ContinuousGeometryBatchState.READY, batch.state)
    }

    @Test fun `geometry batch exposes missing required measurements without changing collection`() {
        val batch = geometryBatch(3, mapOf(0 to 10L, 1 to 11L, 2 to 12L))

        assertEquals(mapOf(0 to 10L, 1 to 11L, 2 to 12L), batch.missingRequiredResourceGenerations())
        assertEquals(ContinuousGeometryBatchCollection.REQUIRED, batch.collect(measurement(0, 420, 3, 10, 1)))
        assertEquals(mapOf(1 to 11L, 2 to 12L), batch.missingRequiredResourceGenerations())
        assertEquals(ContinuousGeometryBatchState.COLLECTING, batch.state)
        assertEquals(ContinuousGeometryBatchCollection.REQUIRED, batch.collect(measurement(1, 500, 3, 11, 1)))
        assertEquals(ContinuousGeometryBatchCollection.READY, batch.collect(measurement(2, 520, 3, 12, 1)))
        assertTrue(batch.missingRequiredResourceGenerations().isEmpty())
    }

    @Test fun `newer required report replaces ready value before apply`() {
        val batch = geometryBatch(3, mapOf(0 to 10L, 1 to 11L))
        batch.collect(measurement(0, 400, 3, 10, 1))
        assertEquals(ContinuousGeometryBatchCollection.READY, batch.collect(measurement(1, 500, 3, 11, 1)))

        assertEquals(ContinuousGeometryBatchCollection.READY, batch.collect(measurement(0, 420, 3, 10, 2)))
        assertEquals(listOf(420L, 500L), batch.requiredMeasurementsForCommit()?.map { it.heightPx })
        assertTrue(batch.beginCommit())
        assertTrue(batch.markApplied())
        assertEquals(ContinuousGeometryBatchCollection.DEFERRED, batch.collect(measurement(0, 430, 3, 10, 3)))
    }

    @Test fun `commit window stages latest reports without changing prepared geometry and drains after terminal`() {
        val batch = geometryBatch(3, mapOf(0 to 10L, 1 to 11L))
        batch.collect(measurement(0, 400, 3, 10, 1))
        assertEquals(ContinuousGeometryBatchCollection.READY, batch.collect(measurement(1, 500, 3, 11, 1)))
        val prepared = batch.requiredMeasurementsForCommit()!!
        assertTrue(batch.beginCommit())

        assertEquals(ContinuousGeometryBatchCollection.DEFERRED, batch.collect(measurement(0, 420, 3, 10, 2)))
        assertEquals(ContinuousGeometryBatchCollection.DUPLICATE, batch.collect(measurement(0, 415, 3, 10, 1)))
        assertEquals(ContinuousGeometryBatchCollection.DEFERRED, batch.collect(measurement(1, 520, 3, 11, 3)))
        assertEquals(listOf(400L, 500L), prepared.map { it.heightPx })

        assertTrue(batch.markApplied())
        assertEquals(listOf(420L, 520L), batch.finish().map { it.heightPx })
    }

    @Test fun `commit failure preserves late reports for terminal drain`() {
        val batch = geometryBatch(3, mapOf(0 to 10L, 1 to 11L))
        batch.collect(measurement(0, 400, 3, 10, 1))
        batch.collect(measurement(1, 500, 3, 11, 1))
        assertTrue(batch.beginCommit())

        assertEquals(ContinuousGeometryBatchCollection.DEFERRED, batch.collect(measurement(0, 430, 3, 10, 2)))
        assertTrue(batch.failAfterCommitStart())
        assertEquals(listOf(430L), batch.finish().map { it.heightPx })
    }

    @Test fun `required resource failure remains sticky after collection becomes ready`() {
        val batch = geometryBatch(3, mapOf(0 to 10L, 1 to 11L))
        batch.collect(measurement(0, 400, 3, 10, 1))
        batch.collect(measurement(1, 500, 3, 11, 1))

        assertTrue(batch.failRequired(ContinuousReflowTarget(1, 3, 11)))
        assertEquals(ContinuousGeometryBatchState.FAILED, batch.state)
        assertEquals(null, batch.requiredMeasurementsForCommit())
        assertFalse(batch.markApplied())
    }

    @Test fun `post-mutation batch failure is explicit and cannot be discarded`() {
        val batch = geometryBatch(3, mapOf(0 to 10L, 1 to 11L))
        batch.collect(measurement(0, 400, 3, 10, 1))
        batch.collect(measurement(1, 500, 3, 11, 1))

        assertTrue(batch.beginCommit())
        assertEquals(ContinuousGeometryBatchState.COMMIT_STARTED, batch.state)
        assertFalse(batch.discard())
        assertFalse(batch.fail())
        assertTrue(batch.failAfterCommitStart())
        assertEquals(ContinuousGeometryBatchState.FAILED_AFTER_COMMIT_START, batch.state)
        assertFalse(batch.markApplied())
        assertFalse(batch.failAfterCommitStart())
    }

    @Test fun `irrelevant measurement is deferred without blocking required batch`() {
        val batch = geometryBatch(3, mapOf(0 to 10L, 1 to 11L))
        assertEquals(ContinuousGeometryBatchCollection.DEFERRED, batch.collect(measurement(2, 700, 3, 12, 1)))
        assertEquals(ContinuousGeometryBatchCollection.REQUIRED, batch.collect(measurement(0, 420, 3, 10, 1)))
        assertEquals(ContinuousGeometryBatchCollection.READY, batch.collect(measurement(1, 510, 3, 11, 1)))
        val groupedMeasurements = batch.requiredMeasurementsForCommit().orEmpty() + batch.optionalMeasurementsForCommit()
        assertEquals(listOf(420L, 510L, 700L), groupedMeasurements.map { it.heightPx })
        assertTrue(batch.beginCommit())
        assertTrue(batch.markApplied())
        assertTrue(batch.finish().isEmpty())
    }

    @Test fun `invalid grouped model update changes no accepted geometry`() {
        val host = host(240, 360, 180)
        val generation = host.beginInPlaceReflow()
        val valid = measurement(0, 420, generation, 10, 1)
        val stale = measurement(1, 510, generation - 1, 11, 1)

        try {
            host.reportMeasuredHeightsTogether(listOf(valid, stale))
            throw AssertionError("Expected stale grouped measurement to be rejected")
        } catch (_: IllegalArgumentException) {
            // Validation happens before any member is installed.
        }
        assertEquals(null, host.measuredHeightOrNull(0))
        assertEquals(240L, host.geometryHeightOrNull(0))
        assertEquals(360L, host.geometryHeightOrNull(1))
    }

    private fun geometryBatch(layoutGeneration: Int, required: Map<Int, Long>) =
        ContinuousGeometryMeasurementBatch(
            owner = ContinuousGeometryBatchOwner(7, 9, layoutGeneration),
            anchor = ContinuousReflowTarget(0, layoutGeneration, required.getValue(0)),
            requiredResourceGenerations = required,
        )

    private fun measurement(
        index: Int,
        height: Long,
        layoutGeneration: Int,
        resourceGeneration: Long,
        sequence: Long,
    ) = ResourceLayoutMeasurement(index, height, layoutGeneration, resourceGeneration, sequence, measurementEpoch = 2)

    @Test fun `locator and whole book progression stay href and positions based`() {
        val host = host(250, 1_200, 350)
        assertEquals("b.xhtml", host.locatorAnchor(300, 900, 0.25).href)
        assertEquals(35.0 / 130.0, ContinuousPublicationProgression.totalProgression(listOf(10, 100, 20), 1, 0.25), 0.0001)
    }

    @Test fun `future host remains inside one platform view publication and reader session`() {
        assertEquals(ContinuousHostOwnership(1, 1, 1), ContinuousHostOwnership(1, 1, 1))
        try {
            ContinuousHostOwnership(1, 2, 1)
            throw AssertionError("Expected duplicate publication ownership to be rejected")
        } catch (_: IllegalArgumentException) {
            // The existing ReadiumReaderSession remains the sole owner.
        }
    }
}
