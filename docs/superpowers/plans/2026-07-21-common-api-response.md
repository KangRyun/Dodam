# Common API Success Response Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spring Boot Controller가 일관된 성공 응답 JSON을 생성하도록 불변 `ApiResponse<T>`와 성공 코드 계약을 구현한다.

**Architecture:** `SuccessCode`가 HTTP Status와 애플리케이션 코드·메시지 계약을 제공하고, `CommonSuccessCode`가 공통 200·201 값을 구현한다. `ApiResponse<T>`는 private 생성자와 정적 Factory Method만 사용해 `success=true`를 보장하며, Jackson Annotation으로 JSON 이름과 순서를 고정한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Web MVC/Jackson, JUnit 5, AssertJ, Gradle 8.14.3, Spotless 8.8.0

## Global Constraints

- Base Package는 `com.ssafy.b209`를 유지한다.
- 작업 브랜치는 이슈 번호가 없는 `feat/common-api-response`를 사용한다.
- 새 Gradle 의존성을 추가하지 않는다.
- 기존 DB, Profile, Flyway Migration, Spotless와 Javadoc 설정을 변경하지 않는다.
- 성공 응답 JSON 필드는 `success`, `code`, `message`, `data` 순서로 유지하며 `data=null`을 포함한다.
- HTTP Status는 응답 Body에 포함하지 않고 `ResponseEntity`에서 전달한다.
- HTTP 204 응답에는 `ApiResponse` Body를 사용하지 않는다.
- 오류 응답, 전역 예외 처리, 자동 응답 래핑, Controller와 도메인 API를 구현하지 않는다.
- 새 공개 타입과 의미 있는 공개 Factory Method의 Javadoc은 한국어로 작성한다.
- 사용자의 별도 요청 전에는 Commit, Push와 Merge Request 생성을 수행하지 않는다.

---

## File Structure

- Create: `backend/src/main/java/com/ssafy/b209/global/response/SuccessCode.java` — 성공 코드 계약
- Create: `backend/src/main/java/com/ssafy/b209/global/response/CommonSuccessCode.java` — 공통 200·201 성공 코드
- Create: `backend/src/main/java/com/ssafy/b209/global/response/ApiResponse.java` — 불변 Generic 성공 응답 Wrapper
- Create: `backend/src/test/java/com/ssafy/b209/global/response/ApiResponseTest.java` — Factory와 값 계약 단위 테스트
- Create: `backend/src/test/java/com/ssafy/b209/global/response/ApiResponseJsonTest.java` — Jackson 직렬화 계약 테스트
- Modify: `README.md` — 성공 응답 구조와 Controller 사용 규칙

### Task 1: 성공 코드와 불변 응답 객체

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/global/response/ApiResponseTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/SuccessCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/CommonSuccessCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/ApiResponse.java`

**Interfaces:**
- Consumes: Spring MVC `HttpStatus`
- Produces: `SuccessCode#getHttpStatus()`, `SuccessCode#getCode()`, `SuccessCode#getMessage()`, `ApiResponse.ok(T)`, `ApiResponse.ok()`, `ApiResponse.of(SuccessCode, T)`, `ApiResponse#success()`, `ApiResponse#code()`, `ApiResponse#message()`, `ApiResponse#data()`

- [x] **Step 1: Factory 계약을 표현하는 실패 테스트 작성**

```java
package com.ssafy.b209.global.response;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class ApiResponseTest {

  @Test
  void createsOkResponseWithData() {
    TestData data = new TestData(1L, "test");

    ApiResponse<TestData> response = ApiResponse.ok(data);

    assertThat(response.success()).isTrue();
    assertThat(response.code()).isEqualTo("COMMON_200");
    assertThat(response.message()).isEqualTo("요청이 성공했습니다.");
    assertThat(response.data()).isEqualTo(data);
  }

  @Test
  void createsOkResponseWithoutData() {
    ApiResponse<Void> response = ApiResponse.ok();

    assertThat(response.success()).isTrue();
    assertThat(response.code()).isEqualTo("COMMON_200");
    assertThat(response.message()).isEqualTo("요청이 성공했습니다.");
    assertThat(response.data()).isNull();
  }

  @Test
  void createsResponseFromSuccessCode() {
    TestData data = new TestData(1L, "created");

    ApiResponse<TestData> response = ApiResponse.of(CommonSuccessCode.CREATED, data);

    assertThat(response.success()).isTrue();
    assertThat(response.code()).isEqualTo("COMMON_201");
    assertThat(response.message()).isEqualTo("리소스가 생성되었습니다.");
    assertThat(response.data()).isEqualTo(data);
    assertThat(CommonSuccessCode.CREATED.getHttpStatus()).isEqualTo(HttpStatus.CREATED);
  }

  @Test
  void rejectsNullSuccessCode() {
    assertThatNullPointerException()
        .isThrownBy(() -> ApiResponse.of(null, "data"))
        .withMessage("successCode must not be null");
  }

  private record TestData(Long id, String name) {}
}
```

- [x] **Step 2: 테스트를 실행해 미구현 타입으로 실패하는지 확인**

Run:

```powershell
cd backend
gradlew.bat test --tests "com.ssafy.b209.global.response.ApiResponseTest"
```

Expected: `ApiResponse`, `CommonSuccessCode`를 찾을 수 없어 `compileTestJava`가 실패한다.

- [x] **Step 3: `SuccessCode` 계약 구현**

```java
package com.ssafy.b209.global.response;

import org.springframework.http.HttpStatus;

/**
 * API 성공 응답 코드가 제공해야 하는 HTTP Status, 애플리케이션 코드와 기본 메시지의 계약이다.
 *
 * <p>공통 성공 코드와 도메인별 성공 코드가 같은 규격으로 {@link ApiResponse}를 생성할 때 사용한다.
 */
public interface SuccessCode {

  /**
   * 성공 상황에 대응하는 HTTP Status를 반환한다.
   *
   * @return HTTP 응답에 사용할 상태
   */
  HttpStatus getHttpStatus();

  /**
   * 클라이언트가 성공 상황을 식별할 애플리케이션 코드를 반환한다.
   *
   * @return 애플리케이션 성공 코드
   */
  String getCode();

  /**
   * 성공 상황의 기본 설명을 반환한다.
   *
   * @return 성공 메시지
   */
  String getMessage();
}
```

- [x] **Step 4: `CommonSuccessCode` 구현**

```java
package com.ssafy.b209.global.response;

import org.springframework.http.HttpStatus;

/** 도메인에 종속되지 않고 여러 API에서 공유하는 성공 코드를 관리한다. */
public enum CommonSuccessCode implements SuccessCode {
  OK(HttpStatus.OK, "COMMON_200", "요청이 성공했습니다."),
  CREATED(HttpStatus.CREATED, "COMMON_201", "리소스가 생성되었습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  CommonSuccessCode(HttpStatus httpStatus, String code, String message) {
    this.httpStatus = httpStatus;
    this.code = code;
    this.message = message;
  }

  @Override
  public HttpStatus getHttpStatus() {
    return httpStatus;
  }

  @Override
  public String getCode() {
    return code;
  }

  @Override
  public String getMessage() {
    return message;
  }
}
```

- [x] **Step 5: private 생성자를 사용하는 `ApiResponse<T>` 구현**

```java
package com.ssafy.b209.global.response;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import java.util.Objects;

/**
 * API의 일반 성공 결과를 일관된 JSON 구조로 감싸는 불변 응답 객체다.
 *
 * <p>HTTP Status는 응답 Body에 포함하지 않고 Controller의 {@code ResponseEntity}로 전달한다. HTTP 204 응답에는 이
 * 객체를 사용하지 않는다.
 *
 * @param <T> 응답 데이터 타입
 */
@JsonPropertyOrder({"success", "code", "message", "data"})
public final class ApiResponse<T> {

  private final boolean success;
  private final String code;
  private final String message;
  private final T data;

  private ApiResponse(String code, String message, T data) {
    this.success = true;
    this.code = code;
    this.message = message;
    this.data = data;
  }

  /**
   * 데이터가 포함된 기본 HTTP 200 성공 응답을 생성한다.
   *
   * @param data 응답 데이터
   * @param <T> 응답 데이터 타입
   * @return 기본 성공 코드와 데이터를 가진 응답
   */
  public static <T> ApiResponse<T> ok(T data) {
    return of(CommonSuccessCode.OK, data);
  }

  /**
   * 데이터가 없는 기본 HTTP 200 성공 응답을 생성한다.
   *
   * @return {@code data}가 {@code null}인 기본 성공 응답
   */
  public static ApiResponse<Void> ok() {
    return of(CommonSuccessCode.OK, null);
  }

  /**
   * 지정한 성공 코드와 데이터로 응답을 생성한다.
   *
   * @param successCode 응답 코드, HTTP Status와 기본 메시지를 제공하는 성공 코드
   * @param data 응답 데이터
   * @param <T> 응답 데이터 타입
   * @return 지정한 성공 코드의 코드와 메시지를 가진 응답
   * @throws NullPointerException {@code successCode}가 {@code null}인 경우
   */
  public static <T> ApiResponse<T> of(SuccessCode successCode, T data) {
    Objects.requireNonNull(successCode, "successCode must not be null");
    return new ApiResponse<>(successCode.getCode(), successCode.getMessage(), data);
  }

  @JsonProperty("success")
  public boolean success() {
    return success;
  }

  @JsonProperty("code")
  public String code() {
    return code;
  }

  @JsonProperty("message")
  public String message() {
    return message;
  }

  @JsonProperty("data")
  public T data() {
    return data;
  }
}
```

- [x] **Step 6: Factory 단위 테스트 통과 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.response.ApiResponseTest"
```

Expected: `BUILD SUCCESSFUL`, 4 tests pass.

### Task 2: Jackson 직렬화 계약

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/global/response/ApiResponseJsonTest.java`
- Verify: `backend/src/main/java/com/ssafy/b209/global/response/ApiResponse.java`

**Interfaces:**
- Consumes: Task 1의 `ApiResponse.ok(T)`, `ApiResponse.ok()`, `ApiResponse.of(SuccessCode, T)`
- Produces: `success`, `code`, `message`, `data` 순서와 null·Generic 데이터 유지가 검증된 JSON 계약

- [x] **Step 1: JSON 직렬화 계약 테스트 작성**

```java
package com.ssafy.b209.global.response;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class ApiResponseJsonTest {

  private final ObjectMapper objectMapper = new ObjectMapper();

  @Test
  void serializesFieldsInContractOrder() throws Exception {
    ApiResponse<TestData> response = ApiResponse.ok(new TestData(1L, "test"));

    JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(response));

    List<String> fieldNames = new ArrayList<>();
    json.fieldNames().forEachRemaining(fieldNames::add);
    assertThat(fieldNames).containsExactly("success", "code", "message", "data");
    assertThat(json.get("success").asBoolean()).isTrue();
    assertThat(json.get("code").asText()).isEqualTo("COMMON_200");
    assertThat(json.get("message").asText()).isEqualTo("요청이 성공했습니다.");
    assertThat(json.get("data").get("id").asLong()).isEqualTo(1L);
    assertThat(json.get("data").get("name").asText()).isEqualTo("test");
  }

  @Test
  void keepsNullDataField() throws Exception {
    JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(ApiResponse.ok()));

    assertThat(json.has("data")).isTrue();
    assertThat(json.get("data").isNull()).isTrue();
  }

  @Test
  void serializesListAndEmptyList() throws Exception {
    JsonNode listJson =
        objectMapper.readTree(
            objectMapper.writeValueAsString(
                ApiResponse.ok(List.of(new TestData(1L, "first")))));
    JsonNode emptyListJson =
        objectMapper.readTree(objectMapper.writeValueAsString(ApiResponse.ok(List.of())));

    assertThat(listJson.get("data").isArray()).isTrue();
    assertThat(listJson.get("data").size()).isEqualTo(1);
    assertThat(listJson.get("data").get(0).get("name").asText()).isEqualTo("first");
    assertThat(emptyListJson.get("data").isArray()).isTrue();
    assertThat(emptyListJson.get("data").size()).isZero();
  }

  @Test
  void doesNotExposeHttpStatusOrEnumName() throws Exception {
    JsonNode json =
        objectMapper.readTree(
            objectMapper.writeValueAsString(
                ApiResponse.of(CommonSuccessCode.CREATED, new TestData(1L, "created"))));

    assertThat(json.has("httpStatus")).isFalse();
    assertThat(json.toString()).doesNotContain("CREATED");
    assertThat(json.get("code").asText()).isEqualTo("COMMON_201");
  }

  private record TestData(Long id, String name) {}
}
```

- [x] **Step 2: 직렬화 테스트 실행**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.response.ApiResponseJsonTest"
```

Expected: `BUILD SUCCESSFUL`, 4 tests pass. 실패하면 JSON Property Annotation 또는 순서 선언만 계약에 맞게 수정한다.

- [x] **Step 3: 공통 응답 테스트 전체 실행**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.response.*"
```

Expected: `BUILD SUCCESSFUL`, 공통 응답 관련 8 tests pass.

### Task 3: README 사용 계약 문서화

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1의 Factory Method와 `CommonSuccessCode.CREATED.getHttpStatus()`
- Produces: 향후 Controller 구현자가 따를 성공 응답·HTTP 204·빈 목록 사용 규칙

- [x] **Step 1: API 버전 안내 앞에 공통 성공 응답 섹션 추가**

다음 내용을 README의 `## API 버전과 내부 시스템 경계` 앞에 추가한다.

````markdown
## 공통 API 성공 응답

일반 성공 응답은 다음 구조를 사용합니다.

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {}
}
```

- `success`: 요청 성공 여부이며 성공 응답에서는 항상 `true`입니다.
- `code`: HTTP Status와 구분되는 애플리케이션 응답 코드입니다.
- `message`: 성공 상황의 기본 설명입니다.
- `data`: 실제 반환 데이터이며, 데이터가 없는 HTTP 200 응답에서는 `null`입니다.

공통 성공 코드는 다음과 같습니다.

| Code | HTTP Status | Message |
| --- | --- | --- |
| `COMMON_200` | `200 OK` | 요청이 성공했습니다. |
| `COMMON_201` | `201 Created` | 리소스가 생성되었습니다. |

Controller에서는 다음과 같이 사용합니다.

```java
return ResponseEntity.ok(ApiResponse.ok(response));
```

```java
return ResponseEntity
        .status(CommonSuccessCode.CREATED.getHttpStatus())
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
```

반환 데이터가 없는 HTTP 200 응답은 다음과 같이 생성합니다.

```java
return ResponseEntity.ok(ApiResponse.ok());
```

HTTP 204 응답에는 Body를 포함하지 않습니다.

```java
return ResponseEntity.noContent().build();
```

- 일반 성공 응답은 `ApiResponse<T>`로 감쌉니다.
- HTTP Status는 `ResponseEntity`로 표현하고 Response Body에 중복해서 넣지 않습니다.
- 목록이 비어 있으면 `null` 대신 빈 배열을 반환합니다.
- Controller에서 Code와 Message를 문자열로 직접 작성하지 않습니다.
- 파일 다운로드와 Streaming 응답에는 공통 Wrapper를 강제하지 않습니다.
- 오류 응답은 후속 전역 예외 처리 Jira 이슈에서 구현합니다.
````

- [x] **Step 2: Markdown 형식 검사**

Run:

```powershell
gradlew.bat spotlessCheck
```

Expected: `BUILD SUCCESSFUL`. README의 기존 문서가 삭제되거나 깨지지 않아야 한다.

### Task 4: 전체 품질 검증과 변경 범위 확인

**Files:**
- Verify: `backend/src/main/java/com/ssafy/b209/global/response/*.java`
- Verify: `backend/src/test/java/com/ssafy/b209/global/response/*.java`
- Verify: `README.md`
- Verify: `docs/superpowers/specs/2026-07-21-common-api-response-design.md`
- Verify: `docs/superpowers/plans/2026-07-21-common-api-response.md`

**Interfaces:**
- Consumes: Tasks 1–3의 전체 결과
- Produces: 테스트·형식·Javadoc과 변경 범위가 검증된 작업 트리

- [x] **Step 1: Spotless가 요구하는 Java와 Markdown 형식 적용**

Run:

```powershell
gradlew.bat spotlessApply
```

Expected: `BUILD SUCCESSFUL`; 의미 변경 없이 포맷만 적용된다.

- [x] **Step 2: 전체 테스트 실행**

Run:

```powershell
gradlew.bat clean test
```

Expected: `BUILD SUCCESSFUL`; 기존 H2 Context, Testcontainers MySQL/Flyway와 공통 응답 테스트가 모두 통과한다. Docker를 사용할 수 없다면 통합 테스트를 비활성화하지 않고 실패 원인을 기록한다.

- [x] **Step 3: Spotless 검사 실행**

Run:

```powershell
gradlew.bat spotlessCheck
```

Expected: `BUILD SUCCESSFUL`.

- [x] **Step 4: Javadoc 생성 및 결과 확인**

Run:

```powershell
gradlew.bat javadoc
Test-Path build/docs/javadoc/index.html
```

Expected: `BUILD SUCCESSFUL`, 경고 또는 오류 없이 `True`가 출력된다.

- [x] **Step 5: 변경 범위와 의존성 확인**

Run from repository root:

```powershell
git status --short
git diff --check
git diff -- backend/build.gradle backend/src/main/resources backend/src/test/java/com/ssafy/b209/database
```

Expected: 공통 응답 Java·테스트, README와 설계·계획 문서만 변경되고 마지막 명령은 출력이 없다. Commit, Push와 Merge Request는 생성하지 않는다.
