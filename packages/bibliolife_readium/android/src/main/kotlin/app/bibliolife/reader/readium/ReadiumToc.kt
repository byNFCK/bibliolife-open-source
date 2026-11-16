package app.bibliolife.reader.readium

import java.net.URI

/** UI-independent TOC tree retained by a reader session. */
data class ReadiumTocEntry(
    val id: String,
    val title: String,
    val href: String,
    val fragment: String?,
    val level: Int,
    val children: List<ReadiumTocEntry>,
)

sealed interface ReadiumTocState {
    data object NotLoaded : ReadiumTocState
    data object Loading : ReadiumTocState
    data class Ready(val entries: List<ReadiumTocEntry>) : ReadiumTocState
    data object Empty : ReadiumTocState
    data class Failed(val error: ReadiumTocError) : ReadiumTocState
}

sealed class ReadiumTocError(val code: String) {
    data object PublicationUnavailable : ReadiumTocError("toc_publication_unavailable")
    data class LoadingFailed(val cause: Throwable? = null) : ReadiumTocError("toc_loading_failed")
    data object UnknownEntry : ReadiumTocError("toc_entry_unknown")
    data object SessionDisposed : ReadiumTocError("session_disposed")
}

/** A separate book title is deliberately never folded into this chapter state. */
data class ReadiumChapterState(
    val entryId: String?,
    val title: String?,
    val href: String?,
) {
    companion object {
        val Unknown = ReadiumChapterState(null, null, null)
    }
}

internal data class ReadiumTocIndex<T>(
    val entries: List<ReadiumTocEntry>,
    val flattened: List<ReadiumTocEntry>,
    val targets: Map<String, T>,
)

/** Presentation-only pre-order flattening. It contains no target or navigation logic. */
fun List<ReadiumTocEntry>.flattenReadiumToc(): List<ReadiumTocEntry> = buildList {
    fun append(entries: List<ReadiumTocEntry>) {
        entries.forEach { entry ->
            add(entry)
            append(entry.children)
        }
    }
    append(this@flattenReadiumToc)
}

internal object ReadiumTocNormalizer {
    private const val MAX_DEPTH = 64
    private const val MAX_ENTRIES = 4096

    fun <T : Any> normalize(
        roots: List<T>,
        titleOf: (T) -> String?,
        hrefOf: (T) -> String,
        childrenOf: (T) -> List<T>,
    ): ReadiumTocIndex<T> {
        val targets = LinkedHashMap<String, T>()
        var entryCount = 0
        fun entries(nodes: List<T>, level: Int): List<ReadiumTocEntry> {
            if (level > MAX_DEPTH || entryCount >= MAX_ENTRIES) return emptyList()
            return nodes.mapNotNull { node ->
                if (entryCount >= MAX_ENTRIES) return@mapNotNull null
                val target = normalizeTarget(hrefOf(node))
                if (target.href.isBlank()) return@mapNotNull null
                entryCount++
                val id = uniqueId(targets, target, titleOf(node).orEmpty())
                targets[id] = node
                ReadiumTocEntry(
                    id = id,
                    title = titleOf(node)?.trim().orEmpty(),
                    href = target.href,
                    fragment = target.fragment,
                    level = level,
                    children = entries(childrenOf(node), level + 1),
                )
            }
        }
        val normalized = entries(roots, level = 0)
        return ReadiumTocIndex(normalized, normalized.flattenReadiumToc(), targets)
    }

    fun resolveChapter(
        index: ReadiumTocIndex<*>,
        href: String,
        fragments: List<String>,
        current: ReadiumChapterState,
    ): ReadiumChapterState {
        val normalizedHref = normalizeTarget(href).href
        if (normalizedHref.isBlank()) return ReadiumChapterState.Unknown
        val candidates = index.flattened.filter { it.href == normalizedHref }
        if (candidates.isEmpty()) return ReadiumChapterState.Unknown
        val normalizedFragments = fragments.mapNotNull(::normalizeFragment).toSet()
        val selected = candidates.firstOrNull { entry -> entry.fragment in normalizedFragments }
            ?: candidates.firstOrNull { it.id == current.entryId }
            ?: candidates.first()
        return ReadiumChapterState(selected.id, selected.title.takeIf { it.isNotBlank() }, selected.href)
    }

    fun normalizeTarget(value: String): ReadiumTocTarget {
        val raw = value.trim()
        if (raw.isBlank()) return ReadiumTocTarget("", null)
        val withoutFragment = raw.substringBefore('#')
        val fragment = normalizeFragment(raw.substringAfter('#', "").takeIf { raw.contains('#') })
        val normalized = runCatching { URI(withoutFragment).normalize().path ?: withoutFragment }
            .getOrDefault(withoutFragment)
            .removePrefix("./")
            .trimStart('/')
        return ReadiumTocTarget(normalized, fragment)
    }

    private fun uniqueId(
        targets: Map<String, *>,
        target: ReadiumTocTarget,
        title: String,
    ): String {
        val base = buildString {
            append(target.href)
            target.fragment?.let { append('#').append(it) }
            append('|').append(title.trim())
        }.ifBlank { "toc" }
        var occurrence = 1
        var id = base
        while (id in targets) id = "$base@$occurrence".also { occurrence++ }
        return id
    }

    private fun normalizeFragment(value: String?): String? = value
        ?.trim()
        ?.removePrefix("#")
        ?.takeIf { it.isNotEmpty() }
}

internal data class ReadiumTocTarget(val href: String, val fragment: String?)
