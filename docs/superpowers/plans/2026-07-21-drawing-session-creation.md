# Drawing Session Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `POST /api/v1/drawing-sessions`에서 검증, 멱등성, 아동 단위 동시성 제어와 201 응답을 제공한다.

**Architecture:** 최소 JPA Entity로 기존 `children`, `drawing_types`, `drawing_sessions`를 매핑한다. Service는 `READ_COMMITTED` Transaction에서 기존 멱등 Key를 먼저 확인하고, 신규 요청은 Child Row 잠금 후 멱등 Key와 진행 세션을 현재 읽기로 재확인한다. V2 Flyway Migration은 세션 생성 멱등 Key와 진행 세션 조회 Index만 추가하며, Controller는 공통 응답과 Location Header만 조립한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, Bean Validation, Flyway, MySQL 8, H2, Testcontainers, Springdoc OpenAPI, JUnit 5, AssertJ, Mockito, MockMvc

## Global Constraints

- 브랜치는 `feat/drawing-session-create`이며 Jira 코드는 브랜치명에 넣지 않는다.
- 사용자가 별도로 요청하기 전까지 Commit, Push와 Merge Request를 생성하지 않는다.
- 기존 V1 Migration, 공통 응답, 전역 예외, Swagger/CORS와 Profile 구조를 변경하지 않는다.
- 운영 `drawing_types` Seed를 추가하지 않는다.
- Spring Security, JWT, 임의 사용자 Header와 가짜 Principal을 추가하지 않는다.
- 인증 연결 전 `startedByUserId`는 `null`이다.
- Entity, 아동 개인정보, Idempotency-Key, SQL과 내부 예외를 응답이나 로그에 노출하지 않는다.
- 모든 Production 동작은 실패하는 테스트를 먼저 확인한 뒤 최소 구현한다.
- 새 주요 Production Type의 Javadoc은 한국어로 실제 책임과 계약을 설명한다.
- 이미지, Stroke, AI, 대화, 감정, 완료와 리포트 기능을 구현하지 않는다.

---

## File Map

### Create

- `backend/src/main/resources/db/migration/V2__add_drawing_session_creation_constraints.sql`: 멱등 Key와 Index
- `backend/src/main/java/com/ssafy/b209/global/config/TimeConfig.java`: UTC `Clock` Bean
- `backend/src/main/java/com/ssafy/b209/child/domain/Child.java`: 아동 활동 가능 여부와 Tutorial 상태
- `backend/src/main/java/com/ssafy/b209/child/domain/ChildProfileStatus.java`
- `backend/src/main/java/com/ssafy/b209/child/domain/ChildTutorialStatus.java`
- `backend/src/main/java/com/ssafy/b209/child/repository/ChildRepository.java`
- `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingInputMethod.java`
- `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSessionStatus.java`
- `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingStage.java`
- `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingTypeSelectableBy.java`
- `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingType.java`
- `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSession.java`
- `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingTypeRepository.java`
- `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingSessionRepository.java`
- `backend/src/main/java/com/ssafy/b209/drawing/dto/request/CanvasConfigurationRequest.java`
- `backend/src/main/java/com/ssafy/b209/drawing/dto/request/CreateDrawingSessionRequest.java`
- `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingTypeSummaryResponse.java`
- `backend/src/main/java/com/ssafy/b209/drawing/dto/response/CreateDrawingSessionResponse.java`
- `backend/src/main/java/com/ssafy/b209/drawing/exception/DrawingErrorCode.java`
- `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingSessionService.java`
- `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingSessionController.java`
- 대응하는 Domain, Repository, Service, Controller와 MySQL 통합 테스트

### Modify

- `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`: V2 검증
- `README.md`: Endpoint와 현재 인증 제한 문서화

---

### Task 1: V2 Flyway Migration

**Files:**
- Create: `backend/src/main/resources/db/migration/V2__add_drawing_session_creation_constraints.sql`
- Modify: `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`

**Interfaces:**
- Produces: `drawing_sessions.idempotency_key`, `uk_drawing_sessions_idempotency_key`, `idx_drawing_sessions_active_child`

- [ ] **Step 1: Migration 검증 테스트를 먼저 확장한다**

```java
assertThat(columnExists("drawing_sessions", "idempotency_key")).isTrue();
assertThat(indexExists("drawing_sessions", "uk_drawing_sessions_idempotency_key", true))
    .isTrue();
assertThat(indexExists("drawing_sessions", "idx_drawing_sessions_active_child", false))
    .isTrue();
```

- [ ] **Step 2: RED를 확인한다**

Run: `gradlew.bat test --tests "*DatabaseMigrationIntegrationTest"`

Expected: V2 Column 또는 Index가 없어 실패한다.

- [ ] **Step 3: 최소 Migration을 작성한다**

```sql
ALTER TABLE drawing_sessions
    ADD COLUMN idempotency_key VARCHAR(100) NULL COMMENT '그림 세션 생성 멱등성 Key';

ALTER TABLE drawing_sessions
    ADD CONSTRAINT uk_drawing_sessions_idempotency_key UNIQUE (idempotency_key);

CREATE INDEX idx_drawing_sessions_active_child
    ON drawing_sessions (child_id, session_status, deleted_at);
```

- [ ] **Step 4: GREEN과 형식을 확인한다**

Run: `gradlew.bat test --tests "*DatabaseMigrationIntegrationTest"`

Expected: PASS. `git diff --check`도 오류가 없다.

- [ ] **Step 5: Commit 체크포인트를 기록한다**

제안 메시지: `db(drawing): S15P11B209-138 그림 세션 멱등성 스키마 보완`

실제 Commit은 사용자 요청 전까지 실행하지 않는다.

---

### Task 2: Domain Model과 UTC 시간

**Files:**
- Create: `TimeConfig.java`, Child 관련 3개 Type, Drawing 관련 Enum과 Entity 6개
- Test: `ChildTest.java`, `DrawingTypeTest.java`, `DrawingSessionTest.java`, `TimeConfigTest.java`
- Test Fixtures: `child/domain/ChildTestFixtures.java`, `drawing/domain/DrawingTestFixtures.java`

**Interfaces:**
- Produces: `Child.isAvailable()`, `Child.isTutorialRequired()`, `Child.ageOn(LocalDate)`
- Produces: `DrawingType.isAvailableForAge(int)`
- Produces: `DrawingSession.start(Child, DrawingType, DrawingInputMethod, LocalDateTime, String)`
- Produces: `DrawingSession.matchesCoreRequest(Long, Long, DrawingInputMethod)`

- [ ] **Step 1: Domain의 기대 동작을 테스트로 작성한다**

```java
@Test
void startsWithInProgressDrawingState() {
  DrawingSession session =
      DrawingSession.start(child, drawingType, DrawingInputMethod.CANVAS, startedAt, key);

  assertThat(session.getSessionStatus()).isEqualTo(DrawingSessionStatus.IN_PROGRESS);
  assertThat(session.getCurrentStage()).isEqualTo(DrawingStage.DRAWING);
  assertThat(session.getStartedAt()).isEqualTo(startedAt);
  assertThat(session.getCompletedAt()).isNull();
  assertThat(session.getDeletedAt()).isNull();
  assertThat(session.getStartedByUserId()).isNull();
}

@ParameterizedTest
@EnumSource(value = ChildTutorialStatus.class, names = {"COMPLETED", "SKIPPED"})
void completedOrSkippedTutorialIsNotRequired(ChildTutorialStatus status) {
  assertThat(ChildTestFixtures.child(status).isTutorialRequired()).isFalse();
}
```

- [ ] **Step 2: RED를 확인한다**

Run: `gradlew.bat test --tests "*ChildTest" --tests "*DrawingTypeTest" --tests "*DrawingSessionTest"`

Expected: Domain Type이 없어 컴파일이 실패한다.

- [ ] **Step 3: 문자열 Enum과 최소 Entity를 구현한다**

```java
public enum DrawingInputMethod { CANVAS, UPLOAD }
public enum DrawingSessionStatus { IN_PROGRESS, COMPLETED, FAILED, DELETED }
public enum DrawingStage { DRAWING, ANALYZING, CONVERSING, REFLECTION, REPORTING, COMPLETED }
public enum DrawingTypeSelectableBy { GUARDIAN, CHILD, BOTH }
public enum ChildProfileStatus { ACTIVE, DELETED }
public enum ChildTutorialStatus {
  NOT_STARTED, IN_PROGRESS, COMPLETED, SKIPPED;

  public boolean isRequired() {
    return this != COMPLETED && this != SKIPPED;
  }
}
```

`DrawingSession.start(...)`는 모든 필수 인자를 `Objects.requireNonNull`로 검사하고 초기 상태를
직접 설정한다. Entity는 `@Enumerated(EnumType.STRING)`, LAZY 단방향 관계와 protected JPA
기본 생성자를 사용하며 Public Setter와 Lombok을 사용하지 않는다.

- [ ] **Step 4: UTC Clock Bean을 테스트하고 구현한다**

```java
@Bean
public Clock clock() {
  return Clock.systemUTC();
}
```

Run: `gradlew.bat test --tests "*TimeConfigTest" --tests "*DrawingSessionTest"`

Expected: PASS.

- [ ] **Step 5: 전체 Domain GREEN과 Spotless를 확인한다**

Run: `gradlew.bat test --tests "*ChildTest" --tests "*DrawingTypeTest" --tests "*DrawingSessionTest" --tests "*TimeConfigTest"`

Run: `gradlew.bat spotlessCheck`

- [ ] **Step 6: Commit 체크포인트를 기록한다**

제안 메시지: `feat(drawing): S15P11B209-138 그림 세션 생성 도메인 구현`

---

### Task 3: Repository와 영속성 계약

**Files:**
- Create: `ChildRepository.java`, `DrawingTypeRepository.java`, `DrawingSessionRepository.java`
- Test: `DrawingSessionRepositoryTest.java`

**Interfaces:**
- Produces: `ChildRepository.findNotDeletedByIdForUpdate(Long)`
- Produces: `DrawingSessionRepository.findByIdempotencyKeyForUpdate(String)`
- Produces: `DrawingSessionRepository.findActiveByChildId(Long)`

- [ ] **Step 1: 저장·조회·필터·Lock 테스트를 작성한다**

```java
@Test
void findsOnlyNotDeletedInProgressSession() {
  DrawingSession active = drawingSessionRepository.save(activeSession(child, "active-key"));
  drawingSessionRepository.save(completedSession(child, "completed-key"));

  assertThat(drawingSessionRepository.findActiveByChildId(child.getId())).contains(active);
}

@Test
void findsSessionByIdempotencyKeyWithLockQuery() {
  DrawingSession saved = drawingSessionRepository.saveAndFlush(session);
  assertThat(drawingSessionRepository.findByIdempotencyKeyForUpdate(key)).contains(saved);
}
```

- [ ] **Step 2: RED를 확인한다**

Run: `gradlew.bat test --tests "*DrawingSessionRepositoryTest"`

Expected: Repository가 없어 컴파일에 실패한다.

- [ ] **Step 3: Repository Query를 최소 구현한다**

```java
@Lock(LockModeType.PESSIMISTIC_WRITE)
@Query("select c from Child c where c.id = :childId and c.deletedAt is null")
Optional<Child> findNotDeletedByIdForUpdate(@Param("childId") Long childId);

@Lock(LockModeType.PESSIMISTIC_WRITE)
@Query("select s from DrawingSession s where s.idempotencyKey = :key")
Optional<DrawingSession> findByIdempotencyKeyForUpdate(@Param("key") String key);

@Query("select s from DrawingSession s where s.child.id = :childId "
    + "and s.sessionStatus = com.ssafy.b209.drawing.domain.DrawingSessionStatus.IN_PROGRESS "
    + "and s.deletedAt is null")
Optional<DrawingSession> findActiveByChildId(@Param("childId") Long childId);
```

- [ ] **Step 4: GREEN과 SQL 계약을 확인한다**

Run: `gradlew.bat test --tests "*DrawingSessionRepositoryTest"`

Expected: 관계, Enum 문자열, UTC `LocalDateTime`, 진행 Session 필터와 Key 조회가 모두 PASS.

- [ ] **Step 5: Commit 체크포인트를 기록한다**

제안 메시지: `feat(drawing): S15P11B209-138 그림 세션 Repository 구현`

---

### Task 4: DTO와 Drawing 오류 코드

**Files:**
- Create: Request·Response DTO 4개, `DrawingErrorCode.java`
- Test: `CreateDrawingSessionRequestTest.java`, `DrawingErrorCodeTest.java`

**Interfaces:**
- Produces: `CreateDrawingSessionRequest(Long, Long, DrawingInputMethod, OffsetDateTime, CanvasConfigurationRequest)`
- Produces: `CreateDrawingSessionResponse`와 `DrawingTypeSummaryResponse`
- Produces: 프롬프트의 `DRAWING_400/404/409` 오류 코드 9개

- [ ] **Step 1: Bean Validation과 오류 코드 테스트를 작성한다**

```java
@Test
void rejectsNonPositiveChildId() {
  var request = new CreateDrawingSessionRequest(0L, 2L, CANVAS, clientStartedAt, canvas);
  assertThat(validator.validate(request))
      .extracting(violation -> violation.getPropertyPath().toString())
      .contains("childId");
}

@Test
void activeSessionErrorUsesConflict() {
  assertThat(DrawingErrorCode.ACTIVE_DRAWING_SESSION_EXISTS.getHttpStatus())
      .isEqualTo(HttpStatus.CONFLICT);
  assertThat(DrawingErrorCode.ACTIVE_DRAWING_SESSION_EXISTS.getCode())
      .isEqualTo("DRAWING_409_001");
}
```

- [ ] **Step 2: RED를 확인한다**

Run: `gradlew.bat test --tests "*CreateDrawingSessionRequestTest" --tests "*DrawingErrorCodeTest"`

- [ ] **Step 3: 불변 Record와 ErrorCode를 구현한다**

```java
public record CreateDrawingSessionRequest(
    @NotNull @Positive Long childId,
    @NotNull @Positive Long drawingTypeId,
    @NotNull DrawingInputMethod inputMethod,
    @NotNull OffsetDateTime clientStartedAt,
    CanvasConfigurationRequest canvas) {}
```

Canvas Record에는 Bean Validation을 Cascade하지 않는다. CANVAS 조건은 Service가 검사하고
UPLOAD의 전달된 Canvas는 무시한다. `DrawingErrorCode`는 `ErrorCode`를 구현한다.

```text
CHILD_NOT_FOUND                 404 DRAWING_404_001 아동 정보를 찾을 수 없습니다.
DRAWING_TYPE_NOT_FOUND          404 DRAWING_404_002 그림 활동 유형을 찾을 수 없습니다.
DRAWING_TYPE_NOT_AVAILABLE      400 DRAWING_400_001 현재 선택할 수 없는 그림 활동 유형입니다.
INVALID_CANVAS_CONFIGURATION    400 DRAWING_400_002 캔버스 설정이 올바르지 않습니다.
IDEMPOTENCY_KEY_REQUIRED        400 DRAWING_400_003 Idempotency-Key가 필요합니다.
IDEMPOTENCY_KEY_INVALID         400 DRAWING_400_004 Idempotency-Key 형식이 올바르지 않습니다.
ACTIVE_DRAWING_SESSION_EXISTS   409 DRAWING_409_001 진행 중인 그림 활동이 이미 존재합니다.
IDEMPOTENCY_KEY_CONFLICT        409 DRAWING_409_002 동일한 Idempotency-Key가 다른 요청에 사용되었습니다.
DRAWING_SESSION_CREATION_CONFLICT 409 DRAWING_409_003 그림 활동 생성 요청이 충돌했습니다.
```

- [ ] **Step 4: GREEN과 JSON 직렬화를 확인한다**

Run: `gradlew.bat test --tests "*CreateDrawingSessionRequestTest" --tests "*DrawingErrorCodeTest"`

- [ ] **Step 5: Commit 체크포인트를 기록한다**

제안 메시지: `feat(drawing): S15P11B209-138 그림 세션 API DTO 및 오류 코드 구현`

---

### Task 5: DrawingSessionService

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingSessionService.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingSessionServiceTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/DrawingSessionConcurrencyIntegrationTest.java`

**Interfaces:**
- Consumes: Task 2~4의 Domain, Repository, DTO와 ErrorCode
- Produces: `CreateDrawingSessionResponse createDrawingSession(String, CreateDrawingSessionRequest)`

- [ ] **Step 1: 정상 CANVAS·UPLOAD 실패 테스트를 작성한다**

```java
@Test
void createsCanvasSessionWithServerUtcTime() {
  given(sessionRepository.findByIdempotencyKeyForUpdate(key)).willReturn(Optional.empty());
  given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(child));
  given(drawingTypeRepository.findById(2L)).willReturn(Optional.of(drawingType));
  given(sessionRepository.findActiveByChildId(1L)).willReturn(Optional.empty());
  given(sessionRepository.saveAndFlush(any())).willAnswer(invocation -> persisted(invocation.getArgument(0)));

  CreateDrawingSessionResponse response = service.createDrawingSession(key, canvasRequest);

  assertThat(response.sessionStatus()).isEqualTo(IN_PROGRESS);
  assertThat(response.currentStage()).isEqualTo(DRAWING);
  assertThat(response.startedAt()).isEqualTo(FIXED_INSTANT);
}
```

UPLOAD는 `canvas=null`로 성공하고 Canvas가 전달돼도 검증·저장에 사용되지 않는 테스트를
별도로 작성한다.

Testcontainers MySQL 동시성 테스트도 Production Service보다 먼저 작성한다.

- 같은 Child·다른 Key: `성공 1건 + ACTIVE_DRAWING_SESSION_EXISTS 1건`, Row 1건
- 같은 Child·같은 Key·같은 핵심 요청: 두 응답의 ID가 같고 Row 1건
- 다른 Child·같은 Key: `성공 1건 + IDEMPOTENCY_KEY_CONFLICT 1건`, 전체 Row 1건

- [ ] **Step 2: 정상 경로 RED를 확인한다**

Run: `gradlew.bat test --tests "*DrawingSessionServiceTest" --tests "*DrawingSessionConcurrencyIntegrationTest"`

Expected: Service가 없어 컴파일에 실패한다.

- [ ] **Step 3: 정상 경로의 최소 Service를 구현한다**

```java
@Transactional
public CreateDrawingSessionResponse createDrawingSession(
    String idempotencyKey, CreateDrawingSessionRequest request) {
  validateCanvas(request);
  validateIdempotencyKey(idempotencyKey);
  Optional<DrawingSession> existing =
      drawingSessionRepository.findByIdempotencyKeyForUpdate(idempotencyKey);
  if (existing.isPresent()) {
    return resolveIdempotentRequest(existing.get(), request);
  }
  Child child = childRepository.findNotDeletedByIdForUpdate(request.childId())
      .filter(Child::isAvailable)
      .orElseThrow(() -> new BusinessException(DrawingErrorCode.CHILD_NOT_FOUND));
  DrawingType drawingType = drawingTypeRepository.findById(request.drawingTypeId())
      .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_TYPE_NOT_FOUND));
  validateDrawingType(drawingType, child);
  rejectActiveSession(child.getId());
  LocalDateTime startedAt = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
  DrawingSession saved = drawingSessionRepository.saveAndFlush(
      DrawingSession.start(child, drawingType, request.inputMethod(), startedAt, idempotencyKey));
  return toResponse(saved);
}
```

- [ ] **Step 4: 오류 동작을 테스트 하나씩 RED-GREEN 한다**

각 항목은 테스트 작성 → 예상 ErrorCode 실패 확인 → 최소 분기 구현 순서로 진행한다.

- Child 미존재·삭제·비활성
- DrawingType 미존재·비활성·최소 연령 미만·최대 연령 초과
- CANVAS 누락·너비·높이·색상 오류
- Idempotency-Key 누락·Blank·7자·101자·제어 문자
- 기존 진행 Session
- 동일 Key 동일 핵심 요청
- 동일 Key 다른 Child·DrawingType·InputMethod
- 저장 시 의미를 특정할 수 없는 `DataIntegrityViolationException`

- [ ] **Step 5: 상호작용과 개인정보 비노출을 검증한다**

오류 경로에서는 `saveAndFlush`가 호출되지 않음을 검증한다. Logger를 추가하지 않고 Request와
Key를 예외 메시지에 포함하지 않는다.

- [ ] **Step 6: Service 전체 GREEN을 확인한다**

Run: `gradlew.bat test --tests "*DrawingSessionServiceTest" --tests "*DrawingSessionConcurrencyIntegrationTest"`

Run: `gradlew.bat spotlessCheck`

- [ ] **Step 7: Commit 체크포인트를 기록한다**

제안 메시지: `feat(drawing): S15P11B209-138 그림 세션 생성 서비스 구현`

---

### Task 6: Controller, 공통 응답과 OpenAPI

**Files:**
- Create: `DrawingSessionController.java`
- Test: `DrawingSessionControllerTest.java`, `DrawingSessionOpenApiTest.java`

**Interfaces:**
- Consumes: `DrawingSessionService`, `ApiResponse`, `CommonSuccessCode.CREATED`
- Produces: `POST /api/v1/drawing-sessions`

- [ ] **Step 1: 201·Location·Body MockMvc 테스트를 작성한다**

```java
mockMvc.perform(post("/api/v1/drawing-sessions")
        .header("Idempotency-Key", key)
        .contentType(MediaType.APPLICATION_JSON)
        .content(validCanvasJson))
    .andExpect(status().isCreated())
    .andExpect(header().string("Location", "/api/v1/drawing-sessions/100"))
    .andExpect(jsonPath("$.success").value(true))
    .andExpect(jsonPath("$.code").value("COMMON_201"))
    .andExpect(jsonPath("$.data.sessionStatus").value("IN_PROGRESS"))
    .andExpect(jsonPath("$.data.currentStage").value("DRAWING"));
```

- [ ] **Step 2: RED를 확인한다**

Run: `gradlew.bat test --tests "*DrawingSessionControllerTest"`

Expected: Endpoint가 없어 404 또는 Context 실패다.

- [ ] **Step 3: 얇은 Controller를 구현한다**

```java
@PostMapping
public ResponseEntity<ApiResponse<CreateDrawingSessionResponse>> createDrawingSession(
    @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
    @Valid @RequestBody CreateDrawingSessionRequest request) {
  CreateDrawingSessionResponse response =
      drawingSessionService.createDrawingSession(idempotencyKey, request);
  URI location = URI.create("/api/v1/drawing-sessions/" + response.drawingSessionId());
  return ResponseEntity.created(location)
      .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
}
```

- [ ] **Step 4: Validation과 도메인 오류 Controller 테스트를 RED-GREEN 한다**

Body 필수값, 잘못된 Enum·OffsetDateTime, Header 누락, Canvas 오류, Child·DrawingType 404,
진행 Session·멱등 충돌 409가 기존 `ApiErrorResponse`로 반환되는지 확인한다.

- [ ] **Step 5: OpenAPI 계약을 테스트하고 Annotation을 추가한다**

`/v3/api-docs/api-v1`에 Endpoint, 필수 Header, Request·Response Schema와 201·400·404·409·500이
있고 401·403·Bearer Scheme이 없는지 검증한다.

- [ ] **Step 6: Controller GREEN을 확인한다**

Run: `gradlew.bat test --tests "*DrawingSessionControllerTest" --tests "*DrawingSessionOpenApiTest"`

- [ ] **Step 7: Commit 체크포인트를 기록한다**

제안 메시지: `feat(drawing): S15P11B209-138 그림 활동 생성 API 구현`

---

### Task 7: MySQL 통합·동시성·README와 전체 검증

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/drawing/DrawingSessionIntegrationTest.java`
- Modify: `README.md`

**Interfaces:**
- Verifies: Flyway V1+V2, MySQL Unique·Check·Lock, HTTP 전체 흐름

- [ ] **Step 1: MySQL 통합 테스트를 작성한다**

JdbcTemplate로 필수 Child와 DrawingType Fixture만 삽입한다. MockMvc 또는 Service Bean으로
다음을 검증한다.

```text
CANVAS 201 + Row 1건
UPLOAD 201
동일 Key 동일 요청 = 같은 drawingSessionId, Row 증가 없음
동일 Key 다른 핵심 요청 = DRAWING_409_002
다른 Key 같은 아동 = DRAWING_409_001
다른 아동 = 별도 생성 성공
IN_PROGRESS/DRAWING, started_at, completed_at NULL, deleted_at NULL
idempotency_key Unique Constraint
```

- [ ] **Step 2: 기존 동시성 회귀 테스트를 함께 실행한다**

Task 5에서 RED를 확인하고 통과시킨 `DrawingSessionConcurrencyIntegrationTest`를 전체 API
통합 테스트와 함께 실행한다. 서로 다른 Key의 Child Lock, 동일 Key 재시도와 동일 Key의
핵심 요청 충돌 세 시나리오가 모두 Row 중복 없이 통과해야 한다.

- [ ] **Step 3: README를 보완한다**

Endpoint, Header, CANVAS·UPLOAD 예시, 멱등·진행 Session 규칙, 서버 UTC 시각,
운영 DrawingType Seed 미포함, 인증·보호자 관계·동의 검증 미연결 상태를 기존 문서에 추가한다.

- [ ] **Step 4: 범위와 보안 Audit을 실행한다**

```powershell
rg -n "@CrossOrigin|CorsFilter|SecurityFilterChain|JWT|Bearer|X-User-Id|TODO|package-info" backend/src/main README.md
rg -n "Idempotency-Key|Authorization|birthDate|birth_date|nickname" backend/src/main
git diff --check
```

Expected: 신규 인증·CORS·후속 기능과 민감 정보 Logging이 없다. README의 제한 설명만 허용한다.

- [ ] **Step 5: 최종 검증을 실행한다**

```powershell
$env:JAVA_HOME='<Java 21 설치 경로>'
.\gradlew.bat clean test
.\gradlew.bat spotlessCheck
.\gradlew.bat javadoc --rerun-tasks
```

Expected: 전체 테스트 0 failures/errors, Spotless 성공, Javadoc 경고 없이 성공,
`backend/build/docs/javadoc/index.html` 존재.

- [ ] **Step 6: 최종 리뷰와 Commit 체크포인트를 기록한다**

제안 단일 Commit 메시지:

```text
feat(drawing): S15P11B209-138 그림 활동 생성 API 구현
```

사용자가 요청하기 전에는 Stage, Commit, Push와 Merge Request를 수행하지 않는다.
