# Global Exception Handler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spring MVC와 비즈니스 계층에서 발생한 예외를 안전하고 일관된 `ApiErrorResponse<T>` JSON과 올바른 HTTP Status로 변환한다.

**Architecture:** 오류 코드와 오류 응답은 기존 성공 응답 타입과 분리하며, `GlobalExceptionHandler`가 구체적인 예외별 매핑을 담당한다. Validation 상세는 안정적으로 제공되는 Binding 오류에서만 추출하고 나머지 오류는 내부 정보를 제외한 공통 코드로 응답한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Web MVC, Jakarta Validation, Jackson, SLF4J/Logback, JUnit 5, AssertJ, MockMvc, Gradle 8.14.3, Spotless 8.8.0

## Global Constraints

- Base Package는 `com.ssafy.b209`를 유지한다.
- 작업 브랜치는 이슈 번호가 없는 `feat/global-exception-handler`를 사용한다.
- 기존 `ApiResponse<T>`, `SuccessCode`, `CommonSuccessCode`는 변경하지 않는다.
- `spring-boot-starter-validation`이 이미 있으므로 `build.gradle`을 변경하지 않는다.
- 새 라이브러리와 Lombok을 추가하지 않는다.
- 오류 JSON 필드는 `success`, `code`, `message`, `data` 순서이며 `success=false`와 `data=null`을 유지한다.
- 응답에 Exception 원문, Stack Trace, SQL, DB 구조, 요청 Body, Token과 개인정보를 포함하지 않는다.
- 예상 가능한 4xx는 `DEBUG`, 데이터 무결성은 `WARN`, 예상하지 못한 5xx는 Stack Trace를 포함해 `ERROR`로 기록한다.
- Production Source에는 실제 Controller, 도메인 DTO와 도메인별 ErrorCode를 추가하지 않는다.
- Swagger/OpenAPI, CORS, Security/JWT, `ResponseBodyAdvice`, DB와 Migration은 변경하지 않는다.
- 공개 타입과 의미 있는 공개 메서드는 실제 동작에 맞는 한국어 Javadoc을 제공한다.
- 사용자의 별도 요청 전에는 Commit, Push와 Merge Request를 수행하지 않는다.

---

## File Structure

- Create: `backend/src/main/java/com/ssafy/b209/global/response/ErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/CommonErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/ApiErrorResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/FieldErrorDetail.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/ValidationErrorData.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/exception/BusinessException.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/exception/GlobalExceptionHandler.java`
- Create: `backend/src/test/java/com/ssafy/b209/global/response/ApiErrorResponseTest.java`
- Create: `backend/src/test/java/com/ssafy/b209/global/response/ApiErrorResponseJsonTest.java`
- Create: `backend/src/test/java/com/ssafy/b209/global/exception/BusinessExceptionTest.java`
- Create: `backend/src/test/java/com/ssafy/b209/global/exception/GlobalExceptionHandlerTest.java`
- Modify: `README.md`

### Task 1: 공통 오류 코드와 불변 오류 응답

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/global/response/ApiErrorResponseTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/ErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/CommonErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/ApiErrorResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/FieldErrorDetail.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/response/ValidationErrorData.java`

**Interfaces:**
- Produces: `ErrorCode#getHttpStatus()`, `getCode()`, `getMessage()`
- Produces: `ApiErrorResponse.of(ErrorCode)`, `ApiErrorResponse.of(ErrorCode, T)`와 `success()`, `code()`, `message()`, `data()`
- Produces: `FieldErrorDetail(String, String)`, `ValidationErrorData(List<FieldErrorDetail>, List<String>)`

- [x] **Step 1: 오류 응답과 Validation 불변성 실패 테스트 작성**

`ApiErrorResponseTest`에 다음 계약을 작성한다.

```java
@Test
void createsErrorResponseWithoutData() {
  ApiErrorResponse<Void> response = ApiErrorResponse.of(CommonErrorCode.INVALID_INPUT_VALUE);
  assertThat(response.success()).isFalse();
  assertThat(response.code()).isEqualTo("COMMON_400_001");
  assertThat(response.message()).isEqualTo("요청 값이 올바르지 않습니다.");
  assertThat(response.data()).isNull();
}

@Test
void createsErrorResponseWithValidationData() {
  ValidationErrorData data =
      new ValidationErrorData(
          List.of(new FieldErrorDetail("childName", "아동 이름은 필수입니다.")),
          List.of());
  ApiErrorResponse<ValidationErrorData> response =
      ApiErrorResponse.of(CommonErrorCode.INVALID_INPUT_VALUE, data);
  assertThat(response.data()).isSameAs(data);
}

@Test
void rejectsNullErrorCode() {
  assertThatNullPointerException()
      .isThrownBy(() -> ApiErrorResponse.of(null))
      .withMessage("errorCode must not be null");
}

@Test
void defensivelyCopiesValidationLists() {
  List<FieldErrorDetail> source = new ArrayList<>();
  ValidationErrorData data = new ValidationErrorData(source, List.of());
  source.add(new FieldErrorDetail("name", "invalid"));
  assertThat(data.fieldErrors()).isEmpty();
  assertThatExceptionOfType(UnsupportedOperationException.class)
      .isThrownBy(() -> data.fieldErrors().add(new FieldErrorDetail("name", "invalid")));
}

@Test
void rejectsNullValidationLists() {
  assertThatNullPointerException()
      .isThrownBy(() -> new ValidationErrorData(null, List.of()))
      .withMessage("fieldErrors must not be null");
  assertThatNullPointerException()
      .isThrownBy(() -> new ValidationErrorData(List.of(), null))
      .withMessage("globalErrors must not be null");
}
```

- [x] **Step 2: 테스트가 미구현 타입으로 실패하는지 확인**

Run:

```powershell
cd backend
gradlew.bat test --tests "com.ssafy.b209.global.response.ApiErrorResponseTest"
```

Expected: `ApiErrorResponse`, `CommonErrorCode`, `ValidationErrorData`를 찾을 수 없어 `compileTestJava`가 실패한다.

- [x] **Step 3: 오류 코드 계약과 공통 Enum 구현**

`ErrorCode`는 다음 서명을 제공한다.

```java
public interface ErrorCode {
  HttpStatus getHttpStatus();
  String getCode();
  String getMessage();
}
```

`CommonErrorCode`는 다음 값만 구현한다.

```java
INVALID_INPUT_VALUE(HttpStatus.BAD_REQUEST, "COMMON_400_001", "요청 값이 올바르지 않습니다."),
INVALID_TYPE_VALUE(HttpStatus.BAD_REQUEST, "COMMON_400_002", "요청 값의 형식이 올바르지 않습니다."),
MESSAGE_NOT_READABLE(HttpStatus.BAD_REQUEST, "COMMON_400_003", "요청 본문을 읽을 수 없습니다."),
MISSING_REQUEST_PARAMETER(HttpStatus.BAD_REQUEST, "COMMON_400_004", "필수 요청 파라미터가 누락되었습니다."),
RESOURCE_NOT_FOUND(HttpStatus.NOT_FOUND, "COMMON_404_001", "요청한 리소스를 찾을 수 없습니다."),
METHOD_NOT_ALLOWED(HttpStatus.METHOD_NOT_ALLOWED, "COMMON_405_001", "지원하지 않는 HTTP 메서드입니다."),
DATA_INTEGRITY_VIOLATION(HttpStatus.CONFLICT, "COMMON_409_001", "요청이 현재 데이터 상태와 충돌합니다."),
INTERNAL_SERVER_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "COMMON_500_001", "서버 내부 오류가 발생했습니다.");
```

- [x] **Step 4: 오류 응답과 Validation 값 타입 구현**

`ApiErrorResponse<T>`는 private 생성자와 다음 핵심 구현을 사용한다.

```java
@JsonPropertyOrder({"success", "code", "message", "data"})
public final class ApiErrorResponse<T> {
  private final boolean success;
  private final String code;
  private final String message;
  private final T data;

  private ApiErrorResponse(String code, String message, T data) {
    this.success = false;
    this.code = code;
    this.message = message;
    this.data = data;
  }

  public static ApiErrorResponse<Void> of(ErrorCode errorCode) {
    return of(errorCode, null);
  }

  public static <T> ApiErrorResponse<T> of(ErrorCode errorCode, T data) {
    Objects.requireNonNull(errorCode, "errorCode must not be null");
    return new ApiErrorResponse<>(errorCode.getCode(), errorCode.getMessage(), data);
  }
}
```

네 accessor에는 각각 `@JsonProperty("success")`, `code`, `message`, `data`를 지정한다.

Validation 타입은 다음 불변식을 적용한다.

```java
@JsonPropertyOrder({"field", "message"})
public record FieldErrorDetail(String field, String message) {}

@JsonPropertyOrder({"fieldErrors", "globalErrors"})
public record ValidationErrorData(
    List<FieldErrorDetail> fieldErrors,
    List<String> globalErrors) {
  public ValidationErrorData {
    fieldErrors = List.copyOf(Objects.requireNonNull(fieldErrors, "fieldErrors must not be null"));
    globalErrors = List.copyOf(Objects.requireNonNull(globalErrors, "globalErrors must not be null"));
  }
}
```

- [x] **Step 5: 오류 응답 단위 테스트 통과 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.response.ApiErrorResponseTest"
```

Expected: `BUILD SUCCESSFUL`.

### Task 2: Jackson 오류 응답 계약

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/global/response/ApiErrorResponseJsonTest.java`
- Verify: `backend/src/main/java/com/ssafy/b209/global/response/ApiErrorResponse.java`

**Interfaces:**
- Consumes: Task 1의 오류 응답과 Validation 타입
- Produces: 내부 정보가 없는 고정 JSON 계약

- [x] **Step 1: JSON 직렬화 실패 테스트 작성**

다음 핵심 검증을 `ObjectMapper`와 `JsonNode`로 작성한다.

```java
ApiErrorResponse<Void> response =
    ApiErrorResponse.of(CommonErrorCode.INTERNAL_SERVER_ERROR);
JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(response));

List<String> names = new ArrayList<>();
json.fieldNames().forEachRemaining(names::add);
assertThat(names).containsExactly("success", "code", "message", "data");
assertThat(json.get("success").isBoolean()).isTrue();
assertThat(json.get("success").asBoolean()).isFalse();
assertThat(json.get("data").isNull()).isTrue();
assertThat(json.has("httpStatus")).isFalse();
assertThat(json.has("exception")).isFalse();
assertThat(json.has("trace")).isFalse();
assertThat(json.toString()).doesNotContain("INTERNAL_SERVER_ERROR");
```

Validation 상세 응답에는 `fieldErrors[0].field`, `fieldErrors[0].message`, 빈 `globalErrors` 배열만 존재하는지 검증한다.

- [x] **Step 2: 직렬화 테스트 실행 및 계약 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.response.ApiErrorResponseJsonTest"
```

Expected: `BUILD SUCCESSFUL`. 실패 시 JSON Annotation만 계약에 맞춰 수정한다.

### Task 3: BusinessException

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/global/exception/BusinessExceptionTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/exception/BusinessException.java`

**Interfaces:**
- Consumes: `ErrorCode`
- Produces: `BusinessException(ErrorCode)`, `BusinessException(ErrorCode, Throwable)`, `getErrorCode()`

- [x] **Step 1: BusinessException 실패 테스트 작성**

```java
@Test
void keepsErrorCodeAndSafeMessage() {
  BusinessException exception = new BusinessException(CommonErrorCode.RESOURCE_NOT_FOUND);
  assertThat(exception.getErrorCode()).isEqualTo(CommonErrorCode.RESOURCE_NOT_FOUND);
  assertThat(exception.getMessage()).isEqualTo("요청한 리소스를 찾을 수 없습니다.");
}

@Test
void keepsCause() {
  RuntimeException cause = new RuntimeException("internal detail");
  BusinessException exception =
      new BusinessException(CommonErrorCode.INTERNAL_SERVER_ERROR, cause);
  assertThat(exception.getCause()).isSameAs(cause);
}

@Test
void rejectsNullErrorCode() {
  assertThatNullPointerException()
      .isThrownBy(() -> new BusinessException(null))
      .withMessage("errorCode must not be null");
}
```

- [x] **Step 2: 테스트가 미구현 클래스로 실패하는지 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.exception.BusinessExceptionTest"
```

Expected: `BusinessException`을 찾을 수 없어 실패한다.

- [x] **Step 3: 최소 BusinessException 구현**

```java
public class BusinessException extends RuntimeException {
  private final ErrorCode errorCode;

  public BusinessException(ErrorCode errorCode) {
    super(requireErrorCode(errorCode).getMessage());
    this.errorCode = errorCode;
  }

  public BusinessException(ErrorCode errorCode, Throwable cause) {
    super(requireErrorCode(errorCode).getMessage(), cause);
    this.errorCode = errorCode;
  }

  public ErrorCode getErrorCode() {
    return errorCode;
  }

  private static ErrorCode requireErrorCode(ErrorCode errorCode) {
    return Objects.requireNonNull(errorCode, "errorCode must not be null");
  }
}
```

- [x] **Step 4: BusinessException 테스트 통과 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.exception.BusinessExceptionTest"
```

Expected: `BUILD SUCCESSFUL`.

### Task 4: GlobalExceptionHandler HTTP 계약

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/global/exception/GlobalExceptionHandlerTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/exception/GlobalExceptionHandler.java`

**Interfaces:**
- Consumes: Tasks 1–3의 `ErrorCode`, `ApiErrorResponse`, Validation 타입과 `BusinessException`
- Produces: 명세에 나열된 12개 예외를 처리하는 `@RestControllerAdvice`

- [x] **Step 1: 테스트 전용 Controller와 MockMvc 실패 테스트 작성**

`@WebMvcTest(controllers = TestExceptionController.class)`와 `@Import(GlobalExceptionHandler.class)`를 사용한다. 테스트 Controller에는 다음 Endpoint만 둔다.

```java
@RestController
@RequestMapping("/test/errors")
class TestExceptionController {
  @GetMapping("/business")
  void business() {
    throw new BusinessException(CommonErrorCode.RESOURCE_NOT_FOUND);
  }

  @PostMapping("/body-validation")
  void bodyValidation(@Valid @RequestBody TestRequest request) {}

  @GetMapping("/bind-validation")
  void bindValidation(@Valid @ModelAttribute TestQuery query) {}

  @GetMapping("/constraint")
  void constraint() {
    throw new ConstraintViolationException(Set.of());
  }

  @GetMapping("/method-validation")
  void methodValidation(
      @RequestParam(name = "count") @Min(value = 1, message = "count는 1 이상이어야 합니다.")
          int count) {}

  @GetMapping("/type/{id}")
  void type(@PathVariable Long id) {}

  @PostMapping("/json")
  void json(@RequestBody TestRequest request) {}

  @GetMapping("/required")
  void required(@RequestParam String value) {}

  @GetMapping("/method")
  void method() {}

  @GetMapping("/not-found")
  void notFound() throws NoResourceFoundException {
    throw new NoResourceFoundException(HttpMethod.GET, "/private/path");
  }

  @GetMapping("/integrity")
  void integrity() {
    throw new DataIntegrityViolationException("SQL constraint secret");
  }

  @GetMapping("/unexpected")
  void unexpected() {
    throw new IllegalStateException("password=secret");
  }
}

record TestRequest(@NotBlank(message = "아동 이름은 필수입니다.") String childName) {}
```

`TestQuery`는 기본 생성자와 getter/setter를 가진 테스트 전용 클래스이며 `name`에 `@NotBlank(message = "이름은 필수입니다.")`를 지정한다.

각 Endpoint에 MockMvc 요청을 보내 다음 Status와 코드를 검증한다.

```text
/business -> 404, COMMON_404_001
/body-validation -> 400, COMMON_400_001, fieldErrors 포함
/bind-validation -> 400, COMMON_400_001, fieldErrors 포함
/constraint -> 400, COMMON_400_001, data=null
/method-validation?count=0 -> 400, COMMON_400_001, data=null
/type/not-a-number -> 400, COMMON_400_002
POST /json with malformed JSON -> 400, COMMON_400_003
/required -> 400, COMMON_400_004
POST /method -> 405, COMMON_405_001, Allow=GET
/not-found -> 404, COMMON_404_001
/integrity -> 409, COMMON_409_001
/unexpected -> 500, COMMON_500_001
```

공통 assertion은 `success=false`, `code`, `message`, `data` 존재와 `httpStatus`, `exception`, `trace`, `path`, `timestamp` 미존재를 검증한다. 보안 assertion은 응답 문자열에 `SQL constraint secret`, `password=secret`, `NoResourceFoundException`, `IllegalStateException`이 없는지 확인한다.

- [x] **Step 2: Handler 미구현으로 실패하는지 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.exception.GlobalExceptionHandlerTest"
```

Expected: `GlobalExceptionHandler`를 찾을 수 없어 실패한다.

- [x] **Step 3: 명시적인 예외별 Handler 구현**

`GlobalExceptionHandler`는 다음 Handler를 제공한다.

```java
@ExceptionHandler(BusinessException.class)
ResponseEntity<ApiErrorResponse<Void>> handleBusinessException(BusinessException exception)

@ExceptionHandler(MethodArgumentNotValidException.class)
ResponseEntity<ApiErrorResponse<ValidationErrorData>> handleMethodArgumentNotValidException(
    MethodArgumentNotValidException exception)

@ExceptionHandler(BindException.class)
ResponseEntity<ApiErrorResponse<ValidationErrorData>> handleBindException(BindException exception)

@ExceptionHandler(ConstraintViolationException.class)
ResponseEntity<ApiErrorResponse<Void>> handleConstraintViolationException(
    ConstraintViolationException exception)

@ExceptionHandler(HandlerMethodValidationException.class)
ResponseEntity<ApiErrorResponse<Void>> handleHandlerMethodValidationException(
    HandlerMethodValidationException exception)

@ExceptionHandler(MethodArgumentTypeMismatchException.class)
ResponseEntity<ApiErrorResponse<Void>> handleMethodArgumentTypeMismatchException(
    MethodArgumentTypeMismatchException exception)

@ExceptionHandler(HttpMessageNotReadableException.class)
ResponseEntity<ApiErrorResponse<Void>> handleHttpMessageNotReadableException(
    HttpMessageNotReadableException exception)

@ExceptionHandler(MissingServletRequestParameterException.class)
ResponseEntity<ApiErrorResponse<Void>> handleMissingServletRequestParameterException(
    MissingServletRequestParameterException exception)

@ExceptionHandler(HttpRequestMethodNotSupportedException.class)
ResponseEntity<ApiErrorResponse<Void>> handleHttpRequestMethodNotSupportedException(
    HttpRequestMethodNotSupportedException exception)

@ExceptionHandler(NoResourceFoundException.class)
ResponseEntity<ApiErrorResponse<Void>> handleNoResourceFoundException(
    NoResourceFoundException exception)

@ExceptionHandler(DataIntegrityViolationException.class)
ResponseEntity<ApiErrorResponse<Void>> handleDataIntegrityViolationException(
    DataIntegrityViolationException exception)

@ExceptionHandler(Exception.class)
ResponseEntity<ApiErrorResponse<Void>> handleException(Exception exception)
```

Validation 변환은 다음 기준으로 구현한다.

```java
private ValidationErrorData toValidationErrorData(BindingResult bindingResult) {
  List<FieldErrorDetail> fieldErrors =
      bindingResult.getFieldErrors().stream()
          .map(error -> new FieldErrorDetail(error.getField(), safeMessage(error)))
          .distinct()
          .sorted(Comparator.comparing(FieldErrorDetail::field)
              .thenComparing(FieldErrorDetail::message))
          .toList();
  List<String> globalErrors =
      bindingResult.getGlobalErrors().stream()
          .map(this::safeMessage)
          .distinct()
          .sorted()
          .toList();
  return new ValidationErrorData(fieldErrors, globalErrors);
}

private String safeMessage(ObjectError error) {
  return Objects.requireNonNullElse(
      error.getDefaultMessage(), CommonErrorCode.INVALID_INPUT_VALUE.getMessage());
}
```

응답 helper는 `ResponseEntity.status(errorCode.getHttpStatus()).body(ApiErrorResponse.of(...))`를 사용한다. 405는 `HttpHeaders#setAllow`로 예외가 제공한 Method만 보존한다.

Logging은 다음 문장을 사용하고 사용자 입력이나 예외 원문을 문자열 인자로 전달하지 않는다.

```java
log.debug("Handled client error: code={}", errorCode.getCode());
log.warn("Handled data integrity violation: code={}", errorCode.getCode());
log.error(
    "Handled server error: code={}, exceptionType={}, stackTrace={}",
    errorCode.getCode(),
    exception.getClass().getName(),
    Arrays.toString(exception.getStackTrace()));
```

- [x] **Step 4: GlobalExceptionHandler HTTP 테스트 통과 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.exception.GlobalExceptionHandlerTest"
```

Expected: 모든 예외 매핑과 보안 assertion이 통과한다. Spring MVC에서 실제 발생하지 않는 예외는 테스트 Endpoint가 직접 안전하게 발생시키되 Production Controller는 만들지 않는다.

### Task 5: README와 전체 검증

**Files:**
- Modify: `README.md`
- Verify: 이번 계획의 모든 Java·테스트·문서 파일

**Interfaces:**
- Consumes: Tasks 1–4의 공개 오류 계약
- Produces: Controller·Service 구현자가 따를 오류 처리 규칙과 검증된 작업 트리

- [x] **Step 1: README 공통 성공 응답 다음에 오류 응답 문서 추가**

다음 내용을 포함한다.

```markdown
## 공통 API 오류 응답

- 기본 JSON과 Validation JSON 예시
- 공통 오류 코드 8개의 Code, HTTP Status, Message 표
- Controller에서 반복적인 try-catch를 작성하지 않는 규칙
- 도메인 오류 코드는 ErrorCode를 구현하고 BusinessException으로 전달하는 규칙
- rejectedValue, Exception 원문, Stack Trace와 DB 정보를 응답하지 않는 규칙
- HTTP Status는 ResponseEntity에서 전달하는 규칙
- BusinessException 사용 예시
```

- [x] **Step 2: Spotless 적용**

Run:

```powershell
gradlew.bat spotlessApply
```

Expected: `BUILD SUCCESSFUL`.

- [x] **Step 3: 전체 테스트 실행**

Run:

```powershell
gradlew.bat clean test
```

Expected: 기존 H2 Context, Testcontainers MySQL/Flyway, 성공 응답과 신규 오류 응답 테스트가 모두 통과한다.

- [x] **Step 4: Spotless 검사**

Run:

```powershell
gradlew.bat spotlessCheck
```

Expected: `BUILD SUCCESSFUL`.

- [x] **Step 5: Javadoc 생성과 파일 확인**

Run:

```powershell
gradlew.bat javadoc
Test-Path build/docs/javadoc/index.html
```

Expected: 경고 없이 `BUILD SUCCESSFUL`, `True` 출력.

- [x] **Step 6: 변경 범위 확인**

Run from repository root:

```powershell
git status --short
git diff --check
git diff -- backend/build.gradle backend/src/main/resources backend/src/test/java/com/ssafy/b209/database backend/src/main/java/com/ssafy/b209/global/response/ApiResponse.java
```

Expected: 오류 응답·예외 처리 Java, 관련 테스트, README와 설계·계획 문서만 변경된다. 마지막 diff 명령은 출력이 없어야 하며 Commit, Push와 Merge Request는 생성하지 않는다.
