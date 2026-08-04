# [S15P11B209-875] 보호자 관찰 리포트 재구성 — API 계약 (FE→BE 제안)

FE가 새 리포트 화면을 위해 필요한 응답 계약을 설계한 문서다. BE는 이 형태에 맞춰
응답을 구성하면 된다. **비진단 원칙**(경고/진단 아님)을 데이터 구조에서부터 지킨다.

> 상태: 초안(v1). 필드명은 camelCase(JSON). 모든 배열은 비어 있을 수 있고, 비어 있으면
> FE가 해당 섹션을 **숨긴다**(오류 아님). `null`과 `0`은 구분한다.

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
  "subjectReports":        [ /* SubjectReport */ ],   // 4. HTP 그림
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
  "text": "집에는 우리 가족이 산다고 답했어요."
}
```

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

---

## 9. ChildExpression / ConversationSummary / Reference (요약·참고)

```jsonc
"childExpression":   { "summary": "...", "keywords": ["가족","기다림"] } | null,
"conversationSummary": { "summary": "..." } | null,
"references": [ { "title": "그림 심리의 이해", "url": "https://..." | null } ]
```

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
