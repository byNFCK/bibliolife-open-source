package org.readium.r2.navigator.epub

/** Parser-local marker; no-op when the target diagnostics bridge is absent. */
internal fun parserTimingMarker(label: String): String =
    "<script type=\"text/javascript\">(function(){var b=window.BiblioLifePageLifecycleDiagnostics;if(b)b.parserMarker('$label',performance.now());})();</script>"

internal fun parserTimingBoundary(label: String, html: String): String =
    parserTimingMarker("${label}_B") + html + parserTimingMarker("${label}_E")
