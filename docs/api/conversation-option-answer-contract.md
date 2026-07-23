# 대화 선택형 답변 저장 API 공개 계약

> Jira: `S15P11B209-149` (범위 일부) · `S15P11B209-284` (동일 범위, 이 계약으로 흡수)
> 범위: 대화 세션의 선택형 답변 제출 공개 API (`POST /conversations/{conversationId}/answers/option`)
> 기준 명세: `API_명세서_최종.md` 12.1·12.6 (CONV-06), `erd-cloud-schema-v1.2`
> 최종 수정: 2026-07-23

이 문서는 아동의 **선택형 답변**(이모지·색상·그림·문장 선택)을 저장하는 공개 API의 요청·응답·검증·DB 매핑 계약을 정의한다. 프론트엔드와 백엔드가 이 문서를 단일 기준으로 사용한다.

## 0. 범위 정리 및 결정 사항 (반드시 확인)

이 API를 둘러싼 문서·이슈에 아래 중복·충돌이 있어 다음과 같이 확정한다.

1. **149 ↔ 284 중복**: `S15P11B209-284 "AI 질문 선택지 답변 제출 API"`는 설명·계약·브랜치가 없는 빈 티켓이며, `149` 공개 계약서의 "선택 답변 저장 API"와 **동일한 엔드포인트(CONV-06)**다. 선택형 답변 저장은 **한 번만** 구현하고 149·284를 함께 커버한다. 284는 별도 구현 없이 149로 흡수한다(중복/링크 처리 권장).
2. **요청 스키마 충돌 → 최신본 채택**: 구버전 계약서(`S15P11B209-149_..._공개_계약서.md`, `API_완전_명세서_v1.0` 참조)의 `selectedOptionIds: [숫자]` 스키마는 **폐기**한다. 본 계약은 최신본 `API_명세서_최종.md` 12.6의 `selectedOptions[{ optionId, type, value, labelSnapshot }]` + `directText` 스키마를 기준으로 한다.
3. **음성 답변은 별도**: 음성 답변(`POST .../answers/voice`, CONV-05)은 `S15P11B209-288/289`로 이미 구현되어 있으므로 본 계약 범위에 포함하지 않는다. 인증·동의·소유권·Redis 멱등성·메시지 저장 기반은 해당 구현을 재사용한다.

## 1. 엔드포인트

```http
POST /api/v1/conversations/{conversationId}/answers/option
```

- 역할: 연결 보호자
- 인증: `Authorization: Bearer {accessToken}` (정식 JWT 전환 전까지 임시 `X-Guardian-User-Id` 경계가 남아 있을 수 있으며, 이는 최종 보안 계약이 아니다)
- 동의: 필수 동의가 없으면 `403 CONSENT_REQUIRED`
- Content-Type: `application/json`
- `Idempotency-Key` 헤더 필수. 사용자·대화·endpoint 범위로 Redis에 보관하며, 동일 키·동일 Body 재수신 시 최초 HTTP 응답을 재생한다. 동일 키·다른 Body는 `409 IDEMPOTENCY_KEY_REUSED`. DB 스키마는 변경하지 않는다(음성 답변 API와 동일 정책).

## 2. 요청

```json
{
  "questionMessageId": 803,
  "selectedOptions": [
    { "optionId": "happy", "type": "EMOTION", "value": "HAPPY", "labelSnapshot": "기뻐요" }
  ],
  "directText": null
}
```

| 필드 | 필수 | 규칙 |
| --- | --- | --- |
| `questionMessageId` | O | 같은 대화 세션의 `messageType=QUESTION` 메시지 ID여야 한다 |
| `selectedOptions` | O | 비어 있지 않은 배열. 배열 순서를 `selection_order`로 저장한다 |
| `selectedOptions[].optionId` | O | 해당 질문(`questionMessageId`)에 노출된 선택지의 `option_key`와 일치해야 한다 |
| `selectedOptions[].type` | O | 선택지 유형. 질문 선택지 Snapshot의 `option_type`과 일치해야 한다 |
| `selectedOptions[].value` | O | 선택지 값. 질문 선택지 Snapshot의 `option_value`와 일치해야 한다 |
| `selectedOptions[].labelSnapshot` | O | 화면에 실제 노출된 문구. 서버 선택지의 `label`과 일치해야 한다 |
| `directText` | X | 문장 직접 입력 값(선택). 미사용 시 `null` |

### 처리 규칙

1. 대화 세션과 보호자-아동 소유권·동의를 검증한다.
2. `questionMessageId`가 같은 세션의 `message_type=QUESTION`인지 검증한다.
3. 모든 `optionId`가 해당 질문의 `conversation_message_options` 행에 속하는지 검증한다. 질문에 포함되지 않은 option은 거부(`OPTION_NOT_ALLOWED`)한다. `type`·`value`·`labelSnapshot`은 서버 Snapshot과 일치해야 한다.
4. 아동 답변 메시지(`message_type=OPTION_ANSWER`)를 생성하고 `parent_message_id`에 질문 ID를 저장한다.
5. 선택 항목을 `conversation_message_selected_options`에 요청 순서(`selection_order`)대로 저장한다.

## 3. 성공 응답

HTTP `201 Created` · `Location: /api/v1/conversations/{conversationId}/messages/{messageId}`

```json
{
  "messageId": 805,
  "conversationId": 800,
  "parentMessageId": 803,
  "sequence": 5,
  "senderType": "CHILD",
  "messageType": "ANSWER_OPTION",
  "selectedOptions": [
    { "optionId": "happy", "type": "EMOTION", "value": "HAPPY", "labelSnapshot": "기뻐요" }
  ],
  "directText": null,
  "createdAt": "2026-07-22T09:31:00Z"
}
```

> ✅ **확정 (2026-07-23, QA 반영)**: 최신본 12.6은 선택형 답변의 응답 본문을 정의하지 않아 아래 원칙으로 확정한다. **공개 API는 공개 Enum 값을 노출한다** — `messageType`은 DB 값 `OPTION_ANSWER`가 아닌 공개 값 `ANSWER_OPTION`(§4 매핑 기준)을 쓰고, `conversationId`를 포함한다. `sequence`·`Location`을 포함한다.
> - 근거: §4가 공개↔DB Enum 매핑을 규정하므로 공개 응답은 공개 값이어야 하며, DB Enum 직접 노출은 지양한다.
> - 참고: 명세 12.5(음성 답변) 예시는 DB 값 `"VOICE_ANSWER"`를 노출하고 `conversationId`가 없어 본 원칙과 불일치한다. 이는 **명세 측 기존 불일치**이며, 문서 담당자가 12.5/12.6 응답을 본 원칙으로 통일하는 것을 권고한다(149 범위 밖, 리더 override 가능).

## 4. API Enum ↔ DB Enum 변환

| 공개 API `messageType` | DB `conversation_messages.message_type` |
| --- | --- |
| `ANSWER_VOICE` | `VOICE_ANSWER` |
| `ANSWER_OPTION` | `OPTION_ANSWER` |
| `ANSWER_TEXT` | `TEXT_ANSWER` |
| `SYSTEM` | `SYSTEM_NOTICE` |

DB `message_type` CHECK 제약 허용값: `QUESTION`, `VOICE_ANSWER`, `OPTION_ANSWER`, `TEXT_ANSWER`, `SYSTEM_NOTICE`. `sender_type` 허용값: `AI`, `CHILD`, `GUARDIAN`, `SYSTEM`.

## 5. DB 저장 매핑 (v1.2 정규화)

`options_json`, `selected_response_json`, `target_object_json`, `bounding_box`는 실제 저장 컬럼으로 사용하지 않고 아래 정규화 테이블을 사용한다.

### `conversation_messages` (답변 메시지)

| 저장 값 | 컬럼 |
| --- | --- |
| 답변 메시지 | `message_type = 'OPTION_ANSWER'`, `sender_type = 'CHILD'` |
| 상위 질문 연계 | `parent_message_id = questionMessageId` |
| 순서 | `message_sequence` (세션 내 UNIQUE) |

### `conversation_message_selected_options` (선택 응답)

| 요청 값 | 컬럼 |
| --- | --- |
| 생성된 답변 메시지 ID | `answer_message_id` |
| `questionMessageId` | `question_message_id` |
| 선택된 선택지 행 ID | `message_option_id` → `conversation_message_options.id` |
| `selectedOptions[].labelSnapshot` | `label_snapshot` |
| 요청 배열 순서 | `selection_order` (답변 내 UNIQUE) |

복합 FK `(answer_message_id, question_message_id) → conversation_messages(id, parent_message_id)`가 답변이 실제 해당 질문의 자식인지 보장한다. 요청 `optionId`(=`option_key`)는 `conversation_message_options`에서 `(conversation_message_id=questionMessageId, option_key)` UNIQUE로 조회해 `message_option_id`로 변환한다.

## 6. 공통 오류

공통 오류 envelope으로 반환한다.

| 상태 | 코드(예시) | 상황 |
| --- | --- | --- |
| `400` | 유효성 오류 | `selectedOptions` 비어 있음, 필드 누락·형식 오류 |
| `401` | 인증 실패 | 토큰 없음·만료 |
| `403` | `CONSENT_REQUIRED` / 권한 | 동의 없음, 보호자-아동 소유권 불일치 |
| `404` | `CONVERSATION_NOT_FOUND` / `QUESTION_MESSAGE_NOT_FOUND` | 대화·질문 없음 |
| `409` | `ANSWER_ALREADY_SUBMITTED` / `IDEMPOTENCY_KEY_REUSED` / `CONVERSATION_ALREADY_COMPLETED` | 세션 상태·멱등성 충돌 |
| `422`/`409` | `OPTION_NOT_ALLOWED` | 질문에 속하지 않은 선택지 |
| `500` | 내부 오류 | 서버 오류 |

오류 응답에는 STT 원문·AI 프롬프트·시크릿·Stack Trace·서버 경로·Token을 포함하지 않는다.

## 7. 개인정보·경계

- 요청·응답·로그에 아동 이름·생년월일, 보호자 정보, Token, 오디오 Byte를 포함하지 않는다.
- AI 질문 생성·저장(150번)은 중복 구현하지 않으며 질문 메시지의 `parent_message_id`로만 연계한다.

## 8. 후속·연계 이슈

- `S15P11B209-150`: AI 질문 생성·저장 (선행, 완료)
- `S15P11B209-288/289`: 음성 답변·STT 저장 (기반 재사용 대상, 완료)
- `S15P11B209-285`: AI 질문 건너뛰기 API (CONV-08)
- `S15P11B209-151`: 활동별 대화 내역 조회 API (CONV-02, 저장된 선택 응답 조회)

## 9. QA 검증 결과 및 결정 로그 (2026-07-23)

독립 QA(qa-inspector) 교차 검증 결과 **Blocker 0, 코드 재작업 불필요**. 명세↔Controller, DTO↔ERD/DB, Enum↔CHECK, Entity↔Migration 정합. 신규 테스트 16건 PASS·spotlessCheck PASS 독립 재현. (전체 test 빌드의 6건 실패는 Testcontainers/Docker 미가용 IntegrationTest로 본 이슈 무관.)

구현자가 남긴 미확정 항목은 아래 **합리적 기본값으로 확정**한다(근거 명시, 리더 override 가능).

| # | 항목 | 결정 | 근거 |
| --- | --- | --- | --- |
| 1 | 응답 본문 Enum/필드 | 공개 값(`ANSWER_OPTION`)+`conversationId`+`sequence`+`Location` | §3·§4 (공개 API는 공개 Enum) |
| 2 | `directText` 저장 | `conversation_messages.raw_text` (blank→null 정규화) | 별도 컬럼 없음, 원문 성격상 raw_text 적합 |
| 3 | `OPTION_NOT_ALLOWED` 상태코드 | **409** 유지 | §6에 409 명시, 계약 일관성 |
| 4 | `ANSWER_ALREADY_SUBMITTED` | 질문당 1답변, 기존 존재 시 409 | 재제출 멱등·중복 방지 |
| 5 | 멱등성 store 재사용 부작용 | 현행 유지(공유 store), 후속 분리 검토 | 288/289 음성 답변 영향 최소화 |

### 후속 개선(병합 차단 아님, follow-up)
- **m1** 멱등 재생 시 `Location` 헤더 미재현(`VoiceAnswerIdempotencyStore`가 status+body만 캐시).
- **m2** 음성 전용 코드 `VOICE_ANSWER_IN_PROGRESS`가 선택형 endpoint 타임아웃에 노출 → 공용/전용 코드 분리 검토.
- **m3** Controller try-catch 도메인 처리 — 기존 `VoiceAnswerController` 패턴과 동일, 일관성 위해 유지.
- **m4** `OPTION_NOT_ALLOWED`가 (질문외/snapshot불일치/요청내 중복) 3원인 통일 — 요청 내 중복은 400 분리 검토 가능.
- **m5** [크로스팀] `ConversationMessageOption.snapshot()`의 `option_type="STATIC"` 하드코딩(150 범위) vs 명세 예시 `EMOTION` — 150↔프론트 계약 통합 시 확인.
