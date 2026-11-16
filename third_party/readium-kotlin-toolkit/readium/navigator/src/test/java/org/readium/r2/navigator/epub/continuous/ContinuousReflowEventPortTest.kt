package org.readium.r2.navigator.epub.continuous

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ContinuousReflowEventPortTest {
    private fun locator(href: String = "chapter.xhtml") = Locator(
        href = Url(href)!!,
        mediaType = MediaType.XHTML,
        locations = Locator.Locations(progression = 0.5),
    )

    private fun anchor(target: ContinuousReflowTarget) = EpubContinuousLocatorAnchor(
        readingOrderIndex = target.index,
        resourceGeneration = target.resourceGeneration,
        layoutGeneration = target.layoutGeneration,
        x = 12.0,
        y = 24.0,
    )

    @Test fun `controlled port delivers only the real host event categories`() = runBlocking {
        val port = ControlledContinuousReflowEventPort()
        val events = mutableListOf<String>()
        val target = ContinuousReflowTarget(index = 7, layoutGeneration = 4, resourceGeneration = 12)
        port.bind(object : ContinuousReflowEventPort.Sink {
            override fun onTrueReady(target: ContinuousReflowTarget) { events += "ready:${target.resourceGeneration}" }
            override fun onMeasurement(measurement: ResourceLayoutMeasurement) { events += "measurement:${measurement.measurementGeneration}" }
            override fun onRecyclerLayoutCommitted() { events += "layout" }
            override fun onDisposed() { events += "disposed" }
        })

        port.trueReady(target)
        port.measurement(ResourceLayoutMeasurement(7, 900, 4, 12, 2))
        port.recyclerLayoutCommitted()
        assertNull(port.observeLocator(EpubContinuousLocatorAnchor(7, 12, 4, 0.0, 0.0)) { null })
        port.dispose()

        assertEquals(listOf("ready:12", "measurement:2", "layout", "disposed"), events)
        assertEquals(1, port.locatorRequests)
    }

    @Test fun `controlled port invokes the real runtime only for the ready resource generation`() = runBlocking {
        val port = ControlledContinuousReflowEventPort()
        val g1 = ContinuousReflowTarget(index = 7, layoutGeneration = 4, resourceGeneration = 12)
        val g2 = g1.copy(resourceGeneration = 13)
        var runtimeCalls = 0

        port.trueReady(g1)
        assertNull(port.observeLocator(EpubContinuousLocatorAnchor(7, 12, 4, 0.0, 0.0)) {
            runtimeCalls += 1
            null
        })
        assertNull(port.observeLocator(EpubContinuousLocatorAnchor(7, 13, 4, 0.0, 0.0)) {
            runtimeCalls += 1
            null
        })
        port.trueReady(g2)
        assertNull(port.observeLocator(EpubContinuousLocatorAnchor(7, 13, 4, 0.0, 0.0)) {
            runtimeCalls += 1
            null
        })
        port.dispose()
        assertNull(port.observeLocator(EpubContinuousLocatorAnchor(7, 13, 4, 0.0, 0.0)) {
            runtimeCalls += 1
            null
        })

        assertEquals(2, runtimeCalls)
    }

    @Test fun `controlled port rejects stale layout resource and disposed locator answers`() = runBlocking {
        val port = ControlledContinuousReflowEventPort()
        val current = ContinuousReflowTarget(index = 6, layoutGeneration = 4, resourceGeneration = 10)
        val staleLayout = current.copy(layoutGeneration = 3)
        val staleResource = current.copy(resourceGeneration = 9)
        var runtimeLocatorCalls = 0

        port.offsetAnswer = 72.0
        port.trueReady(staleLayout)
        port.trueReady(staleResource)

        assertFalse(port.canAnswerLocator(current) { true })
        assertNull(port.resolveLocatorVerticalOffset(current, locator()) { 12.0 })
        assertNull(port.observeLocator(anchor(current)) {
            runtimeLocatorCalls += 1
            locator()
        })

        port.trueReady(current)
        assertTrue(port.canAnswerLocator(current) { false })
        assertEquals(72.0, port.resolveLocatorVerticalOffset(current, locator()) { 12.0 })
        assertEquals(locator(), port.observeLocator(anchor(current)) {
            runtimeLocatorCalls += 1
            locator()
        })

        port.dispose()
        assertFalse(port.canAnswerLocator(current) { false })
        assertNull(port.resolveLocatorVerticalOffset(current, locator()) { 12.0 })
        assertNull(port.observeLocator(anchor(current)) {
            runtimeLocatorCalls += 1
            locator()
        })
        assertEquals(1, runtimeLocatorCalls)
    }

    @Test fun `runtime port delegates readiness offsets and locator observation without owning transaction state`() = runBlocking {
        val port = RuntimeContinuousReflowEventPort()
        val target = ContinuousReflowTarget(index = 6, layoutGeneration = 4, resourceGeneration = 10)
        val events = mutableListOf<String>()

        port.bind(object : ContinuousReflowEventPort.Sink {
            override fun onTrueReady(target: ContinuousReflowTarget) { events += "ready:${target.index}" }
            override fun onMeasurement(measurement: ResourceLayoutMeasurement) { events += "measurement:${measurement.heightPx}" }
            override fun onRecyclerLayoutCommitted() { events += "layout" }
            override fun onDisposed() { events += "disposed" }
        })

        port.trueReady(target)
        port.measurement(ResourceLayoutMeasurement(6, 960, 4, 10, 1))
        port.recyclerLayoutCommitted()

        assertFalse(port.canAnswerLocator(target) { false })
        assertTrue(port.canAnswerLocator(target) { true })
        assertEquals(33.0, port.resolveLocatorVerticalOffset(target, locator()) { 33.0 })
        assertEquals(locator(), port.observeLocator(anchor(target)) { locator() })
        port.dispose()

        assertEquals(listOf("ready:6", "measurement:960", "layout", "disposed"), events)
    }
}
