# [S15P11B209-875] 보호자 관찰 리포트 재구성 — API 계약 (정본)

FE가 새 리포트 화면을 위해 필요한 응답 계약을 설계한 문서다. BE는 이 형태에 맞춰
응답을 구성하면 된다. **비진단 원칙**(경고/진단 아님)을 데이터 구조에서부터 지킨다.

> 상태: **정본 v1.1 (2026-08-05)** — 필드명은 camelCase(JSON). 모든 배열은 비어 있을 수 있고,
> 비어 있으면 FE가 해당 섹션을 **숨긴다**(오류 아님). `null`과 `0`은 구분한다.

## 0. 이 문서가 정본이다 (2026-08-05 확정)

AI 파트가 별도로 보낸 "관찰 리포트 정책 및 API 변경 요청"과 이 문서의 필드명이 거의 전부 달랐다
(`evidenceId` 정수 vs `"E1"` 문자열, `evidenceRefs` vs `evidenceIds`, `subjectType` vs `drawingSubject`,
`imageUrl` vs `drawing{}`, `visionObservations` vs `observedFacts`, 초 vs 밀리초 등).

**이 문서를 유일한 정본으로 확정하고 그 요청서는 폐기한다.** 근거: FE가 이미 이 계약으로 DTO·화면·테스트를
구현해 develop에 병합했다(`frontend/mobile/lib/features/report/data/dto/report_dtos.dart`, PDF 섹션 순서 포함).
요청서 필드명으로 가면 FE 전면 재작업이 되고 얻는 것이 없다.

요청서의 **안전 장치만** 필드명을 바꾸지 않고 아래 델타로 이 문서 위에 얹었다 → **FE 재작업 0**.
신규 필드는 FE DTO가 모르는 키를 무시하므로 배포 순서와 무관하다.

| 델타 | 내용 | 반영 위치 |
| --- | --- | --- |
| ① | `evidenceItems[]`에 `sourceRef`·`derivedFrom` 추가 | §4 |
| ② | 카드 공개 조건(독립 근거 2건·아이 표현 1건·병합 상한) | §4-1 |
| ③ | 미확정 STT·위기 발화 — 표시와 근거 분리 | §6-1 |
| ④ | `crisisAlert` 유형별 분기(`ABUSE_DISCLOSURE` 생성 금지) | §7-1 |
| ⑤ | 서버 검증 2단 분리(구조 게이트 / 표현 필터) | §4-2 |
| ⑥ | 기존 EXPERT_ONLY 강등 경로를 타지 않음 | §4-3 |
| ⑦ | 보호자 계약 §4 예외 개정 | `docs/api/report-detail-guardian-contract.md` §4-1~§4-4 (S15P11B209-885) |
| ⑧ | 이 문서 자체 보완 4건 | §2·§5-1·§8-1·§9 |

관련 이슈: **885**(계약 §4 예외 — 이 문서 §0 확정 포함) · **886**(AI 요청 계약에 근거 식별자 수용) ·
**887**(AI 응답 생성) · **888**(AI 구조 게이트) · **889**(AI 위기 재검사) · **890**(완료 — `crisis_guidance`
학대 분기). BE 저장·2단 검증·상세 API·PDF는 별도 이슈로 분리한다.

---

## 1. 엔드포인트 (기존 유지 + 응답 확장)

| 메서드·경로 | 용도 | 비고 |
|---|---|---|
| `GET /api/v1/reports/{reportId}` | 리포트 상세 | 아래 **ReportDetail** 반환 |
| `POST /api/v1/reports/{reportId}/regenerate` | 재생성 | 새 `reportVersion`으로 생성(기존 덮어쓰기 금지) |
| `GET /api/v1/reports/{reportId}/export` | PDF | 화면과 **동일 공개 데이터·섹션 순서** |

상태 흐름(기존 유지): `status ∈ {GENERATING, COMPLETED, FAILED, HIDDEN}`
- GENERATING → FE 폴링 / COMPLETED → 상세 / FAILED → 재생성 안내 / HIDDEN → 조회 불가

---

## 2. ReportDetail (최상위)

```jsonc
{
  "reportId": 123,
  "reportVersion": 3,                 // 재생성 시 증가. FE는 새 버전을 표시
  "status": "COMPLETED",              // GENERATING|COMPLETED|FAILED|HIDDEN
  "activityType": "HTP",              // HTP | ART_DIARY | FREE_DRAWING 등 기존 값
  "childDisplayName": "민준",          // 표지용. 없으면 null
  "createdAt": "2026-08-04T09:00:00Z",

  "nonDiagnosticNotice": "이 리포트는 아이가 그림을 그리고 대화한 과정에서 나타난 특징과 심리적 경향을 정리한 자료입니다. 아이의 평소 성격이나 심리 상태를 확정하거나 진단하는 결과는 아닙니다.",

  "publicInterpretations": [ /* Interpretation */ ],  // 3. 주요 경향
  "evidenceItems":         [ /* EvidenceItem */ ],    // 4. 근거 풀(카드가 evidenceRefs로 참조)
  "subjectReports":        [ /* SubjectReport */ ],   // 5. HTP 그림
  "childExpression":       { /* ChildExpression */ } | null, // 아이의 표현 요약
  "conversationSummary":   { /* ConversationSummary */ } | null,
  "activityFacts":         { /* ActivityFacts */ } | null,    // 객관 수치
  "parentGuides":          [ /* ParentGuide */ ],     // 보호자 가이드(4종)
  "limitations":           [ "문장", ... ],           // 한계
  "references":            [ /* Reference */ ]        // 참고 자료
}
```

> **EXPERT_ONLY 데이터는 이 응답에 포함하지 않는다.** `attentionPoints`,
> 전문가 전용 해석 등은 보호자 공개 응답에서 제외한다(FE가 숨기는 게 아니라 **응답에 없어야** 함).

**보완(델타 ⑧-1):** 초안 §2에는 `evidenceItems`가 빠져 있었지만 §4는 "최상위에 근거 풀을 둔다"고 적고 있었고,
FE DTO는 이미 최상위 `evidenceItems`를 읽는다(`report_dtos.dart:508`·`548`). 실제 구현을 기준으로 위 스키마에
추가했다 — **최상위 배치가 정본**이다.

`crisisAlert`(optional, 기본 `null`)를 최상위에 둔다. `null`은 "위기 신호 없음"을 뜻하며 별도 플래그를 두지
않는다. 유형별 생성 규칙은 §7-1.

---

## 3. Interpretation (`publicInterpretations[]`) — 주요 심리 경향 카드

```jsonc
{
  "category": "RELATIONSHIP",  // RELATIONSHIP|EMOTION|SELF_EXPRESSION|ACTIVITY_STYLE|ADAPTATION
  "title": "가족과의 정서적 연결",
  "tendencyText": "가족에게 정서적으로 의지하려는 경향이 보일 수 있습니다.",
  "scopeText": "이번 그림 활동에서 나타난 가능성입니다.",   // 해석 범위(가정)
  "homeObservationGuide": "새로운 상황에서도 보호자의 확인을 반복해서 구하는지 살펴봐 주세요.",
  "evidenceRefs": [ 101, 102 ]   // evidenceItems[].evidenceId 참조(근거 보기)
}
```

규칙(FE):
- `tendencyText`만 단독으로 크게 표시하지 않는다 — **근거 + scopeText를 항상 함께** 표시.
- 카드 정렬 권장: `RELATIONSHIP → EMOTION → SELF_EXPRESSION → ACTIVITY_STYLE → ADAPTATION`.
- 색상: 라벤더·블루·그린 계열 중립. **빨강/위험/경고 아이콘 금지.** category별 중립 아이콘.
- `publicInterpretations`가 빈 배열이면 섹션 전체 숨김(오류 아님).

BE 유의: `tendencyText`는 반드시 **가능성 어조**("~일 수 있습니다"). 단정/진단 어조 금지.

---

## 4. EvidenceItem (`evidenceItems[]`) — 근거

최상위에 근거 풀을 두고, Interpretation이 `evidenceRefs`로 참조한다(중복 근거 재사용).

```jsonc
{
  "evidenceId": 101,          // 내부 식별자 — 화면 미노출(참조용)
  "sourceType": "CHILD_ANSWER",
  "text": "집에는 우리 가족이 산다고 답했어요.",

  // ↓ 델타 ① (신규) — FE 영향 없음. Dart DTO는 아는 키만 읽어 두 필드를 무시한다.
  "sourceRef":   { "kind": "QA_ANSWER", "id": "202" },  // 원본 근거는 필수
  "derivedFrom": null                                    // 파생 근거만 사용
}
```

**왜 필요한가:** 초안에는 "이 근거가 어디서 왔는지"가 없어 서버가 "독립 근거 2건" 규칙을 검증할 수 없다.
AI 자기 신고가 되어 게이트가 무력해진다.

`sourceRef.id`는 **BE가 발급한 식별자만** 쓴다. 조합키(`analysisId`+`objectCode`+`detectionOrder` 같은)는
**금지** — AI가 조립할 수 있으면 검증이 무의미해진다.

| `kind` | `id` 출처 |
| --- | --- |
| `QA_ANSWER` | 답변 메시지 ID |
| `DETECTED_OBJECT` | 탐지 객체 행 ID |
| `VLM_OBSERVATION` | `analysis_observation_results` 행 ID |
| `EMOTION_SELECTION` | `drawing_session_emotions` 행 ID |
| `ACTIVITY_METRIC` | BE 발급 지표 스냅샷 ID |
| `PRIOR_ACTIVITY` | 이전 활동의 **원본** 관찰 레코드 ID 또는 확인된 아동 표현 메시지 ID |

- `PRIOR_ACTIVITY`는 **이전 AI 해석 결과**(`publicInterpretations`·`features`·요약문) 참조 **금지** — 자기 해석이
  자기 근거가 되는 순환 추론을 차단한다.
- 파생 근거(`REPEATED_SUBJECT`·`LONGITUDINAL`)는 `sourceRef` 대신 `derivedFrom`에 원본 ref 목록을 담는다.
- **배타 규칙: 한 항목은 `sourceRef`와 `derivedFrom` 중 정확히 하나만 갖는다.** 둘 다 있거나 둘 다 없으면 무효.

### 4-1. 카드 공개 조건 (델타 ② — 초안에 없던 규칙)

초안은 "무엇을 담을지"만 정하고 "**언제 담아도 되는지**"가 없었다. 카드 한 건이 응답에 실리려면 아래를 모두 충족한다.

1. **독립 근거 2건 이상.** 계산법: `evidenceRefs`가 가리키는 항목을 `derivedFrom` **말단까지 재귀적으로 펼쳐**
   얻은 **말단 `sourceRef`의 합집합 크기**. 파생과 원본이 같이 실려도 같은 말단은 1건.
2. **아이 표현 근거 1건 이상 필수** — `CHILD_ANSWER`·`SELECTED_EMOTION`·`STATED_EMOTION`.
   `VISION`·`ACTIVITY_METRIC`만으로 구성된 해석은 내지 않는다. 파생 근거는 말단이 아이 표현이면 충족으로 본다.
3. **병합 상한** — 동일 활동의 `SELECTED_EMOTION`+`STATED_EMOTION`은 합쳐 **1건**(선택 감정은 코드, 말한 감정은
   자유 텍스트라 서버가 같은 감정인지 결정적으로 판정할 수 없다. 보수적 선택 — 감정 근거 2건만으로는 통과 불가) /
   `ACTIVITY_METRIC`은 몇 개든 합쳐 **1건**.
4. `scopeText`·`homeObservationGuide`가 비어 있지 않고 `tendencyText`가 가능성 어조다.
5. `evidenceRefs`가 실제 존재하는 `evidenceId`를 가리키고 `sourceRef`가 해석 가능하다.

미달이면 **그 카드만 제외**한다. §10대로 빈 배열은 정상이다.

### 4-2. 서버 검증 2단 (델타 ⑤)

| 단계 | 검사 | 실패 처리 |
| --- | --- | --- |
| **1. 구조적 공개 게이트** | §4-1 전부 + §6-1 배제 | **그 카드만 미공개(제외)** + 사유 코드 로그 |
| **2. 표현 안전 필터** | 진단명·확정 표현·고정 특질·점수·확률·원인 단정·비난 | **EXPERT_ONLY 강등** + `expertReviewRequired=true`, 내용 보존 |

- **1단 실패는 강등이 아니다** — 근거 자체가 없으므로 표현을 다듬어도 공개 대상이 아니다.
- 값싼 결정적 검사인 1단을 먼저 돌리고 통과분만 2단에 넣는다.
- 2단 기준은 AI 측 `ai/report_safety.py`(S15P11B209-591·592 확정 기준)와 **일치시킨다.** 갈리면 통과·차단이 엇갈린다.
  차단 예 "자존감이 낮습니다"·"애정결핍"·"공격적인 성향이 있어요" / 허용 예 "~일 수 있어요"·"~한 경향".
- 리포트 전체를 실패시키지 말고 **문제 항목만** 제외·강등한다.

### 4-3. 기존 EXPERT_ONLY 강등 경로를 타지 않는다 (델타 ⑥ — 가장 실수하기 쉬운 지점)

`publicInterpretations`를 기존 `features` 저장·노출 경로에 실으면
`ObservationReportPersistenceService.resolveVisibility()` 때문에 **전부 EXPERT_ONLY가 되어, 구현은 끝났는데
보호자 화면에는 아무것도 나오지 않는다.** 그리고 **기존 테스트는 전부 통과한다**(모두 "노출되지 않는지"만 보므로).

- `publicInterpretations`·`evidenceItems`는 **별도 저장**(`report_public_interpretations` 등)·**별도 노출 판단**을
  쓰고 `resolveVisibility()`·`expertReviewed` 경로를 타지 않는다. 노출 여부는 §4-2의 1단 결과로 정한다.
- 기존 `features`·`attentionPoints`의 EXPERT_ONLY 강등 규칙은 **그대로 둔다**(완화해서 해결하지 않는다).
- 보호자 안전 규칙 쪽 근거·예외 조항은 `docs/api/report-detail-guardian-contract.md` §4-1~§4-4(S15P11B209-885).

`sourceType` → 화면 라벨(FE 매핑):
| sourceType | 표시 라벨 |
|---|---|
| VISION | 그림에서 확인 |
| CHILD_ANSWER | 아이의 답변 |
| SELECTED_EMOTION | 아이가 선택한 감정 |
| STATED_EMOTION | 아이가 말한 감정 |
| ACTIVITY_METRIC | 활동 기록 |
| REPEATED_SUBJECT | 여러 그림에서 반복 |
| LONGITUDINAL | 이전 활동에서도 반복 |

> `evidenceId`·`sourceType` 코드값은 화면에 노출하지 않는다(라벨만).

---

## 5. SubjectReport (`subjectReports[]`) — HTP 집·나무·사람

**순서 보장: HOUSE → TREE → PERSON.** report 상세의 스냅샷을 우선 사용(별도 재조립 금지).

```jsonc
{
  "subjectType": "HOUSE",             // HOUSE|TREE|PERSON
  "imageUrl": "https://.../house.png", // 완성 그림(접근 URL). 없으면 null
  "visionObservations": [ "지붕과 창문이 크게 그려졌어요." ], // 눈으로 확인된 내용
  "qaPairs": [ /* QaPair */ ],         // 이 주제에서 나눈 문답
  "interpretationRefs": [ 0 ]          // 이 주제와 연결된 publicInterpretations 인덱스(또는 category)
}
```

- HTP가 아닌 활동은 `subjectReports`가 비거나 1개(전체 그림)일 수 있다 → FE가 유연 처리.

### 5-1. `interpretationRefs`의 의미 (델타 ⑧-2)

초안의 `[0]`·"또는 category"는 모호했다. 확정한다.

- `interpretationRefs`는 **같은 응답 안의 `publicInterpretations` 배열 인덱스**다(0-based). `category` 값이 아니다.
- **리포트 버전 스냅샷 안에서 `publicInterpretations` 배열 순서를 재정렬하지 않는다.** 순서가 바뀌면 참조가
  조용히 어긋나 다른 카드를 가리킨다. 재생성은 새 `reportVersion`을 만들므로(§1) 버전 간 순서 변화는 무해하다.
- 안정 키(`interpretationId`) 도입은 FE 변경이 필요해 **후속**으로 둔다. 그때까지 인덱스가 규약이다.

---

## 6. QaPair (`qaPairs[]`) — 아이와 나눈 이야기

```jsonc
{
  "question": "이 집에는 누가 살아요?",
  "answer": "우리 가족이요",           // 없으면 null → "답하지 않았어요"
  "state": "ANSWERED",                // ANSWERED | SKIPPED
  "inputType": "VOICE",               // TEXT | VOICE
  "sttNeedsConfirmation": false,      // VOICE + true → "음성 인식 내용을 확인해 주세요"
  "isRepresentative": true            // 대표 문답(기본 최대 3개 우선 노출)
}
```

FE 규칙: 질문·답변 쌍 표시 / `SKIPPED` → "이 질문은 건너뛰었어요" / 대표 최대 3개 +
나머지는 "대화 더 보기".

### 6-1. 미확정 STT·위기 발화 — 표시와 근거를 분리한다 (델타 ③)

"확인해 주세요" 표시는 **그대로 유지한다**(아이 말을 지우지 않는다). 다만 용도별로 다르게 다룬다.

| 용도 | 미확정 STT(`true`) | 위기 사유 메시지 |
| --- | --- | --- |
| `subjectReports[].qaPairs` 표시 | **유지**(§6 그대로) | **제외** |
| `evidenceItems` 근거·독립 근거 계수 | **제외** | **제외** |
| `childExpression` 대표 발화 | **제외** | **제외** |

- 위기 사유 = `SELF_HARM_RISK`·`ABUSE_DISCLOSURE`·`CRISIS_INTENT`. 판정은 AI가 리포트 생성 시 재검사해
  제외하고(S15P11B209-889), BE는 메시지 단위 영속화를 병행하면 사후 추적이 가능하다.
- **전제(중요):** 지금 BE는 `sttNeedsConfirmation`에 리터럴 `false`를 넘긴다
  (`report/service/ReportDetailQueryService.java:226`). **실데이터로 바꾸지 않으면 이 규칙 전체가 조용히
  무효가 된다.** BE 후속 작업 대상이며 보호자 계약 §5-d6에 기록했다.

---

## 7. ParentGuide (`parentGuides[]`) — 보호자 가이드(4종)

```jsonc
{ "guideType": "DAILY_PARENTING", "items": [ "문장", "문장" ] }
```

`guideType` → 섹션 제목(FE):
| guideType | 화면 제목 |
|---|---|
| DRAWING_CONVERSATION | 그림으로 대화해 보세요 |
| DAILY_PARENTING | 일상에서 이렇게 도와주세요 |
| HOME_OBSERVATION | 가정에서 살펴봐 주세요 |
| PROFESSIONAL_SUPPORT | 도움이 필요할 때 |

- 각 guideType은 있을 수도/없을 수도 있음(없으면 해당 섹션 숨김).
- `PROFESSIONAL_SUPPORT`는 상담 필요성을 **단정하지 않는** 중립 안내 문구.

### 7-1. 위기 안내는 가이드와 다른 필드다 (델타 ④)

`PROFESSIONAL_SUPPORT`는 **상시 노출되는 일반 상담 안내**이므로 **고정 템플릿**을 쓴다.
`crisis_guidance`의 문구·연락처를 재사용하지 않고 **신고·긴급 번호를 포함하지 않는다.**

위기 대응 안내는 별도 최상위 필드 `crisisAlert`(optional, 기본 `null`)로 낸다.

| 사유 코드 | `crisisAlert` | 처리 |
| --- | --- | --- |
| `SELF_HARM_RISK` · `CRISIS_INTENT` | **생성 가능** | 보호자 통지가 도움이 되는 유형 — 현행 유지, 템플릿 축약·재작성 금지 |
| `ABUSE_DISCLOSURE` | **생성 금지(항상 null)** | EXPERT_ONLY 저장 + `expertReviewRequired=true` |

`ABUSE_DISCLOSURE`는 **가해자가 보호자일 수 있어** 자동 통지가 아이를 위험하게 한다. 신호를 버리지는 않고
전문가 검토 신호로 보존한다. AI 측 반영·병합 완료(S15P11B209-890).

---

## 8. ActivityFacts (`activityFacts`) — 객관 수치만

```jsonc
{
  "totalDurationSec": 420,     // 총 활동 시간
  "drawingDurationSec": 260,   // 실제 그린 시간
  "pauseCount": 3,             // 멈춤 횟수
  "eraseCount": 5,             // 지우기
  "undoCount": 2,              // 되돌리기
  "questionCount": 6,          // 질문 수
  "answerCount": 5,            // 답변 수
  "skipCount": 1,              // 건너뜀 수
  "detectedElementCount": 12,  // 탐지된 요소
  "pressureAvailable": false,  // 필압 수치 유무 플래그
  "pressureValue": null,       // pressureAvailable=true & 값 있을 때만 표시
  "truncated": false,          // true → "저장된 구간까지만 집계된 값입니다"
  "aggregatedHtp": true        // HTP 합산이면 true → "집·나무·사람 세 활동 합친 기록입니다"
}
```

FE 규칙: `null`이면 항목 숨김 / `0`이면 "0회" 표시 가능 / 수치에 **심리 해석을 붙이지 않는다** /
`pressureAvailable`만 true고 실제 값 없으면 필압 항목 미표시.

### 8-1. 단위 변환 책임은 BE (델타 ⑧-3)

이 계약은 **초**(`totalDurationSec`·`drawingDurationSec`), AI 응답과 기존 BE 필드는 **밀리초**
(`drawingDurationMs`)다. **변환 책임을 BE에 둔다.**

- FE DTO는 두 형태를 모두 읽으므로(`report_dtos.dart:269`·`275`) 기존 `drawingDurationMs`를 유지하면서 초 필드를
  함께 실어도 안전하다 — 하위 호환이 이미 들어가 있다.
- **`null`(집계 못 함)과 `0`(0회·0초)을 구분해 변환한다.** `null`을 0으로 바꾸면 화면이 "0초 그렸다"로 표시된다.
- 반올림 규칙은 내림(`ms / 1000`)으로 두고, 1초 미만 활동은 `0`이 아니라 `null`이 아님을 유지한다(0초로 표시 가능).

---

## 9. ChildExpression / ConversationSummary / Reference (요약·참고)

```jsonc
"childExpression":   { "summary": "...", "keywords": ["가족","기다림"] } | null,
"conversationSummary": { "summary": "..." } | null,
"references": [ { "title": "그림 심리의 이해", "url": "https://..." | null } ]
```

**보완(델타 ⑧-4):** `references[].url`은 **nullable을 유지**한다 — 자체 저작 자료는 URL이 없다.
라이선스가 확인된 자료만 싣는다.

---

## 10. 빈 상태 규칙(중요)

- 아래가 비어도 **정상 리포트**로 처리: `publicInterpretations`, `evidenceItems`,
  일부 `subjectReports.qaPairs`, 일부 `parentGuides` 유형, `activityFacts`.
- 빈 섹션은 **자연스럽게 숨김**(AI가 억지로 채우지 않음).
- **"아직 표시할 관찰 기록이 없어요"**는 다음이 **모두** 비었을 때만:
  `publicInterpretations` + `childExpression` + `activityFacts` + `conversationSummary` + `parentGuides`.

---

## 11. 화면 섹션 순서(FE 렌더 · PDF 동일)

1. 표지 및 비진단 안내 → 2. 한눈에 보는 이번 활동 → 3. 주요 심리 경향
→ 4. 집·나무·사람 그림 → 5. 주제별 관찰 사실과 문답 → 6. 아이의 표현과 대화 요약
→ 7. 객관적인 활동 기록 → 8. 그림으로 대화하기 → 9. 일상에서 활용할 육아 조언
→ 10. 가정에서 살펴볼 점 → 11. 한계와 참고 자료 → 12. PDF 저장 및 공유

**PDF는 화면과 동일한 공개 데이터·섹션 순서**를 사용한다(화면엔 있고 PDF엔 없는 데이터 금지):
HTP 세 그림 / 주요 경향 / 경향별 근거 / 그림 문답 / 일상 육아 조언 / 비진단 고지 / 참고 자료.

---

## 12. BE 체크리스트(요약)

- [ ] `publicInterpretations[]` (category/title/tendencyText/scopeText/homeObservationGuide/evidenceRefs)
- [ ] `evidenceItems[]` (evidenceId/sourceType/text) — 카드가 참조
- [ ] `subjectReports[]` HOUSE→TREE→PERSON 순서 보장, imageUrl·visionObservations·qaPairs
- [ ] `parentGuides[]` 4종 guideType 분리
- [ ] `activityFacts` null/0 구분, truncated·aggregatedHtp·pressureAvailable 플래그
- [ ] `nonDiagnosticNotice` 고정 문구
- [ ] `reportVersion` 재생성 시 증가
- [ ] **EXPERT_ONLY(attentionPoints 등)는 공개 응답에서 제외**
- [ ] 모든 배열 빈 값 허용(오류 아님), tendency/guide 문구는 비진단·중립 어조

### 12-1. 안전 장치 체크리스트 (2026-08-05 델타 추가분)

- [ ] `evidenceItems`에 `sourceRef`/`derivedFrom` — **정확히 하나**, BE 발급 ID만, 조합키 금지
- [ ] `PRIOR_ACTIVITY`가 이전 AI 해석을 참조하지 않음(순환 추론 차단)
- [ ] 구조 게이트 — 독립 근거 2건(**말단 합집합**)·아이 표현 1건·병합 상한·참조 정합
- [ ] 미확정 STT·위기 발화를 **근거·대표 발화에서 제외**(문답 표시는 §6 유지)
- [ ] `sttNeedsConfirmation` 하드코딩 `false` 제거 → 실데이터 연결 (`ReportDetailQueryService:226`)
- [ ] `ABUSE_DISCLOSURE`에 `crisisAlert` 미생성 + EXPERT_ONLY 저장 + `expertReviewRequired=true`
- [ ] `PROFESSIONAL_SUPPORT`에 위기 연락처 미포함
- [ ] 표현 안전 필터 **신규 구현**, 기준을 `ai/report_safety.py`와 일치
- [ ] 구조 게이트 실패 = **미공개** / 표현 필터 실패 = **강등** — 다르게 처리
- [ ] `publicInterpretations`가 `resolveVisibility()`·`expertReviewed` 경로를 **타지 않음**
- [ ] 기존 `features`는 여전히 EXPERT_ONLY로 강등됨(**회귀 검증**)
- [ ] 활동 수치 ms→초 변환에서 `null`/`0` 구분
- [ ] `interpretationRefs`는 같은 응답의 배열 인덱스이며 버전 스냅샷 안에서 순서 재정렬 금지
- [ ] **(긍정 검증·필수)** 조건을 충족한 경향 카드가 상세 API와 **PDF에 실제로 노출됨**

마지막 항목이 없으면 §4-3의 실패(**전부 숨겨진 채 배포**)를 아무도 잡을 수 없다.
