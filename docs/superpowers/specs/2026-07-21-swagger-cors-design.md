# Swagger UI 및 CORS 설정 설계

## 목표

Spring Boot 백엔드에 Springdoc OpenAPI 기반 Swagger UI를 제공하고, 브라우저 기반 Frontend가 허용된 Origin에서만 외부 REST API를 호출할 수 있도록 Spring MVC CORS 정책을 구성한다. 기존 공통 성공·오류 응답의 JSON 계약과 전역 예외 처리 동작은 변경하지 않는다.

## 기준 상태

- 기준 브랜치: `origin/develop` (`77da34a`)
- 작업 브랜치: `feat/swagger-cors`
- Java: 21
- Spring Boot: 3.5.16
- Gradle Wrapper: 8.14.3
- Base package: `com.ssafy.b209`
- 기존 Springdoc, Swagger, CORS, Spring Security 설정: 없음
- 기존 Profile: `local`, `test`, `integration-test`
- 기준선 검증: 기존 45개 테스트 성공
- 4번 이슈의 공통 오류 응답과 전역 예외 처리: `origin/develop`에 병합됨

## 확인된 충돌과 결정

이슈 프롬프트는 Swagger Group과 CORS의 기본 범위를 `/api/**`로 제시하지만, 기존 README는 외부 REST API의 공식 prefix를 `/api/v1/**`로 정의한다. 기존 계약을 우선하고 허용 범위를 최소화하기 위해 Swagger Group과 CORS 모두 `/api/v1/**`를 사용한다.

저장소에는 Flutter 모바일 앱만 존재하며 Next.js 실행 포트를 확정하는 설정은 없다. `.env.example`에는 Next.js가 Backend `8080` 포트를 호출한다는 정보만 있다. 사용자 승인에 따라 `local` Profile에는 Next.js 기본 개발 Origin인 `http://localhost:3000`과 `http://127.0.0.1:3000`만 등록한다. 운영 Origin은 확정되지 않았으므로 추가하지 않는다.

## Springdoc 의존성

`org.springdoc:springdoc-openapi-starter-webmvc-ui:2.8.17`을 명시적으로 사용한다. Springdoc 공식 호환 표에서 Spring Boot 3.5.x는 Springdoc 2.8.x와 호환되며, 2.8.17은 확인 시점의 안정 버전이다. Spring Boot BOM이 Springdoc 버전을 관리한다고 가정하지 않으며 Dynamic, Snapshot, Milestone 버전을 사용하지 않는다.

Swagger UI와 Swagger Annotation은 starter의 전이 의존성을 사용한다. Springfox, `swagger-core`, `swagger-annotations`, 별도 문서 UI 라이브러리는 직접 추가하지 않는다. 구현 후 `dependencyInsight`로 해석된 버전과 중복 여부를 확인한다.

## OpenAPI 구성

`com.ssafy.b209.global.config.OpenApiConfig`가 다음 두 Bean을 제공한다.

- `OpenAPI`: 문서 제목, 설명, API version `v1`을 설정한다.
- `GroupedOpenApi`: Group 이름 `api-v1`, 탐색 범위 `/api/v1/**`를 설정한다.

문서 제목은 README의 서비스 설명을 기준으로 `아동 그림·대화 기반 정서 지원 서비스 API`를 사용하고, 설명은 `백엔드 REST API 명세`로 제한한다. 운영 또는 localhost Server URL, 회사·담당자 정보, License, Terms of Service, Tag, Security Scheme은 설정하지 않는다.

다음 기본 Endpoint를 유지한다.

- Swagger UI 진입: `/swagger-ui.html`
- Swagger UI Resource: `/swagger-ui/index.html`
- 전체 OpenAPI JSON: `/v3/api-docs`
- `api-v1` Group JSON: `/v3/api-docs/api-v1`

Swagger Endpoint 경로는 CORS 대상에 포함하지 않는다. 운영 환경 공개 여부는 아직 정해지지 않았으므로 임의로 활성화 또는 비활성화 정책을 추가하지 않는다.

## 공통 응답 Schema

다음 기존 타입에는 책임과 실제 JSON 계약에 맞는 `@Schema` 설명과 안전한 예시만 추가한다.

- `ApiResponse<T>`
- `ApiErrorResponse<T>`
- `FieldErrorDetail`
- `ValidationErrorData`

Factory Method, 생성자, Generic 구조, `success` 불변 조건, JSON 필드명, JSON 필드 순서와 `data=null` 직렬화는 변경하지 않는다. Swagger 문서화를 위해 Setter나 기본 생성자를 추가하지 않는다.

Springdoc이 실제 응답 타입으로부터 Schema를 생성하게 하며 OpenAPI Components에 동일 Schema를 수동 등록하지 않는다. 운영 Source에 Sample Controller를 만들지 않는다. 테스트 전용 Controller가 공통 응답 타입을 반환하도록 구성해 실제 Schema 생성을 검증한다.

다음 내부 타입과 정보는 Schema에 노출하지 않는다.

- `SuccessCode`, `CommonSuccessCode`
- `ErrorCode`, `CommonErrorCode`
- `HttpStatus`
- `BusinessException`, `GlobalExceptionHandler`
- Exception 클래스명, Stack Trace, cause
- `timestamp`, `path`, `trace`, `exception`
- Token, 비밀번호, 아동 개인정보와 DB 정보

## CORS 설정값

`com.ssafy.b209.global.config.CorsProperties`는 `app.cors.allowed-origins`를 불변 목록으로 보관한다.

- `null`은 빈 목록으로 변환한다.
- 각 값의 앞뒤 공백을 제거한다.
- 빈 문자열은 제거한다.
- 중복 Origin은 입력 순서를 유지하며 제거한다.
- `*`와 Origin Pattern은 허용하지 않는다.
- Scheme, Host, 선택적 Port로만 구성된 HTTP 또는 HTTPS Origin만 허용한다.
- Path, Query, Fragment, 사용자 정보가 포함된 값은 설정 오류로 처리한다.
- 빈 목록은 모든 Origin 허용이 아니라 Cross-Origin 비허용을 의미한다.

잘못된 Origin을 조용히 무시하지 않고 애플리케이션 시작 시 설정 오류로 드러내 운영 오설정을 방지한다. Setter, Lombok과 Runtime 변경 기능은 추가하지 않는다.

Profile별 설정은 다음과 같다.

- 기본 `application.yml`: 빈 목록
- `application-local.yml`: `http://localhost:3000`, `http://127.0.0.1:3000`
- `application-test.yml`: `http://localhost:3000`
- `application-integration-test.yml`: 빈 목록을 유지
- 운영 Origin: 미확정, 하드코딩하지 않음

`.env.example`에는 검증되지 않은 List 환경 변수 binding 예시를 추가하지 않는다. Origin 추가 방법은 Profile YAML 기준으로 README에 설명한다.

## Spring MVC CORS 정책

`com.ssafy.b209.global.config.CorsConfig`는 `WebMvcConfigurer`를 구현하고 `CorsProperties`를 주입받아 하나의 전역 MVC 정책을 구성한다.

- Mapping: `/api/v1/**`
- Allowed origins: 현재 Profile의 `app.cors.allowed-origins`
- Allowed methods: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`
- Allowed headers: `Content-Type`, `Accept`, `Authorization`
- Exposed headers: 없음
- Allow credentials: `false`
- Preflight max age: 3600초

`CorsFilter`, `CorsConfigurationSource`, Controller별 `@CrossOrigin`, wildcard Origin과 wildcard Header를 사용하지 않는다. CORS는 브라우저의 Cross-Origin 정책이며 인증·인가, CSRF 방어 또는 사용자 권한 검증을 대체하지 않는다.

Origin 목록이 비어 있으면 `/api/v1/**` Mapping은 유지하되 허용 Origin이 없으므로 Cross-Origin 요청에 허용 Header를 반환하지 않는다.

## 테스트 설계

### OpenApiConfigTest

- `OpenAPI` Bean의 Title, Description과 version `v1`을 검증한다.
- Server URL과 Security Scheme이 없음을 검증한다.
- `GroupedOpenApi`의 Group 이름과 `/api/v1/**` 탐색 범위를 검증한다.
- Configuration Context가 정상적으로 생성되는지 검증한다.

### SwaggerEndpointTest

Springdoc Auto Configuration을 포함하는 최소 Spring Boot 테스트 Context와 `MockMvc`를 사용한다. `src/test/java`의 테스트 전용 `/api/v1/test` Controller만 문서 생성에 사용한다.

- `/swagger-ui.html`: 200 또는 `/swagger-ui/index.html` Redirect
- `/swagger-ui/index.html`: 200 및 HTML Resource
- `/v3/api-docs`: 200, JSON, `openapi`, `info`, `paths` 존재
- `/v3/api-docs/api-v1`: 200, `/api/v1/test` 포함
- Swagger 자체 Endpoint와 API 범위 밖 테스트 Endpoint 미포함
- 공통 성공·오류·Validation Schema의 공개 필드 존재
- 내부 코드 객체, HTTP Status, Exception 정보 미노출

Swagger UI HTML 전체, OpenAPI JSON 전체와 Springdoc 내부 Schema 이름 또는 속성 순서에는 과도하게 결합하지 않는다.

### CorsPropertiesTest와 CorsConfigTest

- `null`, 빈 목록, 공백 제거와 중복 제거를 검증한다.
- wildcard와 잘못된 Origin을 거부하는지 검증한다.
- 허용 Origin의 실제 GET 요청에 정확한 `Access-Control-Allow-Origin`이 반환되는지 검증한다.
- 허용 Origin의 Preflight 요청에 Method, Header와 Max Age가 반영되는지 검증한다.
- `Access-Control-Allow-Credentials`가 `true`가 아님을 검증한다.
- 비허용 Origin과 비허용 Method가 허용되지 않는지 검증한다.
- `/api/v1/**` 밖의 요청에는 CORS Header가 적용되지 않는지 검증한다.
- 빈 Origin 목록이 wildcard 허용으로 동작하지 않는지 검증한다.

CORS 테스트는 테스트 전용 Controller와 Spring MVC만 사용하며 DB, Repository, Service, 외부 네트워크 또는 Browser 자동화를 사용하지 않는다.

## 회귀 및 완료 검증

다음 명령을 Windows 환경에서 실행한다.

```powershell
gradlew.bat clean test
gradlew.bat spotlessCheck
gradlew.bat javadoc
gradlew.bat dependencyInsight --dependency springdoc-openapi --configuration runtimeClasspath
```

추가로 다음을 확인한다.

- 기존 H2, Testcontainers MySQL, Flyway 테스트 성공
- 기존 `ApiResponse` JSON 테스트 성공
- 기존 `GlobalExceptionHandler` 테스트 성공
- Javadoc 인덱스 생성
- Springdoc 중복과 Springfox 의존성 없음
- 기존 JSON 응답 계약 유지
- DB 설정, Flyway Migration, 테이블, 인증 코드와 실제 도메인 API 변경 없음
- 애플리케이션 실행 환경이 준비되면 Swagger Endpoint를 실제 HTTP로 확인하고 MockMvc 결과와 구분해 보고

## 문서화

README에는 다음 내용만 기존 문서에 추가한다.

- Backend 기본 포트 `8080`과 Swagger/OpenAPI 접속 경로
- Swagger UI 사용 순서와 현재 운영 Controller가 없을 수 있다는 제한
- 공통 성공·오류·Validation 응답 예시
- `/api/v1/**` CORS 적용 범위
- `local` Profile의 허용 Origin
- 허용 Method, Header, Credentials와 Max Age
- Profile YAML에서 Origin을 추가하는 방법
- wildcard 금지, 운영 Origin 분리, Cookie 인증 및 Spring Security 도입 시 재검토 사항
- CORS가 인증·인가나 CSRF 방어가 아니라는 설명

## 제외 범위

이번 작업에서는 Spring Security, JWT, 인증·인가, Swagger Authorize 기능, 실제 Controller·Service·Repository·도메인 DTO, 도메인별 Swagger 문서, 그림 활동 API, DB 변경, S3, Redis, FastAPI 연동, 운영 배포 설정과 Swagger UI 커스텀을 구현하지 않는다.

## Git 정책

- Branch 이름에는 Jira 이슈 코드를 넣지 않는다.
- 권장 작업 Branch: `feat/swagger-cors`
- Commit 및 Merge Request에만 `S15P11B209-135`를 포함한다.
- 사용자가 별도로 요청하기 전에는 Commit, Push와 Merge Request 생성을 수행하지 않는다.
- Merge 후에도 기록용 Source branch를 삭제하지 않는다.
