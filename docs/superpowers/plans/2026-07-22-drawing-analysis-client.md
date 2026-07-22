# Drawing Analysis AI Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `S15P11B209-144` 계약 DTO로 그림 분석 AI 서버를 호출하는 설정 기반 동기식 `RestClient` 어댑터를 구현한다.

**Architecture:** `infrastructure.ai.drawing`에 Application 경계 Interface와 HTTP 어댑터를 분리한다. 전용 `ConfigurationProperties`와 `RestClient` Bean을 사용하고, 요청·응답을 Bean Validation으로 검증한 뒤 HTTP 및 전송 오류를 안전한 Client Exception 유형으로 변환한다. 연결 설정의 불변 조건은 기존 `ImageStorageProperties`와 동일하게 compact constructor에서 검증한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring `RestClient`, Jakarta Bean Validation, JUnit 5, AssertJ, `MockRestServiceServer`

## Global Constraints

- 브랜치명에는 Jira 이슈 코드를 넣지 않고 `feat/drawing-analysis-client`를 사용한다.
- 144번 DTO를 변경하거나 복제하지 않는다.
- 실제 AI 서버, DB, Entity, Repository, Controller, Application Service와 Production Mock을 구현하지 않는다.
- Retry, Circuit Breaker, Fallback, 비동기 처리와 인증 Header를 추가하지 않는다.
- 전체 Request/Response, Storage Key, 서버 URL·경로와 AI 오류 원문을 로그·Exception 메시지에 포함하지 않는다.
- 사용자의 별도 요청 전까지 commit, push, merge를 수행하지 않는다.

---

### Task 1: Client 설정 계약

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientProperties.java`
- Create: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientPropertiesTest.java`
- Modify: `backend/src/main/resources/application.yml`

**Interfaces:**
- Produces: `DrawingAnalysisClientProperties(URI baseUrl, String endpointPath, Duration connectTimeout, Duration readTimeout)`
- Consumes: Spring Boot Configuration Properties Binding과 Jakarta Validation

- [ ] **Step 1: 설정 Binding 실패 테스트 작성**

`ApplicationContextRunner`와 `@EnableConfigurationProperties(DrawingAnalysisClientProperties.class)`로 기본값 Binding 성공, 비 HTTP 절대 URI, 완전한 Endpoint URL, 0 이하 Timeout의 Context 시작 실패를 검증한다.

```java
assertThat(context).hasNotFailed();
assertThat(context.getBean(DrawingAnalysisClientProperties.class).endpointPath())
    .isEqualTo("/internal/ai/v1/drawings/analysis");
```

- [ ] **Step 2: 테스트가 타입 부재로 실패하는지 확인**

Run: `gradlew.bat test --tests "*DrawingAnalysisClientPropertiesTest"`

Expected: `DrawingAnalysisClientProperties`를 찾지 못해 실패한다.

- [ ] **Step 3: 설정 타입과 기본 YAML 구현**

```java
@ConfigurationProperties(prefix = "app.ai.drawing-analysis")
public record DrawingAnalysisClientProperties(
    URI baseUrl, String endpointPath, Duration connectTimeout, Duration readTimeout) {

  public DrawingAnalysisClientProperties {
    // Base URL, Endpoint Path와 양수 Timeout 불변 조건을 검증한다.
  }
}
```

`application.yml`에는 `AI_DRAWING_ANALYSIS_BASE_URL`, `AI_DRAWING_ANALYSIS_ENDPOINT_PATH`, `AI_DRAWING_ANALYSIS_CONNECT_TIMEOUT`, `AI_DRAWING_ANALYSIS_READ_TIMEOUT` 기본값을 추가한다.

- [ ] **Step 4: 설정 테스트 통과 확인**

Run: `gradlew.bat test --tests "*DrawingAnalysisClientPropertiesTest"`

Expected: 설정 테스트가 모두 통과한다.

---

### Task 2: Client 경계와 전용 RestClient Bean

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClient.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientException.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientConfig.java`
- Create: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientConfigTest.java`

**Interfaces:**
- Produces: `DrawingAnalysisResponse analyze(DrawingAnalysisRequest request)`
- Produces: `DrawingAnalysisClientException.Type`의 `REQUEST_FAILED`, `TIMEOUT`, `INVALID_RESPONSE`, `SERVER_ERROR`
- Produces: `drawingAnalysisRestClient` Bean
- Consumes: Task 1의 `DrawingAnalysisClientProperties`

- [ ] **Step 1: RestClient Bean 무호출 테스트 작성**

설정된 Base URL이 응답하지 않는 주소여도 `ApplicationContextRunner`가 전용 `RestClient`와 Properties Bean을 생성하고 실패하지 않는지 검증한다. Context 생성 과정에서 HTTP 요청을 수행하지 않는다.

- [ ] **Step 2: 테스트가 Client 타입 부재로 실패하는지 확인**

Run: `gradlew.bat test --tests "*DrawingAnalysisClientConfigTest"`

Expected: Client와 Config 타입 부재로 실패한다.

- [ ] **Step 3: Interface, Exception, Config 최소 구현**

```java
public interface DrawingAnalysisClient {
  DrawingAnalysisResponse analyze(DrawingAnalysisRequest request);
}
```

Config는 `SimpleClientHttpRequestFactory`에 설정의 Connect/Read Timeout을 적용하고 `RestClient.Builder.baseUrl(...)`로 전용 Bean을 만든다. HTTP 어댑터 Bean은 Task 3에서 추가한다.

- [ ] **Step 4: Context 테스트 통과 확인**

Run: `gradlew.bat test --tests "*DrawingAnalysisClientConfigTest"`

Expected: Context가 네트워크 없이 시작되고 설정 및 전용 `RestClient` Bean이 존재한다.

---

### Task 3: 정상 응답과 계약 Validation

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/RestClientDrawingAnalysisClient.java`
- Create: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/RestClientDrawingAnalysisClientTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientConfig.java`

**Interfaces:**
- Consumes: `DrawingAnalysisRequest`, `DrawingAnalysisResponse`, `RestClient`, `Validator`, Endpoint Path
- Produces: 유효한 2xx `DrawingAnalysisResponse`

- [ ] **Step 1: 정상 흐름 RED 테스트 작성**

`MockRestServiceServer`로 POST URI, `Content-Type`, 144번 요청 JSON을 검증하고 일반 성공, 빈 `detections`, 계약상 `FAILED` 응답이 그대로 반환되는지 테스트한다. 잘못된 요청은 서버 호출 전에 `REQUEST_FAILED`가 발생하는지도 검증한다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `gradlew.bat test --tests "*RestClientDrawingAnalysisClientTest"`

Expected: HTTP 어댑터 부재로 실패한다.

- [ ] **Step 3: 정상 호출과 Bean Validation 구현**

```java
DrawingAnalysisResponse response =
    restClient.post()
        .uri(endpointPath)
        .contentType(MediaType.APPLICATION_JSON)
        .body(request)
        .retrieve()
        .body(DrawingAnalysisResponse.class);
```

호출 전 요청 Validation, 역직렬화 후 응답 Validation을 수행한다. `response == null` 또는 응답 위반은 `INVALID_RESPONSE`로 변환하고, 유효한 `FAILED` 응답은 반환한다. Config에는 전용 `RestClient`, `Validator`, Properties로 `DrawingAnalysisClient`를 생성하는 Bean을 추가한다.

- [ ] **Step 4: 정상 흐름 테스트 통과 확인**

Run: `gradlew.bat test --tests "*RestClientDrawingAnalysisClientTest"`

Expected: 정상 흐름과 계약 Validation 테스트가 통과한다.

---

### Task 4: HTTP·전송·역직렬화 오류 매핑

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/RestClientDrawingAnalysisClient.java`
- Modify: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/RestClientDrawingAnalysisClientTest.java`

**Interfaces:**
- Produces: 3xx·4xx=`REQUEST_FAILED`, 5xx=`SERVER_ERROR`, Timeout=`TIMEOUT`, 잘못된 응답=`INVALID_RESPONSE`

- [ ] **Step 1: 오류별 RED 테스트 작성**

302, 400, 500, 빈 Body, 잘못된 JSON, 알 수 없는 Enum, 응답 Validation 위반, 요청과 다른 `requestId`, `ConnectException`, Connect/Read `SocketTimeoutException`을 각각 Stub하고 정확한 Exception Type과 안전한 메시지를 검증한다.

```java
assertThatThrownBy(() -> client.analyze(request))
    .isInstanceOfSatisfying(
        DrawingAnalysisClientException.class,
        exception -> assertThat(exception.getType()).isEqualTo(expectedType));
```

- [ ] **Step 2: 새 오류 테스트 실패 확인**

Run: `gradlew.bat test --tests "*RestClientDrawingAnalysisClientTest"`

Expected: 아직 분류되지 않은 오류 사례가 실패한다.

- [ ] **Step 3: 최소 오류 매핑 구현**

`onStatus`에서 모든 non-2xx를 전용 Exception으로 변환하고 5xx만 `SERVER_ERROR`, 나머지는 `REQUEST_FAILED`로 분류한다. `ResourceAccessException` Cause Chain에 Timeout 예외가 있으면 `TIMEOUT`, 그 밖의 연결 실패는 `REQUEST_FAILED`로 변환한다. 그 외 JSON/메시지 변환 오류와 `requestId` 불일치는 `INVALID_RESPONSE`로 변환한다. Exception 메시지는 `Type.name()`만 사용한다.

- [ ] **Step 4: 오류 테스트 통과 확인**

Run: `gradlew.bat test --tests "*RestClientDrawingAnalysisClientTest"`

Expected: 모든 오류 유형과 비노출 assertion이 통과한다.

---

### Task 5: 문서와 전체 검증

**Files:**
- Modify: `docs/api/ai-drawing-analysis-contract.md`
- Modify: `docs/superpowers/specs/2026-07-22-drawing-analysis-client-design.md` only if implementation reveals a verified discrepancy

**Interfaces:**
- Documents: Client Interface, `RestClient` 구현, 환경 변수, Endpoint, Timeout, 오류 매핑, Storage 제한 및 후속 범위

- [ ] **Step 1: 계약 문서 보완**

실제 운영 연결이 검증되지 않았고 테스트는 `MockRestServiceServer`만 사용한다는 제한을 명시한다. 실제 Secret이나 로컬 절대 경로는 기록하지 않는다.

- [ ] **Step 2: Spotless 적용 후 변경 범위 확인**

Run: `gradlew.bat spotlessApply`

Run: `git diff --check`

Expected: 형식 오류가 없고 DB·Entity·Repository·Controller 변경이 없다.

- [ ] **Step 3: 전체 검증 실행**

Run: `gradlew.bat clean test`

Run: `gradlew.bat spotlessCheck`

Run: `gradlew.bat javadoc --rerun-tasks`

Expected: 모든 명령이 성공하고 `backend/build/docs/javadoc/index.html`이 생성된다. 기존 범위 밖 경고는 발생 파일과 개수를 별도 보고한다.

- [ ] **Step 4: Git 상태와 후속 범위 확인**

실제 AI 호출, Production Mock, DB 변경, Controller, Retry가 포함되지 않았고 브랜치가 `feat/drawing-analysis-client`인지 확인한다. Commit·push는 수행하지 않고 권장 메시지 `[S15P11B209-145] feat(ai): 그림 분석 AI Client 구조 구현`만 보고한다.
