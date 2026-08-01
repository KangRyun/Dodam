# syntax=docker/dockerfile:1
# 도담 커뮤니티 웹(Next.js 16 + React 19, pnpm) 런타임 이미지. — S15P11B209-383
#
# 백엔드 Dockerfile 과 원리는 같지만 한 가지가 결정적으로 다르다.
#
# ⚠️ NEXT_PUBLIC_* 는 **빌드 시점에 번들에 구워진다.** 런타임 env 로는 못 바꾼다.
#    그래서 API 주소를 build-arg 로 받는다. 값이 바뀌면 재기동이 아니라 **재빌드**다.
#    (backend 는 env 만 갈고 재기동하면 되지만 여기는 안 된다 — 같은 감각으로 다루면 틀린다.)
#
# 기본값을 상대경로 /api/v1 로 둔 것도 의도다. 웹과 API 가 같은 오리진(gateway)에서
# 서비스되므로 절대 URL 을 구울 이유가 없다. 절대 URL 을 구우면 도메인이 바뀔 때마다
# 이미지를 다시 만들어야 하고, 스테이징 이미지를 운영에 못 쓴다.

# ── deps: 의존성만 먼저 (소스가 바뀌어도 이 레이어는 캐시된다) ──────────────
FROM node:24-alpine AS deps
WORKDIR /app
RUN corepack enable
# packageManager 필드(pnpm@11.9.0)를 corepack 이 읽어 정확한 버전을 쓴다.
# pnpm-workspace.yaml 도 함께 넣어야 한다 — 이 저장소는 packages:["."] 로 워크스페이스
# 루트를 선언하고 있어서, 빠지면 pnpm 이 다른 해석을 한다.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

# ── build: next build → .next/standalone ────────────────────────────────────
FROM node:24-alpine AS build
WORKDIR /app
RUN corepack enable
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG NEXT_PUBLIC_API_BASE_URL=/api/v1
ENV NEXT_PUBLIC_API_BASE_URL=$NEXT_PUBLIC_API_BASE_URL
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

# ── runner: 산출물만. 빌드 도구도 소스도 남기지 않는다 ──────────────────────
FROM node:24-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# 루트가 아닌 전용 유저로 실행 — 권한 최소화(가드레일 9절, backend 와 동일 원칙).
RUN addgroup -g 1001 -S nodejs && adduser -S -u 1001 -G nodejs nextjs

# standalone 번들은 server.js 와 최소 node_modules 를 함께 낸다.
COPY --from=build --chown=nextjs:nodejs /app/.next/standalone ./
# 정적 자산은 standalone 에 포함되지 않아 따로 넣어야 한다.
#   빠뜨리면 페이지는 뜨는데 CSS·JS 가 전부 404 나서 "화면이 깨진 채로 200" 이 된다.
COPY --from=build --chown=nextjs:nodejs /app/.next/static ./.next/static
# ※ public/ 은 이 프로젝트에 없다. 생기면 여기에 COPY 를 한 줄 추가할 것.

USER nextjs

# 호스트 3000 은 Grafana 가 점유하고 있다. 이 컨테이너는 내부 포트만 쓰고
# 호스트 바인딩 없이 gateway 를 통해서만 노출된다(다른 서비스와 동일 패턴).
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

CMD ["node", "server.js"]
