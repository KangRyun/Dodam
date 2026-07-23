# 대화 질문 건너뛰기 API 공개 계약서 (CONV-08 / S15P11B209-285)

- 상태: 구현 기준 계약 (draft, FE 크로스팀 확인 필요 항목 §8 표기)
- 작성: 2026-07-23
- 기준 문서: `API_명세서_최종.md §12.8`(최신) + develop 병합 코드(형제 답변 API 149/288) 관례
- 관련 ERD: `conversation_messages`, `conversation_sessions`, `drawing_sessions`

## 1. 개요

아동이 답변하지 않고 "건너뛰기"(또는 "계속 그리기")를 눌렀을 때 현재 AI 질문을 건너뛴 것으로 기록한다. 무응답도 존중되는 유효한 진행이며([CONV-2]), 건너뛴 사실로 아동을 압박하는 어떤 응답도 반환하지 않는다.

| 항목 | 값 |
| --- | --- |
| 메서드·URI | `POST /api/v1/conversations/{conversationId}/skip` |
| 권한 | 연결 보호자(GUARDIAN, Bearer 필요) — 아동 모드 컨텍스트 |
| 성공 | `200 OK` |
| 멱등성 | 자연 멱등 (동일 질문 재요청 시 200 동일 응답). 별도 Idempotency-Key 불요 |

## 2. 명세 충돌 해소 (중요)

구 per-endpoint Notion export(`api v1 conversations {conversationId} skip …md`)와 최신 `API_명세서_최종.md §12.8`이 요청 스키마에서 충돌한다. **사용자 방침(충돌 시 ① develop 병합 코드 → ② 최신 문서 순)** 에 따라 아래로 확정한다.

| 항목 | 구 skip 문서 | §12.8 최신 | develop 코드 관례 | **채택** |
| --- | --- | --- | --- | --- |
| 질문 식별 필드 | `questionId` | `questionMessageId` | `OptionAnswerRequest.questionMessageId` | **`questionMessageId`** |
| 추가 필드 | 없음 | `reason`, `returnToDrawing` | (skip 선례 없음) | **`reason`(선택), `returnToDrawing`(선택)** |
| 404 코드 | `QUESTION_NOT_FOUND` | 미지정 | `QUESTION_MESSAGE_NOT_FOUND` | **`QUESTION_MESSAGE_NOT_FOUND`** |
| 403 코드 | `CHILD_FORBIDDEN` | 미지정 | `CONVERSATION_ACCESS_DENIED` | **`CONVERSATION_ACCESS_DENIED`** |

## 3. Request

### Headers
| 헤더 | 값 | 필수 |
| --- | --- | --- |
| Authorization | Bearer {accessToken} | Y |
| Content-Type | application/json | Y |

### Path Params
| 파라미터 | 타입 | 설명 |
| --- | --- | --- |
| conversationId | number | 대화 세션 ID (`conversation_sessions.id`) |

### Body
| 필드 | 타입 | 필수 | 기본값 | 설명 (ERD 매핑) |
| --- | --- | --- | --- | --- |
| questionMessageId | number(양의 정수) | Y | - | 건너뛸 AI 질문 메시지 ID (`conversation_messages.id`) |
| reason | string(enum) | N | `CHILD_REQUEST` | 건너뛰기 사유. 허용: `CHILD_REQUEST` |
| returnToDrawing | boolean | N | `false` | true → 그림 세션 `current_stage=DRAWING` 전이, false → 대화 상태 유지 |

```json
{ "questionMessageId": 803, "reason": "CHILD_REQUEST", "returnToDrawing": true }
```

## 4. 시스템 처리 (세션 비관 잠금 안)

1. `conversationSessionRepository.findByIdForUpdate(conversationId)` — 없으면 `404 CONVERSATION_NOT_FOUND`.
2. 소유권: 대화 → `drawing_sessions.child_id` → `hasGuardianChildRelation(guardianUserId, childId)` false면 `403 CONVERSATION_ACCESS_DENIED`. 필수 동의 없으면 `403 CONSENT_REQUIRED`.
3. 상태: `isCompleted()` → `409 CONVERSATION_ALREADY_COMPLETED`. `isConversing()` 아니면 `409 CONVERSATION_NOT_CONVERSING`.
4. 질문 검증: `existsQuestion(questionMessageId, conversationId)`(같은 세션의 `message_type='QUESTION'`) false면 `404 QUESTION_MESSAGE_NOT_FOUND`.
5. 답변 존재: `existsAnswerForQuestion(conversationId, questionMessageId)` true면 `409 ANSWER_ALREADY_SUBMITTED` (이미 답변한 질문은 건너뛸 수 없음).
6. 갱신: 해당 질문 메시지 `is_skipped=true` UPDATE. **이미 건너뛴 질문 재요청은 멱등(200 동일 응답)** — 별도 검증 없이 그대로 진행.
7. `returnToDrawing=true`면 그림 세션 `current_stage=DRAWING`(`DrawingStage.DRAWING`)으로 전이. (세션 `conversation_status`는 CONVERSING 유지)
8. `question_count`는 **되돌리지 않는다** (건너뛰기는 이미 카운트된 질문에 대한 표시일 뿐).

## 5. Response `200 OK`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| questionMessageId | number | 건너뛴 질문 메시지 ID |
| isSkipped | boolean | `true` (`conversation_messages.is_skipped`) |
| questionCount | number | 현재 질문 수 (변동 없음) |
| maxQuestionCount | number | 최대 질문 수 |
| currentStage | string | 처리 후 그림 세션 단계 (`DRAWING` 또는 `CONVERSING`). returnToDrawing 반영 여부를 FE에 명시 |

```json
{
  "questionMessageId": 803,
  "isSkipped": true,
  "questionCount": 5,
  "maxQuestionCount": 10,
  "currentStage": "DRAWING"
}
```

> `currentStage`는 §5 기준 확장 필드다. 구 문서엔 없으나 returnToDrawing 동작 결과를 FE가 알아야 하므로 추가. (§8-m1 크로스팀 확인)

## 6. 에러

| HTTP | code | 발생 조건 |
| --- | --- | --- |
| 400 | INVALID_INPUT_VALUE | questionMessageId 누락/비양수, reason 미허용값 |
| 401 | AUTH_UNAUTHORIZED | 토큰 없음/만료 (global) |
| 403 | CONVERSATION_ACCESS_DENIED | 보호자-아동 관계 없음 |
| 403 | CONSENT_REQUIRED | 필수 동의 누락 |
| 404 | CONVERSATION_NOT_FOUND | 대화 세션 없음 |
| 404 | QUESTION_MESSAGE_NOT_FOUND | 같은 세션의 AI 질문 메시지 아님 |
| 409 | ANSWER_ALREADY_SUBMITTED | 이미 답변한 질문 |
| 409 | CONVERSATION_ALREADY_COMPLETED | 종료된 대화 |
| 409 | CONVERSATION_NOT_CONVERSING | 진행 중(CONVERSING) 아님 |

## 7. 저장/불변 규칙

- `is_skipped`는 분석 요약(`analysis_conversation_summaries.skipped_question_count`) 집계의 입력이므로 **삭제·번복 API를 두지 않는다**(이력 보존, BE 노트 준수).
- Flyway 변경 없음: `conversation_messages.is_skipped`, `drawing_sessions.current_stage`는 기존 스키마(v1.2)에 존재.

## 8. 결정 로그 / 크로스팀 확인 필요 (Minor)

- **d1 (확정):** 요청 필드 `questionMessageId`, 에러코드는 develop 형제 API 어휘 정렬 (§2).
- **d2 (확정):** 멱등성은 자연 멱등(재-UPDATE)로 처리, Redis Idempotency-Key 미도입 (단건 UPDATE 단순 유지 원칙).
- **d3 (기본값):** `reason` 허용값은 §12.8의 skip 예시(`CHILD_REQUEST`)만. 종료(complete) reason enum과 분리.
- **m1 (확인 요청):** 응답 `currentStage` 확장 필드 — FE와 표기 통일 필요.
- **m2 (확인 요청):** `returnToDrawing=true` 시 세션 `conversation_status`는 CONVERSING 유지(그림 단계만 전이). 종료가 아님을 FE와 합의.
