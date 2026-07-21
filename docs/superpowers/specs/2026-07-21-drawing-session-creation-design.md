# 그림 활동 세션 생성 API 설계

## 1. 목적

아동이 캔버스 또는 업로드 방식의 그림 활동을 시작할 때 `DrawingSession`을 생성하는
`POST /api/v1/drawing-sessions` API를 구현한다. 생성 직후 세션은 `IN_PROGRESS` 상태와
`DRAWING` 단계이며, 공식 시작 시각은 서버의 UTC 시각을 사용한다.

이번 설계는 Jira `S15P11B209-138`만 다룬다. 이미지, Stroke, AI 분석, 대화, 감정,
활동 완료, 리포트, 인증·인가 신규 구현은 포함하지 않는다.

## 2. 확인된 프로젝트 상태와 충돌

- 기준 브랜치: `origin/develop`의 `e0d2790`
- Java 21, Spring Boot 3.5.16, Gradle Wrapper 8.14.3
- Base Package: `com.ssafy.b209`
- 공통 응답, 전역 예외 처리, Swagger UI, `/api/v1/**` CORS가 적용되어 있다.
- `DrawingActivity`, `/api/activities`, `activities` 테이블은 존재하지 않는다.
- `Child`, `DrawingType`, `DrawingSession` JPA Entity와 Repository는 존재하지 않는다.
- 인증, 보호자-아동 관계, 동의 검증을 수행하는 Production 코드는 존재하지 않는다.
- `children.tutorial_status`와 `children.profile_status`는 존재한다.
- `drawing_sessions.session_status` 기본값과 Check Constraint는 `IN_PROGRESS`를 지원한다.
- `drawing_sessions.current_stage` 기본값과 Check Constraint는 `DRAWING`을 지원한다.
- `drawing_sessions.started_by_user_id`는 Nullable이다.
- `drawing_sessions.idempotency_key`와 진행 세션 전용 Index는 존재하지 않는다.
- `drawing_types` 운영 초기 데이터는 존재하지 않는다.
- 공통 생성 성공 코드는 `COMMON_201`이다.
- JPA Auditing과 공통 `Clock` Bean은 존재하지 않는다.

따라서 URI나 Resource 명칭 충돌은 없다. V1 Migration은 수정하지 않고 V2 Migration에서
멱등성 저장 구조와 진행 세션 조회 Index만 추가한다. 운영 `drawing_types` Seed는 임의로
생성하지 않으며 테스트 Fixture에서만 필요한 행을 만든다.

## 3. 선택한 접근 방식

DB Unique Constraint와 MySQL 비관적 잠금을 함께 사용한다. 생성 Transaction은
`READ_COMMITTED`를 사용해 존재하지 않는 멱등 Key를 조회할 때 발생하는 gap lock 교착을
피한다.

1. `idempotency_key`의 Unique Constraint가 같은 Key의 중복 Row를 최종 방어한다.
2. 기존 Idempotency-Key는 잠금 없는 빠른 조회로 재시도를 처리한다.
3. 신규 요청은 Child Row의 `PESSIMISTIC_WRITE` Lock으로 서로 다른 Key가 같은 아동의 세션을 동시에
   만드는 Race Condition을 방지한다.
4. Child 잠금 뒤 Idempotency-Key와 진행 세션을 잠금 조회해 대기 중 생성된 Row를 현재 읽기로 확인한다.
5. 서로 다른 아동이 같은 Key를 동시에 사용하면 Unique Constraint를 전용 멱등 충돌로 변환한다.

Generated Column 기반 활성 세션 Unique Constraint는 MySQL 의존성과 H2 차이를 늘리므로
사용하지 않는다. 별도 멱등성 테이블은 이번 Endpoint를 넘어서는 범용 구조이므로 만들지
않는다. Redis Lock, JVM Lock, `synchronized`도 사용하지 않는다.

## 4. 패키지와 책임

### 아동

- `child.domain.Child`: 활동 생성에 필요한 ID, 생년월일, Profile 상태, Tutorial 상태,
  삭제 시각을 매핑한다.
- `child.repository.ChildRepository`: 삭제되지 않은 아동 조회와 Child Row 잠금을 담당한다.

### 그림 활동

- `drawing.domain.DrawingType`: 유형 코드·이름·활성 여부·권장 연령·선택 가능 주체를
  매핑한다.
- `drawing.domain.DrawingSession`: 생성 불변 조건과 초기 상태를 보장한다.
- `drawing.repository.DrawingTypeRepository`: 유형 ID 조회를 담당한다.
- `drawing.repository.DrawingSessionRepository`: 멱등 Key 잠금 조회, 진행 세션 조회와
  저장을 담당한다.
- `drawing.service.DrawingSessionService`: 검증 순서, Transaction, 잠금과 DTO 변환을
  조율한다.
- `drawing.controller.DrawingSessionController`: Header와 Body를 받고 201 및 Location을
  반환한다.
- `drawing.dto`: 불변 Request·Response `record`를 제공한다.
- `drawing.exception.DrawingErrorCode`: 이번 생성 API에 필요한 오류만 정의한다.

### 시간

- `global.config.TimeConfig`: `Clock.systemUTC()` Bean을 제공한다.
- Entity의 `startedAt`은 UTC 기준 `LocalDateTime`으로 저장한다.
- Response는 해당 값을 `ZoneOffset.UTC` 기준 `Instant`로 변환한다.
- 시스템 기본 Time Zone을 사용하지 않는다.

## 5. API 계약

### 요청

```http
POST /api/v1/drawing-sessions
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json
```

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

`CreateDrawingSessionRequest`는 `childId`, `drawingTypeId`, `inputMethod`,
`clientStartedAt`, `canvas`를 가진다. `CanvasConfigurationRequest`는 너비, 높이와 배경색을
가진다. 클라이언트는 상태, 단계, 서버 시작 시각, 사용자 ID와 멱등 Key Body 필드를
지정할 수 없다.

### 응답

성공 시 `CommonSuccessCode.CREATED`를 사용한 `ApiResponse<CreateDrawingSessionResponse>`와
HTTP 201을 반환한다. Location은 `/api/v1/drawing-sessions/{drawingSessionId}` 형식의 상대
URI다.

Response Data에는 다음 필드만 포함한다.

- `drawingSessionId`
- `childId`
- `drawingType`: `drawingTypeId`, `code`, `name`
- `inputMethod`
- `sessionStatus`
- `currentStage`
- `tutorialRequired`
- `startedAt`

Entity, 아동 이름·생년월일, 사용자 ID, 삭제 시각과 내부 컬럼은 노출하지 않는다.

## 6. 요청 검증

- `childId`, `drawingTypeId`: 필수이며 1 이상
- `inputMethod`: `CANVAS` 또는 `UPLOAD`
- `clientStartedAt`: Offset이 포함된 `OffsetDateTime`, 필수
- `Idempotency-Key`: 필수, 8~100자, Blank 금지, ISO 제어 문자 금지
- `CANVAS`: Canvas 필수, 너비·높이 1~8192, 배경색 `^#[0-9A-Fa-f]{6}$`
- `UPLOAD`: Canvas가 없어도 성공하며 전달된 Canvas는 검증·저장에 사용하지 않는다.

기본 필드는 Bean Validation으로 검증한다. Canvas는 `UPLOAD`에서 전달값을 무시해야 하므로
Service의 명시적인 조건부 검증을 사용한다. 새로운 Validation Library는 추가하지 않는다.

Controller의 `Idempotency-Key` Header는 `required=false`로 수신하여 누락도 도메인 오류
`IDEMPOTENCY_KEY_REQUIRED`로 일관되게 변환한다.

## 7. 도메인 규칙

### Child

삭제되지 않은 아동을 ID로 조회한다. `profile_status`가 `ACTIVE`가 아니거나 `deleted_at`이
있으면 존재하지 않는 활동 대상과 동일하게 처리한다.

`tutorialRequired`는 다음처럼 계산한다.

- `COMPLETED`, `SKIPPED`: `false`
- `NOT_STARTED`, `IN_PROGRESS`: `true`

### DrawingType

- 존재하고 `is_active=true`여야 한다.
- 아동의 생년월일과 UTC 기준 오늘을 `Period.between`으로 계산한 만 나이를 사용한다.
- 권장 최소·최대 연령이 `null`이면 해당 제한은 없다.
- 인증 주체를 식별할 수 없으므로 `selectable_by`의 실제 주체 검증은 수행하지 않는다.
  값은 문자열 Enum으로 매핑해 DB 허용값과의 일치만 보장한다.

### DrawingSession

Factory Method `DrawingSession.start(...)`가 다음 초기 상태를 보장한다.

- `sessionStatus=IN_PROGRESS`
- `currentStage=DRAWING`
- `startedAt`: 서버 UTC 시각
- `completedAt=null`
- `deletedAt=null`
- `startedByUserId=null`
- `title`, 선택 감정, 표현 감정: DB 기본 `NULL`

DB에 없는 `source_post_id`, Canvas JSON과 후속 도메인 관계는 추가하지 않는다.

## 8. 처리 순서와 Transaction

1. Body 기본 Validation
2. Canvas 조건부 Validation
3. Idempotency-Key 형식 검증
4. Idempotency-Key 기준 일반 조회
5. 기존 Row가 있으면 핵심 요청 비교 후 기존 응답 또는 409 반환
6. 삭제되지 않은 Child Row를 `PESSIMISTIC_WRITE`로 조회
7. Idempotency-Key 기준 `PESSIMISTIC_WRITE` 재조회
8. Child 활성 상태와 Tutorial 상태 확인
9. DrawingType 조회 및 활성·만 나이 제한 확인
10. 같은 아동의 `IN_PROGRESS`이고 삭제되지 않은 Session을 `PESSIMISTIC_WRITE`로 조회
11. `DrawingSession.start(...)` 호출
12. 저장과 Flush
13. Response DTO 변환
14. Commit

전체 흐름은 `READ_COMMITTED`인 하나의 `@Transactional` 경계에서 수행한다. 멱등 핵심 요청 비교값은
`childId`, `drawingTypeId`, `inputMethod`다. `clientStartedAt`과 Canvas 값은 재시도 시 달라질
수 있으므로 비교하지 않는다.

동일 Key·동일 핵심 요청은 기존 Session을 반환한다. 동일 Key·다른 핵심 요청은
`IDEMPOTENCY_KEY_CONFLICT`, 다른 Key·같은 아동의 진행 Session은
`ACTIVE_DRAWING_SESSION_EXISTS`를 반환한다. 잠금 또는 Unique 충돌의 의미를 안전하게
특정할 수 없는 경우 `DRAWING_SESSION_CREATION_CONFLICT`를 사용한다.

## 9. DB Migration

V2 Migration에서 다음만 변경한다.

```sql
ALTER TABLE drawing_sessions
    ADD COLUMN idempotency_key VARCHAR(100) NULL COMMENT '그림 세션 생성 멱등성 Key';

ALTER TABLE drawing_sessions
    ADD CONSTRAINT uk_drawing_sessions_idempotency_key UNIQUE (idempotency_key);

CREATE INDEX idx_drawing_sessions_active_child
    ON drawing_sessions (child_id, session_status, deleted_at);
```

기존 Row와 다른 생성 경로의 호환성을 위해 DB Column은 Nullable로 둔다. 이 API가 생성하는
Row는 Domain Factory에서 Key를 필수로 강제한다. 기존 V1 Migration은 수정하지 않는다.

## 10. 오류 코드

| Enum | HTTP | Code |
| --- | --- | --- |
| `CHILD_NOT_FOUND` | 404 | `DRAWING_404_001` |
| `DRAWING_TYPE_NOT_FOUND` | 404 | `DRAWING_404_002` |
| `DRAWING_TYPE_NOT_AVAILABLE` | 400 | `DRAWING_400_001` |
| `INVALID_CANVAS_CONFIGURATION` | 400 | `DRAWING_400_002` |
| `IDEMPOTENCY_KEY_REQUIRED` | 400 | `DRAWING_400_003` |
| `IDEMPOTENCY_KEY_INVALID` | 400 | `DRAWING_400_004` |
| `ACTIVE_DRAWING_SESSION_EXISTS` | 409 | `DRAWING_409_001` |
| `IDEMPOTENCY_KEY_CONFLICT` | 409 | `DRAWING_409_002` |
| `DRAWING_SESSION_CREATION_CONFLICT` | 409 | `DRAWING_409_003` |

기존 `BusinessException`, `GlobalExceptionHandler`와 `ApiErrorResponse`를 그대로 사용한다.
전역 계층이 도메인 DTO에 의존하지 않도록 이번 작업의 오류 Data는 `null`로 유지한다.
응답에는 SQL, Constraint 이름, Stack Trace, Idempotency-Key와 개인정보를 포함하지 않는다.

## 11. Swagger와 README

Controller에 `@Tag`, `@Operation`, `@ApiResponses`와 Request Header 문서를 작성한다.
201·400·404·409·500만 문서화하고 인증이 없으므로 401·403과 Bearer Scheme은 추가하지
않는다. 실제 파일은 별도 API에서 저장됨을 명시한다.

README에는 CANVAS·UPLOAD 예시, Idempotency-Key, 201·Location, 진행 세션과 멱등 규칙,
서버 시각, 운영 Seed 미포함, 인증·보호자 소유권·동의 검증 미연결 상태를 추가한다.

## 12. 테스트 전략

모든 Production 동작은 RED-GREEN-REFACTOR 순서로 구현한다.

- Domain 단위 테스트: 초기 상태, 필수 관계와 Key, Tutorial 계산, 만 나이 경계
- Service 단위 테스트: CANVAS·UPLOAD 성공, 활성·연령·Canvas 오류, 멱등 재요청,
  멱등 충돌, 진행 Session 충돌, 저장 미호출 조건
- Repository H2 테스트: 관계·Enum·UTC 시각·Key 저장, 진행 Session 필터,
  멱등 Key 조회와 Lock Method 실행
- Controller MockMvc 테스트: 201, Location, 공통 응답, Body·Header Validation,
  도메인 404·409, OpenAPI Schema
- Testcontainers MySQL 통합 테스트: V2 Flyway 적용, Unique·Check Constraint,
  같은 Key 재시도 Row 1건, 다른 Key 같은 아동 409, 동시 요청 중복 방지
- 회귀 검증: 전체 `clean test`, `spotlessCheck`, `javadoc`

Docker가 불가능하면 MySQL 테스트를 비활성화하거나 삭제하지 않고 미실행 이유를 보고한다.

## 13. Javadoc 원칙

새 Production Type과 공개 생성·서비스 메서드에는 책임, 계층 관계, 입력 계약과 상태 변경을
설명하는 한국어 Javadoc을 작성한다. 단순 Getter, Repository 선언과 테스트 메서드에는
형식적인 문서를 작성하지 않는다. `@author`, TODO와 `package-info.java`는 만들지 않는다.

## 14. 보안과 개인정보

- 사용자 ID를 하드코딩하지 않는다.
- Spring Security, JWT, 가짜 Principal과 임의 사용자 Header를 추가하지 않는다.
- `startedByUserId`는 인증 연결 전까지 `null`이다.
- Idempotency-Key, Authorization, Request Body와 아동 개인정보를 로그에 남기지 않는다.
- 아동 이름·생년월일, Entity, SQL과 내부 예외를 응답하지 않는다.

## 15. 제외 범위

- 아동 CRUD와 그림 유형 목록 API
- 그림 활동 상세 조회와 상태 전이
- 이미지, DrawingAsset, Snapshot, Stroke 저장
- AI 분석, FastAPI, 대화, STT·TTS
- 감정 저장, 활동 완료, 리포트와 PDF
- S3, Redis, Message Queue와 범용 멱등성 Framework
- 인증·인가와 보호자 관계·동의 Production 검증
