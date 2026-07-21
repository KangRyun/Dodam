# 전역 예외 처리 설계

## 배경과 목적

Controller마다 예외를 직접 처리하지 않고 `@RestControllerAdvice`가 애플리케이션의 일반적인 오류를 일관된 JSON 계약으로 변환한다. 클라이언트에는 안전한 코드와 메시지만 제공하고, 원본 예외·Stack Trace·DB 정보·사용자 입력과 인증 정보는 응답에서 제외한다.

기존 `ApiResponse<T>`, `SuccessCode`, `CommonSuccessCode`는 성공 전용으로 유지한다. 이번 설계는 오류 응답과 전역 변환만 다루며 Swagger, CORS, 인증·인가와 실제 도메인 API는 포함하지 않는다.

## 패키지와 구성 요소

기존 공통 패키지에 오류 응답 타입을 추가하고 예외 처리는 별도 패키지로 분리한다.

```text
com.ssafy.b209.global
├── response
│   ├── ErrorCode
│   ├── CommonErrorCode
│   ├── ApiErrorResponse<T>
│   ├── FieldErrorDetail
│   └── ValidationErrorData
└── exception
    ├── BusinessException
    └── GlobalExceptionHandler
```

### `ErrorCode`

공통 및 향후 도메인 오류 코드가 구현할 계약이다. Spring MVC의 `HttpStatus`, 애플리케이션 오류 코드와 클라이언트에 전달할 안전한 기본 메시지를 제공한다. 성공 코드, Exception과 상태는 포함하지 않는다.

### `CommonErrorCode`

다음 공통 오류만 정의한다.

| 상수 | HTTP Status | 코드 | 메시지 |
| --- | --- | --- | --- |
| `INVALID_INPUT_VALUE` | `400 Bad Request` | `COMMON_400_001` | `요청 값이 올바르지 않습니다.` |
| `INVALID_TYPE_VALUE` | `400 Bad Request` | `COMMON_400_002` | `요청 값의 형식이 올바르지 않습니다.` |
| `MESSAGE_NOT_READABLE` | `400 Bad Request` | `COMMON_400_003` | `요청 본문을 읽을 수 없습니다.` |
| `MISSING_REQUEST_PARAMETER` | `400 Bad Request` | `COMMON_400_004` | `필수 요청 파라미터가 누락되었습니다.` |
| `RESOURCE_NOT_FOUND` | `404 Not Found` | `COMMON_404_001` | `요청한 리소스를 찾을 수 없습니다.` |
| `METHOD_NOT_ALLOWED` | `405 Method Not Allowed` | `COMMON_405_001` | `지원하지 않는 HTTP 메서드입니다.` |
| `DATA_INTEGRITY_VIOLATION` | `409 Conflict` | `COMMON_409_001` | `요청이 현재 데이터 상태와 충돌합니다.` |
| `INTERNAL_SERVER_ERROR` | `500 Internal Server Error` | `COMMON_500_001` | `서버 내부 오류가 발생했습니다.` |

### `ApiErrorResponse<T>`

기존 `ApiResponse<T>`와 같은 접근 방식을 적용한 `final class`다. 모든 필드는 `private final`, 생성자는 `private`로 제한하고 `of(ErrorCode)`와 `of(ErrorCode, T)`만 공개한다. Factory 내부에서 `success=false`를 고정하며 null `ErrorCode`는 즉시 거부한다.

Jackson Annotation으로 `success`, `code`, `message`, `data`만 같은 순서로 직렬화한다. `data=null`도 유지하고 `HttpStatus`와 `ErrorCode` 자체는 노출하지 않는다.

### Validation 상세 타입

`FieldErrorDetail`은 `field`, `message`만 가진 불변 값 객체다. `ValidationErrorData`는 `fieldErrors`, `globalErrors`를 구분하고 null 목록을 거부한 뒤 `List.copyOf`로 방어적 복사한다.

`MethodArgumentNotValidException`과 `BindException`에서만 상세 정보를 만든다. 필드 오류는 필드명과 안전한 Validation 메시지만 사용하며, 객체 오류는 메시지만 사용한다. 목록은 필드명·메시지 순으로 정렬하고 중복을 제거한다. 기본 메시지가 없으면 `INVALID_INPUT_VALUE`의 메시지를 사용한다. `rejectedValue`, Object Name과 DTO 클래스명은 사용하지 않는다.

`ConstraintViolationException`과 요청 파라미터에 대한 `HandlerMethodValidationException`은 내부 경로·메서드명 노출을 피하기 위해 상세 데이터 없이 `INVALID_INPUT_VALUE`를 반환한다. Controller 반환값 Validation 실패는 클라이언트 요청 오류가 아닌 서버 응답 계약 위반이므로 `INTERNAL_SERVER_ERROR`로 처리한다.

### `BusinessException`

예상 가능한 비즈니스 오류를 표현하는 `RuntimeException`이다. null이 아닌 `ErrorCode`를 보관하고 예외 메시지에는 해당 코드의 안전한 기본 메시지를 사용한다. 선택적 cause 생성자를 제공해 원인 연결을 유지하되 원인 메시지는 클라이언트 응답에 사용하지 않는다.

## 전역 처리 흐름

`GlobalExceptionHandler`는 명시적인 `@ExceptionHandler` 메서드로 예외를 처리한다. 각 Handler는 `ErrorCode`를 선택하고 `ApiErrorResponse`를 만든 뒤 `ResponseEntity`에서 HTTP Status를 설정한다. 가장 포괄적인 `Exception` Handler는 마지막 방어선으로만 사용한다.

| 예외 | 오류 코드 | 상세 데이터 |
| --- | --- | --- |
| `BusinessException` | 예외가 보유한 코드 | 없음 |
| `MethodArgumentNotValidException` | `INVALID_INPUT_VALUE` | Validation 상세 |
| `BindException` | `INVALID_INPUT_VALUE` | Validation 상세 |
| `ConstraintViolationException` | `INVALID_INPUT_VALUE` | 없음 |
| 요청값 `HandlerMethodValidationException` | `INVALID_INPUT_VALUE` | 없음 |
| 반환값 `HandlerMethodValidationException` | `INTERNAL_SERVER_ERROR` | 없음 |
| `MethodArgumentTypeMismatchException` | `INVALID_TYPE_VALUE` | 없음 |
| `HttpMessageNotReadableException` | `MESSAGE_NOT_READABLE` | 없음 |
| `MissingServletRequestParameterException` | `MISSING_REQUEST_PARAMETER` | 없음 |
| `NoResourceFoundException` | `RESOURCE_NOT_FOUND` | 없음 |
| `HttpRequestMethodNotSupportedException` | `METHOD_NOT_ALLOWED` | 없음 |
| `DataIntegrityViolationException` | `DATA_INTEGRITY_VIOLATION` | 없음 |
| 그 외 `Exception` | `INTERNAL_SERVER_ERROR` | 없음 |

405 응답은 예외가 제공한 지원 Method가 있을 때만 `Allow` Header에 복사한다. 임의의 Method 값은 생성하지 않는다.

## Logging과 보안

- 예상 가능한 4xx와 4xx `BusinessException`: `DEBUG`, Stack Trace 없음
- `DataIntegrityViolationException`: `WARN`, 예외 객체와 원문 메시지 없이 공통 코드만 기록
- 5xx `BusinessException`: `ERROR`, 예외 메시지를 제외한 Exception 타입과 Stack Trace 프레임 기록
- 예상하지 못한 `Exception`: `ERROR`, 예외 메시지를 제외한 Exception 타입과 Stack Trace 프레임 기록

로그에는 공통 오류 코드를 필수로 남긴다. 요청 Body, 전체 Query Parameter, Header, Token, 비밀번호, 아동 개인정보와 사용자 입력을 기록하지 않는다. 5xx Stack Trace는 예외 메시지 없이 프레임만 기록하며, 데이터 무결성 오류는 SQL·테이블·컬럼·제약조건 이름이 포함될 수 있어 예외 원문과 Stack Trace를 일반 로그에 출력하지 않는다.

응답에는 Stack Trace, Exception 이름, 패키지명, 서버 경로, SQL, DB 구조, 요청 원문, 인증 정보와 개인정보를 포함하지 않는다. HTTP Status는 Body에 중복하지 않는다.

## 테스트 전략

### 단위 및 직렬화 테스트

- `ApiErrorResponseTest`: 오류 코드 적용, `success=false`, null 데이터, Generic 데이터, null 코드 거부
- `ApiErrorResponseJsonTest`: 필드 이름·타입·순서, null 유지, Validation 상세, 내부 정보 미노출
- `BusinessExceptionTest`: 코드·메시지 저장, null 거부, cause 보존

### HTTP 계약 테스트

`@WebMvcTest`와 `src/test/java`의 최소 테스트 전용 Controller·DTO를 사용한다. `GlobalExceptionHandler`를 가져와 실제 MockMvc 예외 해석과 JSON 응답을 검증하되 DB, Repository와 Service는 사용하지 않는다.

다음 상황을 검증한다.

- BusinessException
- Request Body Validation
- Model Attribute Binding Validation
- Constraint Violation 및 Handler Method Validation
- Path Variable 타입 변환
- 읽을 수 없는 JSON
- 필수 Request Parameter 누락
- 존재하지 않는 리소스
- 지원하지 않는 HTTP Method와 `Allow` Header
- 데이터 무결성 충돌
- 예상하지 못한 Exception

모든 오류 응답에서 `success=false`, 코드·메시지·data 존재, HTTP Status 일치와 내부 필드 미노출을 확인한다. 테스트 Controller와 DTO는 Production Source에 만들지 않는다.

## 문서화

README의 기존 성공 응답 설명을 유지하면서 공통 오류 응답, Validation 오류, 공통 코드 8개, `BusinessException` 사용 예시, 예외 처리·Logging·보안 규칙을 추가한다. 존재하지 않는 도메인 ErrorCode는 예시 코드로만 표기한다.

## 검증 기준

Windows 환경에서 다음을 실행한다.

```powershell
gradlew.bat clean test
gradlew.bat spotlessCheck
gradlew.bat javadoc
```

기존 H2 Context, Testcontainers MySQL/Flyway와 성공 응답 테스트를 포함한 전체 테스트가 통과해야 한다. Javadoc은 경고 없이 생성하고 `build/docs/javadoc/index.html`을 확인한다. Validation Starter는 이미 존재하므로 `build.gradle`을 변경하지 않는다.

## 제외 범위

Swagger/OpenAPI, CORS, `ResponseBodyAdvice`, Spring Security/JWT, 인증·인가 예외, 도메인별 ErrorCode, 실제 Controller·Service·Repository·DTO, DB·Migration 변경, S3·Redis·FastAPI·Firebase 연동을 구현하지 않는다.

## Git 운영

- 작업 브랜치: `feat/global-exception-handler`
- Jira 이슈: `S15P11B209-134`
- 이슈 코드는 브랜치명에 넣지 않고 향후 Commit과 Merge Request에만 포함한다.
- 사용자의 별도 요청 전에는 Commit, Push와 Merge Request 생성을 수행하지 않는다.
- Merge Request 생성 시 source branch 삭제를 요청하는 옵션을 사용하지 않는다.
