// Read-only diagnostics. Physical font identity and Chromium paint are not exposed.
import { continuousDiagnosticAnchorNode } from "./continuous-dom-anchor";

let active = null;
const finite = v => Number.isFinite(v) ? v : null;
const cssNumber = v => /^-?[\d.]+px$/.test(v || "") ? finite(parseFloat(v)) : null;
const bounded = v => String(v || "unknown").replace(/[\r\n<>]/g, "").slice(0, 160);
const families = v => String(v).match(/(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^,])+/g) || [];
const primary = v => (families(v)[0] || "").trim().replace(/^["']|["']$/g, "").toLowerCase();

function emit(state, payload) {
  try {
    window.BiblioLifeContinuousMeasurement.textRenderDiagnostic(state.token,
      JSON.stringify(payload));
  } catch (_) { /* diagnostics never control reflow */ }
}

export function textRenderSnapshot(locator) {
  if (!locator || !locator.locations || !locator.locations.continuousDomAnchor)
    return { result: "exact_anchor_unavailable", sameDomIdentity: false };
  const node = continuousDiagnosticAnchorNode(locator);
  const identity = locator.locations.continuousDomAnchor;
  if (!node) return { result: "exact_anchor_unavailable", sameDomIdentity: false };
  const element = node.parentElement;
  const style = getComputedStyle(element);
  const offset = identity.charOffset;
  const range = document.createRange();
  // Same UTF-16 boundary; never touch the user's Selection or clamp the anchor.
  range.setStart(node, offset);
  range.collapse(true);
  let rect = range.getBoundingClientRect();
  let rangeMode = "caret";
  if ((!rect || !rect.height || !rect.width) && node.length > 0) {
    let start = offset < node.length ? offset : offset - 1;
    let end = offset < node.length ? offset + 1 : offset;
    const value = node.nodeValue;
    if (start > 0 && /[\uDC00-\uDFFF]/.test(value[start]) && /[\uD800-\uDBFF]/.test(value[start - 1])) start--;
    if (end < node.length && /[\uD800-\uDBFF]/.test(value[end - 1]) && /[\uDC00-\uDFFF]/.test(value[end])) end++;
    range.setStart(node, start);
    range.setEnd(node, end);
    rect = range.getBoundingClientRect();
    rangeMode = "one_utf16_unit";
  }
  const rects = range.getClientRects();
  const box = element.getBoundingClientRect();
  const fonts = document.fonts;
  let check = "unknown";
  if (fonts && typeof fonts.check === "function") {
    try { check = fonts.check(`${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`); }
    catch (_) { /* valid CSS may still be unsupported by FontFaceSet.check */ }
  }
  const faces = [];
  let declaredFaceCount = 0;
  // FontFaceSet exposes declarations/status, never the actual rendered file.
  if (fonts && typeof fonts.forEach === "function") fonts.forEach(face => {
    if (primary(face.family) === primary(style.fontFamily)) {
      declaredFaceCount++;
      if (faces.length < 16) faces.push({ weight: bounded(face.weight), status: face.status });
    }
  });
  const requested = Number(style.fontWeight);
  const covers = weight => {
    const pair = weight.replace(/^normal$/, "400").replace(/^bold$/, "700").split(/\s+/).map(Number);
    return pair.length === 2 ? requested >= pair[0] && requested <= pair[1] : requested === pair[0];
  };
  let synthesis = "unknown";
  if (style.fontSynthesis === "none") synthesis = false;
  if (style.fontSynthesis && style.fontSynthesis !== "none" &&
      /auto|weight/.test(style.fontSynthesis) && check === true && faces.length && declaredFaceCount === faces.length &&
      faces.every(face => face.status === "loaded") && Number.isFinite(requested))
    synthesis = faces.some(face => covers(face.weight)) ? false :
      requested >= 600 && faces.every(face => Number(face.weight.replace(/^normal$/, "400")) <= 500) ? true : "unknown";
  return {
    result: "captured", sameDomIdentity: true, anchorIdentityId: identity.id,
    anchorCharacterOffset: offset, forced_layout_sample: true, rangeMode,
    fontFamily: bounded(style.fontFamily), declaredPrimaryFamily: bounded(primary(style.fontFamily)),
    fallbackChainPresent: families(style.fontFamily).length > 1, fontWeight: bounded(style.fontWeight),
    requestedWeight: bounded(document.documentElement.style.getPropertyValue("font-weight")),
    fontSizePx: cssNumber(style.fontSize), lineHeightPx: cssNumber(style.lineHeight),
    lineHeight: bounded(style.lineHeight), letterSpacing: bounded(style.letterSpacing),
    letterSpacingPx: cssNumber(style.letterSpacing), fontStyle: bounded(style.fontStyle),
    fontStretch: bounded(style.fontStretch), fontVariationSettings: bounded(style.fontVariationSettings),
    fontFeatureSettings: bounded(style.fontFeatureSettings), fontSynthesis: bounded(style.fontSynthesis),
    declaredWeights: bounded(faces.map(f => f.weight).join("|")), declaredFaceCount,
    declaredFaceStatuses: bounded(faces.map(f => f.weight + ":" + f.status).join("|")),
    declaredFacesTruncated: declaredFaceCount > faces.length,
    variableWeightDeclared: faces.some(f => /^\d+\s+\d+$/.test(f.weight)), syntheticWeightLikely: synthesis,
    fontSetStatus: fonts ? bounded(fonts.status) : "unsupported", activeFontCheck: check,
    rangeLeftPx: finite(rect.left), rangeTopPx: finite(rect.top), rangeRightPx: finite(rect.right),
    rangeBottomPx: finite(rect.bottom), rangeWidthPx: finite(rect.width), rangeHeightPx: finite(rect.height),
    clientRectCount: rects.length, firstRectTopPx: rects.length ? finite(rects[0].top) : null,
    firstRectHeightPx: rects.length ? finite(rects[0].height) : null,
    elementTag: bounded(element.tagName), elementTopPx: finite(box.top),
    elementBottomPx: finite(box.bottom), elementHeightPx: finite(box.height),
    devicePixelRatio: finite(window.devicePixelRatio), scrollYCssPx: finite(window.scrollY),
    visualViewportScale: window.visualViewport ? finite(window.visualViewport.scale) : null,
    resourceHeightCssPx: finite(document.body.scrollHeight),
  };
}

export function compareTextRender(before, after, loadingEventCount = 0) {
  const same = before.sameDomIdentity === true && after.sameDomIdentity === true &&
    before.anchorIdentityId === after.anchorIdentityId;
  const sameOffset = same && before.anchorCharacterOffset === after.anchorCharacterOffset;
  const comparison = {
    anchorIdentityId: after.anchorIdentityId, sameDomIdentity: same,
    sameCharacterOffset: sameOffset, fontFamilyChanged: before.fontFamily !== after.fontFamily,
    fontWeightBefore: before.fontWeight, fontWeightAfter: after.fontWeight,
    fontSetStatusBefore: before.fontSetStatus, fontSetStatusAfter: after.fontSetStatus,
    activeFontCheckBefore: before.activeFontCheck, activeFontCheckAfter: after.activeFontCheck,
    syntheticWeightLikely: after.syntheticWeightLikely, loadingEventCount,
  };
  for (const name of ["rangeTop", "rangeHeight", "rangeLeft", "rangeWidth", "elementTop",
    "elementHeight", "lineHeight", "fontSize", "letterSpacing", "resourceHeightCss"]) {
    const a = before[name + "Px"], b = after[name + "Px"];
    comparison[name + "DeltaPx"] = typeof a === "number" && typeof b === "number" ? finite(b - a) : null;
  }
  const changed = ["rangeTopDeltaPx", "rangeHeightDeltaPx", "rangeLeftDeltaPx", "rangeWidthDeltaPx",
    "elementTopDeltaPx", "elementHeightDeltaPx", "resourceHeightCssDeltaPx"];
  const styleMetricChanged = ["lineHeightDeltaPx", "fontSizeDeltaPx", "letterSpacingDeltaPx"]
    .some(k => typeof comparison[k] === "number" && Math.abs(comparison[k]) > 0.01);
  comparison.result = "unknown";
  if (!sameOffset) return comparison;
  if (comparison.fontFamilyChanged) comparison.result = "font_face_change"; // computed-family candidate only
  else if (loadingEventCount || before.fontSetStatus === "loading" || after.fontSetStatus === "loading")
    comparison.result = "font_loading_transition";
  else if (after.syntheticWeightLikely === true) comparison.result = "synthetic_weight_likely";
  else if (styleMetricChanged || changed.some(k => typeof comparison[k] === "number" && Math.abs(comparison[k]) > 0.01))
    comparison.result = "range_geometry_changed";
  else if (before.lineHeight === after.lineHeight && before.fontSizePx === after.fontSizePx &&
    before.letterSpacing === after.letterSpacing && changed.every(k => comparison[k] === 0) && before.fontSetStatus === "loaded" &&
    after.fontSetStatus === "loaded" && before.activeFontCheck === true && after.activeFontCheck === true)
    comparison.result = "stable_layout_repaint_suspected";
  return comparison;
}

function stop() {
  if (active) active.cleanup();
  active = null;
}

export function beginTextRender(token, context) {
  stop();
  const state = { token, context, loadingEventCount: 0, events: new Set(), measured: false };
  const fonts = document.fonts;
  const listener = event => {
    // FontFaceSet events are document-wide: report correlation, not active-face proof.
    state.loadingEventCount++;
    state.events.add(event.type);
  };
  const names = ["loading", "loadingdone", "loadingerror"];
  if (fonts && fonts.addEventListener) names.forEach(n => fonts.addEventListener(n, listener));
  state.cleanup = () => { if (fonts && fonts.removeEventListener) names.forEach(n => fonts.removeEventListener(n, listener)); };
  active = state;
  state.before = textRenderSnapshot(context.locator);
  emit(state, { ...state.before, kind: "webview_text_render_snapshot", snapshotStage: "before_css" });
}

export function sampleTextRender(token, stage) {
  if (!active || active.token !== token) return;
  const state = active;
  if (stage === "after_measurement" && state.measured) return;
  if (stage === "after_measurement") state.measured = true;
  const snapshot = textRenderSnapshot(state.context.locator);
  emit(state, { ...snapshot, kind: "webview_text_render_snapshot", snapshotStage: stage,
    loadingEventCount: state.loadingEventCount, fontLoadingEvents: [...state.events].join("|") || "none" });
  if (stage === "after_measurement") emit(state, { ...compareTextRender(state.before, snapshot,
    state.loadingEventCount), kind: "webview_text_render_compare", snapshotStage: stage });
  if (stage === "after_measurement" || stage === "terminal") stop();
}

// Best effort wrappers: unsupported font/DOM APIs cannot interrupt CSS installation.
window.readium.textRenderDiagnostic = function (stage, token, context) {
  try {
    if (stage === "before_css") beginTextRender(token, context);
    else if (stage === "cancel") { if (active && active.token === token) stop(); }
    else sampleTextRender(token, stage);
  } catch (_) { stop(); }
};
