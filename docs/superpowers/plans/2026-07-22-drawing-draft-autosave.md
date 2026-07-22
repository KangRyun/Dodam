# Drawing Draft Autosave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 진행 중인 그림 세션의 현재 초안을 안전하게 저장하고 가장 최근 초안 Metadata를 조회하는 API를 구현한다.

**Architecture:** 확정 API 명세의 단수 Resource인 `PUT/GET /api/v1/drawing-sessions/{drawingSessionId}/draft`를 사용한다. 기존 `DrawingAsset`의 `DRAFT`, `assetVersion`, `lastEventSequence`, `capturedAt`과 `ImageStorage`를 재사용하며 세션 잠금 안에서 버전을 증가시키고 늦게 도착한 이벤트 순서를 거부한다. 이미지 다운로드 API가 없으므로 조회 응답에 임의 URL이나 내부 Storage Key를 노출하지 않는다.

**Tech Stack:** Java 21, Spring Boot 3.5, Spring Data JPA, MySQL 8, Flyway, JUnit 5, Mockito, MockMvc

## Global Constraints

- Branch 이름에는 Jira 코드를 포함하지 않고 Commit 제안에만 `S15P11B209-279`를 포함한다.
- 기존 `ImageStorage`, `ApiResponse`, `GlobalExceptionHandler`, `DrawingAsset`을 재사용한다.
- 인증 인프라가 없으므로 가짜 Principal이나 사용자 ID를 추가하지 않는다.
- 프론트엔드 Timer, 삭제 API, 활동 재개 종합 응답, 이미지 다운로드, AI 호출은 구현하지 않는다.
- Production public type과 공개 메서드에는 실제 동작과 일치하는 한국어 Javadoc을 작성한다.

---

### Task 1: 초안 Domain 및 Repository 계약

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingAsset.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingAssetRepository.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/repository/DrawingAssetRepositoryTest.java`

**Interfaces:**
- Produces: `DrawingAsset.draft(...)`, `findFirstByDrawingSessionIdAndAssetTypeOrderByAssetVersionDesc(...)`

- [ ] **Step 1: 최신 DRAFT 조회와 세션별 버전 분리를 검증하는 Repository 테스트를 작성한다.**
- [ ] **Step 2: `gradlew.bat test --tests "*DrawingAssetRepositoryTest"`가 새 조회 메서드 부재로 실패하는지 확인한다.**
- [ ] **Step 3: `DrawingAsset.draft` Factory와 `Optional<DrawingAsset>` 최신 조회 메서드를 최소 구현한다.**
- [ ] **Step 4: 같은 테스트를 다시 실행해 통과를 확인한다.**

### Task 2: 초안 저장 및 조회 Use Case

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/request/SaveDrawingDraftRequest.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingDraftResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingDraftService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/exception/DrawingErrorCode.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingDraftServiceTest.java`

**Interfaces:**
- Consumes: `ImageStorage.store`, `ImageStorage.delete`, 잠금 세션 조회, 최신 DRAFT 조회
- Produces: `save(Long, StoreImageCommand, SaveDrawingDraftRequest)`와 `getLatest(Long)`

- [ ] **Step 1: 첫 저장, 다음 이벤트 순서 저장, 같은·낮은 순서 거부, 상태 거부, 조회 404, 보상 삭제 테스트를 작성한다.**
- [ ] **Step 2: `gradlew.bat test --tests "*DrawingDraftServiceTest"`가 새 Service 부재로 실패하는지 확인한다.**
- [ ] **Step 3: 세션 잠금 → 상태 검증 → 최신 순서 검증 → 파일 저장 → Metadata 저장 순서로 최소 구현한다.**
- [ ] **Step 4: DB 저장 예외 시 새 파일을 삭제하고 `DataIntegrityViolationException`은 409로 변환한다.**
- [ ] **Step 5: Service 테스트를 다시 실행해 통과를 확인한다.**

### Task 3: HTTP 계약, Swagger 및 문서

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingDraftController.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingDraftControllerTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingDraftOpenApiTest.java`
- Modify: `README.md`

**Interfaces:**
- Produces: `PUT /api/v1/drawing-sessions/{drawingSessionId}/draft`, `GET /api/v1/drawing-sessions/{drawingSessionId}/draft`

- [ ] **Step 1: `preview`와 `canvasState` Multipart 성공·누락·Validation, GET 성공·404 응답 테스트를 작성한다.**
- [ ] **Step 2: Controller 테스트가 Endpoint 부재로 실패하는지 확인한다.**
- [ ] **Step 3: PUT은 `ApiResponse`와 200 OK, GET은 200 OK를 반환하는 Controller를 구현한다.**
- [ ] **Step 4: OpenAPI에 진행 상태 제한, 비최종 초안, AI·상태 변경 없음, 다운로드 API 아님을 문서화한다.**
- [ ] **Step 5: README에 Multipart 예시, 이벤트 순서 증가 규칙, 제한 사항을 추가한다.**
- [ ] **Step 6: Controller 및 OpenAPI 테스트를 다시 실행해 통과를 확인한다.**

### Task 4: 전체 검증

**Files:**
- Verify only

**Interfaces:**
- Consumes: 전체 Backend Build
- Produces: 검증 결과와 권장 Commit/MR 문안

- [ ] **Step 1: `backend\\gradlew.bat clean test`를 실행한다.**
- [ ] **Step 2: `backend\\gradlew.bat spotlessCheck`를 실행하고 형식 오류가 있으면 수정한다.**
- [ ] **Step 3: `backend\\gradlew.bat javadoc`을 실행하고 `backend/build/docs/javadoc/index.html`을 확인한다.**
- [ ] **Step 4: `git diff --check`, `git status --short`와 변경 범위를 검토한다.**
- [ ] **Step 5: 실제 Commit·Push는 하지 않고 `S15P11B209-279 feat(drawing): 진행 중 그림 자동 저장 및 최신 초안 조회 구현`을 제안한다.**
