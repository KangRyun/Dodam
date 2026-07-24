# 대화 종료 API 설계

## 1. 목적

`S15P11B209-390`은 진행 중인 대화를 명시적으로 종료하고 다음 감정 회고 단계로 이동시키는 공개 API를 추가한다.
현재 Flutter 앱에는 `ConversationEndRepository`와 종료 확인 UI가 있으나 Remote 구현과 Backend Endpoint가 없어 Mock으로만 동작한다.

이 설계는 다음 계약 충돌을 해소한다.

- 현재 Jira는 `POST /api/v1/conversations/{conversationId}/end`를 제안한다.
- 이전 Notion 문서는 `/complete`를 사용한다.
- 전체 API 명세 v1.0은 종료 사유와 `REFLECTION` 전이를 요구한다.
- 현재 Flutter 모델은 `lastQuestionMessageId`와 `completed`만 정의한다.

외부 URI는 현재 Jira와 앱의 행위 중심 계약을 따라 `/end`로 확정한다. 범용 상태 변경 `PATCH`는 클라이언트가 임의 상태를
지정하게 하므로 사용하지 않는다.

## 2. 범위

### 포함

- 대화 종료 공개 API
- 보호자 소유 관계 검증
- `CONVERSING` 대화 세션의 `COMPLETED` 전이와 완료 시각 기록
- 연결된 그림 활동의 `REFLECTION` 단계 전이
- 종료 사유 영속화
- 마지막 질문 식별자 검증
- `Idempotency-Key` 기반 최초 응답 재생과 충돌 검증
- Backend 단위·Repository·Controller 테스트
- Flutter Remote Repository와 앱 계약 연결
- Swagger와 API 계약 문서 보완

### 제외

- 질문 건너뛰기 API
- 감정·제목 값 자체의 저장
- 전체 활동 완료 접수
- AI 분석 또는 리포트 생성 이벤트 발행
- 기존 대화 메시지 변경·삭제
- 기존 적용 Flyway Migration 수정

## 3. 외부 API 계약

### 요청

```http
POST /api/v1/conversations/{conversationId}/end
Authorization: Bearer <access-token>
Idempotency-Key: <8~100자 요청 식별자>
Content-Type: application/json
```

```json
{
  "reason": "GUARDIAN_REQUEST",
  "lastQuestionMessageId": 803
}
```

| 필드 | 필수 | 설명 |
| --- | --- | --- |
| `reason` | Y | `QUESTION_LIMIT_REACHED`, `CHILD_REQUEST`, `GUARDIAN_REQUEST`, `NO_MORE_QUESTION` 중 하나 |
| `lastQuestionMessageId` | N | 앱 화면에 마지막으로 표시된 질문 ID. 질문을 한 번도 표시하지 않았다면 `null` |

`lastQuestionMessageId`가 존재하면 해당 대화에 속한 최신 `QUESTION` 메시지여야 한다. 다른 대화의 메시지, 답변 메시지,
과거 질문을 전달하면 상태를 변경하지 않고 `409 CONVERSATION_LAST_QUESTION_MISMATCH`를 반환한다. 이를 통해 오래된 화면의
종료 요청이 더 진행된 대화를 종료하지 못하게 한다.

### 성공 응답

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {
    "conversationId": 20,
    "conversationStatus": "COMPLETED",
    "completed": true,
    "completionReason": "GUARDIAN_REQUEST",
    "completedAt": "2026-07-24T07:30:00",
    "nextStage": "REFLECTION"
  }
}
```

시각은 서버 `Clock`으로 생성한 UTC `LocalDateTime`을 기존 API 형식으로 직렬화한다.

### 오류

| HTTP | 오류 코드 | 조건 |
| --- | --- | --- |
| 400 | 공통 입력 오류 | Path, Header 길이 또는 Body 형식이 잘못됨 |
| 401 | 기존 인증 오류 | 유효한 Access Token이 없음 |
| 404 | `CONVERSATION_NOT_FOUND` | 대화가 없거나 보호자가 접근할 수 없음 |
| 409 | `CONVERSATION_NOT_CONVERSING` | 대화가 `FAILED` 등 종료할 수 없는 상태 |
| 409 | `CONVERSATION_LAST_QUESTION_MISMATCH` | 마지막 질문 Snapshot이 현재 최신 질문과 다름 |
| 409 | 기존 `IDEMPOTENCY_KEY_REUSED` | 같은 키를 다른 요청 Body에 재사용 |

자원 존재 여부가 권한 없는 사용자에게 노출되지 않도록 대화 없음과 접근 불가를 같은 404로 처리한다.

## 4. 상태 전이와 처리 순서

하나의 Transaction에서 다음 순서를 적용한다.

1. 인증된 사용자 ID를 해석한다.
2. 대화 세션을 비관적 쓰기 잠금으로 조회한다.
3. 연결된 그림 활동에 대한 보호자 접근 권한을 검증한다.
4. 그림 활동 세션을 비관적 쓰기 잠금으로 조회한다.
5. 대화와 그림 활동 상태, 마지막 질문 Snapshot을 검증한다.
6. 대화를 `COMPLETED`로 바꾸고 `completion_reason`, `completed_at`을 기록한다.
7. 그림 활동을 `REFLECTION`으로 전환한다.
8. Transaction 완료 후 공통 성공 응답을 반환한다.

후속 흐름은 다음 순서를 유지한다.

```text
대화 종료
  → 감정·제목 저장 PUT /drawing-sessions/{drawingSessionId}/reflection
  → 전체 활동 완료 POST /drawing-sessions/{drawingSessionId}/complete
  → 기존 ReportGenerationRequestedEvent
```

종료 API는 감정 값을 만들거나 전체 활동 완료를 접수하거나 리포트 이벤트를 발행하지 않는다.

## 5. 멱등성

- `Idempotency-Key`는 필수이며 8~100자, 제어 문자를 금지한다.
- 보호자 ID, HTTP Method, URI, Key를 Redis 식별자로 사용한다.
- Body 전체를 SHA-256 fingerprint로 비교한다.
- 같은 키와 같은 Body의 완료 응답은 최초 HTTP 응답을 재생한다.
- 같은 키와 다른 Body는 409를 반환한다.
- Redis 장애 시에도 DB 상태 전이가 자연 멱등하게 동작하도록 이미 `COMPLETED`인 세션은 저장된 완료 결과를 반환한다.
- 이미 완료된 세션에 새로운 키와 다른 종료 사유가 들어와도 최초 `completion_reason`과 `completed_at`을 변경하지 않는다.

기존 다음 질문 멱등 저장소의 Redis 선점·응답 재생 구현을 공통 명령 저장소로 일반화해 재사용하고, 기존 다음 질문 API의
외부 동작은 변경하지 않는다.

## 6. 데이터 모델

새 Flyway Migration에서 `conversation_sessions`에 다음 컬럼과 제약을 추가한다.

```sql
ALTER TABLE conversation_sessions
    ADD COLUMN completion_reason VARCHAR(30) NULL COMMENT '대화 종료 사유' AFTER question_count,
    ADD CONSTRAINT ck_conversation_sessions_completion_reason
        CHECK (
            completion_reason IS NULL
            OR completion_reason IN (
                'QUESTION_LIMIT_REACHED',
                'CHILD_REQUEST',
                'GUARDIAN_REQUEST',
                'NO_MORE_QUESTION'
            )
        );
```

기존 `completed_at` 컬럼은 새로 만들지 않고 Entity에 매핑한다. 기존 완료 데이터와 Migration 호환성을 위해
`completion_reason`은 DB에서 nullable로 두되, 새 종료 API는 완료 전이에 항상 값을 기록한다.

`ConversationCompletionReason`은 Java `enum`과 Dart `enum`으로 정의하고 DB 문자열과 동일하게 유지한다.

## 7. 도메인 규칙

`ConversationSession.complete(reason, completedAt)`은 다음 불변 조건을 담당한다.

- `CONVERSING`이면 `COMPLETED`, 사유, 완료 시각을 한 번만 기록한다.
- 이미 `COMPLETED`이면 기존 값을 유지한다.
- 그 외 상태면 전이를 거부한다.

`DrawingSession.enterReflection()`은 삭제되지 않은 `IN_PROGRESS/CONVERSING` 세션만 `REFLECTION`으로 전이한다.
이미 `REFLECTION`이면 멱등하게 유지하고, 그 외 상태는 거부한다. 감정·제목 저장은 기존 `saveReflection`이 계속 담당한다.

## 8. Flutter 계약

`RemoteConversationEndRepository`는 다음을 수행한다.

- `POST /api/v1/conversations/{conversationId}/end`
- `Idempotency-Key` Header와 JSON Body 전달
- 공통 `ApiResponse.data`에서 종료 결과 역직렬화
- 앱 Composition Root에서 Mock 대신 Remote 구현 주입
- 실패 후 재시도할 때 Controller가 보관한 같은 Key 재사용

현재 Dart의 null-aware map entry 문법은 지원되는 SDK 문법이므로 오류가 아니다. 요청 모델에는 `reason`을 추가하고
`lastQuestionMessageId`가 null이면 JSON에서 생략한다.

## 9. 테스트 전략

### Backend

- Domain: 정상 완료, 중복 완료 값 보존, 잘못된 상태 거부, 그림 단계 전이
- Service: 소유권 없음, 대화 없음, 최신 질문 불일치, 질문 없는 종료, 정상 원자적 전이, 이미 완료된 자연 멱등
- Controller: 인증·Header·Validation·공통 응답·오류 응답
- Idempotency: 같은 요청 재생, 다른 Body 충돌, Redis 장애 시 DB 자연 멱등
- Repository/Migration: `completion_reason`, `completed_at` 저장과 CHECK 제약
- 회귀: Reflection 및 Drawing Completion 흐름

### Flutter

- 요청 URI, Header, Body 직렬화
- 공통 응답 역직렬화
- `reason`과 선택적 마지막 질문 전달
- 동일 Key 재시도
- 앱에서 Remote Repository 주입

## 10. 문서와 완료 검증

- Swagger Operation과 Schema를 실제 계약과 일치시킨다.
- API 계약 문서에 종료→Reflection→완료 접수→리포트 순서를 기록한다.
- Backend: `gradlew.bat clean test`, `gradlew.bat spotlessCheck`, `gradlew.bat javadoc`
- Flutter: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`

