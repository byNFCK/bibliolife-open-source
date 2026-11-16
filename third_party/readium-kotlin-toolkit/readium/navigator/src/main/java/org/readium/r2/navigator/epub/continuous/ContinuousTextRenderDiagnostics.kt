package org.readium.r2.navigator.epub.continuous

import org.json.JSONObject

// Explicit metric-only boundary. Never forward arbitrary JS keys or DOM text.
internal val textRenderNumberFields = setOf(
    "anchorCharacterOffset", "fontSizePx", "lineHeightPx", "letterSpacingPx", "rangeLeftPx", "rangeTopPx",
    "rangeRightPx", "rangeBottomPx", "rangeWidthPx", "rangeHeightPx", "clientRectCount", "firstRectTopPx",
    "firstRectHeightPx", "elementTopPx", "elementBottomPx", "elementHeightPx", "devicePixelRatio", "scrollYCssPx",
    "visualViewportScale", "resourceHeightCssPx", "loadingEventCount", "rangeTopDeltaPx", "rangeHeightDeltaPx",
    "rangeLeftDeltaPx", "rangeWidthDeltaPx", "elementTopDeltaPx", "elementHeightDeltaPx", "lineHeightDeltaPx",
    "fontSizeDeltaPx", "letterSpacingDeltaPx", "resourceHeightCssDeltaPx", "declaredFaceCount",
)
internal val textRenderStringFields = setOf(
    "kind", "result", "snapshotStage", "rangeMode", "anchorIdentityId", "fontFamily", "declaredPrimaryFamily",
    "fontWeight", "requestedWeight", "fontStyle", "fontStretch", "fontVariationSettings", "fontFeatureSettings",
    "fontSynthesis", "declaredWeights", "fontSetStatus", "elementTag", "fontLoadingEvents",
    "fontWeightBefore", "fontWeightAfter", "fontSetStatusBefore", "fontSetStatusAfter",
    "lineHeight", "letterSpacing", "declaredFaceStatuses",
)
internal val textRenderBooleanFields = setOf(
    "sameDomIdentity", "sameCharacterOffset", "forced_layout_sample", "fallbackChainPresent", "fontFamilyChanged",
    "declaredFacesTruncated", "variableWeightDeclared",
)
internal val textRenderTriStateFields = setOf(
    "syntheticWeightLikely", "activeFontCheck", "activeFontCheckBefore", "activeFontCheckAfter",
)

internal fun continuousTextRenderDiagnosticFields(payload: String): Map<String, Any>? {
    if (payload.length > 12000) return null
    val json = try { JSONObject(payload) } catch (_: Exception) { return null }
    if (json.optString("kind") !in setOf("webview_text_render_snapshot", "webview_text_render_compare")) return null
    return buildMap {
        textRenderNumberFields.forEach { key ->
            (json.opt(key) as? Number)?.toDouble()?.takeIf { it.isFinite() }?.let { put(key, it) }
        }
        textRenderStringFields.forEach { key ->
            (json.opt(key) as? String)?.takeIf {
                it.length in 1..160 && it.none { c -> c.isISOControl() || c == '<' || c == '>' }
            }?.let { put(key, it) }
        }
        textRenderBooleanFields.forEach { key -> (json.opt(key) as? Boolean)?.let { put(key, it) } }
        textRenderTriStateFields.forEach { key ->
            json.opt(key)?.takeIf { it is Boolean || it == "unknown" }?.let { put(key, it) }
        }
    }
}
