# AI 대화 질문 생성 내부 요청·응답 계약

> Jira: `S15P11B209-148`
> 상태: 최종 확정(2026-07-22)
> 범위: Spring Boot와 FastAPI AI 서버 사이의 내부 질문 생성 계약

이 문서는 계약만 정의한다. 구현, DB migration, FastAPI Mock 이행, 테스트와 배포는 각각 별도 작업으로 처리한다. AI 결과는 진단이 아닌 대화 보조 용도이며, 아동 발화 원문·운영 프롬프트·토큰·시크릿은 로그나 오류 응답에 포함하지 않는다.

## 1. 엔드포인트와 헤더

- Method/path: `POST /internal/ai/v1/conversations/question`
- `Content-Type: application/json`
- `X-Internal-Token`: 필수. 값은 환경 변수로 주입하며 문서·로그에 기록하지 않는다.
- `X-Request-Id`: 필수. 연결 실패 시에만 동일 값으로 한 번 재시도한다.

클라이언트는 이 내부 API를 직접 호출하지 않는다.

## 2. 요청 계약

모든 최상위 필드는 필수이며, `basisAnalysisId`만 성공한 객체 탐지 분석이 없을 때 `null`일 수 있다.

| 필드 | 타입·규칙 |
| --- | --- |
| `conversationId`, `drawingSessionId` | 양의 int64. `conversationId`는 `conversation_sessions.id`다. |
| `basisAnalysisId` | 양의 int64 또는 `null` |
| `childAge` | 양의 integer. 생년월일은 전달하지 않는다. |
| `difficulty` | `PRESCHOOL`, `ELEMENTARY`, `DEVELOPMENTAL_SUPPORT`, `CUSTOM` 중 하나 |
| `allowedResponseModes` | 중복 없는 비어 있지 않은 `VOICE`/`OPTION` 배열 |
| `currentQuestionCount`, `maxQuestionCount` | 0 이상의 integer, 전자는 후자 이하여야 한다. 질문 여유가 없으면 AI를 호출하지 않는다. |
| `detectedObjects` | 빈 배열 가능. 항목은 `objectCode`, `objectName`, `confidence`, `boundingBox`를 가진다. |
| `recentMessages` | 빈 배열 가능. 항목은 `messageId`, `senderType`, `messageType`, `text`를 가진다. `text`는 최소 문맥만 보내며 로그·오류 응답에 포함하지 않는다. |
| `safetyRuleVersion` | 필수 string 식별자. 프롬프트 본문은 포함하지 않는다. |

`boundingBox`는 `{x, y, width, height}`이며 각 값은 0~1이고 `x + width ≤ 1`, `y + height ≤ 1`이어야 한다.

## 3. 성공 응답 계약

성공 응답은 `questionText`, `questionPurpose`, `options`, `targetObject`, `fallbackUsed`, `safetyResult`, `modelName`, `modelVersion`, `promptVersion`, `processingTimeMs`를 모두 포함한다.

- `options`: `OPTION`이 허용되지 않으면 `null`; 허용되면 하나 이상의 `{code, label}` 배열
- `targetObject`: 대상 객체가 없으면 `null`; 있으면 요청 객체와 같은 키 사용
- `fallbackUsed`: AI 서버가 안전한 내부 대체 질문을 제공한 경우에만 `true`
- `safetyResult`: 성공 시 `{status: "PASSED", ruleVersion: string, blockReasonCode: null}`
- `processingTimeMs`: 0 이상의 integer
- `modelName`, `modelVersion`, `promptVersion`: 비어 있지 않은 string

`questionPurpose`는 `OBJECT_DESCRIPTION`, `DRAWING_CONTEXT`, `EXPRESSION`, `FOLLOW_UP` 중 하나다.

## 4. 저장과 버전 이력

외부·내부 JSON은 camelCase, DB 컬럼은 snake_case, Enum 직렬값은 UPPER_SNAKE_CASE를 사용한다. AI 질문은 `conversation_messages`에 `sender_type=AI`, `message_type=QUESTION`으로 저장한다.

- `options_json`: 선택지가 있을 때만 `{code, label}` 배열을 저장한다. 중복 code, 빈 배열, 빈 label은 금지한다.
- `target_object_json`, `bounding_box`: 대상 객체가 있을 때만 저장한다. 대상이 없으면 `null`이며 빈 객체·빈 배열은 금지한다.
- AI 생성 질문은 `question_template_id=null`이다. BE 템플릿 폴백은 선택한 활성 템플릿 ID를 저장한다.
- 논리명 `drawingSessionId`는 현행 `conversation_sessions.conversation_id` 물리 컬럼에 명시 매핑한다. API에는 `conversation_id` 별칭을 노출하지 않는다.

질문 생성 이력은 별도 migration으로 `ai_question_generation_histories`에 저장한다. 이력에는 세션/메시지/분석 FK, 요청 ID의 SHA-256 해시, 모델·프롬프트·안전 규칙 버전, 결과 상태, 폴백 여부, UTC 생성 시각을 저장한다. 원문 대화·질문·프롬프트 본문·토큰·시크릿·안전 필터 추론 근거는 저장하지 않는다.

## 5. 오류, 폴백, 동시성

AI 호출은 DB 트랜잭션 밖에서 수행한다. 실제 제시할 질문이 결정된 후 짧은 단일 트랜잭션에서 세션을 `SELECT ... FOR UPDATE`로 잠그고, 질문 가능 여부 재확인, 다음 `message_sequence` 결정, AI/QUESTION 저장, `question_count` 증가와 이력 저장을 함께 처리한다.

- 연결 실패는 동일 `X-Request-Id`로 한 번만 재시도한다.
- read timeout 뒤에는 재전송하지 않는다. AI 결과나 카운트를 저장하지 않고, 가능한 경우 활성 `FALLBACK` 템플릿 질문만 저장한다.
- 안전 차단은 `422 AI_SAFETY_POLICY_BLOCKED`, `retryable=false`으로 처리한다.
- 성공 HTTP 200의 스키마 불일치는 `RESPONSE_SCHEMA_INVALID`로 이력에 남기고 템플릿 폴백으로 전환한다.
- 활성 폴백 템플릿이 없으면 질문 저장·횟수 증가는 하지 않으며 기술 오류·차단 사유를 아동에게 노출하지 않는다.

후속 migration은 `UNIQUE(conversation_session_id, message_sequence)`를 추가한다. migration 전에도 모든 질문 쓰기는 위 세션 잠금 규칙을 적용한다.

## 6. AI Mock 이행

현재 `/analyze/conversation` placeholder는 이 계약의 구현으로 인정하지 않는다. AI 담당자는 별도 작업에서 이를 본 문서의 endpoint와 요청·응답 구조로 이행한다. BE는 목표 endpoint 외 경로와 `chips`, `model_id`, `prompt_version` 별칭을 허용하거나 자동 변환하지 않는다.
