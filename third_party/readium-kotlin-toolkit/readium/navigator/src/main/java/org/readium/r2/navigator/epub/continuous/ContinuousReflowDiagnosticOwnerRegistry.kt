package org.readium.r2.navigator.epub.continuous

/** Keeps request provenance adjacent to, and independent from, layout models. */
internal class ContinuousReflowDiagnosticOwnerRegistry(
    private val capacity: Int = 12,
) {
    private val owners = LinkedHashMap<Int, ReflowDiagnosticOwner>()

    init {
        require(capacity > 0)
    }

    fun record(layoutGeneration: Int, owner: ReflowDiagnosticOwner): Int? {
        owners[layoutGeneration] = owner
        if (owners.size <= capacity) return null
        val oldest = owners.keys.first()
        owners.remove(oldest)
        return oldest
    }

    fun ownerFor(layoutGeneration: Int): ReflowDiagnosticOwner? = owners[layoutGeneration]

    fun clear() = owners.clear()
}

internal data class ReflowDiagnosticOwner(
    val context: EpubContinuousReflowDiagnosticContext?,
    val preferenceGeneration: Long?,
    val transactionGeneration: Long,
    val anchorIndex: Int,
    val anchorBeforeY: Double,
)
