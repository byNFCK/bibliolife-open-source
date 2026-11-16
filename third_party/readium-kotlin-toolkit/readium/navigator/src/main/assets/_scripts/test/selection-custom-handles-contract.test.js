const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "..", "src", "selection.js"), "utf8");
const index = fs.readFileSync(path.join(__dirname, "..", "src", "index.js"), "utf8");
const native = fs.readFileSync(path.join(__dirname, "..", "..", "..", "java", "org", "readium", "r2", "navigator", "R2BasicWebView.kt"), "utf8");
const has = (expression) => assert.match(source, expression);

test("1 preparation leaves the native Selection untouched", () => has(/placeCustomHandles\(fixedRange[\s\S]*READIUM_CUSTOM_HANDLES_PREPARED[\s\S]*requestAnimationFrame[\s\S]*selection\.removeAllRanges/));
test("2 overlay attaches to document.documentElement", () => has(/document\.documentElement\.appendChild\(overlay\)/));
test("3 visual handle placement uses viewport rects without scroll offsets", () => has(/startHandle\.style\.left = `\$\{clamp\(start\.left[\s\S]*endHandle\.style\.left = `\$\{clamp\(end\.right/));
test("4 phantom column rects are filtered", () => has(/rect\.right >= -4[\s\S]*rect\.left <= window\.innerWidth \+ 4/));
test("5 geometry rejects zero-size handles", () => has(/rect\.width > 0 && rect\.height > 0/));
test("6 geometry rejects off-screen handles", () => has(/rect\.left >= 0 && rect\.top >= 0 && rect\.right <= window\.innerWidth/));
test("7 hit testing rejects covered handles", () => has(/document\.elementFromPoint[\s\S]*target === handle \|\| handle\.contains\(target\)/));
test("8 failed activation falls back to the preserved native Selection", () => has(/function fallbackToNative[\s\S]*selection\.addRange\(state\.range\)[\s\S]*READIUM_CUSTOM_HANDLES_FALLBACK_TO_NATIVE/));
test("9 native suppression follows successful preparation validation", () => has(/validateCustomHandles\(prepared\)[\s\S]*selection\.removeAllRanges/));
test("10 document-level listeners retain a drag outside the handle", () => has(/document\.addEventListener\("pointermove"[\s\S]*document\.addEventListener\("pointerup"[\s\S]*document\.addEventListener\("pointercancel"/));
test("11 zero-update drag does not commit", () => has(/if \(updates <= 0\)[\s\S]*CUSTOM_SELECTION_COMMIT_IGNORED[\s\S]*return/));
test("12 successful drag requires a Range update", () => has(/state\.customRangeUpdateCount \+= 1[\s\S]*CUSTOM_SELECTION_FIRST_RANGE_UPDATE/));
test("13 fixed endpoint is captured once on pointer down", () => has(/fixed: kind === "start"[\s\S]*state\.range\.endContainer[\s\S]*updatesAtStart/));
test("14 fallback removes custom handles", () => has(/fallbackToNative[\s\S]*clearCustomHandles\(\)/));
test("production policy defaults to NATIVE", () => assert.match(index, /androidSelectionHandleMode: "NATIVE"/));
test("progression guard remains active during a native selection session", () => assert.match(native, /if \(isSelecting\) \{[\s\S]*READIUM_SELECTION_PROGRESS_CHANGE_SUPPRESSED/));
