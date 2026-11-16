package org.readium.r2.navigator.epub

/**
 * Small, synchronous lifecycle primitive used at the real publication web
 * ownership boundary. It deliberately has no restart path.
 */
internal class PublicationWebLifecycle(
    private val onDispose: () -> Unit = {},
) {
    private var disposed = false

    val isDisposed: Boolean get() = disposed

    fun dispose() {
        if (disposed) return
        disposed = true
        onDispose()
    }

    fun checkActive(owner: String) {
        check(!disposed) { "$owner is disposed" }
    }
}
