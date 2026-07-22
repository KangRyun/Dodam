# 공통 API 성공 응답 형식 설계

## 배경과 목적

Flutter와 Next.js 클라이언트가 Spring Boot API의 일반 성공 응답을 일관된 방식으로 처리할 수 있도록 공통 계약을 정의한다. Controller마다 응답 필드, 코드, 메시지를 개별적으로 구성하는 중복을 방지하고, 향후 도메인별 성공 코드가 동일한 규격을 확장하도록 기반을 제공한다.

이번 설계는 성공 응답만 다룬다. 오류 응답과 전역 예외 처리는 후속 Jira 이슈에서 별도로 설계한다.

## 범위

다음 구성 요소만 추가한다.

- `SuccessCode`: HTTP Status, 애플리케이션 코드, 기본 메시지 계약
- `CommonSuccessCode`: 도메인에 종속되지 않는 `COMMON_200`, `COMMON_201`
- `ApiResponse<T>`: 성공 데이터와 공통 메타데이터를 담는 불변 Wrapper
- Factory Method와 JSON 직렬화 계약에 대한 단위 테스트
- Controller 사용 규칙을 설명하는 README 문서

전역 예외 처리, 오류 응답, 자동 응답 래핑, 실제 Controller, 페이지 응답, Swagger, CORS, 인증, DB 변경 및 외부 시스템 연동은 포함하지 않는다.

## 패키지와 구성 요소

기존 공통 응답 패키지가 없으므로 `com.ssafy.b209.global.response`를 사용한다.

### `SuccessCode`

공통 및 향후 도메인별 성공 코드가 구현할 인터페이스다. 다음 정보를 제공한다.

- `HttpStatus getHttpStatus()`
- `String getCode()`
- `String getMessage()`

상태를 저장하거나 불필요한 Default Method를 제공하지 않는다.

### `CommonSuccessCode`

`SuccessCode`를 구현하는 Enum이며 다음 두 값만 제공한다.

| 상수 | HTTP Status | 코드 | 메시지 |
| --- | --- | --- | --- |
| `OK` | `HttpStatus.OK` | `COMMON_200` | `요청이 성공했습니다.` |
| `CREATED` | `HttpStatus.CREATED` | `COMMON_201` | `리소스가 생성되었습니다.` |

HTTP 204는 Body를 만들지 않으므로 성공 코드로 추가하지 않는다.

### `ApiResponse<T>`

Java `final class`로 구현한다. `success`, `code`, `message`, `data`를 `private final` 필드로 유지하며 Setter를 제공하지 않는다. 생성자는 `private`로 제한하고 다음 Factory Method만 공개한다.

- `ok(T data)`: `COMMON_200`과 전달받은 데이터를 사용한다.
- `ok()`: `COMMON_200`과 `null` 데이터를 사용한다.
- `of(SuccessCode successCode, T data)`: 지정된 성공 코드와 데이터를 사용한다.

`success`는 생성 과정에서 항상 `true`로 고정한다. `of`에 `null`인 `SuccessCode`가 전달되면 `Objects.requireNonNull`로 즉시 실패시킨다. 공개 Accessor는 각 필드 값을 읽는 용도로만 제공한다.

## 응답 및 직렬화 계약

일반 성공 응답은 다음 JSON 구조를 사용한다.

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {}
}
```

`@JsonPropertyOrder`로 필드 순서를 `success`, `code`, `message`, `data`로 고정한다. `data`가 `null`이어도 필드를 유지한다. `HttpStatus`, Enum 이름과 내부 구현 정보는 JSON에 포함하지 않는다.

HTTP Status는 `ResponseEntity`에서 전달한다. HTTP 204는 `ResponseEntity.noContent().build()`를 사용하고 `ApiResponse` Body를 생성하지 않는다. 목록 조회 결과가 없으면 호출자가 `null` 대신 빈 목록을 전달해야 한다.

## 사용 흐름

Controller는 Service 결과를 받은 뒤 상황에 맞는 Factory Method로 Body를 만들고 `ResponseEntity`로 HTTP Status를 지정한다.

```text
Service 결과
  -> SuccessCode 선택
  -> ApiResponse Factory Method 호출
  -> ResponseEntity가 HTTP Status 전달
  -> Jackson이 공통 JSON 구조로 직렬화
```

200 응답은 `ResponseEntity.ok(ApiResponse.ok(data))`, 201 응답은 `CommonSuccessCode.CREATED.getHttpStatus()`와 `ApiResponse.of(...)`를 함께 사용한다. 204 응답에는 Wrapper를 사용하지 않는다.

## 잘못된 사용 처리

이번 이슈는 오류 응답을 구현하지 않는다. 공통 응답 객체 자체의 잘못된 사용만 다음과 같이 처리한다.

- `SuccessCode`가 `null`이면 즉시 `NullPointerException`이 발생한다.
- `data`는 계약상 `null`을 허용한다.
- `ApiResponse`의 직접 생성과 필드 변경은 구조적으로 차단한다.

발생한 예외를 HTTP 오류 응답으로 변환하는 책임은 후속 전역 예외 처리 이슈에 둔다.

## 테스트 전략

Spring Application Context와 데이터베이스를 실행하지 않는 순수 단위 테스트로 작성한다.

`ApiResponseTest`는 다음을 검증한다.

- 객체가 있는 기본 200 응답
- 데이터가 없는 기본 200 응답
- `COMMON_201`을 사용한 응답
- `SuccessCode`가 `null`일 때 즉시 실패

`ApiResponseJsonTest`는 Jackson `ObjectMapper`와 JSON Tree를 사용해 다음 계약을 검증한다.

- 필수 필드와 필드 순서
- 객체와 목록의 Generic 데이터 직렬화
- 빈 목록이 빈 배열로 직렬화
- `data=null` 필드 유지
- `httpStatus`와 Enum 이름 미노출

기존 H2 Context 테스트와 Testcontainers MySQL/Flyway 통합 테스트는 유지하며 전체 테스트에서 함께 검증한다.

## 문서화

README의 기존 내용을 유지하면서 공통 성공 응답 구조, 필드 설명, 공통 코드, Controller 사용 예시와 사용 규칙을 추가한다. 특히 HTTP Status를 Body에 중복하지 않는 점, 204 응답에 Body를 만들지 않는 점, 빈 목록 원칙과 오류 응답이 후속 범위라는 점을 명시한다.

## 검증 기준

Windows 환경에서 다음 명령을 실행한다.

```powershell
gradlew.bat clean test
gradlew.bat spotlessCheck
gradlew.bat javadoc
```

전체 테스트, Spotless와 Javadoc이 모두 성공해야 한다. 새 Gradle 의존성은 추가하지 않으며 기존 DB, Profile, Migration 및 빌드 설정은 변경하지 않는다.

## Git 운영

- 작업 브랜치: `feat/common-api-response`
- Jira 이슈: `S15P11B209-133`
- 이슈 코드는 브랜치명에 넣지 않고 향후 Commit과 Merge Request에만 포함한다.
- 사용자의 별도 요청 전에는 Commit, Push와 Merge Request 생성을 수행하지 않는다.
- Merge Request 생성 시 source branch 자동 삭제를 선택하지 않아 기록용 원격 브랜치를 유지한다.
