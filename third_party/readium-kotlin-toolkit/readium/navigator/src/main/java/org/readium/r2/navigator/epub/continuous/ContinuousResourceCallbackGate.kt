package org.readium.r2.navigator.epub.continuous

/** Production callback authority shared by continuous resource event entry points. */
internal class ContinuousResourceCallbackGate {
    private var disposed = false

    fun dispose() { disposed = true }

    fun accepts(
        index: Int,
        resourceGeneration: Long,
        callbackLayoutGeneration: Int,
        currentLayoutGeneration: Int,
        currentResourceGeneration: Long?,
    ): Boolean = !disposed && callbackLayoutGeneration == currentLayoutGeneration && currentResourceGeneration == resourceGeneration && index >= 0
}
