import assert from "node:assert/strict";
import { stat } from "node:fs/promises";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

const landingImage = new URL(
  "../../public/assets/landing/characters/val_talk.png",
  import.meta.url,
);
const landingImagePath = fileURLToPath(landingImage);

test("production image optimizer can resize the landing PNG to WebP", async () => {
  const source = await stat(landingImagePath);
  const optimized = await sharp(landingImagePath)
    .resize({ width: 640 })
    .webp()
    .toBuffer();
  const metadata = await sharp(optimized).metadata();

  assert.equal(metadata.format, "webp");
  assert.equal(metadata.width, 640);
  assert.ok(optimized.byteLength > 0);
  assert.ok(optimized.byteLength < source.size);
});
