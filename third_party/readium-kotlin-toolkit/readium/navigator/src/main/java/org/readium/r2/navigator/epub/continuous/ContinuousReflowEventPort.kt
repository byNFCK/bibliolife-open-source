package org.readium.r2.navigator.epub.continuous

import org.readium.r2.shared.publication.Locator

internal data class ContinuousLocatorPointGeometry(
    val documentYCssPx: Double,
    val viewportTopCssPx: Double,
    val semanticAnchorExact: Boolean = false,
    val anchorIdentityId: String? = null,
    val anchorCharacterOffset: Int? = null,
)

/**
 * Event-only boundary around the Android/WebView callbacks consumed by the
 * real reflow host. It deliberately owns no readiness, restore, convergence,
 * generation, or publication state.
 */
internal interface ContinuousReflowEventPort {
    interface Sink {
        fun onTrueReady(target: ContinuousReflowTarget)
        fun onMeasurement(measurement: ResourceLayoutMeasurement)
        fun onRecyclerLayoutCommitted()
        fun onDisposed()
    }

    fun bind(sink: Sink)
    fun trueReady(target: ContinuousReflowTarget)
    fun measurement(measurement: ResourceLayoutMeasurement)
    fun recyclerLayoutCommitted()
    fun canAnswerLocator(target: ContinuousReflowTarget, runtime: () -> Boolean): Boolean
    suspend fun resolveLocatorVerticalOffset(target: ContinuousReflowTarget, locator: Locator, runtime: suspend () -> Double?): Double?
    suspend fun resolveLocatorPointGeometry(target: ContinuousReflowTarget, locator: Locator, runtime: suspend () -> ContinuousLocatorPointGeometry?): ContinuousLocatorPointGeometry?
    suspend fun observeLocator(anchor: EpubContinuousLocatorAnchor, runtime: suspend () -> Locator?): Locator?
    fun dispose()
}

/** Normal runtime delivery: each event is simply forwarded to the real host. */
internal class RuntimeContinuousReflowEventPort : ContinuousReflowEventPort {
    private var sink: ContinuousReflowEventPort.Sink? = null

    override fun bind(sink: ContinuousReflowEventPort.Sink) { this.sink = sink }
    override fun trueReady(target: ContinuousReflowTarget) { sink?.onTrueReady(target) }
    override fun measurement(measurement: ResourceLayoutMeasurement) { sink?.onMeasurement(measurement) }
    override fun recyclerLayoutCommitted() { sink?.onRecyclerLayoutCommitted() }
    override fun canAnswerLocator(target: ContinuousReflowTarget, runtime: () -> Boolean) = runtime()
    override suspend fun resolveLocatorVerticalOffset(target: ContinuousReflowTarget, locator: Locator, runtime: suspend () -> Double?) = runtime()
    override suspend fun resolveLocatorPointGeometry(target: ContinuousReflowTarget, locator: Locator, runtime: suspend () -> ContinuousLocatorPointGeometry?) = runtime()
    override suspend fun observeLocator(anchor: EpubContinuousLocatorAnchor, runtime: suspend () -> Locator?) = runtime()
    override fun dispose() { sink?.onDisposed(); sink = null }
}

/**
 * Test-only driver for the same host callbacks. It never supplies Locator
 * data: after readiness it invokes the same resource-local runtime path.
 */
internal class ControlledContinuousReflowEventPort : ContinuousReflowEventPort {
    private var sink: ContinuousReflowEventPort.Sink? = null
    private val ready = mutableSetOf<ContinuousReflowTarget>()
    internal var offsetAnswer: Double? = null
    internal var pointGeometryAnswer: ContinuousLocatorPointGeometry? = null
    var locatorRequests = 0
        private set

    override fun bind(sink: ContinuousReflowEventPort.Sink) { this.sink = sink }
    override fun trueReady(target: ContinuousReflowTarget) { ready += target; sink?.onTrueReady(target) }
    override fun measurement(measurement: ResourceLayoutMeasurement) { sink?.onMeasurement(measurement) }
    override fun recyclerLayoutCommitted() { sink?.onRecyclerLayoutCommitted() }
    override fun canAnswerLocator(target: ContinuousReflowTarget, runtime: () -> Boolean) = target in ready
    override suspend fun resolveLocatorVerticalOffset(target: ContinuousReflowTarget, locator: Locator, runtime: suspend () -> Double?) =
        offsetAnswer?.takeIf { target in ready }
    override suspend fun resolveLocatorPointGeometry(target: ContinuousReflowTarget, locator: Locator, runtime: suspend () -> ContinuousLocatorPointGeometry?) =
        pointGeometryAnswer?.takeIf { target in ready }
    override suspend fun observeLocator(anchor: EpubContinuousLocatorAnchor, runtime: suspend () -> Locator?): Locator? {
        locatorRequests += 1
        return if (
            ContinuousReflowTarget(anchor.readingOrderIndex, anchor.layoutGeneration, anchor.resourceGeneration) in ready
        ) runtime() else null
    }
    override fun dispose() { sink?.onDisposed(); sink = null; ready.clear() }
}
