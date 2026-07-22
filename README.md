# S15P11B209

만 4세~12세 아동이 그림과 대화를 통해 생각과 감정을 표현하도록 돕고, 보호자와 전문가에게 활동 기록과 참고용 분석 결과를 제공하는 서비스입니다. 심리 진단이나 치료 결과를 제공하지 않습니다.

Flutter 모바일 앱과 Next.js 웹은 Spring Boot REST API를 공통으로 사용합니다. 그림 분석과 대화 생성을 담당할 FastAPI AI 서버, 파일 저장을 위한 AWS S3, 알림을 위한 Firebase는 후속 작업에서 연동합니다.

주요 사용자는 아동, 보호자, 전문가, 관리자입니다.

## 기술 스택

현재 백엔드 초기 구성에 적용한 기술은 다음과 같습니다.

- Java 21 LTS
- Spring Boot 3.5.16
- Gradle 8.14.3 Wrapper
- Spring Web MVC
- Spring Data JPA
- MySQL 8.4.10 LTS, Flyway
- H2 In-memory, Testcontainers MySQL
- Jakarta Bean Validation
- JUnit 5, Mockito, Spring Boot Test
- springdoc-openapi
- Spotless 8.8.0과 Google Java Format
- SLF4J와 Logback

다음 기술은 후속 작업에서 필요한 시점에 추가합니다.

- Spring Security와 JWT
- AWS S3, Redis, Firebase Cloud Messaging
- FastAPI 연동
- Actuator와 Micrometer

Actuator는 초기 Application Context와 서버 실행 확인에 필수적이지 않아 현재 의존성에서 제외했습니다.

## 저장소 구조

현재 생성된 구조는 다음과 같습니다.

```text
S15P11B209/
├── backend/
│   ├── build.gradle
│   ├── settings.gradle
│   ├── gradlew
│   ├── gradlew.bat
│   ├── gradle/wrapper/
│   └── src/
│       ├── main/
│       │   ├── java/com/ssafy/b209/B209Application.java
│       │   └── resources/
│       │       ├── application.yml
│       │       ├── application-local.yml
│       │       ├── application-test.yml
│       │       ├── application-integration-test.yml
│       │       └── db/migration/V1__create_initial_schema.sql
│       └── test/java/com/ssafy/b209/
│           ├── B209ApplicationTests.java
│           └── database/DatabaseMigrationIntegrationTest.java
├── frontend/
│   ├── mobile/
│   └── web/
├── ai/
├── infra/
├── docs/
└── .env.example
```

Java는 빈 패키지를 Git으로 관리하지 않습니다. 기능 구현 시 필요한 패키지만 생성하며, 빈 클래스·인터페이스·`package-info.java`로 예정 구조를 채우지 않습니다.

향후 백엔드 패키지는 다음 책임을 기준으로 확장합니다.

```text
com.ssafy.b209
├── global
│   ├── config
│   ├── response
│   ├── exception
│   └── util
├── domain
│   ├── auth
│   ├── user
│   ├── expert
│   ├── child
│   ├── consent
│   ├── drawing
│   ├── analysis
│   ├── conversation
│   ├── report
│   ├── history
│   ├── notification
│   ├── community
│   ├── admin
│   └── counseling
└── infrastructure
    ├── ai
    ├── storage
    ├── notification
    └── persistence
```

Controller는 HTTP 요청과 응답, Service는 비즈니스 로직과 트랜잭션, Repository는 데이터베이스 접근을 담당합니다. 외부 시스템 구현은 핵심 비즈니스 로직과 분리된 Client 경계 뒤에 둡니다.

## 실행 환경

```text
Java: 21
Spring Boot: 3.5.16
Gradle: 8.14.3 Wrapper
Default Profile: local
Default Port: 8080
```

로컬에 Java 21을 설치하고 `JAVA_HOME`을 설정해야 합니다. Gradle은 별도로 설치할 필요가 없습니다.

## 실행 방법

먼저 백엔드 디렉터리로 이동합니다.

```bash
cd backend
```

```bash
# macOS / Linux
./gradlew bootRun

# Windows
gradlew.bat bootRun
```

Profile을 명시하려면 다음 명령을 사용합니다.

```bash
# macOS / Linux
./gradlew bootRun --args='--spring.profiles.active=local'

# Windows
gradlew.bat bootRun --args="--spring.profiles.active=local"
```

## Swagger UI와 OpenAPI

백엔드 실행 후 아래 URL에서 API 문서를 확인할 수 있습니다. 기본 포트는 `8080`이며, 서버 포트를 변경했다면 URL의 포트도 함께 변경합니다.

```text
http://localhost:8080/swagger-ui.html
http://localhost:8080/swagger-ui/index.html
http://localhost:8080/v3/api-docs
http://localhost:8080/v3/api-docs/api-v1
```

`/swagger-ui.html`은 `/swagger-ui/index.html`로 리다이렉트되는 호환 경로입니다. Swagger UI를 연 뒤 API와 공통 Schema를 확인하고, 각 Endpoint에서 **Try it out**을 선택해 요청 값을 입력한 다음 **Execute**로 요청합니다. 실행 결과의 HTTP Status와 Response Body를 함께 확인합니다.

기본 OpenAPI 문서는 `/v3/api-docs`이고, `/v3/api-docs/api-v1`은 `/api/v1/**` 경로만 포함하는 `api-v1` 그룹 문서입니다. 현재 Production Controller가 아직 없으므로 문서의 API 목록은 비어 있을 수 있습니다. Controller와 요청·응답 DTO를 추가하면 해당 API와 공통 Schema가 문서에 표시됩니다.

## CORS 정책

CORS는 `/api/v1/**`에만 적용합니다. local Profile에서는 아래 정책을 사용합니다.

| 항목 | 값 |
| --- | --- |
| 허용 Origin | `http://localhost:3000`, `http://127.0.0.1:3000` |
| 허용 Method | `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS` |
| 허용 Header | `Content-Type`, `Accept`, `Authorization` |
| Credentials | `false` |
| Preflight Max Age | 3600초 |

Origin은 scheme·host·port가 모두 정확히 일치해야 하며 wildcard는 허용하지 않습니다. 허용 Origin은 Profile별 `app.cors.allowed-origins`로 분리해 설정하고, 설정이 비어 있으면 Cross-Origin 요청을 허용하지 않습니다. CORS는 브라우저의 Cross-Origin 접근 제어일 뿐 Cookie 인증이나 Spring Security 도입 전의 인증·인가·CSRF 방어를 대체하지 않습니다.

## Database

```text
MySQL: 8.4.10 LTS
H2: 빠른 테스트 전용
Testcontainers MySQL: 통합 테스트 전용
Migration: Flyway
Character Set: utf8mb4
Collation: utf8mb4_0900_ai_ci
Storage Engine: InnoDB
```

Profile별 Database 책임은 다음과 같습니다.

| Profile | Database | Flyway | Hibernate `ddl-auto` | 용도 |
| --- | --- | --- | --- | --- |
| `local` | 로컬 MySQL | 활성화 | `validate` | 개발 서버 실행 |
| `test` | H2 In-memory | 비활성화 | `create-drop` | 빠른 Context·Service 테스트 |
| `integration-test` | Testcontainers MySQL | 활성화 | `validate` | 실제 Migration과 제약조건 검증 |

H2는 MySQL `JSON`, Collation, FK 삭제 정책, Unique와 Index의 최종 검증에 사용하지 않습니다. MySQL용 Migration을 H2용으로 복제하지 않으며, 최종 호환성은 Testcontainers에서 확인합니다.

### Local Database 준비

MySQL에서 먼저 Database 존재 여부를 확인합니다.

```sql
SHOW DATABASES;
```

`dodam`이 없다면 다음과 같이 생성합니다. Database 생성은 Flyway Migration 범위가 아닙니다.

```sql
CREATE DATABASE dodam
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
```

로컬 개발에서는 임시로 `root` 계정을 사용할 수 있습니다. 팀 공용 또는 운영 환경에서는 필요한 권한만 가진 `dodam_app` 전용 계정을 사용하고 실제 비밀번호를 문서나 Git에 저장하지 않습니다.

Local Profile은 다음 환경 변수를 사용합니다.

```text
DB_HOST
DB_PORT
DB_NAME
DB_USERNAME
DB_PASSWORD
```

Spring Boot는 저장소 루트의 `.env` 파일을 자동으로 읽지 않습니다. IntelliJ에서는 아래 위치의 개인 Run Configuration에 환경 변수를 입력합니다.

```text
Run
→ Edit Configurations
→ Spring Boot 실행 설정 선택
→ Environment variables
```

비밀번호가 없는 로컬 MySQL에서는 `DB_PASSWORD`를 빈 값으로 둘 수 있습니다. 개인 Run Configuration과 실제 `.env`는 Git에 포함하지 않습니다.

### Local Profile 실행

macOS 또는 Linux:

```bash
DB_HOST=127.0.0.1 \
DB_PORT=3306 \
DB_NAME=dodam \
DB_USERNAME=root \
DB_PASSWORD='개인 비밀번호' \
./gradlew bootRun --args='--spring.profiles.active=local'
```

Windows PowerShell:

```powershell
$env:DB_HOST="127.0.0.1"
$env:DB_PORT="3306"
$env:DB_NAME="dodam"
$env:DB_USERNAME="root"
$env:DB_PASSWORD="개인 비밀번호"

.\gradlew.bat bootRun --args="--spring.profiles.active=local"
```

### Migration 관리

- 애플리케이션 실행 시 Flyway가 `src/main/resources/db/migration`의 Migration을 적용합니다.
- 파일명은 `V{버전}__{설명}.sql` 형식을 사용합니다.
- 이미 적용된 Migration은 수정하지 않고 스키마 변경 시 새 Migration을 추가합니다.
- Local과 Integration Test에서는 Hibernate `ddl-auto=validate`만 사용합니다.
- Flyway가 스키마 변경의 단일 기준이며 Flyway Clean은 비활성화되어 있습니다.
- ERDCloud에는 `V1__create_initial_schema.sql`을 SQL Import합니다.

예시:

```text
V1__create_initial_schema.sql
V2__add_drawing_indexes.sql
V3__add_report_status.sql
```

## 테스트

```bash
# macOS / Linux
./gradlew clean test

# Windows
gradlew.bat clean test
```

전체 테스트에는 Testcontainers MySQL 통합 테스트가 포함되므로 Docker가 실행 중이어야 합니다. 통합 테스트만 실행하려면 다음 명령을 사용합니다.

```bash
# macOS / Linux
./gradlew test --tests "*DatabaseMigrationIntegrationTest"

# Windows
gradlew.bat test --tests "*DatabaseMigrationIntegrationTest"
```

## 코드 포맷

```bash
# macOS / Linux
./gradlew spotlessCheck
./gradlew spotlessApply

# Windows
gradlew.bat spotlessCheck
gradlew.bat spotlessApply
```

SonarLint는 프로젝트 의존성이 아닌 권장 IDE 플러그인으로 사용합니다.

## Javadoc

```bash
# macOS / Linux
./gradlew javadoc

# Windows
gradlew.bat javadoc
```

생성된 문서는 `build/docs/javadoc/index.html`에서 확인합니다. 저장소 루트 기준 경로는 `backend/build/docs/javadoc/index.html`입니다. Javadoc은 빌드 결과물이므로 `build/` 디렉터리와 함께 Git에 Commit하지 않습니다.

## 로컬 이미지 저장

개발 및 1차 MVP에서는 후속 그림 스냅샷 업로드 API가 사용할 이미지 저장 경계로 로컬 파일 시스템을 사용합니다.

```dotenv
LOCAL_IMAGE_STORAGE_ROOT=./storage/images
LOCAL_IMAGE_MAX_SIZE=10485760
```

- 기본 Root는 애플리케이션 실행 디렉터리 기준 `./storage/images`입니다.
- JPEG와 PNG를 지원하며 파일별 최대 크기는 기본 10 MiB입니다.
- 전달된 MIME Type과 확장자만 신뢰하지 않고 실제 이미지 Signature와 교차 검증합니다.
- 원본 파일명은 저장 경로에 사용하지 않으며 날짜와 UUID로 상대 `storageKey`를 생성합니다.
- 서버 절대 경로는 저장 결과에 포함하지 않고 Storage Root 외부 경로와 Symbolic Link 이탈을 거부합니다.
- 저장 중에는 Root 내부 임시 파일을 사용하고 기존 파일을 덮어쓰지 않습니다.
- 로컬 저장 파일은 `.gitignore` 대상이며 Git에 Commit하지 않습니다.
- 서버 인스턴스 교체나 디스크 초기화 시 파일이 유실될 수 있으므로 운영 환경에서는 S3 호환 Object Storage로 전환해야 합니다.
- 이번 기능에는 HTTP 업로드 API, DB Metadata 저장, 이미지 조회, AI 분석이 포함되지 않습니다.

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

## 공통 API 오류 응답

일반 오류 응답은 성공 응답과 동일한 최상위 필드를 사용하며 `success`는 항상 `false`입니다.

```json
{
  "success": false,
  "code": "COMMON_400_001",
  "message": "요청 값이 올바르지 않습니다.",
  "data": null
}
```

Request Body 또는 Model Attribute Validation이 실패하면 안전한 필드 오류와 객체 오류만 `data`에 포함합니다.

```json
{
  "success": false,
  "code": "COMMON_400_001",
  "message": "요청 값이 올바르지 않습니다.",
  "data": {
    "fieldErrors": [
      {
        "field": "childName",
        "message": "아동 이름은 필수입니다."
      }
    ],
    "globalErrors": []
  }
}
```

공통 오류 코드는 다음과 같습니다.

| Code | HTTP Status | Message |
| --- | --- | --- |
| `COMMON_400_001` | `400 Bad Request` | 요청 값이 올바르지 않습니다. |
| `COMMON_400_002` | `400 Bad Request` | 요청 값의 형식이 올바르지 않습니다. |
| `COMMON_400_003` | `400 Bad Request` | 요청 본문을 읽을 수 없습니다. |
| `COMMON_400_004` | `400 Bad Request` | 필수 요청 파라미터가 누락되었습니다. |
| `COMMON_404_001` | `404 Not Found` | 요청한 리소스를 찾을 수 없습니다. |
| `COMMON_405_001` | `405 Method Not Allowed` | 지원하지 않는 HTTP 메서드입니다. |
| `COMMON_409_001` | `409 Conflict` | 요청이 현재 데이터 상태와 충돌합니다. |
| `COMMON_500_001` | `500 Internal Server Error` | 서버 내부 오류가 발생했습니다. |

예상 가능한 비즈니스 오류는 도메인별 `ErrorCode`를 구현한 뒤 `BusinessException`으로 전달합니다.

```java
throw new BusinessException(SomeDomainErrorCode.RESOURCE_NOT_FOUND);
```

- Controller에서 반복적인 `try-catch`를 작성하지 않습니다.
- `GlobalExceptionHandler`가 예외를 HTTP Status와 `ApiErrorResponse<T>`로 변환합니다.
- 요청 파라미터 Validation 실패는 400으로, Controller 반환값 Validation 실패는 서버 응답 계약 오류인 500으로 처리합니다.
- HTTP Status는 `ResponseEntity`로 전달하고 Response Body에 중복하지 않습니다.
- Exception 원문 메시지와 Stack Trace를 클라이언트에 반환하지 않습니다.
- Validation 오류에는 필드명과 안전한 메시지만 포함하며 `rejectedValue`는 반환하지 않습니다.
- SQL, 테이블·컬럼·제약조건 이름과 요청 Body 전체를 응답하지 않습니다.
- 예상 가능한 4xx는 `DEBUG`, 데이터 무결성 충돌은 `WARN`, 예상하지 못한 5xx는 `ERROR`로 기록합니다.
- 로그에 Token, 비밀번호, 요청 Body와 개인정보를 기록하지 않습니다.

## API 버전과 외부 시스템 경계

외부 REST API는 `/api/v1` 경로를 사용합니다. `/api/v1`을 전역 Context Path로 설정하지 않고 향후 Controller의 Request Mapping 또는 공통 상수로 관리합니다. 따라서 Actuator나 Swagger 같은 비즈니스 API 외 경로에 API 버전이 강제로 붙지 않습니다.

- Flutter와 Next.js는 Spring Boot의 `/api/v1/**`만 호출합니다.
- Spring Boot만 FastAPI의 `/internal/v1/**`를 호출합니다.
- 클라이언트는 FastAPI 내부 API나 S3 `storageKey`를 직접 지정하지 않습니다.
- 그림과 음성 파일은 Spring Boot가 형식과 권한을 검증합니다. 현재 1차 MVP 이미지는 로컬에 저장하며 운영 환경에서는 S3 호환 Object Storage로 전환합니다.
- Firebase 연동은 알림 인프라 구현으로 분리합니다.

그림 활동 생성과 파일 등록 API에는 향후 `Idempotency-Key` Header를 적용합니다. 중복 요청 검사와 저장 방식은 해당 API 작업에서 설계합니다.

## 환경 변수와 보안

실제 비밀번호, Token, API Key, 인증서와 `.env` 파일은 Git에 저장하지 않습니다. 루트 `.env.example`은 향후 연동에 필요한 변수 이름을 공유하기 위한 예시이며 실제 Secret을 포함하지 않습니다.

- 개인정보와 아동 데이터는 애플리케이션 로그에 기록하지 않습니다.
- 아동의 음성 원문과 대화 원문을 로그에 기록하지 않습니다.
- 그림 파일 전체 URL과 Pre-signed URL을 불필요하게 기록하지 않습니다.
- AI 작업 로그에는 사용자 개인정보 대신 작업 ID를 사용합니다.

## 후속 작업

1. MySQL과 Spring Data JPA 연결
2. Flyway 기반 초기 DB 스키마 구성
3. 공통 API 응답 형식 구현
4. 전역 예외 처리 구현
5. Swagger UI와 CORS 설정
6. 그림 활동 생성 API 구현
7. `Idempotency-Key` 처리
8. Spring Security와 JWT 인증
9. S3 Pre-signed URL 업로드
10. FastAPI AI 서버 연동

## 그림 활동 세션 생성 API

아동의 그림 활동을 시작할 때 다음 Endpoint를 사용합니다.

```http
POST /api/v1/drawing-sessions
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json
```

CANVAS 입력 방식은 Canvas 설정이 필요합니다.

```json
{
  "childId": 1,
  "drawingTypeId": 2,
  "inputMethod": "CANVAS",
  "clientStartedAt": "2026-07-21T11:30:00+09:00",
  "canvas": {
    "width": 1920,
    "height": 1080,
    "backgroundColor": "#FFFFFF"
  }
}
```

UPLOAD 입력 방식에서는 `canvas`를 사용하지 않습니다. 이미지 파일 업로드는 이 API의 범위가 아니며 후속 API에서 처리합니다.

```json
{
  "childId": 1,
  "drawingTypeId": 2,
  "inputMethod": "UPLOAD",
  "clientStartedAt": "2026-07-21T11:30:00+09:00",
  "canvas": null
}
```

생성 성공 시 HTTP 201과 `Location: /api/v1/drawing-sessions/{drawingSessionId}`를 반환합니다. 초기 상태는
`IN_PROGRESS`, 초기 단계는 `DRAWING`이며, 공식 `startedAt`은 클라이언트 시각이 아닌 서버 UTC 시각을
사용합니다.

- `Idempotency-Key`는 8~100자이며 제어 문자를 포함할 수 없습니다.
- 동일한 Key와 동일한 `childId`, `drawingTypeId`, `inputMethod` 요청은 기존 세션을 반환합니다.
- 동일한 Key를 다른 핵심 요청에 사용하면 HTTP 409를 반환합니다.
- 아동 한 명에게 동시에 하나의 진행 중인 그림 활동 세션만 허용합니다.
- CANVAS 크기는 가로·세로 각각 1~8192이며 배경색은 `#RRGGBB` 형식입니다.
- 운영용 `drawing_types` Seed는 포함하지 않습니다. API 호출 전에 환경에 맞는 활성 유형 데이터가 필요합니다.
- 현재 인증·보호자 소유 관계·필수 동의 검증은 아직 연결되지 않았으며 `startedByUserId`는 `null`로 저장됩니다.
