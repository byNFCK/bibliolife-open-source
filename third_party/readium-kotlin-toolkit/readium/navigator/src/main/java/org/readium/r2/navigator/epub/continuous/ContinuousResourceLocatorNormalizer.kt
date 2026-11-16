package org.readium.r2.navigator.epub.continuous

import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator

/**
 * Converts a DOM locator produced inside one continuous resource into a
 * publication locator. The Readium web script deliberately uses `#` because
 * it has no knowledge of the publication manifest. The host, however, owns
 * the generation-checked reading-order resource and is the sole authority
 * allowed to bind that DOM location to a publication href.
 */
internal object ContinuousResourceLocatorNormalizer {
    fun normalize(resourceLocator: Locator, readingOrderLink: Link): Locator? {
        if (!resourceLocator.hasSemanticDocumentLocation()) return null

        return resourceLocator.copy(
            href = readingOrderLink.url(),
            mediaType = readingOrderLink.mediaType ?: resourceLocator.mediaType,
            title = readingOrderLink.title ?: resourceLocator.title,
        )
    }

    private fun Locator.hasSemanticDocumentLocation(): Boolean =
        locations.progression?.takeIf { it.isFinite() && it in 0.0..1.0 } != null &&
            (
                locations.fragments.isNotEmpty() ||
                    (locations["cssSelector"] as? String)?.isNotBlank() == true ||
                    !text.highlight.isNullOrBlank()
                )
}
