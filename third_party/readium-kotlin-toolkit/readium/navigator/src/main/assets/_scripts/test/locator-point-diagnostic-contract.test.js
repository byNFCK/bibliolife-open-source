const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const babel = require("@babel/core");

const source = fs.readFileSync(
  path.join(__dirname, "..", "src", "dom.js"),
  "utf8"
);
const index = fs.readFileSync(
  path.join(__dirname, "..", "src", "index.js"),
  "utf8"
);
const utils = fs.readFileSync(
  path.join(__dirname, "..", "src", "utils.js"),
  "utf8"
);

test("progression-only offsets derive a live DOM range without height fallback", () => {
  const progressionRange = utils.match(
    /function rangeFromResourceProgression\(locator\) \{([\s\S]*?)\n\}/
  )[1];
  assert.match(utils, /function rangeFromResourceProgression\(locator\)/);
  assert.match(
    utils,
    /document\.createTreeWalker\([\s\S]*NodeFilter\.SHOW_TEXT/
  );
  assert.match(utils, /Math\.round\(progression \* totalLength\)/);
  assert.match(utils, /range\.setStart\(textNode, remaining\)/);
  assert.match(utils, /range\.collapse\(true\)/);
  assert.doesNotMatch(progressionRange, /scrollHeight/);
  assert.doesNotMatch(progressionRange, /setTimeout/);
});

test("continuous point geometry executes the progression caret and rejects empty geometry", () => {
  const progressionSource = utils.match(
    /function rangeFromResourceProgression\(locator\) \{([\s\S]*?)\n\}/
  )[0];
  const pointSource = utils.match(
    /export function continuousLocatorPointGeometry\(locator\) \{([\s\S]*?)\n\}/
  )[0].replace("export function", "function");
  let selectedOffset = -1;
  let rect = { top: 73.5, height: 18, width: 0 };
  const window = { scrollY: 100 };
  const textNodes = [{ nodeValue: "abcd" }, { nodeValue: "efgh" }];
  const document = {
    body: {},
    createTreeWalker: () => {
      let index = -1;
      return { nextNode: () => textNodes[++index] || null };
    },
    createRange: () => ({
      setStart: (_node, offset) => { selectedOffset = offset; },
      collapse: () => {},
      getBoundingClientRect: () => rect,
    }),
  };
  const run = new Function(
    "document",
    "window",
    "NodeFilter",
    `${progressionSource}\n${pointSource}\nreturn continuousLocatorPointGeometry;`
  )(document, window, { SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2 });

  assert.deepEqual(run({ locations: { progression: 0.75 } }), { documentY: 173.5, viewportTop: 73.5 });
  assert.equal(selectedOffset, 2);
  assert.deepEqual(run({ locations: { progression: 0.75 }, text: { highlight: "wrong block" } }), { documentY: 173.5, viewportTop: 73.5 });
  rect = { top: 73.5, height: 0, width: 0 };
  assert.equal(run({ locations: { progression: 0.75 } }), null);
  assert.equal(run({ locations: { progression: 0.75, cssSelector: ".chapter" } }), null);
});

test("CSS equivalence is resolved from live nodes and one meaningful block", () => {
  assert.match(utils, /export function locatorsShareMeaningfulBlock\(anchor, observed\)/);
  assert.match(utils, /document\.querySelector\(anchorSelector\)/);
  assert.match(utils, /document\.querySelector\(observedSelector\)/);
  assert.match(utils, /anchorNode\.contains\(observedNode\) \|\| observedNode\.contains\(anchorNode\)/);
  assert.match(utils, /return meaningfulBlock\(anchorNode\) === meaningfulBlock\(observedNode\)/);
  assert.match(utils, /function meaningfulBlock\(node\)/);
  assert.doesNotMatch(utils, /anchorSelector\.includes\(observedSelector\)/);
  assert.doesNotMatch(utils, /Math\.abs\([^)]*progression/);
  assert.match(index, /locatorsShareMeaningfulBlock: locatorsShareMeaningfulBlock/);
});

test("point Locator keeps its public return while diagnostics use the same caret range", () => {
  assert.match(
    source,
    /export function findLocatorAtPoint\(x, y\) \{\s*return locatorAtPoint\(x, y\)\.locator;/
  );
  assert.match(
    source,
    /export function findLocatorAtPointDiagnostic\(x, y\) \{[\s\S]*locator: point\.locator,[\s\S]*diagnostic: caretRangeDiagnostic\(point\.range\)/
  );
  assert.match(source, /const range = caretRangeAtPoint\(x, y\);/);
  assert.match(
    index,
    /findLocatorAtPointDiagnostic: findLocatorAtPointDiagnostic/
  );
});

test("point diagnostic extraction is compact, normalized, and structurally bounded", () => {
  assert.match(source, /const DIAGNOSTIC_TEXT_LIMIT = 120;/);
  assert.match(source, /const DIAGNOSTIC_SELECTOR_LIMIT = 160;/);
  assert.match(source, /const DIAGNOSTIC_ANCESTOR_LIMIT = 6;/);
  assert.match(
    source,
    /text: canonicalText,[\s\S]*parentSelector: boundedSelector\(parent\)/
  );
  assert.match(
    source,
    /before: boundedNormalizedText[\s\S]*highlight: boundedNormalizedText[\s\S]*after: boundedNormalizedText/
  );
  assert.match(
    source,
    /normalizedResourceQuoteOccurrences: countExactOccurrence/
  );
  assert.match(
    source,
    /while \(current && ancestors\.length < DIAGNOSTIC_ANCESTOR_LIMIT\)/
  );
  assert.match(
    source,
    /return \(value \|\| ""\)\.replace\(\/\\s\+\/g, " "\)\.trim\(\);/
  );
});

function element(selector, textContent, parentElement = null) {
  const node = {
    nodeType: 1,
    tagName: "P",
    selector,
    textContent,
    parentElement,
    childNodes: [],
  };
  if (parentElement) parentElement.childNodes.push(node);
  return node;
}

function text(value, parentElement) {
  const node = {
    nodeType: 3,
    nodeValue: value,
    parentElement,
  };
  parentElement.childNodes.push(node);
  return node;
}

function loadDomModule(document) {
  const transformed = babel.transformSync(source, {
    filename: "dom.js",
    presets: ["@babel/preset-env"],
  }).code;
  const module = { exports: {} };
  const requireFromDom = (name) => {
    if (name === "css-selector-generator") {
      return { getCssSelector: (element) => element.selector };
    }
    if (name === "./utils") return { isScrollModeEnabled: () => false };
    throw new Error(`Unexpected dependency: ${name}`);
  };
  new Function("require", "module", "exports", transformed)(
    requireFromDom,
    module,
    module.exports
  );
  return module.exports;
}

function withPointDocument(run) {
  const previousDocument = global.document;
  const previousNode = global.Node;
  global.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1 };

  const body = element("body", "Moby-Dick");
  const header = element(
    "#pg-machine-header",
    "Moby-Dick Herman Melville",
    body
  );
  const title = element("#pg-machine-header h1", "Moby-Dick", header);
  const author = element("#pg-header-authlist p", ": Herman Melville", header);
  const authorText = text(": Herman Melville", author);
  text("Moby-Dick", title);
  let caretRange = { startContainer: authorText, startOffset: 2 };
  let hitElement = header;
  global.document = {
    body,
    createRange: () => ({
      setStart() {},
      setEnd() {},
      toString: () => "",
    }),
    caretRangeFromPoint: () => caretRange,
    elementFromPoint: () => hitElement,
  };

  try {
    return run({
      author,
      authorText,
      header,
      setCaretRange: (range) => {
        caretRange = range;
      },
      setHitElement: (next) => {
        hitElement = next;
      },
    });
  } finally {
    global.document = previousDocument;
    global.Node = previousNode;
  }
}

test("point Locator canonicalizes a nested header hit to the caret parent", () => {
  withPointDocument(({ author }) => {
    const dom = loadDomModule(global.document);
    const result = dom.findLocatorAtPointDiagnostic(10, 20);

    assert.equal(result.locator.locations.cssSelector, author.selector);
    assert.equal(result.locator.text.highlight, ": Herman Melville");
    assert.equal(result.diagnostic.caret.parentSelector, author.selector);
  });
});

test("element-boundary and text carets keep the same canonical Locator parent", () => {
  withPointDocument(({ author, authorText, setCaretRange }) => {
    const dom = loadDomModule(global.document);
    const before = dom.findLocatorAtPoint(10, 20);
    setCaretRange({ startContainer: author, startOffset: 0 });
    const after = dom.findLocatorAtPoint(10, 20);

    assert.equal(before.locations.cssSelector, author.selector);
    assert.equal(after.locations.cssSelector, author.selector);
    assert.equal(after.text.highlight, authorText.parentElement.textContent);
  });
});

test("an element-boundary caret selects its semantic child instead of the wrapper", () => {
  withPointDocument(({ header, setCaretRange }) => {
    const dom = loadDomModule(global.document);
    setCaretRange({ startContainer: header, startOffset: 0 });

    const locator = dom.findLocatorAtPoint(10, 20);
    assert.equal(locator.locations.cssSelector, "#pg-machine-header h1");
    assert.equal(locator.text.highlight, "Moby-Dick");
  });
});

test("point Locator preserves its painted-element fallback without a caret range", () => {
  withPointDocument(({ header, setCaretRange, setHitElement }) => {
    const dom = loadDomModule(global.document);
    setCaretRange(null);
    setHitElement(header);

    const locator = dom.findLocatorAtPoint(10, 20);
    assert.equal(locator.locations.cssSelector, header.selector);
    assert.equal(locator.text.highlight, header.textContent);
  });
});

test("caret parents for repeated siblings remain distinguishable", () => {
  withPointDocument(({ header, setCaretRange }) => {
    const first = element(
      "#pg-header-authlist p:nth-child(1)",
      "Herman Melville",
      header
    );
    const second = element(
      "#pg-header-authlist p:nth-child(2)",
      "Herman Melville",
      header
    );
    const firstText = text("Herman Melville", first);
    const secondText = text("Herman Melville", second);
    const dom = loadDomModule(global.document);

    setCaretRange({ startContainer: firstText, startOffset: 1 });
    const firstLocator = dom.findLocatorAtPoint(10, 20);
    setCaretRange({ startContainer: secondText, startOffset: 1 });
    const secondLocator = dom.findLocatorAtPoint(10, 20);

    assert.notEqual(
      firstLocator.locations.cssSelector,
      secondLocator.locations.cssSelector
    );
    assert.equal(firstLocator.text.highlight, first.textContent);
    assert.equal(secondLocator.text.highlight, second.textContent);
  });
});
