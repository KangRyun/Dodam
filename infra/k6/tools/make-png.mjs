#!/usr/bin/env node
// ============================================================================
// 합성 그림 PNG 생성 (S15P11B209-354)
//
// 왜 필요한가: 부하 테스트에 실제 아동 그림을 쓰는 것은 금지다(가드레일 9절).
//   그렇다고 단색 이미지를 쓰면 압축돼 1KB 도 안 되어서 실제 업로드 대역폭을
//   재현하지 못한다. 그래서 **압축되지 않는 난수 픽셀**로 목표 크기를 맞춘다.
//
// 왜 고정 시드인가: 362(전환 후 재측정)가 "동일 스크립트·동일 조건"을 요구한다.
//   매번 다른 크기의 파일을 올리면 전/후 비교가 성립하지 않는다.
//   같은 시드 → 매 실행 바이트 단위로 동일한 파일.
//
// 사용: node tools/make-png.mjs [--bytes 102400] [--out ../assets/synthetic-drawing.png]
// ============================================================================
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));

// CRC32 표. const 는 호이스팅되지 않으므로(TDZ) 이 파일의 최상위 실행 코드보다
// 반드시 위에 있어야 한다 — 아래로 내리면 chunk() 호출 시점에 초기화 전 접근이 된다.
const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();
const args = parseArgs(process.argv.slice(2));

const targetBytes = Number(args['bytes'] || 100 * 1024);
const outPath = resolve(HERE, args['out'] || '../assets/synthetic-drawing.png');
const WIDTH = 180;
const SEED = 20260728; // 고정 — 재현성의 근거

const bytesPerRow = 1 + WIDTH * 3; // 필터 바이트 1 + RGB
const height = Math.max(1, Math.floor(targetBytes / bytesPerRow));

const random = mulberry32(SEED);
const raw = Buffer.alloc(height * bytesPerRow);
for (let y = 0; y < height; y += 1) {
  const rowStart = y * bytesPerRow;
  raw[rowStart] = 0; // 필터 타입 None — 디코더가 그대로 읽는다
  for (let x = 1; x < bytesPerRow; x += 1) {
    raw[rowStart + x] = Math.floor(random() * 256);
  }
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(WIDTH, 0);
ihdr.writeUInt32BE(height, 4);
ihdr[8] = 8; // bit depth
ihdr[9] = 2; // color type: truecolor(RGB)
ihdr[10] = 0; // compression: deflate
ihdr[11] = 0; // filter
ihdr[12] = 0; // interlace: none

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', deflateSync(raw)),
  chunk('IEND', Buffer.alloc(0)),
]);

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, png);
process.stdout.write(`생성: ${outPath}\n크기: ${png.length} bytes (${WIDTH}x${height} RGB, seed=${SEED})\n`);

// ── PNG 저수준 ──────────────────────────────────────────────────────────────
function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const typeBuffer = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 0);
  return Buffer.concat([length, typeBuffer, data, crc]);
}

function crc32(buffer) {
  let c = 0xffffffff;
  for (let i = 0; i < buffer.length; i += 1) c = CRC_TABLE[(c ^ buffer[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** 시드 고정 PRNG — Math.random 은 재현이 안 돼서 쓸 수 없다. */
function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function parseArgs(argv) {
  const parsed = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (!argv[i].startsWith('--')) continue;
    const next = argv[i + 1];
    parsed[argv[i].slice(2)] = next && !next.startsWith('--') ? (i += 1, next) : 'true';
  }
  return parsed;
}
