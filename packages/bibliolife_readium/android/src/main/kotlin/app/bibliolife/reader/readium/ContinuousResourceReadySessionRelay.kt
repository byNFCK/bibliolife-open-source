package app.bibliolife.reader.readium

import org.readium.r2.navigator.epub.continuous.EpubContinuousResourceReadyEvent

/**
 * Retains a true-ready resource generation through the rendition/session seam.
 * The rendition validates that the event's WebView is still live; this relay
 * additionally rejects a callback from a superseded rendition before it can
 * activate session preference readiness or request the real parent-anchor
 * Locator query. Preference readiness is emitted once per rendition identity;
 * later resources still trigger their own Locator refresh.
 */
internal class ContinuousResourceReadySessionRelay {
    private var preferenceReadyRendition: Any? = null

    fun forward(
        activeRendition: Any?,
        sourceRendition: Any,
        event: EpubContinuousResourceReadyEvent,
        markPreferencesReady: () -> Unit,
        requestAnchorLocator: (EpubContinuousResourceReadyEvent) -> Unit,
    ): Boolean {
        if (activeRendition !== sourceRendition) return false
        if (preferenceReadyRendition !== sourceRendition) {
            preferenceReadyRendition = sourceRendition
            markPreferencesReady()
        }
        requestAnchorLocator(event)
        return true
    }
}
