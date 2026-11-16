//
// Copyright 2021 Readium Foundation. All rights reserved.
// Use of this source code is governed by the BSD-style license
// available in the top-level LICENSE file of the project.
//

import { isScrollModeEnabled, log as logNative, logError, snapCurrentOffset } from "./utils";
import { toNativeRect } from "./rect";
import { TextRange } from "./vendor/hypothesis/anchoring/text-range";

import matchAll from "string.prototype.matchall";
matchAll.shim();

export const AndroidSelectionHandleMode = Object.freeze({
  NATIVE: "NATIVE",
  CUSTOM_FOR_UNSAFE_RANGES: "CUSTOM_FOR_UNSAFE_RANGES",
  CUSTOM_FOR_ALL_PAGINATED_SELECTIONS: "CUSTOM_FOR_ALL_PAGINATED_SELECTIONS",
});

const HANDLE_OVERLAY_ID = "readium-custom-selection-handle-overlay";
const HANDLE_START_ID = "readium-custom-selection-handle-start";
const HANDLE_END_ID = "readium-custom-selection-handle-end";
const HANDLE_TOUCH_SIZE = 44;
const GENERATED_HYPHEN_MAX_EM = 0.62;
const RECT_ADJACENCY_PX = 2;
let activeSelectionState = null;

function isPaginatedAndroidSelection() {
  return typeof Android !== "undefined" && window.readium && window.readium.isReflowable && !isScrollModeEnabled();
}

function isNativePaginatedSelection() {
  return isPaginatedAndroidSelection() && selectionHandleMode() === AndroidSelectionHandleMode.NATIVE;
}

function selectionHandleMode() {
  const configured = window.readium && window.readium.androidSelectionHandleMode;
  return Object.values(AndroidSelectionHandleMode).includes(configured)
    ? configured
    : AndroidSelectionHandleMode.NATIVE;
}

function blockAncestor(node) {
  let element = node && (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement);
  while (element) {
    const display = getComputedStyle(element).display;
    if (display !== "inline" && !display.startsWith("ruby")) return element;
    element = element.parentElement;
  }
  return null;
}

// This probes a detached Range only. It never alters the live Selection.
export function rangeBeginsAtBlockStart(range) {
  const block = blockAncestor(range.startContainer);
  if (!block) return false;
  const probe = document.createRange();
  try {
    probe.selectNodeContents(block);
    probe.setEnd(range.startContainer, range.startOffset);
    return probe.toString().trim().length === 0;
  } catch (_) {
    return false;
  }
}

export function hasGeneratedHyphenRects(rects, emPx, vertical = false) {
  for (let index = 1; index < rects.length; index += 1) {
    const previous = rects[index - 1];
    const current = rects[index];
    const sameLine = vertical
      ? Math.abs(previous.left - current.left) <= Math.max(previous.width, current.width) / 2
      : Math.abs(previous.top - current.top) <= Math.max(previous.height, current.height) / 2;
    if (!sameLine) continue;
    const adjacent = vertical
      ? Math.abs(current.top - (previous.top + previous.height)) <= RECT_ADJACENCY_PX
      : Math.abs(current.left - (previous.left + previous.width)) <= RECT_ADJACENCY_PX ||
        Math.abs(previous.left - (current.left + current.width)) <= RECT_ADJACENCY_PX;
    const trailingSize = vertical ? current.height : current.width;
    if (adjacent && trailingSize > 0 && trailingSize <= emPx * GENERATED_HYPHEN_MAX_EM) return true;
  }
  return false;
}

export function blockHasHyphenLayout(block) {
  const style = getComputedStyle(block);
  const hasSoftHyphen = (block.textContent || "").includes("\u00AD");
  const hyphenationEnabled = [style.hyphens, style.webkitHyphens].some((value) => value === "auto");
  if (!hasSoftHyphen && !hyphenationEnabled) return false;

  const vertical = style.writingMode.startsWith("vertical");
  const emPx = parseFloat(style.fontSize) || 16;
  const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
  const probe = document.createRange();
  let textNode;
  while ((textNode = walker.nextNode())) {
    if (!textNode.data.trim()) continue;
    try {
      probe.selectNodeContents(textNode);
      if (hasGeneratedHyphenRects(Array.from(probe.getClientRects()), emPx, vertical)) return true;
    } catch (_) {
      return hasSoftHyphen;
    }
  }
  return hasSoftHyphen;
}

export function isUnsafeAndroidRange(range) {
  const block = blockAncestor(range.startContainer);
  return !!block && rangeBeginsAtBlockStart(range) && blockHasHyphenLayout(block);
}

function shouldUseCustomHandles() {
  if (!isPaginatedAndroidSelection()) return false;
  // Unsafe detection is deliberately disabled until the verified custom path is proven.
  // Only an explicit runtime/debug CUSTOM_FOR_ALL_PAGINATED_SELECTIONS policy may probe it.
  return selectionHandleMode() === AndroidSelectionHandleMode.CUSTOM_FOR_ALL_PAGINATED_SELECTIONS;
}

function customAllPaginatedMode() {
  return isPaginatedAndroidSelection() &&
    selectionHandleMode() === AndroidSelectionHandleMode.CUSTOM_FOR_ALL_PAGINATED_SELECTIONS;
}

function endpoint(node, offset) {
  return { node, offset };
}

function orderedRange(first, second) {
  const forward = document.createRange();
  try {
    forward.setStart(first.node, first.offset);
    forward.setEnd(second.node, second.offset);
    if (!forward.collapsed) return forward;
  } catch (_) {
    // The endpoints are reverse-ordered; try the opposite document order.
  }
  const backward = document.createRange();
  try {
    backward.setStart(second.node, second.offset);
    backward.setEnd(first.node, first.offset);
    return backward.collapsed ? null : backward;
  } catch (_) {
    return null;
  }
}

function snapEndpointToWord(range, isStart) {
  const node = isStart ? range.startContainer : range.endContainer;
  const offset = isStart ? range.startOffset : range.endOffset;
  if (node.nodeType !== Node.TEXT_NODE || typeof Intl === "undefined" || !Intl.Segmenter) return;
  const text = node.data;
  if (offset <= 0 || offset >= text.length) return;
  const segmenter = new Intl.Segmenter(undefined, { granularity: "word" });
  for (const part of segmenter.segment(text)) {
    if (!part.isWordLike || part.index >= offset || part.index + part.segment.length <= offset) continue;
    if (isStart) range.setStart(node, part.index);
    else range.setEnd(node, part.index + part.segment.length);
    return;
  }
}

export function snapRangeToWordBoundaries(range) {
  snapEndpointToWord(range, true);
  snapEndpointToWord(range, false);
  return range;
}

function caretAtPoint(x, y) {
  if (document.caretPositionFromPoint) {
    const position = document.caretPositionFromPoint(x, y);
    if (position) return endpoint(position.offsetNode, position.offset);
  }
  if (document.caretRangeFromPoint) {
    const range = document.caretRangeFromPoint(x, y);
    if (range) return endpoint(range.startContainer, range.startOffset);
  }
  return null;
}

function endpointDocumentX(point) {
  const probe = document.createRange();
  try {
    probe.setStart(point.node, point.offset);
    probe.collapse(true);
    return probe.getBoundingClientRect().left + window.scrollX;
  } catch (_) {
    return null;
  }
}

function clearLockedSelectionPage(state) {
  state.selectionPageScrollX = null;
  state.selectionPageWidth = null;
  state.selectionPageLeft = null;
  state.selectionPageRight = null;
  state.anchorNode = null;
  state.anchorOffset = null;
  state.selectionPageRestoreScheduled = false;
}

function lockNativeSelectionPage(selection, state) {
  if (state.selectionPageScrollX != null || !selection.anchorNode) return;
  state.selectionPageScrollX = window.scrollX;
  state.selectionPageWidth = window.innerWidth;
  state.selectionPageLeft = state.selectionPageScrollX;
  state.selectionPageRight = state.selectionPageLeft + state.selectionPageWidth;
  state.anchorNode = selection.anchorNode;
  state.anchorOffset = selection.anchorOffset;
  logNative(`READIUM_SELECTION_PAGE_LOCKED scrollX=${state.selectionPageScrollX} width=${state.selectionPageWidth}`);
}

function endpointIsInsideLockedPage(point, state) {
  const x = endpointDocumentX(point);
  return x != null && x >= state.selectionPageLeft - 4 && x <= state.selectionPageRight + 4;
}

function endpointClientRect(point) {
  const probe = document.createRange();
  try {
    probe.setStart(point.node, point.offset);
    probe.collapse(true);
    return probe.getBoundingClientRect();
  } catch (_) {
    return null;
  }
}

function setNativeSelectionFocus(selection, state, focus) {
  if (!state.anchorNode || !focus) return;
  state.programmaticSelection = true;
  if (selection.setBaseAndExtent) {
    selection.setBaseAndExtent(state.anchorNode, state.anchorOffset, focus.node, focus.offset);
  } else {
    const range = orderedRange(endpoint(state.anchorNode, state.anchorOffset), focus);
    if (range) {
      selection.removeAllRanges();
      selection.addRange(range);
    }
  }
  setTimeout(() => { state.programmaticSelection = false; }, 0);
}

function scheduleNativeSelectionPageEnforcement(state) {
  if (state.selectionPageRestoreScheduled || state.selectionPageScrollX == null) return;
  state.selectionPageRestoreScheduled = true;
  requestAnimationFrame(() => {
    state.selectionPageRestoreScheduled = false;
    if (state.selectionPageScrollX == null) return;
    if (Math.abs(window.scrollX - state.selectionPageScrollX) > 2) {
      const from = window.scrollX;
      window.scrollTo(state.selectionPageScrollX, window.scrollY);
      logNative(`READIUM_SELECTION_PAGE_SCROLL_RESTORED from=${from} to=${state.selectionPageScrollX}`);
    }
    const selection = window.getSelection();
    if (!selection || selection.isCollapsed || !selection.focusNode) return;
    const focus = endpoint(selection.focusNode, selection.focusOffset);
    const anchor = endpoint(selection.anchorNode, selection.anchorOffset);
    if (endpointIsInsideLockedPage(anchor, state) && endpointIsInsideLockedPage(focus, state)) return;
    const focusX = endpointDocumentX(focus);
    const focusRect = endpointClientRect(focus);
    if (focusX == null || !focusRect) return;
    const edgeX = focusX < state.selectionPageLeft - 4 ? 1 : window.innerWidth - 1;
    const edgeY = Math.max(1, Math.min(window.innerHeight - 1, focusRect.top + focusRect.height / 2));
    const clampedFocus = caretAtPoint(edgeX, edgeY);
    if (!clampedFocus) return;
    setNativeSelectionFocus(selection, state, clampedFocus);
    logNative("READIUM_SELECTION_FOCUS_CLAMPED");
  });
}

export function rangeFromFixedEndpointToPoint(fixed, x, y, lockedPage = null) {
  const boundedX = Math.max(1, Math.min(x, window.innerWidth - 1));
  const boundedY = Math.max(1, Math.min(y, window.innerHeight - 1));
  const caret = caretAtPoint(boundedX, boundedY);
  if (!caret) {
    logNative(`CUSTOM_SELECTION_RANGE_REJECTED reason=no_caret x=${boundedX} y=${boundedY}`);
    return null;
  }
  if (caret && lockedPage) {
    const caretX = endpointDocumentX(caret);
    const minX = lockedPage.scrollX - 4;
    const maxX = lockedPage.scrollX + lockedPage.viewportWidth + 4;
    if (caretX == null || caretX < minX || caretX > maxX) {
      logNative(`CUSTOM_SELECTION_RANGE_REJECTED reason=outside_locked_page caretX=${caretX} minX=${minX} maxX=${maxX}`);
      return null;
    }
  }
  const range = orderedRange(fixed, caret);
  if (!range) logNative("CUSTOM_SELECTION_RANGE_REJECTED reason=unordered_endpoint");
  return range ? snapRangeToWordBoundaries(range) : null;
}

function meaningfulCurrentColumnRects(range) {
  return Array.from(range.getClientRects()).filter((rect) =>
    rect.width > 0.5 && rect.height > 0.5 && rect.right >= -4 && rect.left <= window.innerWidth + 4 && rect.bottom >= -4 && rect.top <= window.innerHeight + 4
  );
}

function handleOverlay() {
  let overlay = document.getElementById(HANDLE_OVERLAY_ID);
  if (overlay) return overlay;
  overlay = document.createElement("div");
  overlay.id = HANDLE_OVERLAY_ID;
  Object.assign(overlay.style, {
    position: "fixed", inset: "0", width: "100vw", height: "100vh", overflow: "visible",
    pointerEvents: "none", zIndex: "2147483647", contain: "none", transform: "none",
    opacity: "1", visibility: "visible", display: "block", userSelect: "none",
    webkitUserSelect: "none", overscrollBehavior: "none",
  });
  document.documentElement.appendChild(overlay);
  return overlay;
}

function makeHandle(id) {
  const handle = document.createElement("div");
  handle.id = id;
  handle.setAttribute("aria-hidden", "true");
  Object.assign(handle.style, {
    position: "absolute", width: `${HANDLE_TOUCH_SIZE}px`, height: `${HANDLE_TOUCH_SIZE}px`,
    zIndex: "2147483647", opacity: "1", visibility: "visible", display: "block",
    pointerEvents: "auto", touchAction: "none", background: "transparent",
    userSelect: "none", webkitUserSelect: "none", overscrollBehavior: "none",
  });
  const dot = document.createElement("div");
  Object.assign(dot.style, {
    position: "absolute", left: "14px", top: "4px", width: "16px", height: "16px",
    borderRadius: "50% 50% 50% 0", transform: "rotate(-45deg)",
    background: "var(--USER__selectionColor, #4f7cff)", boxShadow: "0 1px 3px rgba(0,0,0,.36)",
  });
  handle.appendChild(dot);
  handleOverlay().appendChild(handle);
  return handle;
}

function clearCustomHandles() {
  const start = document.getElementById(HANDLE_START_ID);
  const end = document.getElementById(HANDLE_END_ID);
  start?.remove();
  end?.remove();
  document.getElementById(HANDLE_OVERLAY_ID)?.remove();
  if (start || end) logNative("READIUM_CUSTOM_HANDLES_REMOVED");
}

function setLiveSelection(range, state) {
  state.programmaticSelection = true;
  const selection = window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  setTimeout(() => { state.programmaticSelection = false; }, 0);
}

function placeCustomHandles(range, state) {
  const rects = meaningfulCurrentColumnRects(range);
  if (!rects.length) return null;
  const forward = state.direction !== "backward";
  const start = forward ? rects[0] : rects[rects.length - 1];
  const end = forward ? rects[rects.length - 1] : rects[0];
  const startHandle = document.getElementById(HANDLE_START_ID) || makeHandle(HANDLE_START_ID);
  const endHandle = document.getElementById(HANDLE_END_ID) || makeHandle(HANDLE_END_ID);
  const radius = HANDLE_TOUCH_SIZE / 2;
  const clamp = (value, max) => Math.max(radius, Math.min(max - radius, value));
  // Client rects are already viewport coordinates. Never add scrollX/scrollY here.
  startHandle.style.left = `${clamp(start.left, window.innerWidth) - radius}px`;
  startHandle.style.top = `${clamp(start.bottom, window.innerHeight) - radius}px`;
  endHandle.style.left = `${clamp(end.right, window.innerWidth) - radius}px`;
  endHandle.style.top = `${clamp(end.bottom, window.innerHeight) - radius}px`;
  bindHandleDrag(startHandle, "start", state);
  bindHandleDrag(endHandle, "end", state);
  return { startHandle, endHandle };
}

function bindHandleDrag(handle, kind, state) {
  if (handle.dataset.bound === "true") return;
  handle.dataset.bound = "true";
  handle.dataset.pointerListeners = "pointerdown,pointermove,pointerup,pointercancel,lostpointercapture";
  handle.addEventListener("pointerdown", (event) => {
    if (!state.range || state.activationState !== "ACTIVE") return;
    event.preventDefault(); event.stopPropagation();
    handle.setPointerCapture(event.pointerId);
    state.dragging = {
      pointerId: event.pointerId, kind, handle,
      fixed: kind === "start" ? endpoint(state.range.endContainer, state.range.endOffset) : endpoint(state.range.startContainer, state.range.startOffset),
      updatesAtStart: state.customRangeUpdateCount,
    };
    state.customHandleDragActive = true;
    state.toolbarHiddenForCustomDrag = true;
    Android.onCustomSelectionHandleDragStarted(state.sessionId);
    logNative(`CUSTOM_SELECTION_POINTER_DOWN pointerId=${event.pointerId} handle=${kind} clientX=${event.clientX} clientY=${event.clientY}`);
    logNative(`CUSTOM_SELECTION_HANDLE_DRAG_STARTED handle=${kind}`);
    document.addEventListener("pointermove", state.documentPointerMove, { capture: true, passive: false });
    document.addEventListener("pointerup", state.documentPointerFinish, { capture: true, passive: false });
    document.addEventListener("pointercancel", state.documentPointerFinish, { capture: true, passive: false });
  }, { passive: false });
  handle.addEventListener("lostpointercapture", state.documentPointerFinish, { passive: false });
}

function removeDocumentDragListeners(state) {
  document.removeEventListener("pointermove", state.documentPointerMove, true);
  document.removeEventListener("pointerup", state.documentPointerFinish, true);
  document.removeEventListener("pointercancel", state.documentPointerFinish, true);
}

function onDocumentPointerMove(event, state) {
  const drag = state.dragging;
  if (!drag || drag.pointerId !== event.pointerId) return;
  event.preventDefault(); event.stopPropagation();
  // The overlay and selected range share this document, so client coordinates need no offset.
  const range = rangeFromFixedEndpointToPoint(drag.fixed, event.clientX, event.clientY, state.lockedPage);
  if (!range || range.collapsed) return;
  state.range = range.cloneRange();
  setLiveSelection(range, state);
  placeCustomHandles(range, state);
  state.customRangeUpdateCount += 1;
  if (!drag.firstUpdateLogged) {
    drag.firstUpdateLogged = true;
    const caret = caretAtPoint(event.clientX, event.clientY);
    logNative(`CUSTOM_SELECTION_FIRST_RANGE_UPDATE pointerId=${event.pointerId} clientX=${event.clientX} clientY=${event.clientY} caretNode=${caret ? caret.node.nodeType : -1} caretOffset=${caret ? caret.offset : -1}`);
  }
  logNative("CUSTOM_SELECTION_RANGE_UPDATED");
}

function onDocumentPointerFinish(event, state) {
  const drag = state.dragging;
  if (!drag || (event.pointerId != null && drag.pointerId !== event.pointerId)) return;
  event.preventDefault?.(); event.stopPropagation?.();
  if (event.pointerId != null && drag.handle.hasPointerCapture(event.pointerId)) drag.handle.releasePointerCapture(event.pointerId);
  removeDocumentDragListeners(state);
  state.dragging = null; state.customHandleDragActive = false;
  const updates = state.customRangeUpdateCount - drag.updatesAtStart;
  logNative(`CUSTOM_SELECTION_HANDLE_DRAG_FINISHED updates=${updates}`);
  if (updates <= 0) {
    logNative("CUSTOM_SELECTION_COMMIT_IGNORED reason=no_range_updates");
    return;
  }
  state.selectionSerializationCount += 1;
  logNative("CUSTOM_SELECTION_COMMIT_STARTED");
  Android.onCustomSelectionCommitted(state.sessionId);
  logNative(`CUSTOM_SELECTION_COMMIT_COMPLETED textLength=${state.range ? state.range.toString().length : 0}`);
}

function handleValidation(handle, name) {
  const rect = handle?.getBoundingClientRect();
  const style = handle && getComputedStyle(handle);
  const inViewport = !!rect && rect.width > 0 && rect.height > 0 && rect.left >= 0 && rect.top >= 0 && rect.right <= window.innerWidth && rect.bottom <= window.innerHeight;
  const visible = style?.display !== "none" && style?.visibility !== "hidden" && parseFloat(style?.opacity || "0") > 0.01;
  const centerX = rect ? rect.left + rect.width / 2 : -1;
  const centerY = rect ? rect.top + rect.height / 2 : -1;
  const target = inViewport ? document.elementFromPoint(centerX, centerY) : null;
  const hit = !!target && (target === handle || handle.contains(target));
  logNative(`READIUM_CUSTOM_HANDLE_HIT_TEST handle=${name} success=${hit} targetTag=${target?.tagName || "none"} targetId=${target?.id || "none"}`);
  return { rect, valid: !!handle?.isConnected && inViewport && visible && hit };
}

function validateCustomHandles(handles) {
  const start = handleValidation(handles?.startHandle, "start");
  const end = handleValidation(handles?.endHandle, "end");
  logNative(
    `READIUM_CUSTOM_HANDLE_GEOMETRY startLeft=${start.rect?.left ?? -1} startTop=${start.rect?.top ?? -1} ` +
    `startRight=${start.rect?.right ?? -1} startBottom=${start.rect?.bottom ?? -1} ` +
    `endLeft=${end.rect?.left ?? -1} endTop=${end.rect?.top ?? -1} ` +
    `endRight=${end.rect?.right ?? -1} endBottom=${end.rect?.bottom ?? -1} ` +
    `viewportWidth=${window.innerWidth} viewportHeight=${window.innerHeight}`
  );
  return start.valid && end.valid;
}

function fallbackToNative(selection, state, reason) {
  // Preserve or restore the original live Selection. A failed probe must never strand users.
  if (state.range && (selection.rangeCount !== 1 || selection.isCollapsed)) {
    state.programmaticSelection = true;
    selection.removeAllRanges();
    selection.addRange(state.range);
    setTimeout(() => { state.programmaticSelection = false; }, 0);
  }
  clearCustomHandles();
  state.customActive = false; state.activationPending = false; state.activationState = "FAILED";
  state.programmaticSelection = false;
  logNative(`READIUM_CUSTOM_HANDLES_FALLBACK_TO_NATIVE reason=${reason} sessionId=${state.sessionId}`);
}

function activateCustomHandles(selection, range, state, reason) {
  if (state.customActive || state.activationPending || state.activationState === "PREPARING") return;
  const fixedRange = range.cloneRange();
  state.activationPending = true; state.activationState = "PREPARING";
  state.range = fixedRange;
  state.activationReason = reason;
  state.lockedPage = { scrollX: window.scrollX, scrollY: window.scrollY, viewportWidth: window.innerWidth };
  state.direction = selection.anchorNode === range.startContainer && selection.anchorOffset === range.startOffset ? "forward" : "backward";
  Android.onCustomSelectionHandlesPreparing(state.sessionId);
  const prepared = placeCustomHandles(fixedRange, state);
  logNative(`READIUM_CUSTOM_HANDLES_PREPARED sessionId=${state.sessionId} mode=custom_all_paginated`);
  requestAnimationFrame(() => {
    if (!state.activationPending || state.range !== fixedRange || !validateCustomHandles(prepared)) {
      fallbackToNative(selection, state, "prepare_validation_failed");
      return;
    }
    state.activationState = "VERIFIED";
    // Native handles remain untouched until the overlay is painted and independently verified.
    state.programmaticSelection = true;
    selection.removeAllRanges();
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (!state.activationPending || state.range !== fixedRange) {
        fallbackToNative(selection, state, "session_replaced");
        return;
      }
      selection.addRange(fixedRange);
      const displaced = Math.abs(window.scrollX - state.lockedPage.scrollX) >= state.lockedPage.viewportWidth * 0.5;
      if (displaced && !state.activationPageRestoreUsed) {
        const from = window.scrollX; state.activationPageRestoreUsed = true;
        window.scrollTo(state.lockedPage.scrollX, state.lockedPage.scrollY);
        logNative(`READIUM_CUSTOM_HANDLE_ACTIVATION_PAGE_RESTORED from=${from} to=${state.lockedPage.scrollX}`);
      }
      window.scrollTo(state.lockedPage.scrollX, state.lockedPage.scrollY);
      const restored = placeCustomHandles(fixedRange, state);
      if (!validateCustomHandles(restored)) {
        fallbackToNative(selection, state, "post_suppression_validation_failed");
        return;
      }
      state.customActive = true; state.activationPending = false; state.activationState = "ACTIVE";
      setTimeout(() => { state.programmaticSelection = false; }, 0);
      Android.onCustomSelectionHandlesActivated(state.sessionId);
      logNative(`READIUM_CUSTOM_HANDLES_ACTIVATED sessionId=${state.sessionId} reason=${reason}`);
    }));
  });
}

function logSessionSummary(state) {
  logNative(
    `READIUM_SELECTION_SESSION_SUMMARY nativeSelectionEventCount=${state.nativeSelectionEventCount} ` +
    `customRangeUpdateCount=${state.customRangeUpdateCount} selectionSerializationCount=${state.selectionSerializationCount} ` +
    `pageTurnAttemptCount=0 finalTextLength=${state.range ? state.range.toString().length : 0} ` +
    `customHandleMode=${selectionHandleMode()} activationReason=${state.activationReason || "none"}`
  );
}

window.addEventListener("load", function () {
  const state = { customActive: false, activationPending: false, activationState: "INACTIVE", programmaticSelection: false, range: null, dragging: null,
    userGestureVersion: 0, nativeSelectionEventCount: 0, customRangeUpdateCount: 0,
    selectionSerializationCount: 0, activationReason: null, toolbarHiddenForCustomDrag: false,
    sessionId: 0, lockedPage: null, activationPageRestoreUsed: false, direction: "forward", customHandleDragActive: false,
    selectionPageScrollX: null, selectionPageWidth: null, selectionPageLeft: null, selectionPageRight: null,
    anchorNode: null, anchorOffset: null, selectionPageRestoreScheduled: false,
    documentPointerMove: null, documentPointerFinish: null };
  activeSelectionState = state;
  state.documentPointerMove = (event) => onDocumentPointerMove(event, state);
  state.documentPointerFinish = (event) => onDocumentPointerFinish(event, state);
  if (customAllPaginatedMode()) {
    logNative("READIUM_JS_CUSTOM_HANDLE_POLICY mode=custom_all_paginated");
  }
  document.addEventListener("pointerdown", () => { state.userGestureVersion += 1; }, true);
  window.addEventListener("scroll", () => {
    if (state.selectionPageScrollX != null) scheduleNativeSelectionPageEnforcement(state);
  }, { passive: true });
  document.addEventListener("selectionchange", function () {
    const selection = window.getSelection();
    if (!selection) return;
    const collapsed = selection.isCollapsed;
    if (state.programmaticSelection) return;
    if (collapsed) {
      if (state.customActive || state.range) clearCustomHandles();
      logSessionSummary(state);
      state.customActive = false;
      state.activationPending = false;
      state.activationState = "INACTIVE";
      state.range = null;
      state.dragging = null;
      state.customHandleDragActive = false;
      removeDocumentDragListeners(state);
      state.lockedPage = null;
      clearLockedSelectionPage(state);
      Android.onSelectionEnd(state.sessionId);
      snapCurrentOffset();
      return;
    }
    if (!selection.rangeCount) return;
    const range = selection.getRangeAt(0).cloneRange();
    state.nativeSelectionEventCount += 1;
    if (!state.range) {
      state.sessionId += 1;
      state.range = range.cloneRange();
      state.lockedPage = null;
      state.activationPageRestoreUsed = false;
      if (isNativePaginatedSelection()) lockNativeSelectionPage(selection, state);
      Android.onSelectionStart(state.sessionId);
      logNative("READIUM_NATIVE_SELECTION_CREATED");
      if (customAllPaginatedMode()) {
        activateCustomHandles(selection, range, state, "all_paginated_policy");
      } else if (shouldUseCustomHandles()) {
        activateCustomHandles(selection, range, state, "unsafe_hyphen_range");
      }
    }
    if (isNativePaginatedSelection() && state.selectionPageScrollX != null) {
      scheduleNativeSelectionPageEnforcement(state);
    }
  }, false);
});

export function clearCurrentSelection() {
  window.getSelection()?.removeAllRanges();
  clearCustomHandles();
  if (activeSelectionState) clearLockedSelectionPage(activeSelectionState);
}

export function getCurrentSelection() {
  // This counter represents JavaScript serialization requests, whether native
  // handles or the optional custom handles own the selection.
  const selection = window.getSelection();
  if (activeSelectionState) {
    activeSelectionState.selectionSerializationCount += 1;
    if (selection && selection.rangeCount && !selection.isCollapsed) {
      activeSelectionState.range = selection.getRangeAt(0).cloneRange();
    }
  }
  const text = getCurrentSelectionText();
  if (!text) return null;
  const rect = getSelectionRect();
  return { text, rect };
}

function getSelectionRect() {
  try {
    const selection = window.getSelection();
    if (!selection || !selection.rangeCount) return null;
    return toNativeRect(selection.getRangeAt(0).getBoundingClientRect());
  } catch (error) {
    logError(error);
    return null;
  }
}

function getCurrentSelectionText() {
  const selection = window.getSelection();
  if (!selection || selection.isCollapsed) return undefined;
  const highlight = selection.toString();
  if (highlight.trim().replace(/\n/g, " ").replace(/\s\s+/g, " ").length === 0) return undefined;
  if (!selection.anchorNode || !selection.focusNode) return undefined;
  const range = selection.rangeCount === 1 ? selection.getRangeAt(0) : orderedRange(
    endpoint(selection.anchorNode, selection.anchorOffset), endpoint(selection.focusNode, selection.focusOffset)
  );
  if (!range || range.collapsed) return undefined;
  const text = document.body.textContent;
  const textRange = TextRange.fromRange(range).relativeTo(document.body);
  const start = textRange.start.offset;
  const end = textRange.end.offset;
  let before = text.slice(Math.max(0, start - 200), start);
  const firstWordStart = before.search(/\P{L}\p{L}/gu);
  if (firstWordStart !== -1) before = before.slice(firstWordStart + 1);
  let after = text.slice(end, Math.min(text.length, end + 200));
  const lastWordEnd = Array.from(after.matchAll(/\p{L}\P{L}/gu)).pop();
  if (lastWordEnd !== undefined && lastWordEnd.index > 1) after = after.slice(0, lastWordEnd.index + 1);
  return { highlight, before, after };
}
