package org.readium.r2.navigator.epub.continuous

/** Production authority for mutations of the currently attached native host. */
internal class ContinuousHostGenerationGate {
    var activeGeneration: Long? = null
        private set
    private var disposed = false

    fun acceptAttach(generation: Long): Boolean =
        !disposed && (activeGeneration == null || generation >= activeGeneration!!)

    fun commitAttach(generation: Long) {
        check(acceptAttach(generation)) { "Stale or disposed continuous host" }
        activeGeneration = generation
    }

    fun acceptsDetach(generation: Long): Boolean = !disposed && activeGeneration == generation

    fun dispose() { disposed = true; activeGeneration = null }
}
