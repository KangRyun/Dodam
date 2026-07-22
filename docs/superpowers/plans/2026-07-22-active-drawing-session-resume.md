# Active Drawing Session Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아동의 진행 중 그림 활동과 최신 자동 저장 초안을 한 번에 조회하여 클라이언트가 기존 활동을 재개할 수 있게 한다.

**Architecture:** 기존 `DrawingSessionController`에 조회 API를 추가하되, 생성 트랜잭션과 잠금 정책은 변경하지 않고 `DrawingSessionQueryService`로 읽기 책임을 분리한다. 진행 중 세션은 목록으로 조회해 데이터 무결성 이상을 명시적으로 감지하며, 최신 초안은 기존 `DrawingAssetRepository.findLatestDraft` 기준을 그대로 사용한다.

**Tech Stack:** Java 21, Spring Boot, Spring Data JPA, Bean Validation, springdoc-openapi, JUnit 5, Mockito, MockMvc, Gradle

## Global Constraints

- API는 `GET /api/v1/drawing-sessions/active?childId={childId}`로 제공한다.
- 진행 중 세션은 `session_status = IN_PROGRESS`이고 `deleted_at IS NULL`인 행만 조회한다.
- 세션이 없으면 `ACTIVE_DRAWING_SESSION_NOT_FOUND`, 둘 이상이면 `MULTIPLE_ACTIVE_DRAWING_SESSIONS` 오류를 반환한다.
- 최신 초안이 없으면 성공 응답의 `latestDraft`를 `null`로 반환한다.
- 최신 초안은 `DRAFT` 유형 중 `assetVersion DESC` 첫 행이라는 기존 279번 계약을 재사용한다.
- 저장 키, 로컬 절대 경로, 이미지 바이트/Base64를 응답하지 않으며 `previewUrl`은 현재 `null`이다.
- 조회는 세션 상태를 변경하거나 파일 저장소 및 AI 시스템에 접근하지 않는다.
- 인증 기능이 아직 없으므로 임의 인증·소유권 검증을 추가하지 않는다.
- 공개 Java 클래스와 메서드에는 실제 책임을 설명하는 한국어 Javadoc을 작성한다.
- 커밋과 병합은 사용자가 별도로 요청할 때만 수행하고, 커밋 메시지에 `S15P11B209-280`을 포함한다.

---

### Task 1: 진행 중 세션 조회와 오류 계약

**Files:**
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/repository/DrawingSessionRepositoryTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingSessionRepository.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/exception/DrawingErrorCodeTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/exception/DrawingErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/LatestDrawingDraftResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/ActiveDrawingSessionResponse.java`

**Interfaces:**
- Consumes: `DrawingSessionStatus.IN_PROGRESS`, `DrawingAssetRepository.findLatestDraft(Long)`.
- Produces: `List<DrawingSession> findActiveSessionsByChildId(Long childId)`, `DrawingErrorCode.ACTIVE_DRAWING_SESSION_NOT_FOUND`, `DrawingErrorCode.MULTIPLE_ACTIVE_DRAWING_SESSIONS`, 두 조회 응답 record.

- [ ] **Step 1: 저장소와 오류 코드의 실패 테스트를 작성한다.**

  `DrawingSessionRepositoryTest`에 다른 아동, 완료 상태, soft delete 행을 제외하고 같은 아동의 활성 행을 모두 반환하는 테스트를 추가한다. `DrawingErrorCodeTest`에는 `DRAWING_404_005`/404와 `DRAWING_500_003`/500의 정확한 계약을 추가한다.

- [ ] **Step 2: 대상 테스트가 컴파일 또는 단언 실패하는지 확인한다.**

  Run: `gradlew.bat test --tests "com.ssafy.b209.drawing.repository.DrawingSessionRepositoryTest" --tests "com.ssafy.b209.drawing.exception.DrawingErrorCodeTest"`

  Expected: 새 저장소 메서드 또는 enum 상수가 없어 FAIL.

- [ ] **Step 3: 저장소 조회와 오류·응답 타입을 최소 구현한다.**

  `findActiveSessionsByChildId`는 `child`와 `drawingType`을 fetch join하고 `IN_PROGRESS`, `deletedAt IS NULL`을 적용해 ID 오름차순 목록을 반환한다. 응답 record는 세션 요약과 최신 초안 메타데이터만 노출하고 저장 위치는 포함하지 않는다.

- [ ] **Step 4: 대상 테스트를 다시 실행해 통과를 확인한다.**

  Run: `gradlew.bat test --tests "com.ssafy.b209.drawing.repository.DrawingSessionRepositoryTest" --tests "com.ssafy.b209.drawing.exception.DrawingErrorCodeTest"`

  Expected: PASS.

### Task 2: 조회 전용 서비스

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingSessionQueryServiceTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingSessionQueryService.java`

**Interfaces:**
- Consumes: `DrawingSessionRepository.findActiveSessionsByChildId(Long)`, `DrawingAssetRepository.findLatestDraft(Long)`.
- Produces: `ActiveDrawingSessionResponse getActiveDrawingSession(Long childId)`.

- [ ] **Step 1: 정상·초안 없음·세션 없음·중복 세션 서비스 테스트를 먼저 작성한다.**

  정상 테스트는 세션/그림 유형/최신 DRAFT 메타데이터가 응답으로 정확히 매핑되는지 검증한다. 초안 없음은 `latestDraft == null`, 세션 없음은 404 오류 코드, 중복 세션은 500 오류 코드를 검증한다.

- [ ] **Step 2: 서비스 클래스 부재로 실패하는지 확인한다.**

  Run: `gradlew.bat test --tests "com.ssafy.b209.drawing.service.DrawingSessionQueryServiceTest"`

  Expected: `DrawingSessionQueryService`가 없어 FAIL.

- [ ] **Step 3: 읽기 전용 조회 서비스를 최소 구현한다.**

  클래스에 `@Transactional(readOnly = true)`를 적용한다. 활성 행 개수를 먼저 검사한 뒤 하나일 때만 최신 초안을 조회하고, `capturedAt`과 `createdAt`은 프로젝트의 기존 UTC `Instant` 변환 규칙을 사용한다. `previewUrl`은 URL 제공 계층이 없으므로 `null`로 둔다.

- [ ] **Step 4: 서비스 테스트를 다시 실행해 통과를 확인한다.**

  Run: `gradlew.bat test --tests "com.ssafy.b209.drawing.service.DrawingSessionQueryServiceTest"`

  Expected: PASS.

### Task 3: HTTP API, OpenAPI, 사용 문서

**Files:**
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingSessionControllerTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingSessionOpenApiTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingSessionController.java`
- Modify: `README.md`

**Interfaces:**
- Consumes: `DrawingSessionQueryService.getActiveDrawingSession(Long)`.
- Produces: `GET /api/v1/drawing-sessions/active?childId={positive long}`와 200/400/404/500 OpenAPI 계약.

- [ ] **Step 1: MockMvc와 OpenAPI 실패 테스트를 작성한다.**

  MockMvc 테스트는 정상 응답의 세션·최신 초안 필드, 초안 없는 `null`, 누락/0 이하 `childId`의 400을 검증한다. OpenAPI 테스트는 `childId`가 required query parameter이고 응답 코드가 정확히 200/400/404/500인지 검증한다.

- [ ] **Step 2: 라우트 부재로 실패하는지 확인한다.**

  Run: `gradlew.bat test --tests "com.ssafy.b209.drawing.controller.DrawingSessionControllerTest" --tests "com.ssafy.b209.drawing.controller.DrawingSessionOpenApiTest"`

  Expected: `/active` 라우트 또는 OpenAPI 계약이 없어 FAIL.

- [ ] **Step 3: 컨트롤러와 문서를 최소 구현한다.**

  기존 컨트롤러에 `@Validated`를 추가하고 `@RequestParam @Positive Long childId`를 받는 GET 메서드를 추가한다. 응답은 기존 `ApiResponse.success` 형식을 사용한다. README에는 요청 예시, 재개 판단 기준, `latestDraft: null`, 오류 정책과 저장 위치 미노출을 기록한다.

- [ ] **Step 4: 컨트롤러와 OpenAPI 테스트를 다시 실행해 통과를 확인한다.**

  Run: `gradlew.bat test --tests "com.ssafy.b209.drawing.controller.DrawingSessionControllerTest" --tests "com.ssafy.b209.drawing.controller.DrawingSessionOpenApiTest"`

  Expected: PASS.

### Task 4: 회귀 및 문서 생성 검증

**Files:**
- Verify: `backend/build/reports/tests/test/index.html`
- Verify: `backend/build/docs/javadoc/index.html`

**Interfaces:**
- Consumes: Tasks 1-3의 전체 구현.
- Produces: 테스트, 포맷, Javadoc 검증 증거.

- [ ] **Step 1: 전체 테스트를 깨끗한 빌드에서 실행한다.**

  Run: `gradlew.bat clean test`

  Expected: BUILD SUCCESSFUL.

- [ ] **Step 2: Spotless 검사를 실행한다.**

  Run: `gradlew.bat spotlessCheck`

  Expected: BUILD SUCCESSFUL. 실패하면 `gradlew.bat spotlessApply` 후 변경 내용을 검토하고 다시 검사한다.

- [ ] **Step 3: Javadoc을 생성한다.**

  Run: `gradlew.bat javadoc`

  Expected: BUILD SUCCESSFUL이며 `backend/build/docs/javadoc/index.html`이 존재한다. 새 코드의 잘못된 태그나 깨진 한글이 없어야 한다.

- [ ] **Step 4: 변경 범위와 Git 상태를 검토한다.**

  Run: `git diff --check` 및 `git status --short`

  Expected: whitespace 오류가 없고 이슈 280 구현·테스트·문서와 승인된 설계/계획 파일만 변경되어 있다. 커밋은 사용자 요청 전까지 생성하지 않는다.
