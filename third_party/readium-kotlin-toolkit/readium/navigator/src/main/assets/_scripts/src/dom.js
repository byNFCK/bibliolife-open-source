//
//  Copyright 2022 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import { isScrollModeEnabled } from "./utils";
import { getCssSelector } from "css-selector-generator";

// See. https://github.com/JayPanoz/architecture/tree/touch-handling/misc/touch-handling
export function nearestInteractiveElement(element) {
  if (element == null) {
    return null;
  }
  var interactiveTags = [
    "a",
    "audio",
    "button",
    "canvas",
    "details",
    "input",
    "label",
    "option",
    "select",
    "submit",
    "textarea",
    "video",
  ];
  if (interactiveTags.indexOf(element.nodeName.toLowerCase()) != -1) {
    return element.outerHTML;
  }

  // Checks whether the element is editable by the user.
  if (
    element.hasAttribute("contenteditable") &&
    element.getAttribute("contenteditable").toLowerCase() != "false"
  ) {
    return element.outerHTML;
  }

  // Checks parents recursively because the touch might be for example on an <em> inside a <a>.
  if (element.parentElement) {
    return nearestInteractiveElement(element.parentElement);
  }

  return null;
}

export function findFirstVisibleLocator() {
  const element = findElement(document.body);
  return locatorForElement(element);
}

// The continuous host owns the outer scroll position, so the reader needs a
// locator for a specific point in one already-live resource. This deliberately
// stays resource-local: it has no pager or global WebView dependency.
export function findLocatorAtPoint(x, y) {
  return locatorAtPoint(x, y).locator;
}

// This is intentionally diagnostic-only. The production Locator remains the
// exact value returned by findLocatorAtPoint(); callers must not persist or
// resolve this additional DOM evidence.
export function findLocatorAtPointDiagnostic(x, y) {
  const point = locatorAtPoint(x, y);
  return {
    locator: point.locator,
    diagnostic: caretRangeDiagnostic(point.range),
  };
}

function locatorAtPoint(x, y) {
  const range = caretRangeAtPoint(x, y);
  // A caret describes the semantic point more precisely than the painted
  // container returned by elementFromPoint(), which may be a header wrapper.
  // Keep the legacy painted-element fallback only when the platform cannot
  // provide a caret range at all.
  const element = range
    ? canonicalElementForRange(range) || document.body
    : document.elementFromPoint(x, y) || document.body;
  return {
    locator: locatorForElement(element, progressionForRange(range)),
    range: range,
  };
}

function canonicalElementForRange(range) {
  if (!range) return null;

  const container = range.startContainer;
  if (container.nodeType === Node.ELEMENT_NODE) {
    // A caret at an element boundary belongs to its next DOM child when one
    // exists. Returning the wrapper itself loses the specific semantic node
    // and makes an otherwise identical post-reflow text caret resolve to a
    // different Locator selector.
    // EPUB markup often inserts whitespace text nodes between the wrapper's
    // semantic children. Prefer the child at the boundary, then the closest
    // following or preceding element, instead of promoting that whitespace
    // boundary to the wrapper.
    for (
      let index = range.startOffset;
      index < container.childNodes.length;
      index++
    ) {
      const child = container.childNodes[index];
      if (child.nodeType === Node.ELEMENT_NODE) return child;
    }
    for (let index = range.startOffset - 1; index >= 0; index--) {
      const child = container.childNodes[index];
      if (child.nodeType === Node.ELEMENT_NODE) return child;
    }
    return container;
  }
  return container.parentElement || null;
}

function locatorForElement(element, progression) {
  return {
    href: "#",
    type: "application/xhtml+xml",
    locations: {
      cssSelector: getCssSelector(element),
      // Semantic DOM-text offset at the actual Readium point, not a pixel ratio.
      progression: progression,
    },
    text: {
      highlight: element.textContent,
    },
  };
}

function progressionForRange(range) {
  if (!range || !document.body) return undefined;

  const prefix = document.createRange();
  prefix.setStart(document.body, 0);
  prefix.setEnd(range.startContainer, range.startOffset);
  const total = document.body.textContent.length;
  return total > 0 ? prefix.toString().length / total : undefined;
}

function caretRangeAtPoint(x, y) {
  return (
    (document.caretRangeFromPoint && document.caretRangeFromPoint(x, y)) ||
    caretRangeFromPosition(x, y)
  );
}

const DIAGNOSTIC_TEXT_LIMIT = 120;
const DIAGNOSTIC_SELECTOR_LIMIT = 160;
const DIAGNOSTIC_ANCESTOR_LIMIT = 6;

function caretRangeDiagnostic(range) {
  if (!range || !document.body) return null;

  const caretNode = textNodeForRange(range);
  const parent = canonicalElementForRange(range);
  if (!caretNode || !parent) return null;

  const canonicalText = boundedNormalizedText(
    caretNode.nodeValue,
    DIAGNOSTIC_TEXT_LIMIT
  );
  const quote = boundedCaretQuote(caretNode.nodeValue, range.startOffset);
  const normalizedResource = normalizeDiagnosticText(document.body.textContent);
  return {
    schema: 1,
    caret: {
      text: canonicalText,
      offset: Math.max(
        0,
        Math.min(range.startOffset, caretNode.nodeValue.length)
      ),
      parentSelector: boundedSelector(parent),
    },
    quote: quote,
    ancestors: diagnosticAncestors(parent),
    normalizedResourceQuoteOccurrences: countExactOccurrence(
      normalizedResource,
      quote.highlight
    ),
  };
}

function textNodeForRange(range) {
  if (range.startContainer.nodeType === Node.TEXT_NODE)
    return range.startContainer;
  if (range.startContainer.nodeType !== Node.ELEMENT_NODE) return null;
  const child = range.startContainer.childNodes[range.startOffset];
  if (child && child.nodeType === Node.TEXT_NODE) return child;
  return null;
}

function boundedCaretQuote(text, offset) {
  const start = Math.max(0, offset - DIAGNOSTIC_TEXT_LIMIT);
  const end = Math.min(text.length, offset + DIAGNOSTIC_TEXT_LIMIT);
  return {
    before: boundedNormalizedText(
      text.slice(start, offset),
      DIAGNOSTIC_TEXT_LIMIT
    ),
    highlight: boundedNormalizedText(
      text.slice(start, end),
      DIAGNOSTIC_TEXT_LIMIT
    ),
    after: boundedNormalizedText(
      text.slice(offset, end),
      DIAGNOSTIC_TEXT_LIMIT
    ),
  };
}

function diagnosticAncestors(element) {
  const ancestors = [];
  let current = element;
  while (current && ancestors.length < DIAGNOSTIC_ANCESTOR_LIMIT) {
    ancestors.push({
      tag: current.tagName.toLowerCase(),
      id: boundedNormalizedText(current.id, DIAGNOSTIC_SELECTOR_LIMIT),
      selector: boundedSelector(current),
    });
    current = current.parentElement;
  }
  return ancestors;
}

function boundedSelector(element) {
  try {
    return boundedNormalizedText(
      getCssSelector(element),
      DIAGNOSTIC_SELECTOR_LIMIT
    );
  } catch (_) {
    return boundedNormalizedText(
      element.tagName.toLowerCase(),
      DIAGNOSTIC_SELECTOR_LIMIT
    );
  }
}

function boundedNormalizedText(value, limit) {
  return normalizeDiagnosticText(value).slice(0, limit);
}

function normalizeDiagnosticText(value) {
  return (value || "").replace(/\s+/g, " ").trim();
}

function countExactOccurrence(resourceText, quote) {
  if (!quote) return 0;
  let count = 0;
  let index = 0;
  while (index <= resourceText.length - quote.length) {
    const match = resourceText.indexOf(quote, index);
    if (match < 0) break;
    count += 1;
    index = match + quote.length;
  }
  return count;
}

function caretRangeFromPosition(x, y) {
  if (!document.caretPositionFromPoint) return null;
  const position = document.caretPositionFromPoint(x, y);
  if (!position) return null;
  const range = document.createRange();
  range.setStart(position.offsetNode, position.offset);
  range.collapse(true);
  return range;
}

function findElement(rootElement) {
  for (var i = 0; i < rootElement.children.length; i++) {
    const child = rootElement.children[i];
    if (!shouldIgnoreElement(child) && isElementVisible(child)) {
      return findElement(child);
    }
  }
  return rootElement;
}

function isElementVisible(element) {
  if (readium.isFixedLayout) return true;

  if (element === document.body || element === document.documentElement) {
    return true;
  }
  if (!document || !document.documentElement || !document.body) {
    return false;
  }

  const rect = element.getBoundingClientRect();
  if (isScrollModeEnabled()) {
    return rect.bottom > 0 && rect.top < window.innerHeight;
  } else {
    return rect.right > 0 && rect.left < window.innerWidth;
  }
}

function shouldIgnoreElement(element) {
  const elStyle = getComputedStyle(element);
  if (elStyle) {
    const display = elStyle.getPropertyValue("display");
    if (display != "block") {
      return true;
    }
    // Cannot be relied upon, because web browser engine reports invisible when out of view in
    // scrolled columns!
    // const visibility = elStyle.getPropertyValue("visibility");
    // if (visibility === "hidden") {
    //     return false;
    // }
    const opacity = elStyle.getPropertyValue("opacity");
    if (opacity === "0") {
      return true;
    }
  }

  return false;
}
