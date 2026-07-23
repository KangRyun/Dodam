# DRAFT Object Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 자동 저장된 `DRAFT` 그림의 객체 탐지를 허용하고 분석 범위를 `INTERMEDIATE`로 저장한다.

**Architecture:** 기존 `DrawingAnalysisPersistenceService`의 Transaction·중복 검증 경계를 유지하고 Asset 유형과 작업 유형을 분석 범위로 변환하는 규칙만 추가한다. 공개 API는 `OBJECT_DETECTION`만 허용하며 `DRAFT`는 `INTERMEDIATE`, `FINAL`은 `FINAL`로 저장한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, MySQL 8.4, JUnit 5, Mockito, MockMvc, Testcontainers

## Global Constraints

- 기존 Endpoint와 요청·응답 JSON 구조를 변경하지 않는다.
- 허용 조합은 `DRAFT + OBJECT_DETECTION`, `FINAL + OBJECT_DETECTION`뿐이다.
- 프론트엔드의 3초 debounce를 Backend Scheduler로 구현하지 않는다.
- 기존 Flyway Migration을 수정하거나 추가하지 않는다.
- 실제 AI Client 연동 방식과 동기식 결과 저장 흐름을 변경하지 않는다.
- `.idea/modules.xml` 사용자 변경을 Commit하지 않는다.

---

### Task 1: Asset 유형별 분석 범위 규칙

**Files:**
- Modify: `backend/src/test/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceServiceTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceService.java`

**Interfaces:**
- Consumes: `DrawingAssetType`, `DrawingAnalysisType`
- Produces: `DrawingAnalysisScope resolveScope(DrawingAssetType assetType, DrawingAnalysisType taskType)`

- [ ] **Step 1: 실패 테스트 작성**

다음 동작을 각각 검증한다.

```java
@Test
void startsIntermediateObjectDetectionForDraftAsset() {
  givenValidTarget();
  given(asset.getAssetType()).willReturn(DrawingAssetType.DRAFT);
  given(asset.getStorageKey()).willReturn("drawing/draft.png");
  given(asset.getMimeType()).willReturn("image/png");
  given(drawingAnalysisRepository.saveAndFlush(any(DrawingAnalysis.class)))
      .willAnswer(invocation -> invocation.getArgument(0));

  service.start(
      SESSION_ID,
      ASSET_ID,
      DrawingAnalysisType.OBJECT_DETECTION,
      "550e8400-e29b-41d4-a716-446655440000",
      REQUESTED_AT);

  ArgumentCaptor<DrawingAnalysis> captor = ArgumentCaptor.forClass(DrawingAnalysis.class);
  verify(drawingAnalysisRepository).saveAndFlush(captor.capture());
  assertThat(ReflectionTestUtils.getField(captor.getValue(), "scope"))
      .isEqualTo(DrawingAnalysisScope.INTERMEDIATE);
}
```

추가로 `FINAL + OBJECT_DETECTION → FINAL`, `DRAFT + ACTIVITY_REPORT → 409`,
`INTERMEDIATE + OBJECT_DETECTION → 409`를 검증한다.

- [ ] **Step 2: 실패 확인**

```powershell
gradlew.bat test --tests "*DrawingAnalysisPersistenceServiceTest"
```

Expected: DRAFT 허용 테스트가 `DRAWING_ANALYSIS_NOT_ALLOWED`로 실패한다.

- [ ] **Step 3: 최소 구현**

기존 동일 세션 검증 후 다음 규칙으로 범위를 계산한다.

```java
private DrawingAnalysisScope resolveScope(
    DrawingAssetType assetType, DrawingAnalysisType taskType) {
  if (taskType != DrawingAnalysisType.OBJECT_DETECTION) {
    throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
  }
  return switch (assetType) {
    case DRAFT -> DrawingAnalysisScope.INTERMEDIATE;
    case FINAL -> DrawingAnalysisScope.FINAL;
    default -> throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
  };
}
```

`DrawingAnalysis.processing(...)`에는 계산된 범위를 전달하고, 관련 Javadoc의 “최종 그림” 표현을 “허용된 그림 파일”로 수정한다.

- [ ] **Step 4: 단위 테스트 통과 확인**

```powershell
gradlew.bat test --tests "*DrawingAnalysisPersistenceServiceTest"
```

Expected: 모든 Persistence Service 테스트 통과.

### Task 2: 실제 MySQL 공개 API 회귀 검증

**Files:**
- Modify: `backend/src/test/java/com/ssafy/b209/analysis/DrawingAnalysisIntegrationTest.java`

**Interfaces:**
- Consumes: `POST /api/v1/drawing-sessions/{drawingSessionId}/analyses`
- Produces: DRAFT 분석 Row의 `analysis_type=INTERMEDIATE`

- [ ] **Step 1: DRAFT 통합 테스트 작성**

Setup에 DRAFT Asset `21`을 추가하고 다음을 검증한다.

```java
@Test
void storesDraftObjectDetectionAsIntermediateAnalysis() throws Exception {
  given(drawingAnalysisClient.analyze(any()))
      .willAnswer(
          invocation -> {
            DrawingAnalysisRequest request = invocation.getArgument(0);
            return successResponse(request.requestId());
          });

  mockMvc.perform(request(21L, "OBJECT_DETECTION")).andExpect(status().isCreated());

  assertThat(
          jdbcTemplate.queryForObject(
              "SELECT analysis_type FROM analyses WHERE drawing_asset_id = 21", String.class))
      .isEqualTo("INTERMEDIATE");
}
```

`request()` Helper는 Asset ID와 작업 유형을 받도록 변경한다. DRAFT의 `ACTIVITY_REPORT` 요청은 `409`이고 AI Client를 호출하지 않는 테스트도 추가한다.

- [ ] **Step 2: 통합 테스트 실행**

```powershell
gradlew.bat test --tests "*DrawingAnalysisIntegrationTest"
```

Expected: DRAFT 객체 탐지, 금지 조합 및 기존 FINAL 회귀 테스트 모두 통과.

### Task 3: 공개 계약과 Javadoc 정합화

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/controller/DrawingAnalysisController.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisService.java`
- Modify: `docs/api/ai-drawing-analysis-contract.md`

**Interfaces:**
- Consumes: Task 1의 허용 조합
- Produces: Swagger·Javadoc·AI 계약 문서의 동일한 설명

- [ ] **Step 1: Controller와 Service 설명 수정**

“최종 그림만 분석” 설명을 다음 의미로 변경한다.

- DRAFT 자동 저장 그림과 FINAL 그림의 객체 탐지 지원
- DRAFT 분석은 중간 분석으로 저장
- 공개 요청은 `OBJECT_DETECTION`만 지원
- 3초 debounce는 Client 책임

- [ ] **Step 2: 계약 문서 수정**

`docs/api/ai-drawing-analysis-contract.md`에 다음 표를 추가한다.

```markdown
| Asset 유형 | 요청 가능 작업 | 저장 분석 범위 |
| --- | --- | --- |
| `DRAFT` | `OBJECT_DETECTION` | `INTERMEDIATE` |
| `FINAL` | `OBJECT_DETECTION` | `FINAL` |
```

`INTERMEDIATE`, `UPLOADED`, `THUMBNAIL`, `TIMELAPSE` 및 공개 `ACTIVITY_REPORT`
요청은 거부된다고 기록한다. 마지막 자동 저장 성공 후 3초 debounce는 프론트엔드 책임임을 명시한다.

- [ ] **Step 3: 변경 범위 검사**

```powershell
git diff --check
git status --short
```

Expected: 144번 파일과 별도 `.idea/modules.xml` 변경만 존재.

### Task 4: 전체 검증과 기능 Commit

**Files:**
- Verify: 전체 Backend
- Preserve: `.idea/modules.xml`

**Interfaces:**
- Consumes: Task 1~3
- Produces: 검증 완료된 S15P11B209-144 후속 수정 Commit

- [ ] **Step 1: 전체 테스트**

```powershell
gradlew.bat clean test
```

Expected: `BUILD SUCCESSFUL`, 0 failures, 0 errors.

- [ ] **Step 2: 형식과 Javadoc**

```powershell
gradlew.bat spotlessCheck
gradlew.bat javadoc
```

Expected: 모두 `BUILD SUCCESSFUL`, `backend/build/docs/javadoc/index.html` 생성.

- [ ] **Step 3: 명시적 Stage와 Commit**

```powershell
git add -- backend/src/main/java/com/ssafy/b209/analysis/controller/DrawingAnalysisController.java backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisService.java backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceService.java backend/src/test/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceServiceTest.java backend/src/test/java/com/ssafy/b209/analysis/DrawingAnalysisIntegrationTest.java docs/api/ai-drawing-analysis-contract.md docs/superpowers/plans/2026-07-23-draft-object-detection.md
git commit -m "fix(analysis): S15P11B209-144 DRAFT 객체 탐지 허용"
```

- [ ] **Step 4: Push·MR·Merge**

MR 제목:

```text
fix(analysis): S15P11B209-144 DRAFT 객체 탐지 허용
```

Merge 성공 후 원격 수정 브랜치를 삭제하고 Jira 144를 다시 완료로 전환한다.
