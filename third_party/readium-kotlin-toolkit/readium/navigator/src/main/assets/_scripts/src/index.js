//
//  Copyright 2021 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

// Base script used by both reflowable and fixed layout resources.

import "./gestures";
import "./keyboard";
import {
  removeProperty,
  scrollLeft,
  scrollRight,
  scrollToEnd,
  scrollToId,
  scrollToPosition,
  scrollToStart,
  scrollToLocator,
  locatorVerticalOffset,
  continuousLocatorPointGeometry,
  isLocatorRangeAtVerticalAnchor,
  locatorsShareMeaningfulBlock,
  setProperty,
  setCSSProperties,
} from "./utils";
import {
  findFirstVisibleLocator,
  findLocatorAtPoint,
  findLocatorAtPointDiagnostic,
} from "./dom";
import { clearCurrentSelection, getCurrentSelection } from "./selection";
import { getDecorations, registerTemplates } from "./decorator";
import { captureContinuousDomAnchor } from "./continuous-dom-anchor";

function captureContinuousReadingAnchor(x, y) {
  return captureContinuousDomAnchor(x, y, findLocatorAtPoint(x, y));
}

// Public API used by the navigator.
function setAndroidSelectionHandleMode(mode) {
  window.readium.androidSelectionHandleMode = mode;
  if (typeof Android !== "undefined" && mode === "CUSTOM_FOR_ALL_PAGINATED_SELECTIONS") {
    Android.log("READIUM_JS_CUSTOM_HANDLE_POLICY mode=custom_all_paginated");
  }
}

window.readium = {
  // utils
  scrollToId: scrollToId,
  scrollToPosition: scrollToPosition,
  scrollToLocator: scrollToLocator,
  locatorVerticalOffset: locatorVerticalOffset,
  continuousLocatorPointGeometry: continuousLocatorPointGeometry,
  isLocatorRangeAtVerticalAnchor: isLocatorRangeAtVerticalAnchor,
  locatorsShareMeaningfulBlock: locatorsShareMeaningfulBlock,
  scrollLeft: scrollLeft,
  scrollRight: scrollRight,
  scrollToStart: scrollToStart,
  scrollToEnd: scrollToEnd,
  setCSSProperties: setCSSProperties,
  setProperty: setProperty,
  removeProperty: removeProperty,

  // selection
  getCurrentSelection: getCurrentSelection,
  clearSelection: clearCurrentSelection,
  // Production safety default. CUSTOM_FOR_ALL_PAGINATED_SELECTIONS is a runtime/debug probe
  // and must earn activation by passing the DOM geometry and hit-test checks in selection.js.
  androidSelectionHandleMode: "NATIVE",
  setAndroidSelectionHandleMode: setAndroidSelectionHandleMode,

  // decoration
  registerDecorationTemplates: registerTemplates,
  getDecorations: getDecorations,

  // DOM
  findFirstVisibleLocator: findFirstVisibleLocator,
  captureContinuousReadingAnchor: captureContinuousReadingAnchor,
  findLocatorAtPoint: findLocatorAtPoint,
  findLocatorAtPointDiagnostic: findLocatorAtPointDiagnostic,
};
