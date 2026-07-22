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

## 4. DB 저장 매핑 (develop V1 실제 스키마 기준)

외부·내부 JSON은 camelCase, DB 컬럼은 snake_case, Enum 직렬값은 UPPER_SNAKE_CASE를 사용한다. 이 절의 DB 기준은 develop 최신 `V1__create_initial_schema.sql`이며, API 요청·응답 JSON 필드 자체는 변경하지 않는다.

| API/계약 항목 | 변경 전 서술 | V1 기준 정정 후 저장 변환 | 정정 근거 | S15P11B209-150 구현 영향 |
| --- | --- | --- | --- | --- |
| `drawingSessionId` | `conversation_sessions.conversation_id`에 매핑 | `conversation_sessions.drawing_session_id`로 변환한다. FK `fk_conversation_sessions_drawing_session_id`는 `drawing_sessions.id`를 참조한다. `conversation_id` 물리 컬럼·API 별칭은 사용하지 않는다. | V1 `conversation_sessions.drawing_session_id`, `fk_conversation_sessions_drawing_session_id` | 대화 세션 조회·생성 시 DTO의 `drawingSessionId`를 이 실제 컬럼으로 매핑한다. DB 변경 불필요. |
| AI 질문 식별·본문 | AI/QUESTION 저장 원칙만 기재 | `conversation_messages.sender_type='AI'`, `message_type='QUESTION'`, `raw_text=questionText`로 저장한다. | V1 `conversation_messages.sender_type`, `message_type`, `raw_text`; 각 CHECK 제약 | 질문 생성·폴백 저장 INSERT에 실제 컬럼을 사용한다. |
| `options` | `options_json`에 배열 저장 | 선택지가 있으면 `options_json=[{"code": string, "label": string}]`; 선택지가 없으면 null이다. | V1 `conversation_messages.options_json` | API `options` camelCase 배열을 snake_case JSON 컬럼으로 직렬화한다. |
| `targetObject`, `boundingBox` | `target_object_json`과 독립 `bounding_box`에 저장 | **독립 `bounding_box` 컬럼은 사용하지 않는다.** 대상 객체가 있으면 `target_object_json={"objectCode": string, "objectName": string|null, "confidence": number|null, "boundingBox": {"x": number, "y": number, "width": number, "height": number}}`로 함께 저장한다. 대상이 없으면 `target_object_json=null`이다. | V1 `conversation_messages.target_object_json`의 주석 “대상 객체 및 Bounding Box”; V1에 `bounding_box` 컬럼 없음 | API의 `targetObject`·`boundingBox` 구조는 그대로 두고 하나의 JSON 컬럼만 읽기·쓰기 한다. |
| 템플릿 출처 | AI 질문 null, 템플릿 폴백 템플릿 ID | AI 생성 질문은 `question_template_id=null`; BE 템플릿 폴백은 실제 선택한 활성 `ai_question_templates.id`를 `question_template_id`에 저장한다. | V1 `conversation_messages.question_template_id`, `fk_conversation_messages_template_id` | 폴백 질문 INSERT 시 템플릿 ID를 설정하고, AI 생성 질문에는 설정하지 않는다. |
| 메시지 순번 | 향후 UNIQUE migration 추가 요구 | `message_sequence`는 세션 안에서 증가시키며, 이미 존재하는 `uk_conversation_messages_session_sequence UNIQUE(conversation_session_id, message_sequence)`를 충족해야 한다. | V1 `conversation_messages.message_sequence`, `uk_conversation_messages_session_sequence` | 중복 키를 처리·회피하는 저장 로직만 구현한다. UNIQUE 추가 migration은 불필요하다. |
| 질문 횟수 | 저장과 별도 이력 저장을 함께 처리 | 실제 제시할 질문 INSERT와 동일 트랜잭션에서 `conversation_sessions.question_count`를 1 증가시키고, `max_question_count`를 넘기지 않는다. V1 CHECK 제약을 준수한다. | V1 `conversation_sessions.question_count`, `max_question_count`, `ck_conversation_sessions_question_count` | 세션 잠금/조건 검증 뒤 메시지 INSERT와 카운트 갱신을 함께 처리한다. DB 변경 불필요. |
| 모델·프롬프트·안전 규칙 버전 이력 | `ai_question_generation_histories` 신규 테이블 영속 요구 | V1에는 해당 테이블·질문별 버전 컬럼이 없다. **본 V1 계약에서는 DB 비영속**으로 처리하며, 모델 응답 값은 요청 처리 범위에서만 사용한다. 영속 감사가 필요하면 별도 승인된 후속 범위에서 스키마·보존 정책을 결정한다. | V1 전체 스키마에 `ai_question_generation_histories` 부재 | 150번은 존재하지 않는 테이블/컬럼을 쓰지 않는다. 버전 이력 영속은 구현 차단 조건이 아니다. |

### V1과 참고 ERD 불일치

| 항목 | V1 실제 기준 | `도담.sql` 참고 문서 | 영향 | 확인 담당자 |
| --- | --- | --- | --- | --- |
| 그림 활동 세션 FK | `drawing_session_id`, `fk_conversation_sessions_drawing_session_id` | `conversation_id` | 이 계약과 150번 구현은 V1의 `drawing_session_id`만 사용한다. 참고 ERD 정정은 별도 문서 작업이다. | 백엔드 문서 담당자·ERD 담당자 |
| Bounding box 저장 | `target_object_json` 내부 JSON | 독립 `bounding_box` 컬럼 | 150번은 독립 컬럼을 참조하지 않는다. API JSON의 `boundingBox`는 유지한다. | 백엔드 문서 담당자·백엔드 검증자 |
| 메시지 순번 UNIQUE | `uk_conversation_messages_session_sequence` 존재 | UNIQUE 제약 미표기 | 추가 migration 없이 기존 UNIQUE를 전제로 구현·검증한다. | 백엔드 생성자·백엔드 검증자 |

V1에는 `ai_question_generation_histories`가 없으므로 본 계약은 해당 테이블이나 질문별 버전 컬럼의 생성을 요구하지 않는다. 원문 대화·질문·프롬프트 본문·토큰·시크릿·안전 필터 추론 근거는 계속 DB·로그에 저장하지 않는다.

## 5. 오류, 폴백, 동시성

AI 호출은 DB 트랜잭션 밖에서 수행한다. 실제 제시할 질문이 결정된 후 짧은 단일 트랜잭션에서 세션을 `SELECT ... FOR UPDATE`로 잠그고, 질문 가능 여부 재확인, 다음 `message_sequence` 결정, AI/QUESTION 저장, `question_count` 증가를 함께 처리한다. 질문별 버전 이력은 §4의 V1 DB 비영속 원칙을 따른다.

- 연결 실패는 동일 `X-Request-Id`로 한 번만 재시도한다.
- read timeout 뒤에는 재전송하지 않는다. AI 결과나 카운트를 저장하지 않고, 가능한 경우 활성 `FALLBACK` 템플릿 질문만 저장한다.
- 안전 차단은 `422 AI_SAFETY_POLICY_BLOCKED`, `retryable=false`으로 처리한다.
- 성공 HTTP 200의 스키마 불일치는 `RESPONSE_SCHEMA_INVALID`로 이력에 남기고 템플릿 폴백으로 전환한다.
- 활성 폴백 템플릿이 없으면 질문 저장·횟수 증가는 하지 않으며 기술 오류·차단 사유를 아동에게 노출하지 않는다.

`uk_conversation_messages_session_sequence UNIQUE(conversation_session_id, message_sequence)`는 V1에 이미 존재한다. 모든 질문 쓰기는 이 제약과 위 세션 잠금 규칙을 함께 적용하며, 이 계약은 UNIQUE 추가 migration을 요구하지 않는다.

## 6. AI Mock 이행

현재 `/analyze/conversation` placeholder는 이 계약의 구현으로 인정하지 않는다. AI 담당자는 별도 작업에서 이를 본 문서의 endpoint와 요청·응답 구조로 이행한다. BE는 목표 endpoint 외 경로와 `chips`, `model_id`, `prompt_version` 별칭을 허용하거나 자동 변환하지 않는다.

## 7. 백엔드 검증 결과 (2026-07-22)

> 검토 범위: API 명세, `도담.sql`, develop 최신 `V1__create_initial_schema.sql`, 현재 `ai/main.py` 및 본 계약서의 문서 대조. 코드·DB·설정·Git은 변경하지 않았다. DB 물리 스키마 판정은 V1을 기준으로 한다.

| 검증 항목 | 판정 | 근거 | 검증 결과·다음 담당자 |
| --- | --- | --- | --- |
| `drawingSessionId` 변환과 FK | PASS | 본 문서 §4 55행; V1 `conversation_sessions.drawing_session_id`, `fk_conversation_sessions_drawing_session_id` (315~318행) | DTO의 `drawingSessionId`를 `drawing_session_id`로 변환하고 `drawing_sessions.id` FK를 사용하도록 명시되어 있다. `도담.sql`의 `conversation_id`는 §4 V1-참고 ERD 불일치로만 기록했으며 구현 기준으로 요구하지 않는다. 150번 생성자가 이 변환 규칙을 구현한다. |
| 대상 객체·bounding box 저장 | PASS | 본 문서 §4 58행·§4 V1-참고 ERD 불일치 69행; V1 `conversation_messages.target_object_json` (341행) | V1에 독립 `bounding_box`가 없음을 정확히 명시하고 `targetObject`와 `boundingBox`를 `target_object_json` 내부 JSON으로 함께 저장한다. 150번은 독립 컬럼을 참조하지 않는다. |
| 질문 메시지 컬럼·CHECK 매핑 | PASS | 본 문서 §4 56~59행; V1 `conversation_messages` (330~356행) | `raw_text`, `options_json`, `question_template_id`가 실제 컬럼과 일치한다. `sender_type='AI'` 및 `message_type='QUESTION'`은 각각 V1 CHECK 허용값에 포함된다. AI 생성 질문의 템플릿 ID null과 BE 템플릿 폴백의 실제 템플릿 ID 저장도 FK와 모순되지 않는다. |
| 메시지 순번 UNIQUE | PASS | 본 문서 §4 60행·§5 84행; V1 `uk_conversation_messages_session_sequence` (345~346행) | `UNIQUE(conversation_session_id, message_sequence)`가 이미 존재함을 명시하며 추가 migration을 요구하지 않는다. 150번은 세션 잠금과 기존 UNIQUE 충돌 처리만 구현하면 된다. |
| 질문별 버전 이력 | PASS | 본 문서 §4 62행·72행; V1 전체 스키마 | `ai_question_generation_histories` 또는 질문별 버전 영속 컬럼을 실제 V1 테이블처럼 요구하지 않는다. 본 V1 범위에서는 DB 비영속으로 처리하며 별도 승인 범위로 분리했다. |
| 현재 AI Mock 호환성 | 미결(별도 작업) | 본 문서 §6 88행; `ai/main.py` 63~88행 | Mock은 현재 `POST /analyze/conversation` 및 `question`/`chips`/`model_id`/`prompt_version`을 사용해 목표 계약과 다르다. 본 문서가 이를 별도 AI 이행 작업으로 명시하므로 150번의 DB 비변경 저장 구현을 차단하지는 않는다. AI 담당자가 목표 endpoint·스키마 이행을 완료하고, 백엔드 생성자가 목표 계약 통합 테스트로 확인한다. |
| 안전 차단 오류 코드 | 확인 필요(API 명세) | 본 문서 §5 80행; `API_완전_명세서_v1.0.md` AI 오류 표 §3.2 | 본 계약은 `422 AI_SAFETY_POLICY_BLOCKED`를 정하지만, 현행 API 명세 오류 표에는 해당 코드가 없다. DB 저장 매핑과 150번의 DB 비변경 구현을 차단하지는 않으나, 문서 담당자·AI 담당자가 API 명세와 계약 중 어느 문서를 기준으로 확정할지 결정하고 통합 테스트 기대값을 일치시켜야 한다. |

### S15P11B209-150 DB 비변경 구현 판정: PASS

V1 실제 물리 스키마만 사용하면 150번은 DB migration이나 존재하지 않는 테이블·컬럼 없이 구현할 수 있다. 필수 구현 범위는 `drawingSessionId → drawing_session_id`, `targetObject`·`boundingBox → target_object_json`, AI/QUESTION·`raw_text`·`options_json`·`question_template_id` 저장, 기존 세션별 순번 UNIQUE 및 질문 수 CHECK 준수다.

미결 사항은 AI Mock의 별도 endpoint 이행과 안전 차단 오류 코드의 API 명세 정합성이다. 둘 다 DB 저장 매핑의 FAIL 사유는 아니며, AI 담당자·문서 담당자·백엔드 생성자가 후속 통합 테스트 전에 해소한다.
