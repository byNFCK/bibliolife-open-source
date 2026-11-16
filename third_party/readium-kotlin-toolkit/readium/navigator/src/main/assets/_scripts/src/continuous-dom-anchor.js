// Temporary same-document preference anchor. Never used for persisted position,
// selection, or general navigation. CSS-only reflow must retain the Text node.
import { getCssSelector } from "css-selector-generator";

const retained = new Map();
let nextId = 0;

function caret(x, y) {
  if (document.caretPositionFromPoint) {
    const p = document.caretPositionFromPoint(x, y);
    if (p) return { node: p.offsetNode, offset: p.offset };
  }
  // Android WebView already uses this feature-detected fallback in dom.js.
  if (document.caretRangeFromPoint) {
    const r = document.caretRangeFromPoint(x, y);
    if (r) return { node: r.startContainer, offset: r.startOffset };
  }
  return null;
}

function rectAt(node, offset) {
  const range = document.createRange();
  range.setStart(node, offset);
  range.collapse(true);
  const rect = range.getBoundingClientRect();
  return Number.isFinite(rect.top) && rect.height > 0 ? rect : null;
}

export function captureContinuousDomAnchor(x, y, fallback) {
  // At most 21 local hit tests, with no document-wide text search.
  for (const dy of [0, -8, 8, -16, 16, -32, 32]) {
    for (const px of [x, x * 0.5, x * 1.5]) {
      const p = caret(px, y + dy);
      if (!p || p.node.nodeType !== Node.TEXT_NODE ||
          !document.body.contains(p.node) || !p.node.nodeValue.trim() ||
          !Number.isInteger(p.offset) || p.offset < 0 ||
          p.offset > p.node.nodeValue.length) continue;
      const rect = rectAt(p.node, p.offset);
      if (!rect || Math.abs(rect.top - y) > 64) continue;
      const parent = p.node.parentElement;
      const start = {
        cssSelector: getCssSelector(parent),
        textNodeIndex: Array.from(parent.childNodes)
          .filter(n => n.nodeType === Node.TEXT_NODE).indexOf(p.node),
        charOffset: p.offset,
      };
      const id = String(++nextId);
      retained.set(id, { node: p.node, value: p.node.nodeValue, start });
      // Bounded retention. Eviction degrades explicitly, never matches another node.
      if (retained.size > 16) retained.delete(retained.keys().next().value);
      return {
        href: "#", type: "application/xhtml+xml",
        locations: {
          ...fallback.locations,
          domRange: { start },
          continuousDomAnchor: { id, charOffset: p.offset,
            pointToTargetOffsetCssPx: rect.top - y },
        },
      };
    }
  }
  return { ...fallback, text: undefined, locations: {
    ...fallback.locations, continuousDomAnchor: { id: null, charOffset: null,
      pointToTargetOffsetCssPx: 0 },
  } };
}

function validatedContinuousAnchor(locator) {
  const identity = locator.locations.continuousDomAnchor;
  const saved = retained.get(identity.id);
  const start = locator.locations.domRange && locator.locations.domRange.start;
  // Node replacement, splitting, normalization or content edits are degradation.
  // Never clamp a character offset or silently select a replacement text node.
  if (!saved || !start || !document.body.contains(saved.node) ||
      saved.node.nodeValue !== saved.value ||
      start.cssSelector !== saved.start.cssSelector ||
      start.textNodeIndex !== saved.start.textNodeIndex ||
      start.charOffset !== saved.start.charOffset ||
      identity.charOffset !== saved.start.charOffset) return null;
  return saved;
}

export function resolveContinuousDomAnchor(locator) {
  const saved = validatedContinuousAnchor(locator);
  if (!saved) return null;
  const identity = locator.locations.continuousDomAnchor;
  const start = locator.locations.domRange.start;
  const rect = rectAt(saved.node, start.charOffset);
  if (!rect) return null;
  return { documentY: rect.top + window.scrollY, viewportTop: rect.top,
    semanticAnchorExact: true, anchorIdentityId: identity.id,
    anchorCharacterOffset: start.charOffset };
}

// Diagnostics reuse the exact retained node and validation; no new anchor search.
export function continuousDiagnosticAnchorNode(locator) {
  const saved = validatedContinuousAnchor(locator);
  return saved ? saved.node : null;
}
