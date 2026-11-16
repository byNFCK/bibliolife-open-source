const assert = require("node:assert/strict");
const test = require("node:test");
const path = require("node:path");
const { chromium } = require("playwright");

test("same DOM character survives real CSS rewrap with explicit degradation", async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.ANCHOR_TEST_BROWSER });
  try {
    const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
    await page.setContent(`<style>body { margin:20px; font:18px/1.4 serif; }
      p { margin:0 0 16px; }</style>` + Array.from({length: 20}, (_, i) =>
      `<p id="p${i}">${("Synthetic sample words for a stable character boundary. ").repeat(12)}</p>`).join(""));
    await page.evaluate(() => { window.Android = { log(){}, logError(){} }; });
    await page.addScriptTag({ path: path.join(__dirname, "../../readium/scripts/readium-reflowable.js") });
    const result = await page.evaluate(async () => {
      const anchor = readium.captureContinuousReadingAnchor(200, 430);
      const initial = readium.continuousLocatorPointGeometry(anchor);
      const start = anchor.locations.domRange.start;
      const node = Array.from(document.querySelector(start.cssSelector).childNodes)
        .filter(n => n.nodeType === Node.TEXT_NODE)[start.textNodeIndex];
      const offset = start.charOffset;
      const selectedCharacter = node.nodeValue.charAt(offset);
      const layouts = [];
      for (const [name, value] of [["font-size", "26px"], ["font-weight", "900"],
        ["line-height", "2"], ["margin", "64px"]]) {
        document.body.style.setProperty(name, value);
        await new Promise(requestAnimationFrame);
        const point = readium.continuousLocatorPointGeometry(anchor);
        layouts.push({ ...point, sameNode: node === Array.from(document.querySelector(start.cssSelector).childNodes)
          .filter(n => n.nodeType === Node.TEXT_NODE)[start.textNodeIndex],
          sameCharacter: node.nodeValue.charAt(offset) === selectedCharacter });
      }
      // Progression metadata cannot invalidate an exact retained DOM point.
      anchor.locations.progression = 0.001;
      const changedProgression = readium.continuousLocatorPointGeometry(anchor);
      const altered = JSON.parse(JSON.stringify(anchor));
      altered.locations.domRange.start.charOffset += 1;
      const tamperedOffset = readium.continuousLocatorPointGeometry(altered);
      node.parentElement.replaceChild(node.cloneNode(true), node);
      const replaced = readium.continuousLocatorPointGeometry(anchor);
      // Bounded nearest-text search must reject a huge image/non-text region.
      document.body.innerHTML = '<div style="height:3000px"></div><p>Sample</p>';
      const empty = readium.captureContinuousReadingAnchor(200, 430);
      document.body.innerHTML = '<p style="position:absolute;top:450px">Nearby synthetic text</p>';
      const nearby = readium.captureContinuousReadingAnchor(200, 430);
      const nearbyPoint = readium.continuousLocatorPointGeometry(nearby);
      return { anchor, initial, layouts, changedProgression, tamperedOffset, replaced, empty, nearby, nearbyPoint };
    });
    assert.equal(result.initial.semanticAnchorExact, true);
    assert.ok(result.layouts.some(p => Math.abs(p.documentY - result.initial.documentY) > 20));
    for (const point of result.layouts) {
      assert.equal(point.semanticAnchorExact, true);
      assert.equal(point.anchorIdentityId, result.initial.anchorIdentityId);
      assert.equal(point.anchorCharacterOffset, result.initial.anchorCharacterOffset);
      assert.equal(point.sameNode, true);
      assert.equal(point.sameCharacter, true);
    }
    assert.equal(result.changedProgression.semanticAnchorExact, true);
    assert.equal(result.tamperedOffset.semanticAnchorExact, false);
    assert.equal(result.replaced.semanticAnchorExact, false);
    assert.equal(result.empty.locations.continuousDomAnchor.id, null);
    assert.ok(Math.abs(result.anchor.locations.continuousDomAnchor.pointToTargetOffsetCssPx) <= 64);
    assert.equal(result.nearbyPoint.semanticAnchorExact, true);
    assert.ok(Math.abs(result.nearby.locations.continuousDomAnchor.pointToTargetOffsetCssPx) <= 64);
    assert.equal(result.nearbyPoint.viewportTop - 430,
      result.nearby.locations.continuousDomAnchor.pointToTargetOffsetCssPx);
  } finally { await browser.close(); }
});
