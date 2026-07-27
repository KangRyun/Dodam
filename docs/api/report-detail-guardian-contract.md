# 보호자용 관찰 리포트 상세 조회 계약서 (REPORT-02 / S15P11B209-153)

- 상태: 구현 기준 계약 (draft)
- 작성: 2026-07-24
- 기준: `API_명세서_최종.md` REPORT-02 §13.2/§13.4 + `erd-cloud-schema-v1.2.sql` 리포트 테이블 + develop 코드(151 읽기 프로젝션 관례)
- 방침: 충돌 시 ① develop 병합 코드 → ② 최신 문서. Notion 라이브 조회 제외. 미확정은 합리적 기본값+근거.

## 1. 개요
| 항목 | 값 |
| --- | --- |
| 메서드·URI | `GET /api/v1/reports/{reportId}` |
| 권한 | 연결 보호자(GUARDIAN, Bearer). 해당 리포트의 아동과 보호자 관계 필수 |
| 성공 | 200 OK |
| 읽기 전용 | `@Transactional(readOnly=true)`, 151처럼 **읽기 전용 프로젝션 엔티티**로 조회(152 write 엔티티 비의존) |

**의존성:** 리포트 데이터는 152(Mock 관찰 리포트 생성)가 채운다. 152 미병합 시 런타임 데이터는 비어있을 수 있으나 153 **코드는 152에 컴파일 의존하지 않는다**(자체 프로젝션). 테이블은 V1/V3에 이미 존재 → 마이그레이션 없음.

## 2. 응답 스키마 (§13.4, 보호자용)
```
{ reportId, reportVersion, reportStatus,
  drawingSession{ drawingSessionId, childId, drawingTypeCode, drawingTypeName, title, inputMethod, startedAt, completedAt, durationMs },
  drawing{ finalImageUrl, thumbnailUrl },
  childExpression{ selectedEmotions[], expressedEmotionText, representativeUtterances[{messageId,text,source,sttNeedsConfirmation}] },
  activityFacts{ detectedObjects[], drawingDurationMs, pauseCount, eraseCount, pressureAvailable, notes[] },
  conversationSummary{ questionCount, answeredCount, skippedCount, summary },
  guardianConversationGuide[],
  limitations[],
  expertReview{ status, available },
  createdAt }
```

## 3. 필드 → 소스 매핑 (camelCase↔snake_case; 정확한 컬럼은 구현자가 ERD로 확정)
| 응답 | 소스 |
| --- | --- |
| reportId/reportVersion/reportStatus/createdAt | `reports` |
| drawingSession.* | `drawing_sessions` + `drawing_types`(code/name). durationMs = started~completed |
| drawing.finalImageUrl/thumbnailUrl | `drawing_assets`(FINAL / THUMBNAIL, 서명 URL은 기존 asset URL 규칙 재사용; 없으면 null) |
| childExpression.selectedEmotions | `drawing_session_emotions` |
| childExpression.expressedEmotionText | `analysis_conversation_summaries.expressed_emotion`/관련 텍스트 (없으면 null) |
| childExpression.representativeUtterances | `report_key_conversations`(question/answer_message_id, text, answer_type) — source(STT/TEXT)·sttNeedsConfirmation은 원 메시지 기준, 불명이면 보수적 기본값 |
| activityFacts.detectedObjects | 분석 detections(그림 객체명) |
| activityFacts.drawingDurationMs/pauseCount/eraseCount/pressureAvailable | `report_activity_summaries` |
| activityFacts.notes | `report_activity_notes`(display_order 순) |
| conversationSummary.questionCount/answeredCount/skippedCount | `report_activity_summaries` |
| conversationSummary.summary | `report_activity_summaries.conversation_summary` 또는 `analysis_conversation_summaries.summary_text` |
| guardianConversationGuide | `report_follow_up_guides.guidance`(display_order 순) |
| limitations | `reports.limitations_text`(줄 분리) 또는 관찰 결과 disclaimer 계열 |
| expertReview | 전문가 리뷰 워크플로 미구현 → 기본값 §5-d3 |
| createdAt | `reports.created_at` |

## 4. 안전 규칙 (보호자 금지 필드 — 반드시 응답에서 제외, §13.4)
- `observedEmotion`, `emotionConfidence`(AI 추정 감정·확률) 노출 금지.
- 질환·장애·성격 분류/점수 금지.
- **전문가 검토 전 `attentionPoints`, raw risk score, 내부 프롬프트 금지.**
- `report_observed_features` 중 **`visibility_scope != 'REVIEWED_GUARDIAN'`(즉 EXPERT_ONLY)** 는 보호자 응답에 절대 포함하지 않는다. (§13.4 보호자 스키마엔 observedFeatures 필드 자체가 없으므로 기본은 미노출; 만약 노출 필드를 둔다면 REVIEWED_GUARDIAN만.)
- RAG 문헌 직접 적용 문장·모델 내부 지표 금지.
- 행동 수치는 객관적 기록으로만("멈춤 4회" O, 해석 X).

## 5. 결정 로그 / 기본값
- **d1 (권한):** 리포트→drawing_session→child→보호자 관계 검증. 관계 없으면 403(기존 `GuardianResourceAccessValidator`/`CONVERSATION_ACCESS_DENIED` 계열 어휘 재사용).
- **d2 (리포트 상태):** `COMPLETED`면 전체 응답. `GENERATING`/`FAILED`면 `reportStatus`와 `drawingSession` 등 기본 정보만 채우고 관찰/대화 섹션은 빈 목록·null(진행 중 조회 대응). 별도 409는 두지 않음(폴링 UX). — 구현자가 단순화 판단.
- **d3 (expertReview):** 전문가 리뷰 테이블/워크플로 미구현 → `{ status: "NOT_REQUESTED", available: false }` 고정. `reports.is_expert_review_recommended`는 보호자 노출 대신 available 판단 근거로만 후속 검토.
- **d4 (representativeUtterances.source/sttNeedsConfirmation):** 원 메시지 유형에서 유도. 정보 부족 시 source=TEXT, sttNeedsConfirmation=false 보수적 기본.
- **d5:** 서명 URL 생성기가 별도로 없으면 asset 저장 URL/키 기반 기존 규칙 재사용, 없으면 null.

## 6. 에러
| HTTP | code | 조건 |
| --- | --- | --- |
| 401 | AUTH_UNAUTHORIZED | 토큰 없음/만료 |
| 403 | REPORT_ACCESS_DENIED | 보호자-아동 관계 없음 |
| 404 | REPORT_NOT_FOUND | 리포트 없음/HIDDEN |
- 신규 `ReportDetailErrorCode`(또는 report 도메인 공통). HIDDEN 리포트는 404 취급(노출 안 함).

## 7. 테스트
- 정상 COMPLETED 리포트 조립(모든 섹션), 권한 없음 403, 없음/HIDDEN 404, GENERATING 시 부분 응답.
- **EXPERT_ONLY 관찰특징이 보호자 응답에 새지 않음**(부정형 검증), 금지 필드 미포함.
- 프로젝션 조립 시 각 서브 테이블 빈 경우 안전(빈 목록).
- 컨트롤러/서비스/DTO JSON 테스트(151 구조). Docker 통합테스트 신규 없음(단위·슬라이스).
