import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { access, cp } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(testDirectory, "../..");
const standaloneRoot = path.join(webRoot, ".next", "standalone");
const port = process.env.IMAGE_SMOKE_PORT ?? "3317";
const baseUrl = `http://127.0.0.1:${port}`;

await access(path.join(standaloneRoot, "server.js"));
await cp(path.join(webRoot, ".next", "static"), path.join(standaloneRoot, ".next", "static"), {
  recursive: true,
  force: true,
});
await cp(path.join(webRoot, "public"), path.join(standaloneRoot, "public"), {
  recursive: true,
  force: true,
});

const server = spawn(process.execPath, ["server.js"], {
  cwd: standaloneRoot,
  env: {
    ...process.env,
    HOSTNAME: "127.0.0.1",
    PORT: port,
  },
  stdio: ["ignore", "pipe", "pipe"],
  windowsHide: true,
});

let output = "";
server.stdout.on("data", (chunk) => {
  output += chunk;
});
server.stderr.on("data", (chunk) => {
  output += chunk;
});

try {
  await waitUntilReady();

  const startedAt = performance.now();
  const response = await fetch(
    `${baseUrl}/_next/image?url=%2Fassets%2Flanding%2Fcharacters%2Fval_talk.png&w=640&q=75`,
    {
      headers: {
        Accept: "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
      },
      signal: AbortSignal.timeout(15_000),
    },
  );
  const body = await response.arrayBuffer();
  const elapsedMs = performance.now() - startedAt;

  assert.equal(response.status, 200, output);
  assert.match(response.headers.get("content-type") ?? "", /^image\/(webp|avif)$/);
  assert.ok(body.byteLength > 0);
  assert.ok(elapsedMs < 15_000, `image optimization took ${elapsedMs}ms`);

  console.log(
    `image optimizer smoke: status=${response.status} type=${response.headers.get("content-type")} size=${body.byteLength} time=${Math.round(elapsedMs)}ms`,
  );
} finally {
  server.kill();
}

async function waitUntilReady() {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (server.exitCode !== null) {
      throw new Error(`standalone server exited early (${server.exitCode})\n${output}`);
    }
    try {
      const response = await fetch(baseUrl, { signal: AbortSignal.timeout(1_000) });
      if (response.ok) {
        return;
      }
    } catch {
      // 서버가 listen하기 전 연결 실패는 정상적인 준비 과정이다.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`standalone server did not become ready\n${output}`);
}
