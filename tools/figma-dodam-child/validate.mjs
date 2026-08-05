import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(await readFile(resolve(root, "manifest.json"), "utf8"));
const source = await readFile(resolve(root, "src/code.js"), "utf8");
const dist = await readFile(resolve(root, "dist/code.js"), "utf8");
const ui = await readFile(resolve(root, "dist/ui.html"), "utf8");

assert.equal(manifest.editorType[0], "figma");
assert.equal(manifest.main, "dist/code.js");
assert.equal(manifest.ui, "dist/ui.html");
assert.equal(manifest.documentAccess, "dynamic-page");

for (const required of [
  "#F2D765",
  "NanumSquare Neo",
  "Dodam Child UI v2 · All Screens",
  "00 · V2 Direction",
  "01 · V2 Foundations",
  "02 · V2 Components",
  "10 · V2 Mobile",
  "11 · V2 Tablet",
  "99 · V2 Flow",
  "createMobileScreen",
  "createTabletScreen",
  "ensureVariables",
  "ensureTextStyles",
  "Action / Button",
  "Activity / Card",
  "Choice / Chip",
  "Emotion / Choice",
  "V2_REFERENCE_MODE",
  "addTactileTile",
  "addSceneBackdrop",
  "addCrayonTray",
  "addStickerBurst",
  "createV2DirectionSection",
  "createV2FoundationsSection",
  "createV2ComponentsSection",
  "renderMobileHomeV2",
  "renderMobileTopicV2",
  "renderMobileDrawingV2",
  "renderMobileEmotionV2",
  "renderMobileCompleteV2",
  "renderTabletHomeV2",
  "renderTabletTopicV2",
  "renderTabletDrawingV2",
  "renderTabletEmotionV2",
  "renderTabletCompleteV2",
]) {
  assert.ok(source.includes(required), `Missing source marker: ${required}`);
}

const mobileBlock = source.match(
  /const MOBILE_SCREENS = \[(.*?)\];\s*\n\s*const TABLET_SCREENS/s,
);
assert.ok(mobileBlock, "MOBILE_SCREENS array not found");
assert.equal((mobileBlock[1].match(/\["C\d{2}"/g) || []).length, 14);
assert.ok(source.includes("const TABLET_SCREENS = MOBILE_SCREENS.slice(2);"));
assert.ok(
  !source.includes('const GENERATED_PAGES = ["Dodam Child UI · All Screens"]'),
  "v1 output name must be replaced by the v2 design page",
);
const generatedPagesBlock = source.match(
  /const GENERATED_PAGES = \[(.*?)\];/s,
);
assert.ok(generatedPagesBlock, "GENERATED_PAGES array not found");
assert.equal(
  (generatedPagesBlock[1].match(/"/g) || []).length,
  2,
  "Starter-compatible generator must use exactly one generated page",
);
assert.ok(
  !source.includes("figma.createPage()"),
  "Starter-compatible generator must not create additional Figma pages",
);
assert.ok(
  source.includes("createSectionBoard"),
  "The single page must organize content into named sections",
);
assert.ok(
  !source.includes("figma.getLocalTextStyles()"),
  "dynamic-page plugins must not call getLocalTextStyles()",
);
assert.ok(
  source.includes("await figma.getLocalTextStylesAsync()"),
  "dynamic-page plugins must await getLocalTextStylesAsync()",
);
assert.ok(
  source.includes("await figma.loadAllPagesAsync()"),
  "document-wide cleanup must load all pages in dynamic-page mode",
);
assert.ok(
  source.includes("await page.loadAsync()"),
  "new pages must be loaded before appendChild in dynamic-page mode",
);
const vectorPathData = [...source.matchAll(/data:\s*`([^`]*)`/g)].map(
  (match) => match[1],
);
assert.ok(vectorPathData.length > 0, "Expected at least one editable vector path");
assert.ok(
  vectorPathData.every((value) => !value.includes(",")),
  "Figma VectorPath commands must use single spaces, not commas",
);
assert.ok(
  source.includes('windingRule: "NONE"'),
  "Open stroked vector paths must use the NONE winding rule",
);
assert.ok(
  !source.includes(".endCap ="),
  "Figma LineNode has no endCap property",
);
assert.ok(
  source.includes('arrow.strokeCap = "ARROW_LINES"'),
  "Handoff arrows must use the supported LineNode strokeCap property",
);
assert.ok(
  /function imageRect\([^)]*scaleMode = "FILL"\)/s.test(source),
  "Transparent Dodami assets must crop transparent canvas padding with FILL",
);

assert.ok(dist.length > 900_000, "Embedded mascot assets are missing");
assert.ok(dist.includes("const DODAMI_BRAND_BASE64 ="));
assert.ok(dist.includes("const DODAMI_DRAWING_BASE64 ="));
assert.ok(!dist.includes("__DODAMI_BRAND_BASE64__"));
assert.ok(
  ui.includes("한 페이지 안에"),
  "Plugin UI must explain the Starter-compatible single-page layout",
);
assert.ok(ui.includes("Dodam Child UI v2 Generator"));
assert.ok(ui.includes("v2 아동 화면 새로 만들기"));

for (const [asset, expectedHash] of [
  [
    "../../docs/design/assets/characters/dodami-brand-yellow-scarf.png",
    "47c8bf3d7107babe64b65e79bf6194fb9e7d32b0372038fa50824c01f3370f87",
  ],
  [
    "../../docs/design/assets/characters/dodami-drawing-yellow-scarf.png",
    "6cf738d30fc9ea23e0342734f26e36e999ea59b870a634e5ba9ebe12a4b43f16",
  ],
]) {
  const assetPath = resolve(root, asset);
  const info = await stat(assetPath);
  assert.ok(info.size > 250_000, `Asset is unexpectedly small: ${asset}`);
  const png = await readFile(assetPath);
  assert.equal(png.toString("ascii", 1, 4), "PNG", `Not a PNG: ${asset}`);
  assert.equal(
    png.readUInt8(25),
    6,
    `Dodami asset must be RGBA with a transparent background: ${asset}`,
  );
  assert.equal(
    createHash("sha256").update(png).digest("hex"),
    expectedHash,
    `Dodami asset differs from the user-approved transparent source: ${asset}`,
  );
}

console.log("Dodam Figma plugin validation passed");
console.log("- 1 generated page with 6 sections");
console.log("- 14 mobile screens");
console.log("- 12 tablet screens");
console.log("- 4 component sets");
console.log("- 2 embedded Dodami assets");
