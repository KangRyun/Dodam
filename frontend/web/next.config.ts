import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // 서버 실행에 필요한 파일만 추린 self-contained 번들을 .next/standalone 에 낸다.
  // 이게 없으면 런타임 이미지가 node_modules 를 통째로 안고 가야 한다(S15P11B209-383).
  output: "standalone",
};

export default nextConfig;
