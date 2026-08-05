# 보호자용 관찰 리포트 상세 조회 계약서 (REPORT-02 / S15P11B209-153)

- 상태: 구현 기준 계약 (draft) · **2026-08-05 §4-1~§4-4·§5-d6~d8·§7-1 추가 (S15P11B209-885)**
- 작성: 2026-07-24
- 기준: `API_명세서_최종.md` REPORT-02 §13.2/§13.4 + `erd-cloud-schema-v1.2.sql` 리포트 테이블 + develop 코드(151 읽기 프로젝션 관례)
- 방침: 충돌 시 ① develop 병합 코드 → ② 최신 문서. Notion 라이브 조회 제외. 미확정은 합리적 기본값+근거.
- **응답 형태의 정본은 `docs/S15P11B209-875-report-api-contract.md`다**(FE 구현 완료분). 이 문서는 그 위에 얹히는 **보호자 안전 규칙**을 정한다 — 필드명이 갈리면 875를 따른다.

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
| activityFacts.detectedObjects | 최신 리포트는 `report_drawn_items.name`(AI VLM 관찰 서술에서 실제 등장한 대상만, `display_order` 순). `has_drawn_items=false`인 과거 리포트만 YOLO 탐지 객체명을 confidence 0.50 이상으로 폴백한다. 필드명·타입은 하위 호환을 위해 유지한다. |
| activityFacts.drawingDurationMs/pauseCount/eraseCount/pressureAvailable | `report_activity_summaries` |
| activityFacts.notes | `report_activity_notes`(display_order 순) |
| conversationSummary.questionCount/answeredCount/skippedCount | `report_activity_summaries` |
| conversationSummary.summary | `report_activity_summaries.conversation_summary` 또는 `analysis_conversation_summaries.summary_text` |
| guardianConversationGuide | `report_follow_up_guides.guidance`(display_order 순) |
| limitations | `reports.limitations_text`(줄 분리) 또는 관찰 결과 disclaimer 계열 |
| expertReview | 사람 전문가 리뷰 워크플로 없음 → 항상 기본값 §5-d3 |
| observedFeatures | `report_observed_features` 중 `visibility_scope='REVIEWED_GUARDIAN'`(display_order 순) — §4-2 결정 2 개정 |
| createdAt | `reports.created_at` |

## 4. 안전 규칙 (보호자 금지 필드 — 반드시 응답에서 제외, §13.4)
- `observedEmotion`, `emotionConfidence`(AI 추정 감정·확률) 노출 금지.
- 질환·장애·성격 분류/점수 금지.
- **전문가 검토 전 `attentionPoints`, raw risk score, 내부 프롬프트 금지.**
- `report_observed_features` 중 **`visibility_scope != 'REVIEWED_GUARDIAN'`(즉 EXPERT_ONLY)** 는 보호자 응답에 절대 포함하지 않는다. **개정(2026-08-05):** 반대로 `REVIEWED_GUARDIAN`인 항목은 **공개 대상이며 최상위 `observedFeatures[]`로 싣는다**(S15P11B209-875 §2-1). 조회 자체를 `REVIEWED_GUARDIAN`으로 좁혀 EXPERT_ONLY 행은 읽지도 않는다 — 읽고 나서 거르는 방식은 다음 사람이 필터를 빠뜨릴 여지를 남긴다.
- RAG 문헌 직접 적용 문장·모델 내부 지표 금지.
- 행동 수치는 객관적 기록으로만("멈춤 4회" O, 해석 X).

### 4-1. 경향 해석 예외 (S15P11B209-885, 2026-08-05 확정)

리포트 정책이 "객관 기록 + 대화 요약"에서 "**근거로 뒷받침되는 비진단 경향 해석**"으로 확장된다. 위 금지 조항을 문자 그대로 적용하면 그 경향 문장이 우리 금지 조항에 걸리므로, 아래 예외를 둔다.

> **네 조건을 모두 충족한 경향 문장은 보호자 노출을 허용한다.**
>
> 1. **서버가 발급하고 검증할 수 있는, 서로 독립된 원본 근거 2건 이상.** 독립성은 근거 종류(`sourceType`)가 아니라 **원본(`sourceRef`) 단위**로 판정한다.
> 2. 그중 **아이 자신의 확인 가능한 표현 근거 1건 이상** — 아이 답변(`CHILD_ANSWER`) · 고른 감정(`SELECTED_EMOTION`) · 말한 감정(`STATED_EMOTION`). 그림 관찰(`VISION`)·활동 지표(`ACTIVITY_METRIC`)만으로 구성된 해석은 공개하지 않는다.
> 3. **`scopeText`(해석 범위 안내) 동반**, 그리고 `category`가 성격 분류가 아닌 **관찰 관점 라벨**(RELATIONSHIP·EMOTION·SELF_EXPRESSION·ACTIVITY_STYLE·ADAPTATION).
> 4. **구조적 공개 게이트와 표현 안전 필터를 모두 통과**(§4-3).

**적용 범위:** 이 예외는 **경향 해석(`publicInterpretations`) 경로에만** 적용된다. `attentionPoints`는 종전대로 보호자 응답에서 제외한다.

> **개정(2026-08-05) — `features`(`report_observed_features`)는 더 이상 "전부 강등"이 아니다.** 아래 §4-2 결정 2를 개정했다. AI 자체 검토(`AI_REVIEWED`)를 통과한 리포트의 `REVIEWED_GUARDIAN` 항목은 공개한다(S15P11B209-875 §2-1). 경향 해석 예외와는 **별개의 경로**이며 서로 대체하지 않는다.

**예외 대상이 아닌 것(유지 금지):**

- 심리·발달 질환명·진단명
- 점수·등급·확률·또래 평균 비교
- "이 아이는 불안정하다/공격적이다" 같은 고정 특질·낙인 단정
- `observedEmotion`·`emotionConfidence` 필드 노출
- EXPERT_ONLY 데이터·`attentionPoints`의 보호자 노출

### 4-2. 경향 해석은 기존 강등 경로를 타지 않는다 (결정 1·2)

**결정 1 — `publicInterpretations`는 기존 `features` 저장·노출 경로를 재사용하지 않는다.** 별도 저장(`report_public_interpretations` 등)과 **별도 노출 판단**을 쓰고, `ObservationReportPersistenceService.resolveVisibility()`·`expertReviewed` 경로를 **타지 않는다.** 노출 여부는 §4-3의 구조적 공개 게이트 결과로 정한다.

근거(2026-08-05 실코드 확인):

```java
// 2026-08-05 개정 전 (report/service/ObservationReportPersistenceService.java)
private static ReportFeatureVisibility resolveVisibility(String value, boolean expertReviewed) {
  if (expertReviewed && "REVIEWED_GUARDIAN".equals(value)) {
    return ReportFeatureVisibility.REVIEWED_GUARDIAN;
  }
  return ReportFeatureVisibility.EXPERT_ONLY;   // 그 외 전부 강등
}

boolean expertReviewed = observation.getReviewStatus() != ObservationReviewStatus.AI_DRAFT;
// ↑ ObservationReviewStatus 값이 AI_DRAFT 하나뿐이라 이 식은 컴파일 시점부터 항상 false 였다.
```

개정 후에는 판정이 enum 한 곳에 모인다(사람 검토 상태가 생기면 여기에만 추가한다).

```java
// analysis/domain/ObservationReviewStatus.java
public enum ObservationReviewStatus { AI_DRAFT, AI_REVIEWED;
  public boolean isReviewed() { return this != AI_DRAFT; }
  public static ObservationReviewStatus fromAiStatus(String value) { /* 모르는 값 → AI_DRAFT */ }
}

// report/service/ObservationReportPersistenceService.java
boolean reviewed = observation.getReviewStatus().isReviewed();
```

`ObservationReviewStatus`를 세팅하는 곳은 `analysis/domain/AnalysisObservationResult.java`의 `AI_DRAFT` 고정 대입 한 군데뿐이고 다른 상태로 전이시키는 코드가 없었다(전문가 검토 워크플로 미구현) → **`expertReviewed`는 항상 false**였다. 따라서 경향 해석을 이 경로에 실으면 **구현은 끝났는데 보호자 화면에는 아무것도 나오지 않고, 기존 테스트는 전부 통과한다**(전부 "노출되지 않는지"만 검증하므로). §7의 긍정 케이스가 이 실패를 잡는다.

**결정 1은 그대로 유효하다** — 경향 해석은 별도 저장·별도 노출 판단을 쓴다.

**결정 2 — 개정(2026-08-05).** 원문은 "기존 `features`의 EXPERT_ONLY 정책은 변경 없음"이었다. 그러나 위 진단이 드러낸 것은 "정책이 엄격하다"가 아니라 **통과가 구조적으로 불가능했다**는 것이다. 열어 줄 주체(사람 전문가)가 없는데 "검토 후 공개" 규칙만 남아 있어, 운영 `report_observed_features` 97건이 전부 `EXPERT_ONLY`로 쌓였고 읽는 경로는 0건이었다.

개정 내용:

- `ObservationReviewStatus`에 **`AI_REVIEWED`** 를 추가하고, AI가 자체 검토를 통과시킨 결과에 이 상태를 실어 보낸다. 서버는 AI가 보낸 값을 해석만 하고 임의로 올리지 않는다. **모르는 값·누락은 `AI_DRAFT`** 로 떨어뜨린다(실패는 닫히는 쪽으로만).
- `resolveVisibility()`의 **강등 규칙 자체는 완화하지 않는다.** 두 조건(리포트 검토 통과 + 항목이 `REVIEWED_GUARDIAN`)을 여전히 모두 요구한다. 바뀐 것은 첫 조건이 이제 **참이 될 수 있다**는 점뿐이다.
- **소급 적용 없음.** 기존 97건은 `EXPERT_ONLY`로 남는다 — 검토를 거치지 않은 과거 리포트를 여는 셈이 되기 때문이다.
- `expertReviewRequired`의 뜻은 **"사람 상담 권유가 필요한 신호"** 로 재정의한다. 사람 검토 대기열이 아니므로 응답의 `expertReview`는 계속 `NOT_REQUESTED`·`available=false`다.

### 4-3. 서버 안전 검증 2단 (성질이 다르므로 분리한다)

| 단계 | 검사 | 실패 처리 |
| --- | --- | --- |
| **1. 구조적 공개 게이트** | §4-1의 ①②③ 조건 + 근거 배제 규칙(§4-4) + 참조 정합(`evidenceRefs`가 실제 `evidenceId`를 가리키고 `sourceRef`가 해석 가능) | **해당 카드만 미공개(제외)** + 사유 코드 로그. **EXPERT_ONLY 강등이 아니다** — 근거 자체가 없으므로 표현을 다듬어도 공개 대상이 아니다 |
| **2. 표현 안전 필터** | 진단명·확정 표현·고정 특질·점수·확률·원인 단정·비난 | **EXPERT_ONLY 강등** + `expertReviewRequired=true`, 내용은 보존 |

- **실행 순서: 1단을 먼저** 돌리고(값싼 결정적 검사) 통과분만 2단에 넣는다.
- 리포트 전체를 실패시키지 않고 **문제 항목만 제외·강등**한다.
- 2단 기준은 AI 측 `ai/report_safety.py`(S15P11B209-591·592 확정 기준)와 **일치시킨다.** 갈리면 통과·차단이 엇갈린다.
  - 차단 예: "자존감이 낮습니다" · "애정결핍" · "공격적인 성향이 있어요" · 임상 질환명 · "이 그림은 ~를 의미합니다"
  - 허용 예: "~일 수 있어요" · "~한 경향" · "~한 모습을 보였어요"(행동 관찰)
- **BE 현재 상태:** 리포트 저장 경로에 텍스트 기반 안전 필터가 **없다**(`진단`·`diagnos`·`forbidden`·`reject`·`sanitiz`·`Pattern` 전부 0건, 하는 일은 `ColumnTextLimiter.fit` 길이 자르기뿐). 두 단 모두 **BE 신규 구현**이다.

**독립 근거 계수 알고리즘** (AI·BE가 같은 절차를 쓴다):

1. `evidenceRefs`가 가리키는 `evidenceItem`을 모은다.
2. 각 항목을 `derivedFrom` **말단까지 재귀적으로** 펼친다(파생의 파생 포함).
3. 얻어진 **말단 `sourceRef`의 합집합**을 만든다.
4. **합집합 크기 = 독립 근거 수.** 파생 근거와 그 원본이 동시에 실려도 같은 말단은 1건.
5. 병합 상한을 적용한다 — 동일 활동의 `SELECTED_EMOTION` + `STATED_EMOTION`은 합쳐 **최대 1건**(선택 감정은 코드, 말한 감정은 자유 텍스트라 서버가 "같은 감정인지"를 결정적으로 비교할 수 없다) / `ACTIVITY_METRIC`은 몇 개든 합쳐 **최대 1건**.

### 4-4. 미확정 STT·위기 발화 — 표시와 근거를 분리한다

| 용도 | 미확정 STT(`sttNeedsConfirmation=true`) | 위기 사유 메시지 |
| --- | --- | --- |
| 문답 표시(`subjectReports[].qaPairs`) | **유지** — 아이 말을 지우지 않고 "확인해 주세요"로 표시 | **제외** |
| 근거(`evidenceItems`)·독립 근거 계수 | **제외** | **제외** |
| `childExpression` 대표 발화 | **제외** | **제외** |

- 위기 사유 = `SELF_HARM_RISK` · `ABUSE_DISCLOSURE` · `CRISIS_INTENT`. 판정은 AI가 리포트 생성 시 재검사해 제외하고(S15P11B209-889), BE는 메시지 단위 영속화를 병행해 사후 추적을 가능케 한다.
- **전제:** 현재 `ReportDetailQueryService`의 `sttNeedsConfirmation`은 **하드코딩 `false`**다(§5-d6). 실데이터로 바꾸지 않으면 이 규칙 전체가 조용히 무효가 된다.

**위기 안내 유형별 분기:**

| 사유 코드 | `crisisAlert` | 처리 |
| --- | --- | --- |
| `SELF_HARM_RISK` · `CRISIS_INTENT` | 생성 가능 | 보호자 통지가 도움이 되는 유형 — 현행 유지 |
| `ABUSE_DISCLOSURE` | **생성 금지(항상 null)** | EXPERT_ONLY 저장 + `expertReviewRequired=true` |

`ABUSE_DISCLOSURE`는 **가해자가 보호자일 수 있어** 자동 통지가 아이를 위험하게 한다(S15P11B209-890에서 AI 측 반영 완료). 그리고 `parentGuides`의 `PROFESSIONAL_SUPPORT`는 **상시 노출되는 일반 상담 안내**이므로 `crisis_guidance`의 문구·연락처를 재사용하지 않고 신고·긴급 번호를 포함하지 않는다.

## 5. 결정 로그 / 기본값
- **d1 (권한):** 리포트→drawing_session→child→보호자 관계 검증. 관계 없으면 403(기존 `GuardianResourceAccessValidator`/`CONVERSATION_ACCESS_DENIED` 계열 어휘 재사용).
- **d2 (리포트 상태):** `COMPLETED`면 전체 응답. `GENERATING`/`FAILED`면 `reportStatus`와 `drawingSession` 등 기본 정보만 채우고 관찰/대화 섹션은 빈 목록·null(진행 중 조회 대응). 별도 409는 두지 않음(폴링 UX). — 구현자가 단순화 판단.
- **d3 (expertReview):** 전문가 리뷰 테이블/워크플로 미구현 → `{ status: "NOT_REQUESTED", available: false }` 고정. `reports.is_expert_review_recommended`는 보호자 노출 대신 available 판단 근거로만 후속 검토.
- **d4 (representativeUtterances.source/sttNeedsConfirmation):** 원 메시지 유형에서 유도. 정보 부족 시 source=TEXT, sttNeedsConfirmation=false 보수적 기본.
- **d5:** 서명 URL 생성기가 별도로 없으면 asset 저장 URL/키 기반 기존 규칙 재사용, 없으면 null.
- **d6 (sttNeedsConfirmation 실데이터화 — 미완, 2026-08-05 확인):** `ReportDetailQueryService`가 `ReportUtteranceResponse`의 `sttNeedsConfirmation`에 **리터럴 `false`를 넘긴다**(`report/service/ReportDetailQueryService.java:226`). d4의 "보수적 기본값"이 사실상 상수가 됐다. §4-4의 STT 배제 규칙은 이 값이 원 메시지 기준 실데이터로 바뀐 뒤에만 효력이 있다 — 그때까지 규칙은 문서상으로만 존재한다. 이 항목은 BE 후속 작업 대상이다.
- **d7 (경향 해석 저장 위치):** §4-2 결정 1에 따라 `report_observed_features`를 재사용하지 않고 별도 테이블(`report_public_interpretations`·`report_evidence_items` 등)을 신설한다. 마이그레이션이 필요하므로 계약 §1의 "마이그레이션 없음"은 153 범위에만 해당한다.
- **d8 (활동 수치 단위 변환 책임):** 875 계약은 **초**(`totalDurationSec`·`drawingDurationSec`), AI 응답과 기존 BE 필드는 **밀리초**(`drawingDurationMs`)다. **변환 책임은 BE**에 둔다. FE DTO는 두 형태를 모두 읽으므로(`report_dtos.dart:275`·`269`) 기존 ms 필드를 유지하면서 초 필드를 함께 실어도 안전하다. 변환 시 **`null`(집계 못 함)과 `0`(0회·0초)을 구분**한다 — `null`을 0으로 만들면 화면이 "0초 그렸다"로 표시된다.

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

### 7-1. 경향 해석 예외 검증 (§4-1~§4-4 추가분)

- **(긍정·필수) 네 조건을 충족한 경향 카드가 보호자 응답에 실제로 포함된다.** 독립 원본 근거 2건 + 아이 표현 근거 1건 + `scopeText`·`homeObservationGuide` 동반 + 두 단 통과인 카드를 넣고 응답에 나오는지 본다. **이 케이스가 없으면 §4-2의 실패(전부 숨겨진 채 배포)를 아무도 잡지 못한다** — 기존 검증은 모두 "노출되지 않는지"만 보므로 전부 통과한다. PDF 내보내기에도 같은 카드가 실리는지 함께 본다(875 §11: 화면엔 있고 PDF엔 없는 데이터 금지).
- **(긍정) 검토를 통과한 `features`가 `observedFeatures[]`로 실제로 노출된다** — 닫힘만 보는 검증은 전부 숨겨진 채 배포돼도 통과한다(결정 2 개정).
- **(회귀) `AI_DRAFT`·해석 불가 상태의 `features`는 여전히 EXPERT_ONLY로 강등된다** — 실패 방향이 닫히는 쪽인지 확인.
- (유지) 진단명·점수·고정 특질 표현이 보호자 응답에 없다(부정형).
- (유지) `visibility_scope != 'REVIEWED_GUARDIAN'` 데이터가 새지 않는다.
- **구조 게이트 계수** — 같은 `sourceType`이라도 다른 원본이면 2건으로 인정 / 파생 근거와 그 원본이 함께 실리면 1건 / 감정 근거만 2건이면 미공개 / 아이 표현 근거 없으면 미공개 / 해석 불가·미제공 참조는 미공개.
- **실패 처리 구분** — 구조 게이트 실패는 **제외**이고 EXPERT_ONLY 강등이 **아니다**(부정형). 표현 필터 실패는 강등 + `expertReviewRequired=true`.
- **경향 해석이 `resolveVisibility()`·`expertReviewed` 경로를 타지 않는다**(결정 1 준수).
- 게이트 통과 0건이면 `publicInterpretations`가 **빈 배열**이고 리포트 조회는 200으로 성공한다(875 §10).
- `ABUSE_DISCLOSURE`에서 `crisisAlert`가 `null`이고 `expertReviewRequired=true`다 / `PROFESSIONAL_SUPPORT` 안내에 신고·긴급 연락처가 없다.
- 미확정 STT 발화가 **문답 표시에는 남고** 근거·대표 발화에는 **없다**(§4-4).
- 활동 수치 ms→초 변환에서 `null`과 `0`이 구분된다(d8).
