# Public API Contract Freeze Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 최신 `develop`의 Spring Boot와 Flutter 구현을 대조해 외부 공개 API 계약 목록과 불일치를 동결한다.

**Architecture:** Spring Boot Controller와 Springdoc OpenAPI를 구현된 API의 정본으로 삼고, Flutter Remote Repository를 소비자 상태로 대조한다. 새로운 런타임 기능을 만들지 않고 `docs/api/public-api-contract-v1.md`에 구현·불일치·미구현 상태를 분리해 기록한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Springdoc OpenAPI 2.8.17, Flutter, Markdown

## Global Constraints

- 기준 브랜치는 최신 `origin/develop`이다.
- 외부 API Base URL은 `/api/v1`이며 `/internal/v1` 계약은 제외한다.
- Backend에 구현된 API는 Controller와 OpenAPI를 우선한다.
- 공통 Envelope 변경, 신규 Endpoint 구현, Flutter 경로 수정은 수행하지 않는다.
- 기존 API 전체 명세서와 적용된 Flyway Migration을 수정하지 않는다.

---

### Task 1: 공개 API 계약 동결 문서 작성

**Files:**
- Create: `docs/api/public-api-contract-v1.md`

**Interfaces:**
- Consumes: Spring Boot Controller Mapping, 요청 DTO, Flutter Remote Repository 경로
- Produces: Backend와 Flutter가 함께 참조할 공개 API 계약 목록과 차이표

- [x] **Step 1: Backend 공개 API 목록을 수집한다**

  `backend/src/main/java/com/ssafy/b209/**/controller`에서
  `@RequestMapping`과 HTTP Method Mapping을 수집한다. `/internal/v1`은 제외하고
  Method, `/api/v1` URI, 인증 여부, 필수 Header, 요청 Content-Type을 기록한다.

- [x] **Step 2: Flutter 소비 경로를 대조한다**

  `frontend/mobile/lib/features/**/data/repositories/remote_*_repository.dart`의
  `ApiClient` 호출을 확인해 Backend와 일치하면 `연동`, 경로나 응답 파싱이
  다르면 `불일치`, 호출 코드가 없으면 `미연동`으로 기록한다.

- [x] **Step 3: 계약 동결 문서를 작성한다**

  문서 첫 부분에 정본 우선순위, 공통 인증·Header·Envelope, 상태 정의를
  작성한다. 도메인별 표에는 `Method`, `URI`, `Backend`, `Flutter`, `비고`를
  포함하고 미구현 API를 구현된 항목과 분리한다.

- [x] **Step 4: 충돌과 후속 범위를 명시한다**

  `activities`와 `drawing-sessions`, `upload`와 `snapshots`, 리포트 공개 API,
  공통 Envelope 차이를 기록한다. 공통 Envelope는 S15P11B209-526, 나머지는
  각 도메인 Jira에서 처리하도록 명시한다.

- [x] **Step 5: 문서 변경을 검사한다**

  Run:

  ```powershell
  git diff --check
  rg -n "TBD|TODO|구현 예정" docs/api/public-api-contract-v1.md
  ```

  Expected: 공백 오류가 없고 미확정 Placeholder가 검색되지 않는다.

### Task 2: 계약 목록 정합성과 프로젝트 회귀 검증

**Files:**
- Verify: `docs/api/public-api-contract-v1.md`
- Verify: `backend/src/main/java/com/ssafy/b209/**/controller/*.java`
- Verify: `frontend/mobile/lib/features/**/data/repositories/remote_*_repository.dart`

**Interfaces:**
- Consumes: Task 1의 동결 문서
- Produces: 중복·누락·회귀가 없는 검증 결과

- [x] **Step 1: Method와 URI 중복을 검사한다**

  계약 표의 각 `Method + URI` 조합이 한 번만 등장하고 외부 URI가
  `/api/v1`로 시작하는지 확인한다. `/internal/v1` 항목이 있으면 제거한다.

- [x] **Step 2: Backend 구현 상태를 Controller와 재대조한다**

  `구현`으로 표시한 각 항목이 실제 Controller Mapping에 존재하는지
  `rg`로 확인한다. Controller가 없는 리포트 조회 등은 `미구현` 상태로
  유지한다.

- [x] **Step 3: Flutter 상태를 Remote Repository와 재대조한다**

  `연동`으로 표시한 경로가 실제 `ApiClient` 호출과 일치하는지 확인하고,
  `activities`, `upload`, 리포트 조회의 차이가 `불일치` 또는 `미구현`으로
  남아 있는지 확인한다.

- [x] **Step 4: Backend 검증을 실행한다**

  Run:

  ```powershell
  cd backend
  .\gradlew.bat clean test
  .\gradlew.bat spotlessCheck
  .\gradlew.bat javadoc
  ```

  Expected: 세 명령이 모두 `BUILD SUCCESSFUL`로 종료된다.

- [x] **Step 5: Flutter 회귀 테스트를 실행한다**

  Run:

  ```powershell
  cd frontend/mobile
  flutter test
  ```

  Expected: 모든 Flutter 테스트가 통과한다.

- [x] **Step 6: 변경을 커밋한다**

  Run:

  ```powershell
  git add docs/api/public-api-contract-v1.md docs/superpowers/plans/2026-07-27-public-api-contract-freeze.md
  git commit -m "docs(contract): [S15P11B209-525] 공개 API 계약 목록 동결"
  ```

  Expected: S15P11B209-525의 문서 파일만 커밋된다.
