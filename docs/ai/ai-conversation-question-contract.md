# AI 대화 질문 생성 내부 요청·응답 계약

> Jira: `S15P11B209-148`
> **정본: `docs/api/API_명세서_최종.md`** (S15P11B209-400)
> 상태: 운영 중 (as-built, 2026-07-22 확정) — 정본 §19.5와 차이 있음
> 범위: Spring Boot와 FastAPI AI 서버 사이의 내부 질문 생성 계약

## ⚠️ 정본과의 차이

계약의 정본은 `API_명세서_최종.md`다. 이 문서는 **현재 운영 중인 as-built 계약**을 기술하며, 정본 §19.5와 아래가 다르다.

| 항목 | 이 문서(운영 중) | 정본 §19.5 |
| --- | --- | --- |
| 경로 | `POST /internal/ai/v1/conversations/question` | `POST /internal/v1/conversations/next-question` |
| 응답 구조 | 평면 — `questionText`, `questionPurpose`, `options`, `targetObject` | 중첩 — `question{text, purpose, options, targetObject}` |
| 안전 결과 | `safetyResult{status, ruleVersion, blockReasonCode}` | `safety{passed, blockedReasons}` |
| 모델 표기 | `modelName`, `modelVersion`, `promptVersion` | `modelVersion` |
| 인증 헤더 | `X-Internal-Token` | `X-Internal-Api-Key` |

**지금 이 차이를 정본 쪽으로 바꾸면 안 된다.** 배포된 BE(`RestClientAiQuestionClient`)가 경로를 하드코딩해 호출하고 있고, 응답이 `AiQuestionResponse.isContractValidFor` 검증에 실패하면 BE는 예외 없이 **폴백 템플릿으로 조용히 대체**한다. 즉 한쪽만 바꾸면 에러 없이 AI 질문 품질만 떨어진다.

정합화는 BE·AI 동시 수정이 필요한 2단계 작업이며, 정본 §21이 허용한 방식(새 경로 추가 → BE 전환 확인 → 구 경로 제거)으로 진행한다. 인증 헤더는 이미 AI 서버가 두 헤더를 함께 수용하도록 바뀌어 있어(S15P11B209-398) BE가 자기 속도로 옮길 수 있다.

이 문서는 계약만 정의한다. 구현, DB migration, FastAPI Mock 이행, 테스트와 배포는 각각 별도 작업으로 처리한다. AI 결과는 진단이 아닌 대화 보조 용도이며, 아동 발화 원문·운영 프롬프트·토큰·시크릿은 로그나 오류 응답에 포함하지 않는다.

## 1. 엔드포인트와 헤더

- Method/path: `POST /internal/ai/v1/conversations/question`
- `Content-Type: application/json`
- `X-Internal-Token`: 필수. 값은 환경 변수로 주입하며 문서·로그에 기록하지 않는다.
- `X-Request-Id`: 필수. 연결 실패 시에만 동일 값으로 한 번 재시도한다.

클라이언트는 이 내부 API를 직접 호출하지 않는다.

## 2. 요청 계약

`basisAnalysisId`와 `drawingDescription`은 `null`일 수 있다(각각 성공한 객체 탐지 분석이
없을 때, 그림 서술이 없을 때). 그 밖에 아래 표에서 **선택 필드**로 표시한 것들은 롤아웃 중
구버전 BE가 보내지 않을 수 있고, 그때 AI는 그 필드가 없던 시절의 동작으로 떨어진다.
나머지 최상위 필드는 필수다.

| 필드 | 타입·규칙 |
| --- | --- |
| `conversationId`, `drawingSessionId` | 양의 int64. `conversationId`는 `conversation_sessions.id`다. |
| `basisAnalysisId` | 양의 int64 또는 `null` |
| `childAge` | 양의 integer. 생년월일은 전달하지 않는다. |
| `difficulty` | `PRESCHOOL`, `ELEMENTARY`, `DEVELOPMENTAL_SUPPORT`, `CUSTOM` 중 하나 |
| `allowedResponseModes` | 중복 없는 비어 있지 않은 `VOICE`/`OPTION` 배열 |
| `currentQuestionCount`, `maxQuestionCount` | 0 이상의 integer, 전자는 후자 이하여야 한다. 질문 여유가 없으면 AI를 호출하지 않는다. AI는 `currentQuestionCount == maxQuestionCount - 1`을 '이번이 마지막 질문'으로 읽어 프롬프트에 마무리 지시를 싣는다(S15P11B209-976). 상한 자체는 BE가 활동 유형별로 정한다 — HTP는 주제(그림 한 장)당 3, 그림일기는 5. |
| `detectedObjects` | 빈 배열 가능. 항목은 `objectCode`, `objectName`, `confidence`, `boundingBox`를 가진다. |
| `drawingDescription` | string 또는 `null`. 분석에서 만든 2~4문장 한국어 그림 서술(VLM). BE가 `basisAnalysisId`로 `analysis_observation_results.overall_summary`를 찾아 채운다. **선택 필드** — 없으면 AI는 `detectedObjects`만으로 기존과 동일하게 동작한다. |
| `recentMessages` | 빈 배열 가능. 항목은 `messageId`, `senderType`, `messageType`, `text`, 선택형 답변에만 쓰는 선택 필드 `selectedOptionCodes`를 가진다. `text`는 최소 문맥만 보내며 로그·오류 응답에 포함하지 않는다. |
| `safetyRuleVersion` | 필수 string 식별자. 프롬프트 본문은 포함하지 않는다. |
| `resumedByNewDrawing` | boolean, 기본값 `false`. **선택 필드** — 이 요청을 촉발한 것이 아이의 발화가 아니라 **캔버스에 붙은 새 그림**임을 알린다(그림일기 대화 재개). `true`면 AI는 이 턴에서 그만하기 의사 해석을 건너뛴다(§2-3). 안 보내면 `false`로 읽어 기존 동작 그대로다. |

`boundingBox`는 `{x, y, width, height}`이며 각 값은 0~1이고 `x + width ≤ 1`, `y + height ≤ 1`이어야 한다.

### 2-1. 선택형 답변 문맥 (`selectedOptionCodes`)

선택형 답변 문맥은 다음 규칙을 따른다.

- `messageType=OPTION_ANSWER`이면 `selectedOptionCodes`에 선택 순서대로 옵션 `code`를 전달한다.
- 같은 메시지의 `text`에는 선택 당시 저장한 Label을 전달한다. 복수 선택은 `, `로 연결하고 `directText`가 있으면 ` / ` 뒤에 보존한다.
- 음성 답변의 `text`는 기존처럼 `sttText`를 우선하며 `selectedOptionCodes`는 `null`이다.
- 구버전 AI 호환을 위해 `selectedOptionCodes`는 선택 필드이며, 누락 시 기존 `text` 기반 처리를 유지한다.

> 🔴 **선택형 답변의 `text`는 아이가 한 말이 아니라 AI가 낸 Label이다** (S15P11B209-950).
> **AI가 낸 문구에 AI가 다시 반응하는 기능**은 `selectedOptionCodes`가 있는 메시지의 `text`를
> 자유 발화로 스캔하면 안 된다. 실제로 938의 되묻기 칩 라벨("이야기만 그만할래"·"그림 다
> 그렸어")이 그만하기 문구로 재판정되어 되묻기가 무한 반복됐고, 그만두겠다고 고른 아이일수록
> 갇혔다. 칩 코드를 하나씩 예외 처리하면 새 칩이 생길 때마다 같은 사고가 되살아나므로,
> 판정 계층에서 **"선택 코드가 있으면 자유 발화가 아니다"**로 끊는다.
>
> ⚠️ **모든 판정기에 일괄 적용하지 말 것.** 혼합 답변의 `text`는 `Label / directText` 형태라
> **아이가 직접 입력한 문자열이 뒤에 붙어 있다.** 인젝션 검사처럼 놓쳤을 때의 대가가 큰
> 보안성 판정은 이 메시지도 계속 스캔해야 한다(`_detect_injection`은 그래서 그대로 둔다).
> 기준은 "칩 답변이냐"가 아니라 **"AI 자신의 출력에 되반응하느냐"**다.

### 2-2. `drawingDescription` 취급 규칙 (S15P11B209-704)

객체 이름 목록만으로는 색·표정·구도·크기 관계를 물을 수 없어 그림 서술을 함께 보낸다.
서술은 분석 시점에 이미 만들어져 저장돼 있으므로 BE는 조회만 하고, 새로 생성하지 않는다.

- **길이**: AI가 프롬프트에 넣기 전 300자(`QUESTION_DESCRIPTION_MAX_CHARS`)로 자르고 말줄임표를 남긴다.
  VLM 프롬프트가 2~4문장을 지시하므로 정상 범위는 그대로 통과한다.
- **프롬프트에서의 지위**: 서술은 **참고 자료이지 인용문이 아니다.** 질문 프롬프트에
  "그대로 읽어주지 말 것"·"아이 마음을 단정하지 말 것"을 명시한다. 이 지시가 없으면
  서술 문장이 아이에게 그대로 나가고, 진단형 표현이 섞여 있으면 아이가 그것을 듣는다
  (CLAUDE.md 9절).
- **로그**: `DETECTION_LOG_DETAIL`이 꺼져 있으면 서술 내용은 남기지 않고 존재 사실만
  `서술있음`으로 남긴다. 서술은 객체 이름보다 훨씬 구체적인 아동 그림 내용이다.
- **노출 금지**: 출처인 `observationDraft`는 전문가 검토 전 초안이라 보호자에게 그대로
  노출하지 않는다. LLM 입력으로만 쓴다.
- **없을 때**: 분석 전 첫 질문, VLM 실패, 구버전 데이터가 모두 정상 경로다. BE는 예외를
  던지지 않고 `null`로 보낸다 — 보조 정보 때문에 대화가 끊기면 안 된다.

### 2-3. 재개 턴 표시 `resumedByNewDrawing`

**왜 필요한가 — 묵은 종료 확인이 재생돼 재개된 대화가 1초 만에 다시 끝났다.**
그림일기는 질문 상한(5)을 다 쓰면 대화가 끝나고, 그 뒤에도 아이가 캔버스에 더 그리면 대화를
다시 연다(reopen). 실기기에서 재개된 질문이 곧바로 종료되는 사고가 났고 원인은 이랬다.

1. 대화가 끝나기 직전 AI가 그만하기 되묻기("정말 그만할래?")를 냈고 아이가 "응"이라고 답했다.
2. 그 답을 처리할 차례에 질문 상한 409가 나면서 **확인이 소비되지 않은 채** 대화가 끝났다.
3. 아이가 그림을 더 그려 재개되자 AI가 그 묵은 "응"을 **지금 막 한 대답으로** 읽어
   맺음말 + `confirmedStopTarget`을 돌려줬다.
4. 앱은 `confirmedStopTarget`이 실린 응답을 질문이 아닌 맺음말로 보고 즉시 대화를 끝냈다
   (§3-1 설계대로다 — 틀린 것은 신호를 낸 쪽이다).

**아이가 그림을 더 그렸다는 행동 자체가 이전 "그만할래"를 뒤집는다.** 그래서 그 턴에서는
묵은 의사를 재생하지 않는다. 판정 근거가 되는 사실("이 요청은 발화가 아니라 새 그림이
촉발했다")은 BE만 알고 있어 계약 필드로 받는다.

- **BE**: 새 그림이 붙어 대화를 재개하며 질문을 요청할 때만 `true`를 싣는다. 아이 발화에
  이어 묻는 평범한 턴은 `false`(또는 생략)다.
- **AI(`true`일 때)**: 그만하기 의사 감지 되묻기(`_detect_stop_intent`)와 묵은 확인 처리
  (`_stop_confirmation_response`)를 **둘 다 건너뛴다.** 그 턴 응답에는 `confirmedStopTarget`이
  절대 실리지 않는다. 그 밖에는 평소대로 새 그림의 `detectedObjects`·`drawingDescription`을
  근거로 질문을 만든다.
- **AI(`false`·미전송)**: 지금까지와 100% 같다. 이 필드는 기존 그만하기 흐름(정상 대화 중
  아이가 말로 그만하겠다고 하는 경로)을 건드리지 않는다.
- 마지막 아이 발화는 **이력에서 지우지 않는다.** 질문 생성의 문맥으로 여전히 쓸모가 있고,
  안전 검사도 그 원문을 봐야 한다.

> 🔴 **이 플래그는 "그만하기 의사 해석"만 무력화한다 — 안전 검사는 하나도 끄지 않는다.**
> 위기 감지(`crisis_detection`)·프롬프트 인젝션 검사(`_detect_injection`)는 이 분기보다
> **앞에** 있어 그대로 돌고, 생성된 질문의 안전 판정(`question_safety`)도 그대로다.
> 재개는 드문 예외가 아니라 흔한 정상 경로라서, 여기 얹은 예외는 사실상 상시 적용된다 —
> 안전 검사를 이 플래그 뒤로 옮기지 말 것(CLAUDE.md 9절).

## 3. 성공 응답 계약

성공 응답은 `questionText`, `questionPurpose`, `options`, `targetObject`, `fallbackUsed`, `safetyResult`, `modelName`, `modelVersion`, `promptVersion`, `processingTimeMs`를 모두 포함한다.

- `options`: `OPTION`이 허용되지 않으면 `null`; 허용되면 하나 이상의 `{code, label}` 배열
- `targetObject`: 대상 객체가 없으면 `null`; 있으면 요청 객체와 같은 키 사용
- `fallbackUsed`: AI 서버가 안전한 내부 대체 질문을 제공한 경우에만 `true`
- `safetyResult`: 성공 시 `{status: "PASSED", ruleVersion: string, blockReasonCode: null}`
- `processingTimeMs`: 0 이상의 integer
- `modelName`, `modelVersion`, `promptVersion`: 비어 있지 않은 string

`questionPurpose`는 `OBJECT_DESCRIPTION`, `DRAWING_CONTEXT`, `EXPRESSION`, `FOLLOW_UP` 중 하나다.

### 3-1. 종료 확인 신호 `confirmedStopTarget` (S15P11B209-951)

아이가 그만하기 되묻기에 **말로** 그만하겠다고 확인했을 때만 실리는 선택 필드다.
값은 `CONVERSATION`(대화만 종료) 또는 `ACTIVITY`(그림 활동까지 완료)이고, 확인이 없으면 `null`이다.

- **명령이 아니라 관찰 보고다.** "아이가 확인했다"는 사실만 싣고 실제 종료는 FE가 기존 종료
  흐름으로 수행한다 — 786이 정한 "턴·활동 제어는 AI 소유가 아니다"는 그대로다.
- 값이 있으면 그 응답은 질문이 아니라 **맺음말**이다. 그래서 `OPTION`이 허용돼도 `options`는
  `null`일 수 있다(§3의 `options` 규칙에 대한 유일한 예외). 맺음말 자체는 대화의 마지막 AI
  메시지로 저장되어 리포트에 남는다.
- 요청이 `resumedByNewDrawing=true`이면 이 필드는 **절대 실리지 않는다.** 그 턴의 마지막 아이
  발화는 이번 질문에 대한 대답이 아니라 이전 라운드의 잔여물이라, 거기서 읽어 낸 확인은
  아이가 지금 한 확인이 아니다(§2-3).
- BE는 모르는 값을 **계약 위반으로 보고 폴백 질문으로 간다.** 모르는 대상으로 대화를 끝내지 않는다.
- 앱도 아는 값만 종료로 옮긴다. 서버가 새 대상을 먼저 배포해도 구버전 앱은 그 메시지를 평범한
  질문으로 다룬다 — 질문을 삼켜 대화가 멈추는 것보다 낫다.

> **938의 설계 결정을 뒤집은 것이다.** 938은 "AI 응답 계약을 바꾸지 않는다"를 설계 이유 1번으로
> 적고 종료를 선택 칩만으로 표현했다. 실사용에서 그 선택의 대가가 드러났다 — 마이크로 대화하는
> 아이가 되묻기에 "응"이라고 **말하면 아무 일도 일어나지 않았다.** 종료 실행이 칩 코드에만
> 걸려 있었기 때문이다. 계약을 늘리지 않으면 아이는 화면을 눌러야만 빠져나갈 수 있다.
> 되돌리려는 사람이 이유를 모른 채 되돌리지 않도록 여기 남긴다.

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
- 안전 차단(AI가 자체 차단해 `422 AI_SAFETY_POLICY_BLOCKED`로 응답한 경우)은 **재전송하지 않고 스키마 불일치·연결 오류와 똑같이 활성 `FALLBACK` 템플릿 질문으로 전환한다** (2026-08-08 변경). 차단된 AI 문장은 저장하지도, 아이에게 보여주지도 않는다 — 아이에게 나가는 것은 사전 검증된 템플릿 질문뿐이라 이 전환이 안전 경계를 넓히지 않는다.
  - 이전 규칙(BE가 `422 AI_SAFETY_POLICY_BLOCKED`, `retryable=false`로 대화를 끝냄)은 폐기했다. 아이가 대화 중 부적절한 말을 하면 그 뒤 AI 응답이 안전 규칙에 걸릴 확률이 올라가고, 걸리는 순간 재시도 경로도 없이 대화가 끊기는 문제가 실사용에서 확인됐다. **BE 공개 오류 코드 `ConversationErrorCode.AI_SAFETY_POLICY_BLOCKED`도 함께 제거했다** — §7의 "안전 차단 오류 코드" 미결 행(API 명세에 이 코드가 없어 기준 확정이 필요하다는 항목)은 이 결정으로 종료한다.
  - AI→BE 응답의 `errorCode: AI_SAFETY_POLICY_BLOCKED`와 이를 분류하는 클라이언트 계층(`AiQuestionClientException.Type.SAFETY_POLICY_BLOCKED`)은 그대로 유지한다. 바뀐 것은 BE가 그 분류를 받고 하는 일뿐이다.
- 성공 HTTP 200의 스키마 불일치는 `RESPONSE_SCHEMA_INVALID`로 이력에 남기고 템플릿 폴백으로 전환한다.
- 활성 폴백 템플릿이 없으면 질문 저장·횟수 증가는 하지 않으며 기술 오류·차단 사유를 아동에게 노출하지 않는다.

`uk_conversation_messages_session_sequence UNIQUE(conversation_session_id, message_sequence)`는 V3에도 유지된다. 모든 질문 쓰기는 이 제약과 위 세션 잠금 규칙을 함께 적용하며, 이 계약은 UNIQUE 추가 Migration을 요구하지 않는다.

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
| 안전 차단 오류 코드 | ~~확인 필요(API 명세)~~ → **종결(2026-08-08, §5)** | 본 문서 §5 80행; `API_완전_명세서_v1.0.md` AI 오류 표 §3.2 | ~~본 계약은 `422 AI_SAFETY_POLICY_BLOCKED`를 정하지만, 현행 API 명세 오류 표에는 해당 코드가 없다. 문서 담당자·AI 담당자가 API 명세와 계약 중 어느 문서를 기준으로 확정할지 결정해야 한다.~~ **→ 2026-08-08 §5로 종결한다.** 안전 차단을 스키마 불일치·연결 오류와 똑같이 폴백 템플릿으로 전환하기로 하면서 BE 공개 오류 코드 `ConversationErrorCode.AI_SAFETY_POLICY_BLOCKED` 자체를 제거했다. 공개 오류 코드가 없어졌으므로 API 명세와 맞출 대상도 없다 — API 명세 오류 표에 해당 코드가 없는 것이 이제 맞는 상태다. (AI→BE 응답의 `errorCode`와 클라이언트 계층 분류는 §5대로 유지한다.) |

### S15P11B209-150 DB 비변경 구현 판정: PASS

V1 실제 물리 스키마만 사용하면 150번은 DB migration이나 존재하지 않는 테이블·컬럼 없이 구현할 수 있다. 필수 구현 범위는 `drawingSessionId → drawing_session_id`, `targetObject`·`boundingBox → target_object_json`, AI/QUESTION·`raw_text`·`options_json`·`question_template_id` 저장, 기존 세션별 순번 UNIQUE 및 질문 수 CHECK 준수다.

남은 미결 사항은 AI Mock의 별도 endpoint 이행뿐이다. DB 저장 매핑의 FAIL 사유는 아니며, AI 담당자·백엔드 생성자가 후속 통합 테스트 전에 해소한다.

> 안전 차단 오류 코드는 **2026-08-08 §5로 종결됐다** — BE 공개 오류 코드를 제거해 API 명세와 맞출 대상 자체가 사라졌다. 위 표의 해당 행 참고.
