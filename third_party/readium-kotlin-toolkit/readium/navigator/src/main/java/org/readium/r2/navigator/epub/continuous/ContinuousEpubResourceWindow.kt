package org.readium.r2.navigator.epub.continuous

/**
 * The authoritative lifetime owner for real continuous EPUB resources.
 * RecyclerView holders only host a resource temporarily; they never decide
 * whether its R2BasicWebView remains alive.
 */
internal class ContinuousEpubResourceWindow<T>(
    private val create: (index: Int, generation: Long) -> T,
    private val release: (T) -> Unit,
    private val maxNonVisiblePreloadResources: Int = MAX_NON_VISIBLE_PRELOAD_RESOURCES,
) {
    init { require(maxNonVisiblePreloadResources >= 0) }

    enum class State { LIVE_VISIBLE, LIVE_PRELOAD, LIVE_PINNED }

    private data class Live<T>(val value: T, val generation: Long)
    private val live = linkedMapOf<Int, Live<T>>()
    private val generations = mutableMapOf<Int, Long>()
    private val pins = mutableMapOf<Int, MutableSet<ContinuousResourcePinReason>>()
    private var visible = emptySet<Int>()

    fun reconcile(visibleIndices: Set<Int>, preloadCandidates: Sequence<Int>) {
        visible = visibleIndices.toSet()
        val pinned = pins.filterValues { it.isNotEmpty() }.keys
        val preload = preloadCandidates
            .asSequence()
            .filter { it !in visible && it !in pinned }
            .distinct()
            .take(maxNonVisiblePreloadResources)
            .toSet()
        val desired = visible + pinned + preload

        live.keys.filter { it !in desired }.toList().forEach { index ->
            release(live.remove(index)!!.value)
        }
        desired.sorted().forEach { index ->
            if (index !in live) {
                val generation = (generations[index] ?: 0L) + 1L
                generations[index] = generation
                live[index] = Live(create(index, generation), generation)
            }
        }
    }

    fun pin(index: Int, reason: ContinuousResourcePinReason) {
        pins.getOrPut(index, ::mutableSetOf).add(reason)
    }

    fun unpin(index: Int, reason: ContinuousResourcePinReason) {
        pins[index]?.apply { remove(reason); if (isEmpty()) pins.remove(index) }
    }

    fun resourceAt(index: Int): T? = live[index]?.value
    fun generationAt(index: Int): Long? = live[index]?.generation

    /** Explicit resource-local operation; never falls back to another live resource. */
    fun <R> withLiveResource(index: Int, generation: Long, block: (T) -> R): R? =
        live[index]?.takeIf { it.generation == generation }?.let { block(it.value) }
    fun liveIndices(): Set<Int> = live.keys.toSet()
    fun states(): Map<Int, State> = live.keys.associateWith { index ->
        when {
            index in visible -> State.LIVE_VISIBLE
            index in pins -> State.LIVE_PINNED
            else -> State.LIVE_PRELOAD
        }
    }
    fun nonVisibleUnpinnedLiveCount(): Int = states().values.count { it == State.LIVE_PRELOAD }

    fun disposeAll() {
        live.values.toList().asReversed().forEach { release(it.value) }
        live.clear()
        pins.clear()
        visible = emptySet()
    }

    companion object { const val MAX_NON_VISIBLE_PRELOAD_RESOURCES = 8 }
}
