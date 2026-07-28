# Drawing Activity Completion Implementation Plan

> 계약 변경: S15P11B209-645부터 `requestReport=false`는 `400 DRAWING_400_012`로 거절한다. 이 문서의 `false` 저장·검증 단계는 초기 구현 이력이며 현재 API 계약이 아니다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 그림 활동의 최종 분석과 선택적 리포트 생성을 멱등하게 접수하고 세션을 REPORTING 단계로 전환하는 HTTP 202 API를 구현한다.

**Architecture:** `DrawingCompletionService`가 인증·권한·상태 검증과 세션 잠금을 조정하고, 기존 `DrawingAnalysis`와 새 최소 `Report` Entity를 한 Transaction에서 저장한다. 멱등성은 `analyses.idempotency_key` UNIQUE 제약과 세션 행 잠금으로 보장하며 실제 AI 또는 리포트 생성 작업은 호출하지 않는다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, Jakarta Validation, MySQL 8.4, JUnit 5, Mockito, MockMvc, Testcontainers

## Global Constraints

- Endpoint는 `POST /api/v1/drawing-sessions/{drawingSessionId}/complete` 하나만 추가한다.
- 필수 Header는 `Idempotency-Key`, 필수 Body 필드는 `conversationSkipped`, `requestReport`다.
- 성공 응답은 HTTP 202와 기존 `ApiResponse<T>`를 사용한다.
- 실제 AI 호출, 분석 결과 생성, 리포트 본문 생성, 세션 `COMPLETED` 전환은 구현하지 않는다.
- 기존 Flyway Migration은 수정하지 않고, V7에서 분석 작업 유형 CHECK에 `ACTIVITY_REPORT`를 추가한다.
- 기존 인증 Resolver, `GuardianResourceAccessValidator`, `BusinessException`, `GlobalExceptionHandler`를 재사용한다.
- 주요 Production Type과 공개 메서드에는 실제 역할과 일치하는 한국어 Javadoc을 작성한다.
- 사용자 변경 `.idea/modules.xml`은 수정하거나 Commit하지 않는다.

---

### Task 1: 대기 분석과 리포트 접수 Domain

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/domain/DrawingAnalysis.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/dto/DrawingAnalysisType.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/repository/DrawingAnalysisRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/domain/Report.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/domain/ReportStatus.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/domain/ReportPdfStatus.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/repository/ReportRepository.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/domain/DrawingAnalysisPendingTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/report/domain/ReportTest.java`

**Interfaces:**
- Produces: `DrawingAnalysis.pending(DrawingSession, DrawingAsset, DrawingAnalysisType, String, LocalDateTime)`
- Produces: `DrawingAnalysis.matchesCompletionRequest(Long, boolean)`
- Produces: `Report.generating(DrawingSession, DrawingAnalysis, int, LocalDateTime)`
- Produces: `DrawingAnalysisRepository.findByRequestId(String)`
- Produces: `ReportRepository.findByAnalysisId(Long)` and `findTopByDrawingSessionIdOrderByReportVersionDesc(Long)`

- [ ] **Step 1: 대기 분석과 생성 중 리포트의 실패 테스트를 작성한다.**

```java
DrawingAnalysis analysis =
    DrawingAnalysis.pending(session, finalAsset, DrawingAnalysisType.ACTIVITY_REPORT, "completion-key", now);

assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.PENDING);
assertThat(analysis.getRequestedAt()).isEqualTo(now);
assertThat(analysis.getStartedAt()).isNull();

Report report = Report.generating(session, analysis, 1, now);
assertThat(report.getStatus()).isEqualTo(ReportStatus.GENERATING);
assertThat(report.getPdfStatus()).isEqualTo(ReportPdfStatus.NONE);
```

- [ ] **Step 2: Domain 테스트가 Factory 부재로 실패하는지 확인한다.**

```powershell
.\gradlew.bat --no-daemon test --tests "*DrawingAnalysisPendingTest" --tests "*ReportTest"
```

Expected: `pending` 또는 `Report` Type을 찾을 수 없어 compile 실패.

- [ ] **Step 3: 기존 PROCESSING Factory와 구분되는 PENDING Factory를 구현한다.**

```java
public static DrawingAnalysis pending(
    DrawingSession session,
    DrawingAsset finalAsset,
    DrawingAnalysisType taskType,
    String idempotencyKey,
    LocalDateTime requestedAt) {
  DrawingAnalysis analysis = new DrawingAnalysis();
  analysis.drawingSession = Objects.requireNonNull(session);
  analysis.drawingAsset = Objects.requireNonNull(finalAsset);
  analysis.scope = DrawingAnalysisScope.FINAL;
  analysis.taskType = Objects.requireNonNull(taskType);
  analysis.requestId = requireText(idempotencyKey, "idempotencyKey");
  analysis.state = DrawingAnalysisState.PENDING;
  analysis.triggerReason = "SESSION_COMPLETE";
  analysis.requestedAt = Objects.requireNonNull(requestedAt);
  analysis.createdAt = requestedAt;
  return analysis;
}
```

`DrawingAnalysisType`에는 DB `VARCHAR(30)` 길이 안의 `ACTIVITY_REPORT`를 추가하고, `getStartedAt()`과 완료 요청 비교에 필요한 식별자 Getter를 제공한다.

- [ ] **Step 4: 최종 Schema의 필수 Column만 매핑한 Report Entity를 구현한다.**

```java
@Entity
@Table(name = "reports")
public class Report {
  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_session_id", nullable = false)
  private DrawingSession drawingSession;

  @OneToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "analysis_id", nullable = false)
  private DrawingAnalysis analysis;

  @Enumerated(EnumType.STRING)
  @Column(name = "report_status", nullable = false)
  private ReportStatus status;
}
```

Factory는 `reportVersion >= 1`, 필수 관계와 시각을 검증하고 `GENERATING`, `false`, 안전한 한계 안내, `NONE`을 저장한다. 정규화된 리포트 상세 Table은 매핑하지 않는다.

- [ ] **Step 5: Repository 멱등 조회와 다음 버전 조회를 추가한다.**

```java
Optional<DrawingAnalysis> findByRequestId(String requestId);
Optional<Report> findByAnalysisId(Long analysisId);
Optional<Report> findTopByDrawingSessionIdOrderByReportVersionDesc(Long drawingSessionId);
```

- [ ] **Step 6: Domain 테스트를 다시 실행해 통과시킨다.**

```powershell
.\gradlew.bat --no-daemon test --tests "*DrawingAnalysisPendingTest" --tests "*ReportTest"
```

Expected: 모든 대상 테스트 PASS.

### Task 2: 완료 접수 Use Case와 멱등성

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSession.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/exception/DrawingErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/request/CompleteDrawingSessionRequest.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingCompletionResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingCompletionService.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/domain/DrawingSessionCompletionTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingCompletionServiceTest.java`

**Interfaces:**
- Consumes: Task 1의 `DrawingAnalysis.pending`, `Report.generating`과 Repository 조회
- Produces: `DrawingSession.canRequestCompletion()`, `DrawingSession.startReporting()`
- Produces: `DrawingCompletionService.complete(Long, String, CompleteDrawingSessionRequest)`

- [ ] **Step 1: 세션 상태 전이와 Service 정상·오류·멱등 시나리오 테스트를 작성한다.**

```java
DrawingCompletionResponse response = service.complete(100L, "completion-key", request);

assertThat(response.currentStage()).isEqualTo(DrawingStage.REPORTING);
assertThat(response.analysisStatus()).isEqualTo(DrawingAnalysisState.PENDING);
assertThat(response.reportStatus()).isEqualTo(ReportStatus.GENERATING);
verify(analysisRepository).saveAndFlush(any(DrawingAnalysis.class));
verify(reportRepository).saveAndFlush(any(Report.class));
```

다음 경계를 각각 독립 테스트한다.

- `requestReport=false`이면 Report를 저장하지 않고 nullable 응답을 반환
- 같은 Key와 같은 요청은 기존 분석·리포트 ID 반환
- 같은 Key와 다른 세션 또는 `requestReport`는 `IDEMPOTENCY_KEY_CONFLICT`
- FINAL Asset 없음은 `FINAL_ASSET_REQUIRED`
- REFLECTION 미도달은 `REFLECTION_REQUIRED`
- `conversationSkipped=false`인데 완료 대화 없음은 `DRAWING_CONVERSATION_NOT_COMPLETED`
- `conversationSkipped=true`인데 대화가 존재하면 동일 오류
- 이미 REPORTING 또는 COMPLETED이면 `DRAWING_SESSION_ALREADY_COMPLETED`

- [ ] **Step 2: 테스트를 실행해 구현 부재로 실패하는지 확인한다.**

```powershell
.\gradlew.bat --no-daemon test --tests "*DrawingSessionCompletionTest" --tests "*DrawingCompletionServiceTest"
```

Expected: 완료 접수 Type 또는 메서드 부재로 compile 실패.

- [ ] **Step 3: 요청·응답 계약과 세션 상태 전이를 구현한다.**

```java
public record CompleteDrawingSessionRequest(
    @NotNull Boolean conversationSkipped,
    @NotNull Boolean requestReport) {}

public void startReporting() {
  if (!canRequestCompletion()) {
    throw new IllegalStateException("현재 단계에서는 완료 처리를 접수할 수 없습니다.");
  }
  currentStage = DrawingStage.REPORTING;
}
```

응답은 `drawingSessionId`, `sessionStatus`, `currentStage`, `analysisId`, `analysisStatus`, `reportId`, `reportStatus` 순으로 선언한다.

- [ ] **Step 4: 완료 접수 전용 오류 코드를 추가한다.**

```java
FINAL_ASSET_REQUIRED(HttpStatus.CONFLICT, "DRAWING_409_013", "최종 그림이 필요합니다."),
REFLECTION_REQUIRED(HttpStatus.CONFLICT, "DRAWING_409_014", "감정 돌아보기 입력이 필요합니다."),
DRAWING_CONVERSATION_NOT_COMPLETED(
    HttpStatus.CONFLICT, "DRAWING_409_015", "대화 완료 또는 생략 상태가 올바르지 않습니다."),
DRAWING_SESSION_ALREADY_COMPLETED(
    HttpStatus.CONFLICT, "DRAWING_409_016", "그림 활동 완료가 이미 접수되었습니다."),
DRAWING_COMPLETION_CONFLICT(
    HttpStatus.CONFLICT, "DRAWING_409_017", "그림 활동 완료 접수 요청이 충돌했습니다.")
```

- [ ] **Step 5: 잠금과 DB 멱등성을 사용하는 Transaction Service를 구현한다.**

```java
@Transactional
public DrawingCompletionResponse complete(
    Long drawingSessionId,
    String idempotencyKey,
    CompleteDrawingSessionRequest request) {
  validateIdempotencyKey(idempotencyKey);
  Long guardianId = currentUserResolver.requireUserId();
  accessValidator.requireDrawingSessionAccess(guardianId, drawingSessionId);
  DrawingSession session = requireLockedSession(drawingSessionId);
  return findIdempotentResult(idempotencyKey, session, request)
      .orElseGet(() -> createCompletion(session, idempotencyKey, request));
}
```

`createCompletion`은 FINAL Asset과 대화 상태를 검증하고 분석, 선택적 리포트, `REPORTING` 전이를 차례로 저장한다. `DataIntegrityViolationException`은 Constraint 내용을 노출하지 않는 `DRAWING_COMPLETION_CONFLICT`로 변환한다.

- [ ] **Step 6: Service와 Domain 테스트를 다시 실행해 통과시킨다.**

```powershell
.\gradlew.bat --no-daemon test --tests "*DrawingSessionCompletionTest" --tests "*DrawingCompletionServiceTest"
```

Expected: 모든 대상 테스트 PASS.

### Task 3: HTTP 계약과 MySQL 원자성 검증

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingCompletionController.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingCompletionControllerTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/DrawingCompletionIntegrationTest.java`

**Interfaces:**
- Consumes: `DrawingCompletionService.complete`
- Produces: `POST /api/v1/drawing-sessions/{drawingSessionId}/complete`

- [ ] **Step 1: MockMvc 계약 테스트를 작성한다.**

```java
mockMvc.perform(post("/api/v1/drawing-sessions/100/complete")
        .header("Idempotency-Key", "completion-key")
        .contentType(APPLICATION_JSON)
        .content("""
            {"conversationSkipped":false,"requestReport":true}
            """))
    .andExpect(status().isAccepted())
    .andExpect(jsonPath("$.data.currentStage").value("REPORTING"))
    .andExpect(jsonPath("$.data.analysisStatus").value("PENDING"))
    .andExpect(jsonPath("$.data.reportStatus").value("GENERATING"));
```

Header 누락, Body Boolean 누락, `requestReport=false`의 nullable 필드도 검증한다.

- [ ] **Step 2: Controller 테스트가 Endpoint 부재로 실패하는지 확인한다.**

```powershell
.\gradlew.bat --no-daemon test --tests "*DrawingCompletionControllerTest"
```

Expected: HTTP 404 또는 Controller Type compile 실패.

- [ ] **Step 3: HTTP 202 Controller와 OpenAPI 문서를 구현한다.**

```java
@PostMapping
public ResponseEntity<ApiResponse<DrawingCompletionResponse>> complete(
    @PathVariable @Positive Long drawingSessionId,
    @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
    @Valid @RequestBody CompleteDrawingSessionRequest request) {
  return ResponseEntity.accepted()
      .body(ApiResponse.ok(service.complete(drawingSessionId, idempotencyKey, request)));
}
```

Controller는 요청 수신과 응답 조립만 수행하고 Repository나 Entity를 직접 사용하지 않는다.

- [ ] **Step 4: MySQL 통합 테스트를 작성한다.**

최종 그림, REFLECTION 세션, 완료 대화를 Fixture로 저장한 뒤 아래를 검증한다.

```java
DrawingCompletionResponse first = service.complete(sessionId, "completion-key", request);
DrawingCompletionResponse retry = service.complete(sessionId, "completion-key", request);

assertThat(retry.analysisId()).isEqualTo(first.analysisId());
assertThat(retry.reportId()).isEqualTo(first.reportId());
assertThat(analysisRepository.count()).isEqualTo(1);
assertThat(reportRepository.count()).isEqualTo(1);
assertThat(drawingSessionRepository.findById(sessionId).orElseThrow().getCurrentStage())
    .isEqualTo(DrawingStage.REPORTING);
```

`requestReport=false`도 별도 세션으로 실행해 분석만 한 건 생성되는지 확인한다.

- [ ] **Step 5: Endpoint와 통합 테스트를 실행해 통과시킨다.**

```powershell
.\gradlew.bat --no-daemon test --tests "*DrawingCompletionControllerTest" --tests "*DrawingCompletionIntegrationTest"
```

Expected: Docker 사용 가능 시 모든 대상 테스트 PASS. Docker를 사용할 수 없으면 Testcontainers 테스트만 미실행 사유를 기록하고 삭제하지 않는다.

### Task 4: 전체 품질 검증과 Git 통합

**Files:**
- Verify: `backend/src/main/java/com/ssafy/b209/analysis/**`
- Verify: `backend/src/main/java/com/ssafy/b209/drawing/**`
- Verify: `backend/src/main/java/com/ssafy/b209/report/**`
- Verify: `backend/src/test/java/com/ssafy/b209/**`
- Verify: `docs/superpowers/specs/2026-07-23-drawing-activity-completion-design.md`
- Verify: `docs/superpowers/plans/2026-07-23-drawing-activity-completion.md`

**Interfaces:**
- Consumes: Task 1~3의 Production과 Test 코드
- Produces: 검증된 S15P11B209-143 작업 Branch

- [ ] **Step 1: 전체 테스트를 새 Build 결과에서 실행한다.**

```powershell
.\gradlew.bat --no-daemon clean test
```

Expected: exit code 0이며 기존 테스트를 포함한 전체 Suite가 PASS.

- [ ] **Step 2: Java 형식을 검사하고 필요한 경우 Spotless를 적용한 뒤 재검사한다.**

```powershell
.\gradlew.bat --no-daemon spotlessCheck
```

Expected: exit code 0.

- [ ] **Step 3: UTF-8 Javadoc을 생성한다.**

```powershell
.\gradlew.bat --no-daemon javadoc
```

Expected: exit code 0이고 `backend/build/docs/javadoc/index.html`이 존재한다.

- [ ] **Step 4: 변경 범위와 공백 오류를 검사한다.**

```powershell
git diff --check
git status --short
git diff --name-only
```

Expected: `.idea/modules.xml`은 기존 사용자 변경으로 남고 Stage 대상에서 제외되며, 이슈 범위 밖 파일은 없다.

- [ ] **Step 5: 사용자가 이미 승인한 Git 작업 범위에 따라 Commit, Push, Merge Request 생성과 Merge를 수행한다.**

```powershell
git add backend/src/main backend/src/test docs/superpowers/specs/2026-07-23-drawing-activity-completion-design.md docs/superpowers/plans/2026-07-23-drawing-activity-completion.md
git commit -m "feat(drawing): S15P11B209-143 그림 활동 완료 접수 API 구현"
git push -u origin feature/S15P11B209-143-drawing-completion
```

Merge Request 제목은 `feat(drawing): S15P11B209-143 그림 활동 완료 접수 API 구현`, 대상 Branch는 `develop`, 원격 작업 Branch는 기록을 위해 유지한다.
