# 도담 Web

커뮤니티와 관리자 화면을 위한 Next.js 웹 프로젝트입니다.

## 실행 환경

- Node.js 20.9 이상
- pnpm 11

## 로컬 실행

```bash
pnpm install
pnpm dev
```

브라우저에서 `http://localhost:3000`을 엽니다.

## 환경 변수

`.env.example`을 `.env.local`로 복사하고 백엔드 API 주소를 설정합니다.

```text
NEXT_PUBLIC_API_BASE_URL=http://localhost:8080/api/v1
```

## 검증

```bash
pnpm lint
pnpm build
pnpm test:e2e
```
