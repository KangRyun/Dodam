# AI Analysis Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spring Boot 그림 분석 Client와 결과 저장을 `POST /internal/v1/analyses`의 §19.3·§19.4 계약에 맞춘다.

**Architecture:** 공개 API와 Application Service는 기존 경계를 유지하고, AI 전용 계약 DTO와 이미지 URL Provider를 Infrastructure에 둔다. HTTP Adapter가 내부 명령을 정본 JSON으로 변환하며, Persistence Service는 정규화된 결과를 한 Transaction에서 저장한다. 실제 이미지 URL Provider와 운영 HTTP 활성화는 S15P11B209-372가 담당한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring RestClient, Spring Data JPA, JdbcTemplate, Flyway, JUnit 5, AssertJ, MockRestServiceServer

## Global Constraints

- 기본 `app.ai.drawing-analysis.mode`는 `mock`으로 유지한다.
- 실제 Secret, Token, signed URL, 이미지·아동 발화를 로그나 오류 응답에 남기지 않는다.
- 기존 적용 Flyway Migration은 수정하지 않고 새 Migration만 추가한다.
- 공개 `/api/v1/**` URI와 요청·응답 형식은 변경하지 않는다.
- 새 Production Type과 공개 메서드에는 실제 책임과 일치하는 한국어 Javadoc을 작성한다.
- 모든 기능 변경은 실패하는 테스트를 먼저 확인한 후 구현한다.

---

### Task 1: 정본 AI 요청·응답 계약

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/contract/AiDrawingAnalysisRequest.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/contract/AiDrawingAnalysisResponse.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/dto/DrawingAnalysisRequest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/dto/DrawingAnalysisResponse.java`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/AiDrawingAnalysisContractTest.java`

**Interfaces:**
- Consumes: `DrawingAnalysisRequest`의 요청 추적 UUID, 분석 ID, 세션 ID, 분석 범위, 이미지 저장 Metadata
- Produces: §19.3 JSON Body와 §19.4 전체 응답을 표현하는 불변 Record

- [ ] **Step 1: 실패하는 JSON 계약 테스트 작성**

```java
assertThatJson(objectMapper.writeValueAsString(request))
    .node("analysisId").isEqualTo(701);
assertThatJson(json).node("drawing.signedUrl").isEqualTo("https://signed.example/image");
assertThat(response.detectedObjects()).singleElement()
    .extracting(AiDetectedObject::objectCode).isEqualTo("HOUSE");
```

- [ ] **Step 2: 테스트가 구 계약 필드 때문에 실패하는지 확인**

Run: `gradlew.bat test --tests "*AiDrawingAnalysisContractTest"`

Expected: `analysisId`, `drawing`, `detectedObjects`, `modelInfo` 타입 또는 필드가 없어 컴파일 실패

- [ ] **Step 3: 최소 정본 계약 구현**

```java
public record AiDrawingAnalysisRequest(
    Long analysisId,
    Long drawingSessionId,
    DrawingAnalysisScope analysisType,
    String triggerReason,
    DrawingInput drawing) {}

public record AiDrawingAnalysisResponse(
    Long analysisId,
    AiDrawingAnalysisStatus status,
    ModelInfo modelInfo,
    List<DetectedObject> detectedObjects,
    VisualFeatures visualFeatures,
    BehaviorFeatures behaviorFeatures,
    ConversationSummary conversationSummary,
    ObservationDraft observationDraft,
    List<EvidenceReference> evidenceReferences,
    List<UnusedInput> unusedInputs,
    List<String> warnings,
    Long processingTimeMs) {}
```

- [ ] **Step 4: 계약 테스트 통과 확인**

Run: `gradlew.bat test --tests "*AiDrawingAnalysisContractTest"`

Expected: PASS

### Task 2: Endpoint·인증·이미지 URL 경계

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisImageUrlProvider.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/UnavailableDrawingAnalysisImageUrlProvider.java`
- Modify: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientProperties.java`
- Modify: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientConfig.java`
- Modify: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/RestClientDrawingAnalysisClient.java`
- Modify: `backend/src/main/resources/application.yml`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/RestClientDrawingAnalysisClientTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientPropertiesTest.java`

**Interfaces:**
- Consumes: `DrawingAnalysisImageUrlProvider#createReadUrl(String)`과 `AI_INTERNAL_TOKEN`
- Produces: `/internal/v1/analyses` JSON 요청, `X-Internal-Token`, `X-Request-Id`

- [ ] **Step 1: 실패하는 HTTP 요청 테스트 작성**

```java
server.expect(requestTo("/internal/v1/analyses"))
    .andExpect(header("X-Internal-Token", "internal-token"))
    .andExpect(header("X-Request-Id", REQUEST_ID))
    .andExpect(jsonPath("$.analysisId").value(701));
```

- [ ] **Step 2: 기존 Client가 구 경로·무인증 요청을 보내 테스트가 실패하는지 확인**

Run: `gradlew.bat test --tests "*RestClientDrawingAnalysisClientTest"`

Expected: Header 또는 JSON Path 기대 불일치

- [ ] **Step 3: Provider와 HTTP Adapter 구현**

```java
public interface DrawingAnalysisImageUrlProvider {
  URI createReadUrl(String storageKey);
}

restClient.post()
    .uri(endpointPath)
    .header("X-Internal-Token", internalToken)
    .header("X-Request-Id", request.requestId())
    .body(toAiRequest(request));
```

- [ ] **Step 4: HTTP·설정 테스트 통과 확인**

Run: `gradlew.bat test --tests "*RestClientDrawingAnalysisClientTest" --tests "*DrawingAnalysisClientPropertiesTest" --tests "*DrawingAnalysisClientConfigTest"`

Expected: PASS

### Task 3: 정규화 결과 Schema

**Files:**
- Create: `backend/src/main/resources/db/migration/V10__align_ai_analysis_results.sql`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/repository/DrawingAnalysisRepositoryTest.java`

**Interfaces:**
- Consumes: §19.4의 구성요소별 Model, 정규화 Bounding Box, 경고, 관찰·후속 질문
- Produces: 손실 없는 정규화 저장 Table과 0~1 Bounding Box 제약

- [ ] **Step 1: 실패하는 Repository Schema 테스트 작성**

```java
jdbcTemplate.update(
    "INSERT INTO analysis_warnings (analysis_id, warning_order, warning_code) VALUES (?, ?, ?)",
    analysisId, 0, "PRESSURE_DATA_UNAVAILABLE");
assertThat(jdbcTemplate.queryForObject(
    "SELECT COUNT(*) FROM analysis_warnings WHERE analysis_id = ?", Integer.class, analysisId))
    .isOne();
```

- [ ] **Step 2: 새 Table이 없어 테스트가 실패하는지 확인**

Run: `gradlew.bat test --tests "*DrawingAnalysisRepositoryTest"`

Expected: `analysis_warnings` Table not found

- [ ] **Step 3: 새 Migration 작성**

```sql
ALTER TABLE analysis_detected_objects
    MODIFY COLUMN bbox_x DECIMAL(8,6) NULL,
    MODIFY COLUMN bbox_y DECIMAL(8,6) NULL,
    MODIFY COLUMN bbox_width DECIMAL(8,6) NULL,
    MODIFY COLUMN bbox_height DECIMAL(8,6) NULL;

CREATE TABLE analysis_model_components (...);
CREATE TABLE analysis_warnings (...);
CREATE TABLE analysis_observation_items (...);
```

- [ ] **Step 4: MySQL/H2 호환 Repository 테스트 통과 확인**

Run: `gradlew.bat test --tests "*DrawingAnalysisRepositoryTest"`

Expected: PASS

### Task 4: 종합 결과 저장과 상태 전이

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/analysis/repository/AnalysisResultJdbcRepository.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/domain/DrawingAnalysis.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/domain/DrawingDetectedObject.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisService.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/domain/DrawingAnalysisDomainTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceServiceTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/service/DrawingAnalysisServiceTest.java`

**Interfaces:**
- Consumes: `AiDrawingAnalysisResponse`
- Produces: `SUCCESS` 또는 `PARTIAL_SUCCESS` 분석과 정규화된 모든 결과 행

- [ ] **Step 1: PARTIAL_SUCCESS와 종합 결과 저장 실패 테스트 작성**

```java
analysis.complete(
    DrawingAnalysisState.PARTIAL_SUCCESS,
    "yolo",
    "1.0.0",
    detections,
    completedAt);
assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.PARTIAL_SUCCESS);
```

- [ ] **Step 2: 기존 `succeed`가 부분 성공을 표현하지 못해 실패하는지 확인**

Run: `gradlew.bat test --tests "*DrawingAnalysisDomainTest" --tests "*DrawingAnalysisPersistenceServiceTest" --tests "*DrawingAnalysisServiceTest"`

Expected: 새 완료 메서드 또는 저장 Repository가 없어 컴파일 실패

- [ ] **Step 3: 상태 전이와 정규화 결과 저장 구현**

```java
public void complete(
    DrawingAnalysisState completedState,
    String modelName,
    String modelVersion,
    List<DrawingDetectedObject> detectedObjects,
    LocalDateTime completedAt) {
  if (completedState != DrawingAnalysisState.SUCCESS
      && completedState != DrawingAnalysisState.PARTIAL_SUCCESS) {
    throw new IllegalArgumentException("completedState must be a success state");
  }
  // 기존 PROCESSING 검증과 Detection 연결 후 completedState 저장
}
```

- [ ] **Step 4: Service·Persistence 테스트 통과 확인**

Run: `gradlew.bat test --tests "*DrawingAnalysisDomainTest" --tests "*DrawingAnalysisPersistenceServiceTest" --tests "*DrawingAnalysisServiceTest"`

Expected: PASS

### Task 5: Mock·대화 객체 연결·문서·전체 검증

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/MockDrawingAnalysisClient.java`
- Modify: `backend/src/main/java/com/ssafy/b209/conversation/service/ConversationNextQuestionService.java`
- Modify: `README.md`
- Modify: `docs/api/ai-drawing-analysis-contract.md`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/MockDrawingAnalysisClientTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/conversation/service/ConversationNextQuestionServiceTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/DrawingAnalysisIntegrationTest.java`

**Interfaces:**
- Consumes: 저장된 정규화 객체 탐지 결과
- Produces: 결정적 Mock 종합 결과와 다음 질문 Client의 `detectedObjects`

- [ ] **Step 1: Mock 정본 응답과 저장 객체 전달 테스트 작성**

```java
assertThat(mockResponse.status()).isEqualTo(AiDrawingAnalysisStatus.PARTIAL_SUCCESS);
assertThat(request.detectedObjects()).extracting(DetectedObject::objectCode)
    .contains("HOUSE");
```

- [ ] **Step 2: 기존 픽셀 Mock과 빈 객체 목록 때문에 실패하는지 확인**

Run: `gradlew.bat test --tests "*MockDrawingAnalysisClientTest" --tests "*ConversationNextQuestionServiceTest"`

Expected: 상태·좌표·객체 목록 기대 불일치

- [ ] **Step 3: Mock과 객체 조회, 제한 문서 구현**

```java
return new DrawingAnalysisResponse(
    request.analysisId(),
    AiDrawingAnalysisStatus.PARTIAL_SUCCESS,
    modelInfo,
    normalizedDetections,
    visualFeatures,
    behaviorFeatures,
    null,
    null,
    List.of(),
    unusedInputs,
    List.of("PRESSURE_DATA_UNAVAILABLE"),
    0L);
```

- [ ] **Step 4: 관련 테스트 통과 확인**

Run: `gradlew.bat test --tests "*MockDrawingAnalysisClientTest" --tests "*ConversationNextQuestionServiceTest" --tests "*DrawingAnalysisIntegrationTest"`

Expected: PASS

- [ ] **Step 5: 전체 검증**

Run:

```powershell
gradlew.bat clean test
gradlew.bat spotlessCheck
gradlew.bat javadoc
```

Expected: 모든 명령 성공, `backend/build/docs/javadoc/index.html` 생성
