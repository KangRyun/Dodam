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

## 4. DB 저장 매핑 (develop Flyway V3 스키마 기준)

외부·내부 JSON은 camelCase, DB 컬럼은 snake_case, Enum 직렬값은 UPPER_SNAKE_CASE를 사용한다. 이 절의 DB 기준은 `V1__create_initial_schema.sql`부터 `V3__normalize_json_columns.sql`까지 적용한 스키마이며, API 요청·응답 JSON 필드 자체는 변경하지 않는다.

| API/계약 항목 | 변경 전 서술 | V3 기준 저장 변환 | 정정 근거 | S15P11B209-150 구현 영향 |
| --- | --- | --- | --- | --- |
| `drawingSessionId` | `conversation_sessions.conversation_id`에 매핑 | `conversation_sessions.drawing_session_id`로 변환한다. FK `fk_conversation_sessions_drawing_session_id`는 `drawing_sessions.id`를 참조한다. `conversation_id` 물리 컬럼·API 별칭은 사용하지 않는다. | V3 `conversation_sessions.drawing_session_id`, `fk_conversation_sessions_drawing_session_id` | 대화 세션 조회·생성 시 DTO의 `drawingSessionId`를 이 실제 컬럼으로 매핑한다. |
| AI 질문 식별·본문 | AI/QUESTION 저장 원칙만 기재 | `conversation_messages.sender_type='AI'`, `message_type='QUESTION'`, `raw_text=questionText`로 저장한다. | V3 `conversation_messages.sender_type`, `message_type`, `raw_text`; 각 CHECK 제약 | 질문 생성·폴백 저장 INSERT에 실제 컬럼을 사용한다. |
| `options` | `options_json`에 배열 저장 | 선택지가 있으면 `conversation_message_options`에 선택지별 Snapshot 행을 저장하고, 없으면 행을 생성하지 않는다. `code`는 `option_key`, 표시 문구는 `label`에 매핑한다. | V3에서 `options_json` 제거, `conversation_message_options` 추가 | JSON 직렬화 대신 질문 메시지 FK와 선택지 행을 같은 트랜잭션에서 저장한다. |
| `targetObject`, `boundingBox` | `target_object_json`과 독립 `bounding_box`에 저장 | 대상 객체가 있으면 `conversation_message_targets`에 메시지당 한 행을 저장하고, 없으면 행을 생성하지 않는다. Bounding Box는 `bbox_x`, `bbox_y`, `bbox_width`, `bbox_height`에 저장한다. | V3에서 `target_object_json` 제거, `conversation_message_targets` 추가 | API 구조는 유지하되 관계형 컬럼으로 변환해 저장한다. |
| 템플릿 출처 | AI 질문 null, 템플릿 폴백 템플릿 ID | AI 생성 질문은 `question_template_id=null`; BE 템플릿 폴백은 실제 선택한 활성 `ai_question_templates.id`를 저장한다. | V3 `conversation_messages.question_template_id`, `fk_conversation_messages_template_id` | 폴백 질문 INSERT 시 템플릿 ID를 설정하고, AI 생성 질문에는 설정하지 않는다. |
| 메시지 순번 | 향후 UNIQUE migration 추가 요구 | `message_sequence`는 세션 안에서 증가시키며, 기존 `uk_conversation_messages_session_sequence UNIQUE(conversation_session_id, message_sequence)`를 충족해야 한다. | V3 `conversation_messages.message_sequence`, `uk_conversation_messages_session_sequence` | 중복 키를 처리·회피하는 저장 로직만 구현한다. |
| 질문 횟수 | 저장과 별도 이력 저장을 함께 처리 | 실제 제시할 질문 INSERT와 동일 트랜잭션에서 `conversation_sessions.question_count`를 1 증가시키고 `max_question_count`를 넘기지 않는다. | V3 `conversation_sessions.question_count`, `max_question_count`, `ck_conversation_sessions_question_count` | 세션 잠금/조건 검증 뒤 메시지 INSERT와 카운트 갱신을 함께 처리한다. |
| 모델·프롬프트·안전 규칙 버전 이력 | `ai_question_generation_histories` 신규 테이블 영속 요구 | V3에도 해당 테이블·질문별 버전 컬럼이 없다. 본 계약에서는 DB 비영속으로 처리하고, 영속 감사가 필요하면 별도 승인된 후속 범위에서 스키마·보존 정책을 결정한다. | V3 전체 스키마에 `ai_question_generation_histories` 부재 | 존재하지 않는 테이블/컬럼을 사용하지 않는다. 버전 이력 영속은 구현 차단 조건이 아니다. |

### V3와 이전 참고 ERD 차이

| 항목 | V3 실제 기준 | 이전 참고 문서 | 영향 | 확인 담당자 |
| --- | --- | --- | --- | --- |
| 그림 활동 세션 FK | `drawing_session_id`, `fk_conversation_sessions_drawing_session_id` | `conversation_id` | `drawing_session_id`만 사용한다. | 백엔드 문서 담당자·ERD 담당자 |
| 선택지 저장 | `conversation_message_options` 행 | `options_json` | JSON 컬럼을 참조하지 않고 관계 Entity·Repository를 사용한다. | 백엔드 생성자·검증자 |
| 대상 객체와 Bounding Box | `conversation_message_targets` 행 | `target_object_json`, 독립 `bounding_box` | API JSON은 유지하되 DB에는 정규화된 컬럼으로 저장한다. | 백엔드 생성자·검증자 |
| 메시지 순번 UNIQUE | `uk_conversation_messages_session_sequence` 존재 | UNIQUE 제약 미표기 | 추가 Migration 없이 기존 UNIQUE를 전제로 구현·검증한다. | 백엔드 생성자·검증자 |

V3에는 `ai_question_generation_histories`가 없으므로 본 계약은 해당 테이블이나 질문별 버전 컬럼의 생성을 요구하지 않는다. 원문 대화·질문·프롬프트 본문·토큰·시크릿·안전 필터 추론 근거는 계속 DB·로그에 저장하지 않는다.

## 5. 오류, 폴백, 동시성

AI 호출은 DB 트랜잭션 밖에서 수행한다. 실제 제시할 질문이 결정된 후 짧은 단일 트랜잭션에서 세션을 `SELECT ... FOR UPDATE`로 잠그고, 질문 가능 여부 재확인, 다음 `message_sequence` 결정, AI/QUESTION 저장, `question_count` 증가를 함께 처리한다. 질문별 버전 이력은 §4의 V3 DB 비영속 원칙을 따른다.

- 연결 실패는 동일 `X-Request-Id`로 한 번만 재시도한다.
- read timeout 뒤에는 재전송하지 않는다. AI 결과나 카운트를 저장하지 않고, 가능한 경우 활성 `FALLBACK` 템플릿 질문만 저장한다.
- 안전 차단은 `422 AI_SAFETY_POLICY_BLOCKED`, `retryable=false`으로 처리한다.
- 성공 HTTP 200의 스키마 불일치는 `RESPONSE_SCHEMA_INVALID`로 이력에 남기고 템플릿 폴백으로 전환한다.
- 활성 폴백 템플릿이 없으면 질문 저장·횟수 증가는 하지 않으며 기술 오류·차단 사유를 아동에게 노출하지 않는다.

`uk_conversation_messages_session_sequence UNIQUE(conversation_session_id, message_sequence)`는 V3에도 유지된다. 모든 질문 쓰기는 이 제약과 위 세션 잠금 규칙을 함께 적용하며, 이 계약은 UNIQUE 추가 Migration을 요구하지 않는다.

## 6. AI Mock 이행

현재 `/analyze/conversation` placeholder는 이 계약의 구현으로 인정하지 않는다. AI 담당자는 별도 작업에서 이를 본 문서의 endpoint와 요청·응답 구조로 이행한다. BE는 목표 endpoint 외 경로와 `chips`, `model_id`, `prompt_version` 별칭을 허용하거나 자동 변환하지 않는다.
