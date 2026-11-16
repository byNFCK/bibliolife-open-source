const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const source = fs.readFileSync(path.join(__dirname, '../src/utils.js'), 'utf8');
const body = source.match(/export function isLocatorRangeAtVerticalAnchor\(locator, y, maxDistance\) \{([\s\S]*?)\n\}/)[1];
const range = top => ({getBoundingClientRect: () => ({top})});
const check = (semantic, progression) => new Function('rangeFromLocator', 'rangeFromResourceProgression', 'window', `return function(locator,y,maxDistance){${body}}`)(semantic, progression, {scrollY:0});
test('initial position locator verifies its resolved range, not observed selector or nearby progression', () => {
 const locator = {locations:{progression:0.6363636363636364}};
 const verify = check(() => null, actual => {assert.equal(actual, locator); return range(31817.43359375);});
 assert.equal(verify(locator,31817.5,1/2.8),true);
 assert.equal(verify(locator,31819,1/2.8),false);
});
test('semantic range remains authoritative and invalid geometry cannot pass', () => {
 const verify = check(() => range(50), () => {throw Error('unexpected fallback');});
 assert.equal(verify({},50,0.3),true);
 assert.equal(verify({},51,0.3),false);
 assert.equal(verify({},NaN,0.3),false);
 assert.equal(verify({},50,-1),false);
 assert.equal(check(() => null, () => null)({},50,0.3),false);
});

test('diagnostic envelope preserves the decision and samples the same Range once', () => {
 let reads=0;
 const resolved={collapsed:true,getBoundingClientRect:()=>{reads++;return {top:50,height:2};}};
 const verify=check(()=>resolved,()=>{throw Error('unexpected fallback');});
 const evidence=verify({},52,0.3,true);
 assert.equal(evidence.matches,false); assert.equal(evidence.rangeResolved,true);
 assert.equal(evidence.rangeCollapsed,true); assert.equal(evidence.distanceCssPx,2);
 assert.equal(evidence.rangeTopCssPx,50); assert.equal(reads,1);
 assert.equal(verify({},52,0.3),evidence.matches);
});
test('unresolved and non-finite diagnostic queries remain false', () => {
 assert.equal(check(()=>null,()=>null)({},10,1,true).matches,false);
 const verify=check(()=>range(50),()=>null);
 assert.equal(verify({},NaN,1,true).matches,false);
});
