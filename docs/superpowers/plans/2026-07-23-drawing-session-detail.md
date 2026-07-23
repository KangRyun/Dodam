# Drawing Session Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 인증된 연결 보호자가 그림 활동 세션의 상태와 최신 연관 리소스 요약을 조회하는 `GET /api/v1/drawing-sessions/{drawingSessionId}`를 구현한다.

**Architecture:** 기존 `DrawingSessionController`와 `DrawingSessionQueryService`를 확장한다. QueryService가 보호자 권한을 먼저 검증하고, 책임별 Repository 조회 결과를 Entity 비노출 응답 DTO로 조합한다. 조회는 읽기 전용이며 AI Client, Storage, 상태 변경을 호출하지 않는다.

**Tech Stack:** Java 21, Spring Boot 3.5.3, Spring Data JPA, Spring Security, Jakarta Validation, Springdoc OpenAPI, JUnit 5, Mockito, AssertJ, MockMvc, Testcontainers MySQL 8

## Global Constraints

- 최신 `develop`과 기존 Package·응답·예외·인증 구조를 유지한다.
- 연결 보호자만 조회할 수 있으며 공유 전문가는 이번 범위에서 제외한다.
- Entity, 내부 `storageKey`, 아동 생년월일, 이미지 Byte/Base64를 API에 노출하지 않는다.
- 연관 데이터가 없으면 객체와 ID는 `null`, 감정은 빈 배열로 반환한다.
- 조회 과정에서 AI Client, ImageStorage, 세션 상태를 변경하지 않는다.
- DB Schema와 Flyway Migration을 변경하지 않는다.
- 주요 Production Type과 공개 메서드에 실제 동작과 일치하는 한국어 Javadoc을 작성한다.

---

### Task 1: 상세 응답 DTO와 최소 Domain 접근자

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingSessionChildSummaryResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingSessionAssetSummaryResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingSessionAnalysisSummaryResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingSessionDetailResponse.java`
- Modify: `backend/src/main/java/com/ssafy/b209/child/domain/Child.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/domain/DrawingAnalysis.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/dto/response/DrawingSessionDetailResponseTest.java`

**Interfaces:**
- Consumes: 기존 `DrawingInputMethod`, `DrawingSessionStatus`, `DrawingStage`, `DrawingAssetType`, `DrawingAnalysisScope`, `DrawingAnalysisType`, `DrawingAnalysisState`
- Produces: `DrawingSessionDetailResponse`와 중첩 요약 DTO, `Child.getNickname()`, `DrawingAnalysis.getScope()`

- [ ] **Step 1: Write the failing serialization and immutability test**

```java
@Test
void copiesSelectedEmotionsAndSerializesNullableResources() throws Exception {
  List<DrawingEmotionCode> emotions = new ArrayList<>(List.of(DrawingEmotionCode.HAPPY));
  DrawingSessionDetailResponse response =
      new DrawingSessionDetailResponse(
          10L,
          new DrawingSessionChildSummaryResponse(3L, "도담"),
          new DrawingTypeSummaryResponse(7L, "HOUSE", "집"),
          DrawingInputMethod.CANVAS,
          "우리 집",
          emotions,
          DrawingSessionStatus.IN_PROGRESS,
          DrawingStage.REFLECTION,
          null,
          null,
          null,
          null,
          Instant.parse("2026-07-23T01:00:00Z"),
          null,
          false);

  emotions.clear();

  assertThat(response.selectedEmotions()).containsExactly(DrawingEmotionCode.HAPPY);
  assertThat(objectMapper.writeValueAsString(response))
      .contains("\"latestAsset\":null", "\"latestAnalysis\":null");
}
```

- [ ] **Step 2: Run the DTO test to verify it fails**

Run:

```powershell
cd backend
.\gradlew.bat test --tests "*DrawingSessionDetailResponseTest"
```

Expected: FAIL because the response types do not exist.

- [ ] **Step 3: Add immutable response records and accessors**

```java
public record DrawingSessionChildSummaryResponse(Long childId, String nickname) {}
```

```java
public record DrawingSessionAssetSummaryResponse(
    Long drawingAssetId,
    DrawingAssetType assetType,
    int assetVersion,
    String mimeType,
    long fileSizeBytes,
    Instant capturedAt,
    Instant createdAt) {}
```

```java
public record DrawingSessionAnalysisSummaryResponse(
    Long drawingAnalysisId,
    DrawingAnalysisScope analysisScope,
    DrawingAnalysisType analysisType,
    DrawingAnalysisState analysisStatus,
    Instant requestedAt,
    Instant completedAt) {}
```

```java
public record DrawingSessionDetailResponse(
    Long drawingSessionId,
    DrawingSessionChildSummaryResponse child,
    DrawingTypeSummaryResponse drawingType,
    DrawingInputMethod inputMethod,
    String title,
    List<DrawingEmotionCode> selectedEmotions,
    DrawingSessionStatus sessionStatus,
    DrawingStage currentStage,
    DrawingSessionAssetSummaryResponse latestAsset,
    DrawingSessionAnalysisSummaryResponse latestAnalysis,
    Long conversationId,
    Long reportId,
    Instant startedAt,
    Instant completedAt,
    boolean recoverableDraft) {

  public DrawingSessionDetailResponse {
    selectedEmotions = List.copyOf(selectedEmotions);
  }
}
```

`Child`에는 nickname getter, `DrawingAnalysis`에는 scope getter를 한국어 Javadoc과 함께 추가한다.

- [ ] **Step 4: Run the DTO test**

Run:

```powershell
.\gradlew.bat test --tests "*DrawingSessionDetailResponseTest"
```

Expected: PASS.

---

### Task 2: 상세 조회 Repository 계약

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingSessionRepository.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingSessionEmotionRepository.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingAssetRepository.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/repository/DrawingAnalysisRepository.java`
- Modify: `backend/src/main/java/com/ssafy/b209/report/repository/ReportRepository.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/repository/DrawingSessionDetailRepositoryTest.java`

**Interfaces:**
- Consumes: `drawingSessionId`
- Produces:
  - `DrawingSessionRepository.findDetailById(Long)`
  - `DrawingSessionEmotionRepository.findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(Long)`
  - `DrawingAssetRepository.findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(Long)`
  - `DrawingAnalysisRepository.findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(Long)`
  - `ReportRepository.findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(Long)`
- Reuses: `ConversationSessionRepository.findByDrawingSessionId(Long)` because DB Unique constraint permits one conversation per drawing session

- [ ] **Step 1: Write failing MySQL repository tests**

Create a `@DataJpaTest` with the existing MySQL Testcontainers configuration and SQL fixtures for one session. Verify:

```java
assertThat(drawingSessionRepository.findDetailById(10L)).isPresent();
assertThat(drawingSessionEmotionRepository
        .findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(10L))
    .extracting(DrawingSessionEmotion::getEmotionCode)
    .containsExactly(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM);
assertThat(drawingAssetRepository
        .findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(10L)
        .orElseThrow()
        .getId())
    .isEqualTo(22L);
assertThat(drawingAnalysisRepository
        .findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(10L)
        .orElseThrow()
        .getId())
    .isEqualTo(32L);
assertThat(reportRepository
        .findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(10L)
        .orElseThrow()
        .getId())
    .isEqualTo(42L);
```

Add a deleted session fixture and assert `findDetailById` returns empty.

- [ ] **Step 2: Run repository tests to verify they fail**

Run:

```powershell
.\gradlew.bat test --tests "*DrawingSessionDetailRepositoryTest"
```

Expected: FAIL because the repository methods are absent.

- [ ] **Step 3: Implement minimal repository methods**

```java
@Query(
    "select s from DrawingSession s "
        + "join fetch s.child "
        + "join fetch s.drawingType "
        + "where s.id = :id and s.deletedAt is null")
Optional<DrawingSession> findDetailById(@Param("id") Long id);
```

```java
List<DrawingSessionEmotion>
    findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(Long drawingSessionId);
```

```java
Optional<DrawingAsset> findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(
    Long drawingSessionId);
```

```java
Optional<DrawingAnalysis> findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(
    Long drawingSessionId);
```

```java
Optional<Report> findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(Long drawingSessionId);
```

각 공개 Repository 메서드에는 선택 기준과 빈 값 의미를 설명하는 한국어 Javadoc을 추가한다.

- [ ] **Step 4: Run repository tests**

Run:

```powershell
.\gradlew.bat test --tests "*DrawingSessionDetailRepositoryTest"
```

Expected: PASS. Docker가 없어 실행되지 않으면 테스트를 유지하고 사유를 기록한다.

---

### Task 3: QueryService 상세 응답 조립

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingSessionQueryService.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingSessionQueryServiceTest.java`

**Interfaces:**
- Consumes: Task 1 DTO, Task 2 Repository 메서드, 기존 권한 Validator
- Produces: `DrawingSessionDetailResponse getDrawingSessionDetail(Long drawingSessionId)`

- [ ] **Step 1: Write failing service tests**

Add tests with Mockito for:

```java
@Test
void returnsAuthorizedSessionDetailWithLatestResources() {
  given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
  given(drawingSessionRepository.findDetailById(SESSION_ID)).willReturn(Optional.of(session));
  given(drawingSessionEmotionRepository
      .findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(SESSION_ID))
      .willReturn(List.of(happyEmotion, calmEmotion));
  given(drawingAssetRepository
      .findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(SESSION_ID))
      .willReturn(Optional.of(asset));
  given(drawingAssetRepository
      .existsByDrawingSessionIdAndAssetType(SESSION_ID, DrawingAssetType.DRAFT))
      .willReturn(true);
  given(drawingAnalysisRepository
      .findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(SESSION_ID))
      .willReturn(Optional.of(analysis));
  given(conversationSessionRepository.findByDrawingSessionId(SESSION_ID))
      .willReturn(Optional.of(conversation));
  given(reportRepository.findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(SESSION_ID))
      .willReturn(Optional.of(report));

  DrawingSessionDetailResponse result = service.getDrawingSessionDetail(SESSION_ID);

  assertThat(result.selectedEmotions())
      .containsExactly(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM);
  assertThat(result.latestAsset().drawingAssetId()).isEqualTo(20L);
  assertThat(result.latestAnalysis().drawingAnalysisId()).isEqualTo(30L);
  assertThat(result.conversationId()).isEqualTo(40L);
  assertThat(result.reportId()).isEqualTo(50L);
  assertThat(result.recoverableDraft()).isTrue();
}
```

Also add:

- missing optional resources return `null`, empty emotion list, and `recoverableDraft=false`
- access validator failure prevents all detail Repository reads
- authorized but deleted/missing session returns `DRAWING_SESSION_NOT_FOUND`

- [ ] **Step 2: Run service tests to verify they fail**

Run:

```powershell
.\gradlew.bat test --tests "*DrawingSessionQueryServiceTest"
```

Expected: FAIL because dependencies and `getDrawingSessionDetail` are absent.

- [ ] **Step 3: Implement the read-only aggregation**

Extend the constructor with emotion, analysis, conversation, and report repositories. Implement:

```java
public DrawingSessionDetailResponse getDrawingSessionDetail(Long drawingSessionId) {
  Long guardianUserId = currentUserResolver.requireUserId();
  accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
  DrawingSession session =
      drawingSessionRepository
          .findDetailById(drawingSessionId)
          .orElseThrow(
              () -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));

  List<DrawingEmotionCode> emotions =
      drawingSessionEmotionRepository
          .findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(drawingSessionId)
          .stream()
          .map(DrawingSessionEmotion::getEmotionCode)
          .toList();

  return new DrawingSessionDetailResponse(
      session.getId(),
      new DrawingSessionChildSummaryResponse(
          session.getChild().getId(), session.getChild().getNickname()),
      toDrawingTypeSummary(session.getDrawingType()),
      session.getInputMethod(),
      session.getTitle(),
      emotions,
      session.getSessionStatus(),
      session.getCurrentStage(),
      drawingAssetRepository
          .findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(drawingSessionId)
          .map(this::toAssetSummary)
          .orElse(null),
      drawingAnalysisRepository
          .findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(drawingSessionId)
          .map(this::toAnalysisSummary)
          .orElse(null),
      conversationSessionRepository
          .findByDrawingSessionId(drawingSessionId)
          .map(ConversationSession::getId)
          .orElse(null),
      reportRepository
          .findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(drawingSessionId)
          .map(Report::getId)
          .orElse(null),
      toInstant(session.getStartedAt()),
      toNullableInstant(session.getCompletedAt()),
      drawingAssetRepository.existsByDrawingSessionIdAndAssetType(
          drawingSessionId, DrawingAssetType.DRAFT));
}
```

Private mapper methods must omit `storageKey` and convert `LocalDateTime` with `ZoneOffset.UTC`.

- [ ] **Step 4: Run service tests**

Run:

```powershell
.\gradlew.bat test --tests "*DrawingSessionQueryServiceTest"
```

Expected: PASS.

---

### Task 4: Controller, OpenAPI, integration contract

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingSessionController.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingSessionControllerTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingSessionOpenApiTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/DrawingSessionIntegrationTest.java`
- Modify: `README.md`

**Interfaces:**
- Consumes: `DrawingSessionQueryService.getDrawingSessionDetail(Long)`
- Produces: `GET /api/v1/drawing-sessions/{drawingSessionId}`, HTTP 200 `ApiResponse<DrawingSessionDetailResponse>`

- [ ] **Step 1: Write failing Controller tests**

```java
@Test
void returnsDrawingSessionDetail() throws Exception {
  given(drawingSessionQueryService.getDrawingSessionDetail(100L))
      .willReturn(detailResponse());

  mockMvc.perform(get("/api/v1/drawing-sessions/{drawingSessionId}", 100))
      .andExpect(status().isOk())
      .andExpect(jsonPath("$.code").value("COMMON_200"))
      .andExpect(jsonPath("$.data.drawingSessionId").value(100))
      .andExpect(jsonPath("$.data.child.nickname").value("도담"))
      .andExpect(jsonPath("$.data.selectedEmotions[0]").value("HAPPY"))
      .andExpect(jsonPath("$.data.latestAsset.storageKey").doesNotExist())
      .andExpect(jsonPath("$.data.recoverableDraft").value(true));
}
```

Add a non-positive path test expecting HTTP 400 and a BusinessException test expecting the existing 404 code.

- [ ] **Step 2: Run Controller tests to verify they fail**

Run:

```powershell
.\gradlew.bat test --tests "*DrawingSessionControllerTest"
```

Expected: FAIL with HTTP 404 for the missing mapping.

- [ ] **Step 3: Add the Endpoint and OpenAPI contract**

```java
@GetMapping("/{drawingSessionId}")
public ResponseEntity<ApiResponse<DrawingSessionDetailResponse>> getDrawingSessionDetail(
    @PathVariable @Positive Long drawingSessionId) {
  return ResponseEntity.ok(
      ApiResponse.ok(drawingSessionQueryService.getDrawingSessionDetail(drawingSessionId)));
}
```

Add Korean Javadoc, `@Operation`, and responses for 200, 400, 404. Update OpenAPI tests to assert the path exists and does not declare a request body.

- [ ] **Step 4: Add MySQL integration coverage**

Extend `DrawingSessionIntegrationTest` with an authenticated guardian fixture and assert:

- owned session returns HTTP 200
- selected emotions preserve order
- latest Asset and analysis IDs follow time/id ordering
- internal `storageKey` is absent
- another guardian receives HTTP 404

- [ ] **Step 5: Document the implemented limitation**

Add a focused README section:

```markdown
### 그림 활동 상세 조회

`GET /api/v1/drawing-sessions/{drawingSessionId}`는 연결 보호자에게 세션 상태와 최신 연관 리소스 Metadata를 반환한다. 이미지 원본과 내부 저장 경로는 반환하지 않는다. 공유 전문가 조회 권한은 아직 제공하지 않는다.
```

- [ ] **Step 6: Run focused tests**

Run:

```powershell
.\gradlew.bat test --tests "*DrawingSessionControllerTest" --tests "*DrawingSessionOpenApiTest" --tests "*DrawingSessionIntegrationTest"
```

Expected: PASS.

---

### Task 5: Full verification and delivery

**Files:**
- Verify all files changed in Tasks 1-4

**Interfaces:**
- Produces: merge-ready `S15P11B209-139` branch

- [ ] **Step 1: Check formatting and accidental files**

```powershell
git diff --check
git status --short
```

Expected: `.idea` and `backend/local.properties` remain unstaged; no whitespace errors.

- [ ] **Step 2: Run complete backend verification**

```powershell
cd backend
.\gradlew.bat clean test
.\gradlew.bat spotlessCheck
.\gradlew.bat javadoc
```

Expected: all commands succeed and `backend/build/docs/javadoc/index.html` exists. Existing unrelated Javadoc warnings are reported without disabling DocLint.

- [ ] **Step 3: Review the final diff**

Verify:

- no Entity is returned by the Controller
- no `storageKey`, birth date, image content, token, or absolute path is exposed
- no AI Client, Storage, write Transaction, or state mutation is called
- no Flyway Migration or dependency change exists
- Korean Javadocs match actual behavior

- [ ] **Step 4: Commit implementation**

```powershell
git add -- backend/src/main backend/src/test README.md docs/superpowers/plans/2026-07-23-drawing-session-detail.md
git commit -m "feat(drawing): S15P11B209-139 그림 활동 상세 조회 구현"
```

- [ ] **Step 5: Push, create MR, merge, and close Jira**

After the user-authorized verification succeeds:

- push `feature/S15P11B209-139-drawing-session-detail`
- create a non-draft MR targeting `develop`
- merge only when GitLab reports no conflict
- remove the remote source branch, retain the local branch for record
- transition Jira `S15P11B209-139` to 완료
