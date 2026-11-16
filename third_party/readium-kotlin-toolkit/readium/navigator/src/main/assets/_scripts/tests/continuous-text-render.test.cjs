const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function fixture({ fonts = true, check = true, family = '"Example, Book", serif' } = {}) {
  const listeners = new Map(), emitted = [];
  const rect = { left: 11, top: 22, right: 19, bottom: 40, width: 8, height: 18 };
  const style = { fontFamily: family, fontSize: '18px', fontWeight: '400', lineHeight: '24px',
    fontStyle: 'normal', letterSpacing: 'normal', fontSynthesis: 'weight style',
    fontStretch: '100%', fontVariationSettings: 'normal', fontFeatureSettings: 'normal' };
  const element = { tagName: 'P', getBoundingClientRect: () => ({top: 20, bottom: 80, height: 60}), childNodes: [] };
  const node = { nodeType: 3, nodeValue: 'SECRET BOOK CONTENT', length: 19, parentElement: element };
  element.childNodes = [node];
  let connected = true;
  const fontSet = { status: 'loaded', faces: [], check: descriptor => {
    assert.ok(descriptor.includes(family)); return check;
  }, forEach(fn) { this.faces.forEach(fn); },
    addEventListener(n, fn) { listeners.set(n, fn); }, removeEventListener(n) { listeners.delete(n); } };
  const document = { body: { contains: n => connected && n === node, scrollHeight: 86657 },
    documentElement: { style: { getPropertyValue: () => style.fontWeight } },
    caretPositionFromPoint: () => ({offsetNode: node, offset: 2}),
    createRange: () => ({ setStart() {}, setEnd() {}, collapse() {},
      getBoundingClientRect: () => rect, getClientRects: () => [rect] }),
    fonts: fonts ? fontSet : undefined };
  const context = vm.createContext({ document, getComputedStyle: () => style, Node: {TEXT_NODE: 3},
    window: {readium: {}, scrollY: 0, devicePixelRatio: 2.625, visualViewport: {scale: 1},
      BiblioLifeContinuousMeasurement: { textRenderDiagnostic: (token, data) => emitted.push({token, ...JSON.parse(data)}) }},
    getCssSelector: () => 'p', console });
  const base = path.join(__dirname, '..', 'src');
  const anchor = fs.readFileSync(path.join(base, 'continuous-dom-anchor.js'), 'utf8')
    .replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
  const diagnostic = fs.readFileSync(path.join(base, 'continuous-text-render.js'), 'utf8')
    .replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
  vm.runInContext(anchor + '\n' + diagnostic, context);
  context.locator = vm.runInContext('captureContinuousDomAnchor(20,22,{locations:{}})', context);
  return {context, style, rect, fontSet, listeners, emitted, disconnect: () => connected = false,
    snapshot: () => vm.runInContext('textRenderSnapshot(locator)', context),
    stage: (stage, token = 7) => context.window.readium.textRenderDiagnostic(stage, token, {locator: context.locator}),
    compare: (a,b,count=0) => context.compareTextRender(a,b,count) };
}

test('exact retained node/UTF16 identity, computed state and geometry without text', () => {
  const f=fixture(), s=f.snapshot();
  assert.equal(s.anchorIdentityId, f.context.locator.locations.continuousDomAnchor.id);
  assert.equal(s.anchorCharacterOffset, 2); assert.equal(s.fontWeight,'400');
  assert.equal(s.fontFamily,'"Example, Book", serif'); assert.equal(s.declaredPrimaryFamily,'example, book');
  assert.equal(s.fontSizePx,18); assert.equal(s.lineHeightPx,24);
  assert.equal(s.rangeTopPx,22); assert.equal(s.elementHeightPx,60);
  assert.equal(s.devicePixelRatio,2.625); assert.equal(s.forced_layout_sample,true);
  assert.ok(!JSON.stringify(s).includes('SECRET')); assert.equal(s.letterSpacingPx,null);
});
test('unsupported document.fonts is safe unknown', () => {
  const s=fixture({fonts:false}).snapshot(); assert.equal(s.fontSetStatus,'unsupported');
  assert.equal(s.activeFontCheck,'unknown'); assert.equal(s.syntheticWeightLikely,'unknown');
});
for (const check of [true,false]) test('FontFaceSet check '+check, () => {
  const s=fixture({check}).snapshot(); assert.equal(s.fontSetStatus,'loaded'); assert.equal(s.activeFontCheck,check);
});
test('quoted multi-family descriptor safely checks fonts', () => {
  const f=fixture({family:'"A Font", "B Font", sans-serif'});
  assert.equal(f.snapshot().fallbackChainPresent,true);
});
test('collapsed zero width uses a local range without touching Selection', () => {
  const f=fixture(); f.rect.width=0; assert.equal(f.snapshot().rangeMode,'one_utf16_unit');
});
test('changed or detached exact node cannot be replaced by another anchor', () => {
  const f=fixture(); f.disconnect(); assert.equal(f.snapshot().sameDomIdentity,false);
});
test('three samples, one compare, scoped font listeners and no duplicate ACK sample', () => {
  const f=fixture(); f.stage('before_css'); assert.equal(f.listeners.size,3);
  f.style.fontWeight='700'; f.stage('after_css'); f.stage('after_measurement'); f.stage('after_measurement');
  assert.equal(f.listeners.size,0); assert.equal(f.emitted.length,4);
  assert.deepEqual(f.emitted.map(x=>x.snapshotStage),['before_css','after_css','after_measurement','after_measurement']);
  assert.equal(f.emitted[3].result,'stable_layout_repaint_suspected');
  assert.ok(!JSON.stringify(f.emitted).includes('SECRET'));
});
test('font events correlated during active generation only and summarized', () => {
  const f=fixture(); f.stage('before_css'); f.listeners.get('loading')({type:'loading'});
  f.stage('after_css'); f.stage('after_measurement');
  assert.equal(f.emitted.at(-1).result,'font_loading_transition'); assert.equal(f.listeners.size,0);
});
test('cancel and replacement remove listeners; stale tokens cannot sample new generation', () => {
  const f=fixture(); f.stage('before_css',7); f.stage('before_css',8);
  f.stage('after_css',7); assert.equal(f.emitted.length,2);
  f.stage('cancel',7); assert.equal(f.listeners.size,3);
  f.stage('cancel',8); assert.equal(f.listeners.size,0);
});
test('stable snapshots only suspect repaint, unavailable font never does', () => {
  const f=fixture(); assert.equal(f.compare(f.snapshot(),f.snapshot()).result,'stable_layout_repaint_suspected');
  const unavailable=fixture({check:false}); assert.equal(unavailable.compare(unavailable.snapshot(),unavailable.snapshot()).result,'unknown');
});
test('computed-family change is candidate only', () => {
  const f=fixture(), a=f.snapshot(); f.style.fontFamily='serif';
  assert.equal(f.compare(a,f.snapshot()).result,'font_face_change');
});
test('range geometry changes detected with same exact character', () => {
  const f=fixture(), a=f.snapshot(); f.rect.top+=0.25;
  const c=f.compare(a,f.snapshot()); assert.equal(c.result,'range_geometry_changed');
  assert.equal(c.rangeTopDeltaPx,0.25); assert.equal(c.sameCharacterOffset,true);
});
test('declared missing bold + allowed synthesis is only a likelihood', () => {
  const f=fixture(), a=f.snapshot(); f.fontSet.faces=[{family:'"Example, Book"',weight:'400',status:'loaded'}];
  f.style.fontWeight='700'; const b=f.snapshot(); assert.equal(b.syntheticWeightLikely,true);
  assert.equal(f.compare(a,b).result,'synthetic_weight_likely');
});
test('variable declared range covers requested weight without synthesis inference', () => {
  const f=fixture(); f.style.fontWeight='650'; f.fontSet.faces=[{family:'"Example, Book"',weight:'100 900',status:'loaded'}];
  assert.equal(f.snapshot().syntheticWeightLikely,false); assert.equal(f.snapshot().variableWeightDeclared,true);
});
test('unknown/loading and truncated declaration evidence cannot imply synthesis', () => {
  const f=fixture(); f.style.fontWeight='700'; f.fontSet.faces=[{family:'"Example, Book"',weight:'400',status:'loading'}];
  assert.equal(f.snapshot().syntheticWeightLikely,'unknown');
  f.fontSet.faces=Array.from({length:17},()=>({family:'"Example, Book"',weight:'400',status:'loaded'}));
  assert.equal(f.snapshot().syntheticWeightLikely,'unknown');
});
test('diagnostic API exceptions never escape into CSS apply', () => {
  const f=fixture(); f.context.getComputedStyle=()=>{throw Error('unsupported')};
  assert.doesNotThrow(()=>f.stage('before_css')); assert.equal(f.listeners.size,0);
});
