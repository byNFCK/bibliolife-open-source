package org.readium.r2.navigator.epub

import org.readium.r2.shared.publication.Link

/**
 * Immutable identity passed across reusable EPUB web-resource boundaries.
 *
 * The legacy pager currently creates one identity per page fragment. Future
 * renditions can keep several identities active without relying on a global
 * current WebView.
 */
internal data class EpubWebResourceIdentity(
    val readingOrderIndex: Int,
    val href: String,
    val generation: Long,
) {
    init {
        require(readingOrderIndex >= 0)
        require(href.isNotBlank())
        require(generation >= 0)
    }

    companion object {
        fun from(link: Link, readingOrderIndex: Int, generation: Long = 0): EpubWebResourceIdentity =
            EpubWebResourceIdentity(readingOrderIndex, link.href.toString(), generation)
    }
}
