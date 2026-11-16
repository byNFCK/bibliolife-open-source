const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const rect = fs.readFileSync(
  path.join(__dirname, "..", "src", "rect.js"),
  "utf8"
);
const decorator = fs.readFileSync(
  path.join(__dirname, "..", "src", "decorator.js"),
  "utf8"
);

test("decoration geometry joins selected words into visual line boxes", () => {
  assert.match(rect, /export function getTextClientRectsNoOverlap/);
  assert.match(rect, /const nonWhitespaceRun = \/\\S\+\/g/);
  assert.match(rect, /textRange\.getClientRects\(\)/);
  assert.match(rect, /mergeTextRectsByVisualLine/);
  assert.match(rect, /gap <= lineThickness \* 2/);
  assert.match(decorator, /getTextClientRectsNoOverlap\(\s*item\.range/);
});
