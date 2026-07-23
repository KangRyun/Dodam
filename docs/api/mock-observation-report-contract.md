# Mock 관찰 리포트 생성 계약서 (S15P11B209-152)

- 상태: 구현 기준 계약 (draft). 미확정 항목은 §8 결정 로그에 기본값·근거 기록.
- 작성: 2026-07-23
- 기준: `API_명세서_최종.md`(DRAWING-11 §10.10, REPORT-02 §13.4, 내부 AI §19, Enum §4) + `erd-cloud-schema-v1.2.sql` + develop 병합 코드
- 방침: 명세 충돌 시 ① develop 병합 코드 → ② 최신 문서. Notion 라이브 조회 제외. 미확정 설계는 합리적 기본값으로 진행·기록.

## 1. 목적과 범위

DRAWING-11(`POST /drawing-sessions/{id}/complete`)이 이미 **PENDING 분석 + GENERATING 리포트 껍데기**만 만들고 종료한다(develop `DrawingCompletionService`). 152는 그 뒤를 이어 **Mock AI 관찰 결과를 생성·검증하고 정규화 테이블에 저장하여 리포트를 COMPLETED로 완성**한다. AI 서버는 stateless(DB 미접근), 저장은 Spring만 수행(명세 §19.2).

**신규 마이그레이션 없음** — 대상 13개 테이블 모두 V1/V3에 존재.

### 1.1 In-scope (이번 이슈)
- Mock observation/FINAL 분석 Client (인터페이스 + Mock 구현 + `@ConditionalOnProperty` 스위치, drawing-analysis Mock 패턴 이식).
- 생성 오케스트레이션 + 영속화 서비스, 상태 전이:
  - `analyses`: PENDING → SUCCESS (실패 시 FAILED), `model_name/model_version/completed_at` 채움.
  - `analysis_observation_results` 저장.
  - `analysis_conversation_summaries` 저장(대화 세션 카운트 집계).
  - `reports` 하위: `report_activity_summaries`, `report_activity_notes`, `report_observed_features`, `report_key_conversations`, `report_follow_up_guides`, `report_guardian_questions` 저장.
  - `reports`: GENERATING → COMPLETED (실패 시 FAILED), `is_expert_review_recommended`·`limitations_text` 갱신.
- 신규 JPA 엔티티(약 8종) + Repository, `Report`에 상태 전이 메서드 추가.

### 1.2 Out-of-scope (후속 이슈로 분리 — §8-f)
- `report_evidence_references`/`report_evidence_authors` (실 RAG 근거) — Mock에선 **미저장**(빈 목록). RAG 연동 이슈에서 채움.
- `analysis_unused_inputs` — 해피패스 Mock에선 **미저장(빈 목록)**. 부분성공/제외 입력 발생 시 저장은 후속.
- PDF 생성(REPORT-04/05), 전문가 리뷰 워크플로우(COUNSEL-*), REPORT-02/03 조회 API 자체(별도 이슈 153).

## 2. 트리거 (결정)

**기본값(§8-d1):** `DrawingCompletionService.complete(...)`가 `requestReport=true`로 리포트/분석 껍데기를 만든 뒤, **커밋 후(afterCommit) Mock 생성 서비스를 호출**해 채운다. Mock 모드에선 동기 즉시 생성이므로 별도 워커 없이 완결. 실제 AI 모드(`mode=http`)로 교체될 자리는 동일 인터페이스 뒤에 둔다.
- 생성 서비스 진입: `MockObservationReportGenerationService.generate(analysisId)` (analysisId = complete가 만든 PENDING FINAL 분석).
- 멱등: complete는 `analyses.idempotency_key`로 이미 멱등. 생성 서비스는 대상 분석이 이미 SUCCESS거나 리포트가 이미 COMPLETED면 **재생성하지 않고 종료**(자연 멱등).
- 스위치: 생성 Client 빈은 `app.ai.observation.mode`(mock|http) `@ConditionalOnProperty`, 기본 `mock`.

## 3. Mock AI 계약 (내부, §19.3/19.4 기반)

내부 observation 전용 엔드포인트는 최신 명세에 **없음**(구 명세 §4.6은 빈 플레이스홀더). 최신 명세는 FINAL 종합분석 응답(§19.4)에 `observationDraft`로 통합. 따라서 Mock Client는 **최신 §19.3 요청 / §19.4 응답 DTO**를 기준으로 한다.

- 요청(Mock 입력, §19.3): `analysisId, drawingSessionId, analysisType=FINAL, triggerReason, childContext{ageGroup, questionDifficulty}`(아동 이름·생년월일 미포함), `conversation{messages[]}`, `reflection{selectedEmotions, expressedEmotionText}`. 실 DB 조회로 채운다(대화 세션·감정 입력).
- 응답(Mock 출력): `observationDraft{status=AI_DRAFT, overallSummary, observations[], followUpQuestions[], expertReviewRequired, disclaimer}` + `conversationSummary{...}` + `modelName, modelVersion`. **observationDraft 필드명 불일치(§8-d2)는 §19.4를 정본으로 통일.**
- 가드레일(§19, §13.4): 진단형 표현 금지, 근거 동반, `disclaimer` 필수, `riskSignal`·`attentionPoints`·`observedEmotion`은 보호자 화면 노출 금지(저장은 전문가 내부용 컬럼에만).

## 4. 저장 매핑 (camelCase → snake_case, ERD 제약 준수)

### 4.1 analyses (PENDING→SUCCESS 전이)
`analysis_status`=SUCCESS, `model_name`/`model_version`(Mock 값), `completed_at`=now. `confidence`는 Mock 고정값(0~1). 기존 `DrawingAnalysis`에 `succeedFinal(...)` 류 전이 메서드 추가(현재 PROCESSING→SUCCESS만 있음, PENDING→SUCCESS 필요).

### 4.2 analysis_observation_results (신규 엔티티)
`analysis_id`, `result_version`=1, `overall_summary`, `positive_signals`, `attention_points`(전문가 내부), `evidence_summary`, `guardian_guidance`, `follow_up_question`, `is_expert_review_required`, `review_status`=`AI_DRAFT`(ObservationReviewStatus), `disclaimer_text`(필수), `generated_model_version`, `created_at`. `observed_emotion`/`emotion_confidence`는 **미저장 또는 전문가 내부용만**(명세 line 2168). UNIQUE 없음.

### 4.3 analysis_conversation_summaries (신규 엔티티)
`analysis_id`, `conversation_session_id`, `summary_text`, `main_topic`, `expressed_emotion`, `emotion_source`(SELECTED/STATED/INFERRED), `question_count`/`response_count`/`skipped_question_count`/`unrecognized_speech_count`(대화 세션·메시지 집계), `representative_utterance`, `summary_model_version`, `created_at/updated_at`. FK `conversation_session_id` ON DELETE SET NULL.

### 4.4 reports (GENERATING→COMPLETED 전이)
`report_status`=COMPLETED, `is_expert_review_recommended`=observationDraft.expertReviewRequired, `limitations_text`(한계 고지 문구, NOT NULL), `updated_at`. `Report`에 `complete(...)`/`fail(...)` 전이 메서드 추가.

### 4.5 reports 하위 (신규 엔티티, 모두 display_order UNIQUE·FK CASCADE)
- `report_activity_summaries`(1:1): `drawing_duration_ms`, `pause_count`, `erase_count`, `pressure_available`, `conversation_question_count/answered_count/skipped_count`, `conversation_summary`. 모든 카운트 `>=0`.
- `report_activity_notes`: `note_text`, `display_order`(0..n).
- `report_observed_features`: `feature_code`, `title`, `description`(NOT NULL), `evidence_summary`, `visibility_scope`(**EXPERT_ONLY|REVIEWED_GUARDIAN**), `display_order`. 보호자 노출은 REVIEWED_GUARDIAN만(전문가 검토 전 관찰특징은 EXPERT_ONLY).
- `report_key_conversations`: `question_message_id`/`answer_message_id`(→conversation_messages, SET NULL), `question_text`(NOT NULL), `answer_text`, `answer_type`, `display_order`. 실제 대화 메시지에서 대표 Q/A 선별.
- `report_follow_up_guides`: `guidance`(NOT NULL), `detail_text`, `display_order`.
- `report_guardian_questions`: `question_text`(NOT NULL), `question_purpose`, `display_order`.

## 5. 상태·트랜잭션 규칙
- 생성 전체는 하나의 `@Transactional` 경계에서 저장(부분 실패 시 전체 롤백). Client 호출은 트랜잭션 밖(drawing-analysis 패턴).
- 성공: analyses SUCCESS + report COMPLETED. 검증/저장 실패: analyses FAILED(`error_code`/`error_message`) + report FAILED, 원본 세션 데이터 보존.
- FK 정합성: 저장 전 `analysis_id`↔`drawing_session_id`↔대화 세션 FK 검증. `uk_reports_session_version`·display_order UNIQUE 위반은 충돌 오류로 매핑.

## 6. 오류 처리
- 공통 규약 재사용. observation 전용 신규 오류코드는 최소화하되, 필요한 것만 `MockObservationReportErrorCode`로 정의: ANALYSIS_NOT_FOUND(404), REPORT_NOT_FOUND(404), ANALYSIS_NOT_PENDING/이미완료(409, 멱등 종료), OBSERVATION_GENERATION_FAILED(502/500), STORAGE_CONFLICT(409). AI 401/403/timeout/5xx는 실 AI 모드용 매핑 자리만 두고 Mock은 정상 경로.
- 민감정보(원문·토큰·파일 바이트) 로그 금지. `requestId`/`analysisId`/상태/처리시간만 로깅.

## 7. 안전 규칙 (가드레일)
- 진단형·확정 표현 금지, 관찰·대화 보조 문구만. `disclaimer_text`/`limitations_text` 필수.
- `attention_points`, `observed_emotion`, `riskSignal`, 전문가 검토 전 `observed_features`는 보호자 응답(REPORT-02)에 노출 금지 → 저장은 전문가 내부/EXPERT_ONLY 컬럼에만.
- 행동 수치는 객관적 기록으로만 저장.

## 8. 결정 로그 / 미확정 기본값

- **d1 (트리거):** complete afterCommit 동기 Mock 생성(§2). 실 AI는 동일 인터페이스 뒤 http 모드. → 뒤집기 쉬움(스위치·훅만 교체).
- **d2 (observationDraft 필드 불일치):** §19.4 응답을 정본으로 통일(status/overallSummary/observations/followUpQuestions/expertReviewRequired/disclaimer).
- **d3 (Mock 내부 DTO):** 최신 명세 §19.3/19.4 기준. 구 명세 `/internal/ai/v1/reports/observation`(빈 계약)은 사용하지 않음.
- **d4 (riskSignal):** ERD 전용 컬럼 없음 → 별도 저장 안 함. 전문가 안내는 `attention_points`/`guardian_guidance`로 표현. (팀 확정 필요)
- **d5 (emotion_source):** CHECK 없는 varchar → SELECTED/STATED/INFERRED 문자열 사용, 애플리케이션 enum으로 강제.
- **d6 (report_version):** 최초 생성은 1(complete가 이미 1로 생성). 재생성/재시도 시 증가 규칙은 후속.
- **f1~f3 (후속 이슈 권장):** RAG 근거(`report_evidence_*`) 저장, PDF 생성, `analysis_unused_inputs` 부분성공 처리.

## 9. 테스트 범위
- 정상: PENDING 분석 → 생성 → analyses SUCCESS + observation/conversation summary + reports 하위 저장 + report COMPLETED.
- 멱등: 이미 SUCCESS/COMPLETED 재요청 시 재생성 없이 종료.
- FK 불일치·존재하지 않는 analysis/report → 오류.
- display_order UNIQUE·카운트 CHECK 경계.
- 안전: disclaimer 누락 차단, EXPERT_ONLY 특징이 보호자 매핑에 새지 않음, 진단 표현 필터(있으면).
- 빈 대화/전부 skip fixture(149/150 데이터 대신 비민감 fixture).
- Mock/실 AI 동일 DTO 검증(Validator, requestId 대조).
