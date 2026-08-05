import { fileURLToPath } from 'node:url';
import { dirname, join, posix } from 'node:path';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import sharp from 'sharp';

const moduleDirectory = dirname(fileURLToPath(import.meta.url));
const safeBox = 224;
const canvasSize = 256;
const toolNames = ['brush', 'crayon', 'eraser', 'fill', 'palette', 'pencil'];
const maskedTools = ['brush', 'crayon', 'fill', 'pencil'];
const swatchNames = ['red', 'orange', 'yellow', 'green', 'teal', 'blue', 'purple', 'charcoal'];
const frameNames = [
  'back', 'undo', 'redo', 'save', 'button_green', 'button_yellow',
  'canvas_frame_mobile', 'canvas_frame_tablet', 'toolbar_frame_mobile',
  'toolbar_frame_tablet', 'frame_patch_graphite', 'paper_texture',
  'selected_tool', 'slider_track', 'speech_bubble', 'spiral_mobile', 'spiral_tablet',
];

export const outputFiles = Object.freeze([
  ...toolNames.map((name) => `tools/${name}_base.png`),
  ...maskedTools.map((name) => `tools/masks/${name}_point.png`),
  ...swatchNames.map((name) => `swatches/${name}.png`),
  ...frameNames.map((name) => `frame/${name}.png`),
]);

async function loadReferenceAffines() {
  const metadata = JSON.parse(await readFile(join(moduleDirectory, 'reference-affines.json'), 'utf8'));
  const names = Object.keys(metadata).sort();
  if (names.length !== toolNames.length || names.some((name, index) => name !== [...toolNames].sort()[index])) {
    throw new Error('Reference affine metadata must match the tool allowlist');
  }
  for (const [name, affine] of Object.entries(metadata)) {
    const keys = Object.keys(affine).sort();
    if (keys.join(',') !== 'scaleX,scaleY,translateX,translateY') throw new Error(`${name} reference affine has unexpected fields`);
    if (![affine.scaleX, affine.scaleY, affine.translateX, affine.translateY].every(Number.isFinite)) {
      throw new Error(`${name} reference affine must use finite numbers`);
    }
    if (affine.scaleX <= 0 || affine.scaleY <= 0) throw new Error(`${name} reference affine scale must be positive`);
  }
  return metadata;
}

function alphaBounds(data, width, height) {
  let left = width;
  let top = height;
  let right = -1;
  let bottom = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (data[(y * width + x) * 4 + 3] < 16) continue;
      left = Math.min(left, x);
      top = Math.min(top, y);
      right = Math.max(right, x);
      bottom = Math.max(bottom, y);
    }
  }
  if (right < left) throw new Error('Expected non-transparent artwork');
  return { left, top, width: right - left + 1, height: bottom - top + 1 };
}

function isChromaCandidate(red, green, blue) {
  return green >= 10 && green > Math.max(red, blue);
}

function removeBorderConnectedChroma(data, width, height) {
  const visited = new Uint8Array(width * height);
  const queue = new Int32Array(width * height);
  let head = 0;
  let tail = 0;
  let borderRed = 0;
  let borderGreen = 0;
  let borderBlue = 0;
  let borderSamples = 0;
  const sampleBorder = (x, y) => {
    const offset = (y * width + x) * 4;
    if (!isChromaCandidate(data[offset], data[offset + 1], data[offset + 2])) return;
    borderRed += data[offset];
    borderGreen += data[offset + 1];
    borderBlue += data[offset + 2];
    borderSamples += 1;
  };
  const enqueue = (x, y) => {
    const pixel = y * width + x;
    if (visited[pixel]) return;
    const offset = pixel * 4;
    if (!isChromaCandidate(data[offset], data[offset + 1], data[offset + 2])) return;
    visited[pixel] = 1;
    queue[tail] = pixel;
    tail += 1;
  };
  for (let x = 0; x < width; x += 1) {
    sampleBorder(x, 0);
    sampleBorder(x, height - 1);
    enqueue(x, 0);
    enqueue(x, height - 1);
  }
  for (let y = 1; y < height - 1; y += 1) {
    sampleBorder(0, y);
    sampleBorder(width - 1, y);
    enqueue(0, y);
    enqueue(width - 1, y);
  }
  while (head < tail) {
    const pixel = queue[head];
    head += 1;
    const x = pixel % width;
    const y = Math.floor(pixel / width);
    for (let deltaY = -1; deltaY <= 1; deltaY += 1) {
      for (let deltaX = -1; deltaX <= 1; deltaX += 1) {
        if ((deltaX === 0 && deltaY === 0) || x + deltaX < 0 || x + deltaX >= width || y + deltaY < 0 || y + deltaY >= height) continue;
        enqueue(x + deltaX, y + deltaY);
      }
    }
  }
  if (borderSamples === 0) throw new Error('Color reference has no chroma background on its border');
  const background = [borderRed / borderSamples, borderGreen / borderSamples, borderBlue / borderSamples];
  const nearBackground = (pixel) => {
    const offset = pixel * 4;
    const redDistance = data[offset] - background[0];
    const greenDistance = data[offset + 1] - background[1];
    const blueDistance = data[offset + 2] - background[2];
    return redDistance * redDistance + greenDistance * greenDistance + blueDistance * blueDistance <= 110 * 110;
  };
  const classified = new Uint8Array(width * height);
  for (let pixel = 0; pixel < visited.length; pixel += 1) {
    const offset = pixel * 4;
    if (visited[pixel] || classified[pixel] || !isChromaCandidate(data[offset], data[offset + 1], data[offset + 2])) continue;
    head = 0;
    tail = 0;
    classified[pixel] = 1;
    queue[tail] = pixel;
    tail += 1;
    let nearBackgroundPixels = 0;
    while (head < tail) {
      const componentPixel = queue[head];
      head += 1;
      if (nearBackground(componentPixel)) nearBackgroundPixels += 1;
      const x = componentPixel % width;
      const y = Math.floor(componentPixel / width);
      for (let deltaY = -1; deltaY <= 1; deltaY += 1) {
        for (let deltaX = -1; deltaX <= 1; deltaX += 1) {
          const nextX = x + deltaX;
          const nextY = y + deltaY;
          if ((deltaX === 0 && deltaY === 0) || nextX < 0 || nextX >= width || nextY < 0 || nextY >= height) continue;
          const next = nextY * width + nextX;
          const nextOffset = next * 4;
          if (visited[next] || classified[next] || !isChromaCandidate(data[nextOffset], data[nextOffset + 1], data[nextOffset + 2])) continue;
          classified[next] = 1;
          queue[tail] = next;
          tail += 1;
        }
      }
    }
    if (nearBackgroundPixels / tail >= 0.5) {
      for (let index = 0; index < tail; index += 1) visited[queue[index]] = 1;
    }
  }
  for (let pixel = 0; pixel < visited.length; pixel += 1) {
    if (!visited[pixel]) continue;
    const offset = pixel * 4;
    data[offset] = 0;
    data[offset + 1] = 0;
    data[offset + 2] = 0;
    data[offset + 3] = 0;
  }
}

async function rawRgba(file) {
  return sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
}

async function resizeRaw(data, width, height, targetWidth, targetHeight, kernel = sharp.kernel.lanczos3) {
  if (width === targetWidth && height === targetHeight) return Buffer.from(data);
  // The caller derives target dimensions from one contain scale. `fill` here
  // realizes that explicit pixel-grid affine; it never forces a 224x224 box.
  return sharp(data, { raw: { width, height, channels: 4 } })
    .resize(targetWidth, targetHeight, { fit: 'fill', kernel })
    .raw()
    .toBuffer();
}

function cropRaw(data, width, bounds) {
  const result = Buffer.alloc(bounds.width * bounds.height * 4);
  for (let y = 0; y < bounds.height; y += 1) {
    const sourceOffset = ((bounds.top + y) * width + bounds.left) * 4;
    data.copy(result, y * bounds.width * 4, sourceOffset, sourceOffset + bounds.width * 4);
  }
  return result;
}

function alphaCentroid(data) {
  let pixels = 0;
  let xTotal = 0;
  let yTotal = 0;
  for (let pixel = 0; pixel < data.length / 4; pixel += 1) {
    if (data[pixel * 4 + 3] < 16) continue;
    pixels += 1;
    xTotal += pixel % canvasSize;
    yTotal += Math.floor(pixel / canvasSize);
  }
  return { x: xTotal / pixels, y: yTotal / pixels };
}

function binaryAlpha(data) {
  const support = Buffer.alloc(data.length);
  for (let offset = 3; offset < data.length; offset += 4) {
    support[offset] = data[offset] >= 16 ? 255 : 0;
  }
  return support;
}

function containedTransform(bounds) {
  const scale = Math.min(safeBox / bounds.width, safeBox / bounds.height);
  const targetWidth = Math.max(1, Math.min(safeBox, Math.round(bounds.width * scale)));
  const targetHeight = Math.max(1, Math.min(safeBox, Math.round(bounds.height * scale)));
  return {
    sourceLeft: bounds.left,
    sourceTop: bounds.top,
    sourceWidth: bounds.width,
    sourceHeight: bounds.height,
    targetLeft: Math.floor((canvasSize - targetWidth) / 2),
    targetTop: Math.floor((canvasSize - targetHeight) / 2),
    targetWidth,
    targetHeight,
  };
}

function applyReferenceAffine(containTransform, affine) {
  const targetWidth = Math.max(1, Math.round(containTransform.targetWidth * affine.scaleX));
  const targetHeight = Math.max(1, Math.round(containTransform.targetHeight * affine.scaleY));
  const targetLeft = Math.round(
    containTransform.targetLeft + containTransform.targetWidth / 2 - targetWidth / 2 + affine.translateX,
  );
  const targetTop = Math.round(
    containTransform.targetTop + containTransform.targetHeight / 2 - targetHeight / 2 + affine.translateY,
  );
  if (targetLeft < 0 || targetTop < 0 || targetLeft + targetWidth > canvasSize || targetTop + targetHeight > canvasSize) {
    throw new Error('Reference affine must remain inside the 256px registration canvas');
  }
  return {
    ...containTransform,
    targetLeft,
    targetTop,
    targetWidth,
    targetHeight,
  };
}

async function applyTransform(data, sourceWidth, transform, kernel = sharp.kernel.lanczos3) {
  const crop = cropRaw(data, sourceWidth, {
    left: transform.sourceLeft,
    top: transform.sourceTop,
    width: transform.sourceWidth,
    height: transform.sourceHeight,
  });
  const fitted = await resizeRaw(
    crop,
    transform.sourceWidth,
    transform.sourceHeight,
    transform.targetWidth,
    transform.targetHeight,
    kernel,
  );
  const canvas = Buffer.alloc(canvasSize * canvasSize * 4);
  for (let y = 0; y < transform.targetHeight; y += 1) {
    const sourceOffset = y * transform.targetWidth * 4;
    const destinationOffset = ((transform.targetTop + y) * canvasSize + transform.targetLeft) * 4;
    fitted.copy(canvas, destinationOffset, sourceOffset, sourceOffset + transform.targetWidth * 4);
  }
  return canvas;
}

const bitWordsPerRow = canvasSize / 32;

function supportBitRows(data) {
  const rows = new Uint32Array(canvasSize * bitWordsPerRow);
  for (let pixel = 0; pixel < canvasSize * canvasSize; pixel += 1) {
    if (data[pixel * 4 + 3] === 0) continue;
    const x = pixel % canvasSize;
    const y = Math.floor(pixel / canvasSize);
    rows[y * bitWordsPerRow + Math.floor(x / 32)] |= 1 << (x % 32);
  }
  return rows;
}

function popcount32(value) {
  let result = value - ((value >>> 1) & 0x55555555);
  result = (result & 0x33333333) + ((result >>> 2) & 0x33333333);
  return (((result + (result >>> 4)) & 0x0f0f0f0f) * 0x01010101) >>> 24;
}

function shiftedRowWord(rows, row, word, translateX) {
  if (translateX === 0) return rows[row * bitWordsPerRow + word];
  const shift = Math.abs(translateX);
  const wordShift = Math.floor(shift / 32);
  const bitShift = shift % 32;
  const read = (sourceWord) => (
    sourceWord < 0 || sourceWord >= bitWordsPerRow ? 0 : rows[row * bitWordsPerRow + sourceWord]
  );
  if (translateX > 0) {
    const sourceWord = word - wordShift;
    if (bitShift === 0) return read(sourceWord);
    return (read(sourceWord) << bitShift) | (read(sourceWord - 1) >>> (32 - bitShift));
  }
  const sourceWord = word + wordShift;
  if (bitShift === 0) return read(sourceWord);
  return (read(sourceWord) >>> bitShift) | (read(sourceWord + 1) << (32 - bitShift));
}

function translatedOverlap(authorityRows, referenceRows, translateX, translateY) {
  let overlap = 0;
  for (let y = 0; y < canvasSize; y += 1) {
    const referenceY = y - translateY;
    if (referenceY < 0 || referenceY >= canvasSize) continue;
    for (let word = 0; word < bitWordsPerRow; word += 1) {
      const authorityWord = authorityRows[y * bitWordsPerRow + word];
      if (authorityWord === 0) continue;
      overlap += popcount32(authorityWord & shiftedRowWord(referenceRows, referenceY, word, translateX));
    }
  }
  return overlap;
}

function uniformScaleCandidates(width, height, maximumScale) {
  const scalePrecision = 10000;
  const maximumTick = Math.floor(maximumScale * scalePrecision + 1e-9);
  const candidates = [];
  let previousSize;
  for (let tick = scalePrecision; tick <= maximumTick; tick += 1) {
    const scale = tick / scalePrecision;
    const targetWidth = Math.round(width * scale);
    const targetHeight = Math.round(height * scale);
    if (targetWidth > canvasSize || targetHeight > canvasSize) break;
    const size = `${targetWidth}x${targetHeight}`;
    if (size === previousSize) continue;
    candidates.push(scale);
    previousSize = size;
  }
  return candidates;
}

export async function findMinimumUniformReferenceAffine({
  sourceDir = join(moduleDirectory, 'source'),
  name,
  minimumOverlap = 0.98,
  maximumScale = 1.25,
} = {}) {
  if (!toolNames.includes(name)) throw new Error(`Unknown tool for affine calibration: ${name}`);

  const authority = await rawRgba(join(sourceDir, 'tools', `${name}.png`));
  const authorityTransform = containedTransform(alphaBounds(authority.data, authority.info.width, authority.info.height));
  const authoritySupport = await applyTransform(
    binaryAlpha(authority.data),
    authority.info.width,
    authorityTransform,
    sharp.kernel.nearest,
  );
  const authorityRows = supportBitRows(authoritySupport);
  let authoritativePixels = 0;
  for (const word of authorityRows) authoritativePixels += popcount32(word);

  const reference = await rawRgba(join(sourceDir, 'color-references', `${name}.png`));
  removeBorderConnectedChroma(reference.data, reference.info.width, reference.info.height);
  const referenceContainTransform = containedTransform(alphaBounds(reference.data, reference.info.width, reference.info.height));
  const referenceBinaryAlpha = binaryAlpha(reference.data);
  let previousBestOverlap = 0;

  for (const scale of uniformScaleCandidates(
    referenceContainTransform.targetWidth,
    referenceContainTransform.targetHeight,
    maximumScale,
  )) {
    const centeredTransform = applyReferenceAffine(referenceContainTransform, {
      scaleX: scale,
      scaleY: scale,
      translateX: 0,
      translateY: 0,
    });
    const centeredSupport = await applyTransform(
      referenceBinaryAlpha,
      reference.info.width,
      centeredTransform,
      sharp.kernel.nearest,
    );
    const referenceRows = supportBitRows(centeredSupport);
    const candidates = [];
    let bestOverlap = 0;
    const minimumTranslateX = -centeredTransform.targetLeft;
    const maximumTranslateX = canvasSize - centeredTransform.targetLeft - centeredTransform.targetWidth;
    const minimumTranslateY = -centeredTransform.targetTop;
    const maximumTranslateY = canvasSize - centeredTransform.targetTop - centeredTransform.targetHeight;

    for (let translateX = minimumTranslateX; translateX <= maximumTranslateX; translateX += 1) {
      for (let translateY = minimumTranslateY; translateY <= maximumTranslateY; translateY += 1) {
        const rawOverlap = translatedOverlap(authorityRows, referenceRows, translateX, translateY) / authoritativePixels;
        bestOverlap = Math.max(bestOverlap, rawOverlap);
        if (rawOverlap >= minimumOverlap) candidates.push({ translateX, translateY, rawOverlap });
      }
    }
    if (candidates.length === 0) {
      previousBestOverlap = Math.max(previousBestOverlap, bestOverlap);
      continue;
    }
    candidates.sort((left, right) => (
      Math.abs(left.translateX) + Math.abs(left.translateY)
      - Math.abs(right.translateX) - Math.abs(right.translateY)
      || right.rawOverlap - left.rawOverlap
      || left.translateX - right.translateX
      || left.translateY - right.translateY
    ));
    const selected = candidates[0];
    return {
      affine: {
        scaleX: scale,
        scaleY: scale,
        translateX: selected.translateX,
        translateY: selected.translateY,
      },
      targetSize: [centeredTransform.targetWidth, centeredTransform.targetHeight],
      rawOverlap: selected.rawOverlap,
      previousBestOverlap,
    };
  }
  throw new Error(`${name} has no passing uniform affine at or below scale ${maximumScale}`);
}

async function renderBase(sourceDir, name, referenceAffine) {
  const authority = await rawRgba(join(sourceDir, 'tools', `${name}.png`));
  const authorityBounds = alphaBounds(authority.data, authority.info.width, authority.info.height);
  const authorityTransform = containedTransform(authorityBounds);
  const registeredAuthority = await applyTransform(authority.data, authority.info.width, authorityTransform);
  const registeredAuthoritySupport = await applyTransform(
    binaryAlpha(authority.data),
    authority.info.width,
    authorityTransform,
    sharp.kernel.nearest,
  );

  const reference = await rawRgba(join(sourceDir, 'color-references', `${name}.png`));
  removeBorderConnectedChroma(reference.data, reference.info.width, reference.info.height);
  const referenceBounds = alphaBounds(reference.data, reference.info.width, reference.info.height);
  const referenceContainTransform = containedTransform(referenceBounds);
  const referenceTransform = applyReferenceAffine(referenceContainTransform, referenceAffine);
  const registeredReference = await applyTransform(reference.data, reference.info.width, referenceTransform);
  const registeredReferenceSupport = await applyTransform(
    binaryAlpha(reference.data),
    reference.info.width,
    referenceTransform,
    sharp.kernel.nearest,
  );

  let overlap = 0;
  let authoritativePixels = 0;
  let referencePixels = 0;
  for (let offset = 3; offset < registeredAuthoritySupport.length; offset += 4) {
    if (registeredReferenceSupport[offset] > 0) referencePixels += 1;
    if (registeredAuthoritySupport[offset] > 0) {
      authoritativePixels += 1;
      if (registeredReferenceSupport[offset] > 0) overlap += 1;
    }
  }
  const overlapRatio = overlap / authoritativePixels;
  if (overlapRatio < 0.98) {
    const authorityCentroid = alphaCentroid(registeredAuthoritySupport);
    const referenceCentroid = alphaCentroid(registeredReferenceSupport);
    throw new Error(`${name} color-reference alpha overlap is below 98% (${(overlapRatio * 100).toFixed(2)}%); reference area ${(referencePixels / authoritativePixels * 100).toFixed(2)}%, centroid delta x=${(authorityCentroid.x - referenceCentroid.x).toFixed(2)}, y=${(authorityCentroid.y - referenceCentroid.y).toFixed(2)}`);
  }

  const rgba = Buffer.alloc(canvasSize * canvasSize * 4);
  for (let offset = 0; offset < rgba.length; offset += 4) {
    const alpha = registeredAuthority[offset + 3];
    rgba[offset + 3] = alpha;
    if (alpha === 0) continue;
    if (registeredReferenceSupport[offset + 3] === 0) {
      rgba[offset] = registeredAuthority[offset];
      rgba[offset + 1] = registeredAuthority[offset + 1];
      rgba[offset + 2] = registeredAuthority[offset + 2];
    } else {
      rgba[offset] = registeredReference[offset];
      rgba[offset + 1] = registeredReference[offset + 1];
      rgba[offset + 2] = registeredReference[offset + 2];
    }
  }
  return {
    png: await sharp(rgba, { raw: { width: canvasSize, height: canvasSize, channels: 4 } }).png().toBuffer(),
    rgba,
    authorityTransform,
    rawOverlap: overlapRatio,
  };
}

async function renderMask(sourceDir, name, base) {
  const mask = await rawRgba(join(sourceDir, 'masks', `${name}-point.png`));
  let sourceAlphaPixels = 0;
  for (let offset = 3; offset < mask.data.length; offset += 4) {
    if (mask.data[offset] > 0) sourceAlphaPixels += 1;
  }
  if (sourceAlphaPixels === 0) throw new Error(`${name} point mask is blank`);
  if (mask.info.width !== canvasSize || mask.info.height !== canvasSize) {
    throw new Error(`${name} point mask must use the registered ${canvasSize}x${canvasSize} canvas`);
  }
  // Handoff masks use the legacy 224px safe-box coordinate system. Map that
  // registered box through the authority's aspect-preserving target affine so
  // the variable-color region follows the same geometry as the base artwork.
  const fitted = await applyTransform(mask.data, mask.info.width, {
    sourceLeft: (canvasSize - safeBox) / 2,
    sourceTop: (canvasSize - safeBox) / 2,
    sourceWidth: safeBox,
    sourceHeight: safeBox,
    targetLeft: base.authorityTransform.targetLeft,
    targetTop: base.authorityTransform.targetTop,
    targetWidth: base.authorityTransform.targetWidth,
    targetHeight: base.authorityTransform.targetHeight,
  });
  const rgba = Buffer.alloc(canvasSize * canvasSize * 4);
  let outputAlphaPixels = 0;
  for (let y = 0; y < canvasSize; y += 1) {
    for (let x = 0; x < canvasSize; x += 1) {
      const sourceOffset = (y * canvasSize + x) * 4;
      const destinationOffset = sourceOffset;
      rgba[destinationOffset] = 255;
      rgba[destinationOffset + 1] = 255;
      rgba[destinationOffset + 2] = 255;
      rgba[destinationOffset + 3] = Math.min(fitted[sourceOffset + 3], base.rgba[destinationOffset + 3]);
      if (rgba[destinationOffset + 3] > 0) outputAlphaPixels += 1;
    }
  }
  if (outputAlphaPixels === 0) throw new Error(`${name} point mask is blank after registration`);
  return sharp(rgba, { raw: { width: canvasSize, height: canvasSize, channels: 4 } }).png().toBuffer();
}

async function sourceCopy(sourceDir, group, name) {
  return readFile(join(sourceDir, group, `${name}.png`));
}

async function buildOutputs(sourceDir) {
  const referenceAffines = await loadReferenceAffines();
  const outputs = new Map();
  const bases = new Map();
  const registrations = new Map();
  for (const name of toolNames) {
    const base = await renderBase(sourceDir, name, referenceAffines[name]);
    bases.set(name, base);
    registrations.set(name, { ...referenceAffines[name], rawOverlap: base.rawOverlap });
    outputs.set(`tools/${name}_base.png`, base.png);
  }
  for (const name of maskedTools) outputs.set(`tools/masks/${name}_point.png`, await renderMask(sourceDir, name, bases.get(name)));
  for (const name of swatchNames) outputs.set(`swatches/${name}.png`, await sourceCopy(sourceDir, 'swatches', name));
  for (const name of frameNames) outputs.set(`frame/${name}.png`, await sourceCopy(sourceDir, 'frame', name));
  return { outputs, registrations };
}

async function outputDirectoryFiles(directory, prefix = '') {
  try {
    const entries = await readdir(directory, { withFileTypes: true });
    const results = [];
    for (const entry of entries) {
      const relative = posix.join(prefix, entry.name);
      if (entry.isDirectory()) results.push(...await outputDirectoryFiles(join(directory, entry.name), relative));
      else results.push(relative);
    }
    return results.sort();
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
}

function manifest(registrations) {
  const affineRows = toolNames.map((name) => {
    const registration = registrations.get(name);
    return `| ${name} | ${registration.scaleX.toFixed(4)} | ${registration.scaleY.toFixed(4)} | ${registration.translateX.toFixed(2)} | ${registration.translateY.toFixed(2)} | ${(registration.rawOverlap * 100).toFixed(2)}% |`;
  }).join('\n');
  return `# Canvas asset manifest\n\nAll assets are for internal Dodam project usage. The grayscale source icons are the geometry authority; robust bounds ignore isolated alpha noise below 16/255. Each authority silhouette is aspect-preservingly contained and centered in the 224px safe box. Border-connected chroma is removed from each fixed color reference, the reference is aspect-preservingly contained, and then the reviewed reference-only affine below is applied around the contain center. Raw registered reference alpha must cover at least 98% of authority alpha before authority alpha is imposed. Gate masks are binarized at alpha>=16 before registration and transformed with nearest-neighbor sampling; Lanczos resampling is used only for visual RGBA and cannot add gate support. No dilation, blur, or support expansion participates in this gate.\n\nTransform order: alpha>=16 binary masks -> authority bbox contain -> reference bbox contain -> reference-only scaleX/scaleY -> reference-only translateX/translateY -> nearest-neighbor raw binary alpha intersection gate -> authority alpha output. Translation values are output-canvas pixels. The palette metadata is contract-tested as the first passing four-decimal uniform-scale breakpoint after exhaustively checking every valid integer translation at each smaller breakpoint.\n\n| Tool | scaleX | scaleY | translateX | translateY | Registered raw overlap |\n| --- | ---: | ---: | ---: | ---: | ---: |\n${affineRows}\n\nThe verified handoff point masks use the registered 224px safe-box coordinate system. They follow the authority's explicit contain affine, then are clipped to the authoritative output alpha.\n\n| Runtime asset | Source | Dimensions | Mask role | Usage |\n| --- | --- | --- | --- | --- |\n${toolNames.map((name) => `| tools/${name}_base.png | tools/${name}.png + color-references/${name}.png | 256x256 | ${maskedTools.includes(name) ? `tools/masks/${name}_point.png` : 'none'} | Canvas toolbar |`).join('\n')}\n${maskedTools.map((name) => `| tools/masks/${name}_point.png | masks/${name}-point.png | 256x256 | Registered variable-region alpha, clipped to artwork | Canvas tool color region |`).join('\n')}\n${swatchNames.map((name) => `| swatches/${name}.png | swatches/${name}.png | 48x48 | none | Canvas color picker |`).join('\n')}\n${frameNames.map((name) => `| frame/${name}.png | frame/${name}.png | source dimensions | none | Canvas chrome |`).join('\n')}\n\nThe removed yellow outer-frame patch is intentionally absent.\n`;
}

export async function materialize({ sourceDir = join(moduleDirectory, 'source'), outputDir = join(moduleDirectory, '../../frontend/mobile/assets/canvas'), check = false } = {}) {
  const { outputs, registrations } = await buildOutputs(sourceDir);
  const expected = [...outputFiles].sort();
  if (!expected.every((file) => outputs.has(file)) || outputs.size !== expected.length) throw new Error('Generated output does not match the approved allowlist');
  const manifestPath = join(outputDir, 'ASSET_MANIFEST.md');
  const manifestContents = manifest(registrations);
  const expectedRuntimeFiles = [...expected, 'ASSET_MANIFEST.md'].sort();
  const actual = await outputDirectoryFiles(outputDir);
  if (actual.length > 0 && (actual.length !== expectedRuntimeFiles.length || actual.some((file, index) => file !== expectedRuntimeFiles[index]))) {
    const unexpected = actual.filter((file) => !expectedRuntimeFiles.includes(file));
    throw new Error(`Unexpected runtime output: ${unexpected.length ? unexpected.join(', ') : 'runtime output is incomplete'}`);
  }
  const writtenFiles = [];
  const verifiedFiles = [];
  for (const relative of outputFiles) {
    const rendered = outputs.get(relative);
    if (check) {
      let existing;
      try { existing = await readFile(join(outputDir, relative)); } catch { throw new Error(`Missing generated output: ${relative}`); }
      if (!existing.equals(rendered)) throw new Error(`Generated output differs: ${relative}`);
      verifiedFiles.push(relative);
    } else {
      await mkdir(dirname(join(outputDir, relative)), { recursive: true });
      await writeFile(join(outputDir, relative), rendered);
      writtenFiles.push(relative);
    }
  }
  if (check) {
    let existingManifest;
    try { existingManifest = await readFile(manifestPath, 'utf8'); } catch { throw new Error('Missing generated asset manifest'); }
    if (existingManifest !== manifestContents) throw new Error('Generated asset manifest differs');
  } else {
    await writeFile(manifestPath, manifestContents);
  }
  return { writtenFiles, verifiedFiles };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const check = process.argv.includes('--check');
  await materialize({ check });
}
