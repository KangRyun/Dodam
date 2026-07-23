# Mock Drawing Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 실제 AI 서버 호출 없이 기존 그림 분석 계약에 맞는 결정적인 Mock 결과를 반환하고 Property로 Mock/HTTP 구현체를 안전하게 선택한다.

**Architecture:** 기존 `DrawingAnalysisClient` 경계와 HTTP Adapter를 유지하고 같은 Package에 독립적인 Mock Adapter를 추가한다. `app.ai.drawing-analysis.mode` 값으로 두 구현체의 Bean 생성을 상호 배타적으로 제어하며, Mock은 기존 `Validator`와 UTC `Clock`을 주입받는다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Gradle 8.14.3, Jakarta Bean Validation, JUnit 5, AssertJ, Jackson

## Global Constraints

- Branch 이름에는 Jira 코드를 넣지 않으며 사용자 요청 전 Commit·Push·Merge를 수행하지 않는다.
- 기존 S15P11B209-144 DTO와 Enum을 수정하거나 중복 생성하지 않는다.
- `RestClientDrawingAnalysisClient`의 HTTP 처리 코드는 변경하지 않는다.
- Entity, Repository, Service, Controller, Flyway Migration과 새 Library를 추가하지 않는다.
- 실제 네트워크 요청, Random, 외부 Fixture 파일, 개인정보와 서버 절대 경로를 사용하지 않는다.
- 주요 Production Type과 공개 메서드에는 실제 책임에 맞는 한국어 Javadoc을 작성한다.

---

### Task 1: Client mode 설정과 Bean 선택

**Files:**
- Modify: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientPropertiesTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientConfigTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientProperties.java`
- Modify: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientConfig.java`
- Modify: `backend/src/main/resources/application.yml`

**Interfaces:**
- Consumes: 기존 `DrawingAnalysisClient`, `RestClientDrawingAnalysisClient`, `Validator`, `Clock`
- Produces: `DrawingAnalysisClientProperties#mode()`과 상호 배타적인 Mock/HTTP Client Bean

- [ ] **Step 1: mode 기본값과 잘못된 값에 대한 실패 테스트 작성**

  `DrawingAnalysisClientPropertiesTest`에서 기본 설정의 `mode()`가 `mock`인지 확인하고 `app.ai.drawing-analysis.mode=unknown` Context가 실패하는 테스트를 추가한다.

- [ ] **Step 2: Bean 선택 실패 테스트 작성**

  `DrawingAnalysisClientConfigTest`에서 `mode=mock`은 `MockDrawingAnalysisClient` 하나만, `mode=http`은 `RestClientDrawingAnalysisClient` 하나만 생성하며 잘못된 mode는 Context 시작에 실패하는지 검증한다. Mock Context에는 고정 `Clock` Bean을 제공하고 Base URL은 연결할 수 없는 `127.0.0.1:1`을 사용해 시작 중 네트워크 호출이 없음을 확인한다.

- [ ] **Step 3: RED 확인**

  Run: `gradlew.bat test --tests "*DrawingAnalysisClientPropertiesTest" --tests "*DrawingAnalysisClientConfigTest"`

  Expected: `mode()` 또는 `MockDrawingAnalysisClient`가 없어 Compile/Test 실패

- [ ] **Step 4: 최소 설정 구현**

  `DrawingAnalysisClientProperties`에 `String mode`를 추가하고 compact constructor에서 `mock`, `http`만 허용한다. `application.yml`에는 아래 기본값을 추가한다.

  ```yaml
  mode: ${AI_DRAWING_ANALYSIS_MODE:mock}
  ```

  `DrawingAnalysisClientConfig`의 HTTP 전용 `RestClient`와 Client Bean에는 `havingValue = "http"`, 신규 Mock Bean에는 `havingValue = "mock"`인 `@ConditionalOnProperty`를 적용한다. Mock Bean은 `Validator`와 `Clock`을 생성자에 전달한다.

- [ ] **Step 5: GREEN 확인**

  Run: `gradlew.bat test --tests "*DrawingAnalysisClientPropertiesTest" --tests "*DrawingAnalysisClientConfigTest"`

  Expected: 모든 설정 및 Bean 선택 테스트 통과

---

### Task 2: 결정적인 MockDrawingAnalysisClient

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/MockDrawingAnalysisClientTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/MockDrawingAnalysisClient.java`

**Interfaces:**
- Consumes: `DrawingAnalysisClient#analyze(DrawingAnalysisRequest)`, 기존 계약 DTO, `Validator`, `Clock`
- Produces: `MockDrawingAnalysisClient(Validator, Clock)`와 `SUCCEEDED` Mock 응답

- [ ] **Step 1: 정상 응답 실패 테스트 작성**

  고정 Clock `2026-07-22T05:00:00Z`와 유효한 요청으로 호출해 다음을 검증한다.

  ```text
  status=SUCCEEDED
  response.requestId=request.requestId
  model=mock-drawing-detector/1.0
  labels=HOUSE,TREE
  confidence=0.95,0.91
  boxes=(120,80,640,520),(820,120,380,700)
  error=null
  processedAt=2026-07-22T05:00:00Z
  ```

- [ ] **Step 2: 결정성·불변성·계약 실패 테스트 작성**

  동일 요청을 두 번 호출한 응답이 같고 탐지 목록이 변경 불가능한지 확인한다. null 요청과 requestId·ID·imageReference·analysisType이 유효하지 않은 요청은 `DrawingAnalysisClientException.Type.REQUEST_FAILED`로 실패해야 한다.

- [ ] **Step 3: Jackson 계약 실패 테스트 작성**

  Mock 응답을 `JsonMapper`로 직렬화 후 `DrawingAnalysisResponse`로 역직렬화하고 `SUCCEEDED`, `OBJECT_DETECTION`, 필수 필드와 기존 Validator 계약을 확인한다.

- [ ] **Step 4: RED 확인**

  Run: `gradlew.bat test --tests "*MockDrawingAnalysisClientTest"`

  Expected: `MockDrawingAnalysisClient`가 없어 Compile 실패

- [ ] **Step 5: 최소 Mock 구현**

  `MockDrawingAnalysisClient`는 HTTP Client를 상속하거나 참조하지 않는다. 요청을 기존 Validator로 검사한 뒤 `List.of`로 고정 탐지 결과를 만들고 `Instant.now(clock)`을 사용해 기존 `DrawingAnalysisResponse` 생성자로 응답한다. JSON 문자열, Random, 파일 I/O와 요청별 Logging은 사용하지 않는다.

- [ ] **Step 6: GREEN 및 회귀 확인**

  Run: `gradlew.bat test --tests "*MockDrawingAnalysisClientTest" --tests "*RestClientDrawingAnalysisClientTest"`

  Expected: Mock과 기존 HTTP Client 테스트 모두 통과

---

### Task 3: 문서화와 전체 검증

**Files:**
- Modify: `docs/api/ai-drawing-analysis-contract.md`

**Interfaces:**
- Consumes: 최종 mode 설정과 Mock Fixture 값
- Produces: 개발자가 Mock/HTTP 구현을 선택할 수 있는 운영 문서

- [ ] **Step 1: 계약 문서 보완**

  `AI_DRAWING_ANALYSIS_MODE`, 기본 `mock`, 허용 값, 모델 `mock-drawing-detector/1.0`, `HOUSE`·`TREE` 고정 결과, 실제 분석 정확도를 의미하지 않음, 실제 HTTP 서버를 호출하지 않음과 `http` 전환 방법을 기록한다.

- [ ] **Step 2: 형식 정리와 변경 범위 확인**

  Run: `gradlew.bat spotlessApply` 후 `git diff --check`, `git status --short`

  Expected: 공백 오류가 없고 Controller·Service·Entity·Repository·Migration 변경 없음

- [ ] **Step 3: 전체 테스트**

  Run: `gradlew.bat clean test`

  Expected: 모든 테스트 통과

- [ ] **Step 4: Spotless 검증**

  Run: `gradlew.bat spotlessCheck`

  Expected: `BUILD SUCCESSFUL`

- [ ] **Step 5: Javadoc 검증**

  Run: `gradlew.bat javadoc --rerun-tasks`

  Expected: `BUILD SUCCESSFUL`, `build/docs/javadoc/index.html`과 Mock Client 문서 생성. 기존 코드 경고와 신규 경고를 구분해 보고한다.

- [ ] **Step 6: 결과 보고 준비**

  테스트 수, 실패 수, Client 선택 방식, Mock Fixture, HTTP 호출 여부, DB 변경 여부와 후속 S15P11B209-147 범위를 정리한다. Commit과 Push는 수행하지 않고 권장 메시지 `[S15P11B209-146] feat(ai): Mock 그림 분석 결과 구현`만 제시한다.
