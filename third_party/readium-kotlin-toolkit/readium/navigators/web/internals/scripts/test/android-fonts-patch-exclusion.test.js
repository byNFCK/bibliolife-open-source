const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const scriptsDir = path.resolve(__dirname, "..");
const webInternals = path.resolve(scriptsDir, "..");
const toolkit = path.resolve(webInternals, "../../..");
const webpackConfig = fs.readFileSync(path.join(scriptsDir, "webpack.config.js"), "utf8");
const generatedCss = path.join(
  webInternals,
  "src/main/assets/readium/navigator/web/internals/generated/readium-css",
);

test("Readium CSS regeneration excludes the legacy Android FXL font patch", () => {
  assert.match(webpackConfig, /ignore:\s*\[\s*["']\*\*\/android-fonts-patch\/\*\*["']\s*\]/);
});

test("the generated Readium CSS asset tree contains no Nimbus Android patch", () => {
  assert.equal(fs.existsSync(path.join(generatedCss, "android-fonts-patch")), false);
  const files = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const target = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(target);
      else files.push(target);
    }
  };
  walk(generatedCss);
  assert.equal(files.some((file) => /\.woff2?$/i.test(file) && /nimbus/i.test(path.basename(file))), false);
});

test("the generated CSS README documents the exclusion without a broken patch link", () => {
  const readme = fs.readFileSync(path.join(generatedCss, "ReadMe.md"), "utf8");
  assert.match(readme, /Android Fixed-Layout system-font patch/);
  assert.doesNotMatch(readme, /android-fonts-patch\/ReadMe\.md/);
});

test("the Android fixed-layout runtime does not request the excluded patch", () => {
  const fixedLayout = path.join(
    toolkit,
    "navigators/web/fixedlayout/src/main/kotlin/org/readium/navigator/web/fixedlayout/FixedWebRenditionState.kt",
  );
  const fixedSingle = path.join(
    webInternals,
    "src/main/kotlin/org/readium/navigator/web/internals/webapi/FixedSingleAreaApi.kt",
  );
  const fixedDouble = path.join(
    webInternals,
    "src/main/kotlin/org/readium/navigator/web/internals/webapi/FixedDoubleAreaApi.kt",
  );
  for (const file of [fixedLayout, fixedSingle, fixedDouble]) {
    assert.equal(fs.readFileSync(file, "utf8").includes("android-fonts-patch"), false, file);
  }
});
