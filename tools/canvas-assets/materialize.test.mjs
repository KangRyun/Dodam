import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { cp, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test, { before } from 'node:test';
import sharp from 'sharp';

import { findMinimumUniformReferenceAffine, materialize, outputFiles } from './materialize.mjs';

const execFileAsync = promisify(execFile);
const sourceDir = path.resolve('source');
const outputDir = path.resolve('../../frontend/mobile/assets/canvas');
const baseFiles = [
  'tools/brush_base.png',
  'tools/crayon_base.png',
  'tools/eraser_base.png',
  'tools/fill_base.png',
  'tools/palette_base.png',
  'tools/pencil_base.png',
];
const maskFiles = [
  'tools/masks/brush_point.png',
  'tools/masks/crayon_point.png',
  'tools/masks/fill_point.png',
  'tools/masks/pencil_point.png',
];
let generated;

before(async () => {
  generated = await materialize({ sourceDir, outputDir });
});

async function listFiles(directory, prefix = '') {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const relative = path.posix.join(prefix, entry.name);
    if (entry.isDirectory()) files.push(...await listFiles(path.join(directory, entry.name), relative));
    else files.push(relative);
  }
  return files.sort();
}

async function metadata(relative) {
  return sharp(path.join(outputDir, relative)).metadata();
}

async function alphaStats(file) {
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let pixels = 0;
  let weight = 0;
  let weightedX = 0;
  let weightedY = 0;
  let vividGreenPixels = 0;
  let chromaGreenPixels = 0;
  for (let y = 0; y < info.height; y += 1) {
    for (let x = 0; x < info.width; x += 1) {
      const offset = (y * info.width + x) * 4;
      const alpha = data[offset + 3];
      if (alpha === 0) continue;
      pixels += 1;
      weight += alpha;
      weightedX += x * alpha;
      weightedY += y * alpha;
      if (data[offset + 1] > 80 && data[offset + 1] > data[offset] + 25 && data[offset + 1] > data[offset + 2] + 25) {
        vividGreenPixels += 1;
      }
      if (data[offset + 1] > 200 && data[offset] < 50 && data[offset + 2] < 100) chromaGreenPixels += 1;
    }
  }
  return {
    pixels,
    centroidX: weightedX / weight,
    centroidY: weightedY / weight,
    vividGreenPixels,
    chromaGreenPixels,
  };
}

async function greenDominantPixelsInCircle(file, centerX, centerY, radius) {
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let pixels = 0;
  for (let y = 0; y < info.height; y += 1) {
    for (let x = 0; x < info.width; x += 1) {
      if ((x - centerX) ** 2 + (y - centerY) ** 2 > radius ** 2) continue;
      const offset = (y * info.width + x) * 4;
      if (data[offset + 3] > 0 && data[offset + 1] > 30 && data[offset + 1] > data[offset] + 5 && data[offset + 1] > data[offset + 2] + 5) pixels += 1;
    }
  }
  return pixels;
}

async function visibleAlphaBounds(file) {
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let left = info.width;
  let top = info.height;
  let right = -1;
  let bottom = -1;
  for (let y = 0; y < info.height; y += 1) {
    for (let x = 0; x < info.width; x += 1) {
      if (data[(y * info.width + x) * 4 + 3] < 16) continue;
      left = Math.min(left, x);
      top = Math.min(top, y);
      right = Math.max(right, x);
      bottom = Math.max(bottom, y);
    }
  }
  assert.ok(right >= left, `${file} must contain visible alpha`);
  return {
    left,
    top,
    right,
    bottom,
    width: right - left + 1,
    height: bottom - top + 1,
  };
}

async function writeAuthorityRectangle(file, rectangle, imageSize = 256) {
  const image = await sharp({
    create: { width: imageSize, height: imageSize, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  }).composite([{
    input: { create: { width: rectangle.width, height: rectangle.height, channels: 4, background: '#777777ff' } },
    left: rectangle.left,
    top: rectangle.top,
  }]).png().toBuffer();
  await writeFile(file, image);
}

async function writeColorReference(file, rectangles, imageSize = 256) {
  const image = await sharp({ create: { width: imageSize, height: imageSize, channels: 3, background: '#00ff00' } })
    .composite(rectangles.map((rectangle) => ({
      input: { create: { width: rectangle.width, height: rectangle.height, channels: 3, background: '#e93434' } },
      left: rectangle.left,
      top: rectangle.top,
    })))
    .png()
    .toBuffer();
  await writeFile(file, image);
}

test('materializes only the approved runtime allowlist', async () => {
  assert.equal(outputFiles.includes('frame/frame_patch_yellow.png'), false);
  assert.deepEqual(generated.writtenFiles, outputFiles);
  assert.deepEqual(await listFiles(outputDir), [...outputFiles, 'ASSET_MANIFEST.md'].sort());
});

test('records every tool reference affine and its measured raw overlap in the manifest', async () => {
  const affineMetadata = JSON.parse(await readFile(path.resolve('reference-affines.json'), 'utf8'));
  assert.deepEqual(Object.keys(affineMetadata).sort(), ['brush', 'crayon', 'eraser', 'fill', 'palette', 'pencil']);
  const manifest = await readFile(path.join(outputDir, 'ASSET_MANIFEST.md'), 'utf8');
  for (const [name, affine] of Object.entries(affineMetadata)) {
    assert.deepEqual(Object.keys(affine).sort(), ['scaleX', 'scaleY', 'translateX', 'translateY']);
    assert.match(
      manifest,
      new RegExp(`\\| ${name} \\| ${affine.scaleX.toFixed(4)} \\| ${affine.scaleY.toFixed(4)} \\| ${affine.translateX.toFixed(2)} \\| ${affine.translateY.toFixed(2)} \\| \\d+\\.\\d{2}% \\|`),
    );
  }
});

test('finds and records the first uniform palette affine that passes the raw 98% gate', async () => {
  const calibration = await findMinimumUniformReferenceAffine({ sourceDir, name: 'palette' });
  assert.deepEqual(calibration.affine, {
    scaleX: 1.0067,
    scaleY: 1.0067,
    translateX: 0,
    translateY: 4,
  });
  assert.deepEqual(calibration.targetSize, [226, 201]);
  assert.ok(calibration.rawOverlap >= 0.98, `${calibration.rawOverlap}`);
  assert.ok(calibration.previousBestOverlap < 0.98, `${calibration.previousBestOverlap}`);

  const affineMetadata = JSON.parse(await readFile(path.resolve('reference-affines.json'), 'utf8'));
  assert.deepEqual(affineMetadata.palette, calibration.affine);
});

test('keeps an exact four-decimal scale breakpoint instead of advancing past it', async () => {
  const identity = await findMinimumUniformReferenceAffine({
    sourceDir,
    name: 'brush',
    maximumScale: 1,
  });
  assert.equal(identity.affine.scaleX, 1);
  assert.equal(identity.affine.scaleY, 1);

  const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'canvas-affine-breakpoint-'));
  const fixtureSource = path.join(fixtureRoot, 'source');
  try {
    await cp(sourceDir, fixtureSource, { recursive: true });
    await writeAuthorityRectangle(
      path.join(fixtureSource, 'tools/brush.png'),
      { left: 16, top: 25, width: 224, height: 205 },
    );
    await writeColorReference(
      path.join(fixtureSource, 'color-references/brush.png'),
      [{ left: 16, top: 28, width: 224, height: 200 }],
    );

    const calibration = await findMinimumUniformReferenceAffine({
      sourceDir: fixtureSource,
      name: 'brush',
      maximumScale: 1.0025,
    });

    assert.deepEqual(calibration.affine, {
      scaleX: 1.0025,
      scaleY: 1.0025,
      translateX: 0,
      translateY: 0,
    });
    assert.deepEqual(calibration.targetSize, [225, 201]);
    assert.equal(calibration.rawOverlap, 201 / 205);
    assert.equal(calibration.previousBestOverlap, 200 / 205);
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});

test('materializes 256px tool artwork and masks, 48px swatches, and contained masks', async () => {
  for (const relative of [...baseFiles, ...maskFiles]) {
    const image = await metadata(relative);
    assert.equal(image.width, 256, relative);
    assert.equal(image.height, 256, relative);
  }
  for (const color of ['red', 'orange', 'yellow', 'green', 'teal', 'blue', 'purple', 'charcoal']) {
    const image = await metadata(`swatches/${color}.png`);
    assert.equal(image.width, 48, color);
    assert.equal(image.height, 48, color);
  }
  for (const relative of maskFiles) {
    const tool = relative.replace('tools/masks/', 'tools/').replace('_point.png', '_base.png');
    const [mask, artwork] = await Promise.all([
      sharp(path.join(outputDir, relative)).ensureAlpha().raw().toBuffer(),
      sharp(path.join(outputDir, tool)).ensureAlpha().raw().toBuffer(),
    ]);
    for (let index = 3; index < mask.length; index += 4) {
      assert.equal(mask[index] > 0 && artwork[index] === 0, false, `${relative} extends beyond ${tool}`);
    }
  }
});

test('retains the palette interior green while removing the connected green screen', async () => {
  const stats = await alphaStats(path.join(outputDir, 'tools/palette_base.png'));
  assert.ok(stats.vividGreenPixels > 250, `expected palette green material, found ${stats.vividGreenPixels} pixels`);
  assert.equal(stats.chromaGreenPixels, 0, `found ${stats.chromaGreenPixels} green-screen pixels in palette output`);
  const thumbHoleGreen = await greenDominantPixelsInCircle(path.join(outputDir, 'tools/palette_base.png'), 172, 135, 35);
  assert.equal(thumbHoleGreen, 0, `found ${thumbHoleGreen} green-screen fringe pixels in palette thumb hole`);
});

test('contains a non-square authority silhouette without distortion and centers it in the 224px safe box', async () => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'canvas-aspect-'));
  const fixtureSource = path.join(fixtureRoot, 'source');
  const fixtureOutput = path.join(fixtureRoot, 'output');
  try {
    await cp(sourceDir, fixtureSource, { recursive: true });
    const rectangle = { left: 48, top: 88, width: 160, height: 80 };
    await writeAuthorityRectangle(path.join(fixtureSource, 'tools/brush.png'), rectangle);
    await writeColorReference(path.join(fixtureSource, 'color-references/brush.png'), [rectangle]);
    await writeAuthorityRectangle(
      path.join(fixtureSource, 'masks/brush-point.png'),
      { left: 100, top: 100, width: 20, height: 20 },
    );

    await materialize({ sourceDir: fixtureSource, outputDir: fixtureOutput });

    const bounds = await visibleAlphaBounds(path.join(fixtureOutput, 'tools/brush_base.png'));
    assert.ok(bounds.left >= 16 && bounds.top >= 16 && bounds.right <= 239 && bounds.bottom <= 239, JSON.stringify(bounds));
    assert.ok(Math.abs(bounds.width / bounds.height - 2) < 0.03, `expected 2:1 silhouette, got ${bounds.width}:${bounds.height}`);
    assert.ok(Math.abs((bounds.left + bounds.right) / 2 - 127.5) <= 1, `x center ${JSON.stringify(bounds)}`);
    assert.ok(Math.abs((bounds.top + bounds.bottom) / 2 - 127.5) <= 1, `y center ${JSON.stringify(bounds)}`);
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});

test('materializes non-empty point masks on their registered tool regions', async () => {
  const expectedCentroids = {
    brush: [68, 213],
    crayon: [117, 137],
    fill: [129, 144],
    pencil: [140, 116],
  };
  for (const [name, [expectedX, expectedY]] of Object.entries(expectedCentroids)) {
    const stats = await alphaStats(path.join(outputDir, `tools/masks/${name}_point.png`));
    assert.ok(stats.pixels > 100, `${name} point mask must not be blank`);
    assert.ok(Math.abs(stats.centroidX - expectedX) < 14, `${name} point mask x centroid ${stats.centroidX}`);
    assert.ok(Math.abs(stats.centroidY - expectedY) < 14, `${name} point mask y centroid ${stats.centroidY}`);
  }
});

test('rejects a blank source point mask', async () => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'canvas-blank-mask-'));
  const fixtureSource = path.join(fixtureRoot, 'source');
  const fixtureOutput = path.join(fixtureRoot, 'output');
  try {
    await cp(sourceDir, fixtureSource, { recursive: true });
    const blank = await sharp({ create: { width: 256, height: 256, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
      .png()
      .toBuffer();
    await writeFile(path.join(fixtureSource, 'masks/brush-point.png'), blank);
    await assert.rejects(
      materialize({ sourceDir: fixtureSource, outputDir: fixtureOutput }),
      /brush point mask is blank/,
    );
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});

test('rejects a color reference whose registered alpha misses the authority silhouette', async () => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'canvas-misaligned-'));
  const fixtureSource = path.join(fixtureRoot, 'source');
  const fixtureOutput = path.join(fixtureRoot, 'output');
  try {
    await cp(sourceDir, fixtureSource, { recursive: true });
    const marker = await sharp({ create: { width: 256, height: 256, channels: 3, background: '#00ff00' } })
      .composite([
        { input: { create: { width: 20, height: 20, channels: 3, background: '#e93434' } }, left: 16, top: 16 },
        { input: { create: { width: 20, height: 20, channels: 3, background: '#e93434' } }, left: 220, top: 220 },
      ])
      .png()
      .toBuffer();
    await writeFile(path.join(fixtureSource, 'color-references/brush.png'), marker);
    await assert.rejects(
      materialize({ sourceDir: fixtureSource, outputDir: fixtureOutput }),
      /brush color-reference alpha overlap is below 98%/,
    );
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});

test('rejects 97% raw reference-alpha coverage before imposing authority alpha', async () => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'canvas-overlap-97-'));
  const fixtureSource = path.join(fixtureRoot, 'source');
  const fixtureOutput = path.join(fixtureRoot, 'output');
  try {
    await cp(sourceDir, fixtureSource, { recursive: true });
    const authority = { left: 16, top: 16, width: 224, height: 224 };
    await writeAuthorityRectangle(path.join(fixtureSource, 'tools/brush.png'), authority);
    await writeColorReference(path.join(fixtureSource, 'color-references/brush.png'), [
      { left: 16, top: 16, width: 218, height: 224 },
      { left: 239, top: 239, width: 1, height: 1 },
    ]);

    await assert.rejects(
      materialize({ sourceDir: fixtureSource, outputDir: fixtureOutput }),
      (error) => {
        const match = /brush color-reference alpha overlap is below 98% \((\d+\.\d+)%\)/.exec(error.message);
        assert.ok(match, error.message);
        assert.ok(Number(match[1]) >= 97 && Number(match[1]) < 98, `expected 97% fixture, got ${match[1]}%`);
        return true;
      },
    );
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});

test('does not count Lanczos alpha ringing as raw reference coverage', async () => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'canvas-overlap-ringing-'));
  const fixtureSource = path.join(fixtureRoot, 'source');
  const fixtureOutput = path.join(fixtureRoot, 'output');
  try {
    await cp(sourceDir, fixtureSource, { recursive: true });
    const authority = { left: 1, top: 1, width: 1000, height: 1000 };
    await writeAuthorityRectangle(path.join(fixtureSource, 'tools/brush.png'), authority, 1002);
    await writeColorReference(path.join(fixtureSource, 'color-references/brush.png'), [
      { left: 1, top: 1, width: 978, height: 1000 },
      { left: 1000, top: 1000, width: 1, height: 1 },
    ], 1002);

    await assert.rejects(
      materialize({ sourceDir: fixtureSource, outputDir: fixtureOutput }),
      /brush color-reference alpha overlap is below 98%/,
    );
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});

test('accepts reference-alpha coverage at or above 98%', async () => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'canvas-overlap-98-'));
  const fixtureSource = path.join(fixtureRoot, 'source');
  const fixtureOutput = path.join(fixtureRoot, 'output');
  try {
    await cp(sourceDir, fixtureSource, { recursive: true });
    const authority = { left: 16, top: 16, width: 224, height: 224 };
    await writeAuthorityRectangle(path.join(fixtureSource, 'tools/brush.png'), authority);
    await writeColorReference(path.join(fixtureSource, 'color-references/brush.png'), [
      { left: 16, top: 16, width: 220, height: 224 },
      { left: 239, top: 239, width: 1, height: 1 },
    ]);

    await materialize({ sourceDir: fixtureSource, outputDir: fixtureOutput });
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});

test('rejects every unexpected runtime file, including non-PNG files', async () => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'canvas-stray-'));
  const fixtureOutput = path.join(fixtureRoot, 'output');
  try {
    await materialize({ sourceDir, outputDir: fixtureOutput });
    await writeFile(path.join(fixtureOutput, 'stray.txt'), 'not an approved runtime asset');
    await assert.rejects(
      materialize({ sourceDir, outputDir: fixtureOutput }),
      /Unexpected runtime output: stray\.txt/,
    );
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});

test('check mode verifies a byte-identical deterministic render without writing', async () => {
  const result = await materialize({ sourceDir, outputDir, check: true });
  assert.deepEqual(result.writtenFiles, []);
  assert.deepEqual(result.verifiedFiles, outputFiles);
  await execFileAsync(process.execPath, ['materialize.mjs', '--check']);
});
