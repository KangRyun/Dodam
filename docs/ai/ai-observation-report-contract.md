# 관찰 리포트 생성 계약 (as-built) — POST /internal/v1/observations

- 상태: **as-built 정본** (S15P11B209-740에서 신설). 이 경로의 요청/응답은 이 문서가 기준이다.
- 작성: 2026-07-30
- 소유: 계약 필드는 BE(`report/dto/ObservationGenerationRequest·Result`)와 AI(`ai/internal_contracts.py`)가 1:1 — **변경은 양쪽 동시 반영**.
- 관련 문서: BE Mock 생성·저장 파이프라인은 [mock-observation-report-contract.md](../api/mock-observation-report-contract.md)(152), 리소스 어휘는 `API_명세서_최종.md` §19.

## 1. 개요

| 항목 | 값 |
|---|---|
| 경로 | `POST /internal/v1/observations` |
| 인증 | `X-Internal-Token` (다른 BE→AI 내부 계약과 동일) |
| 소비자 | BE `RestClientAiObservationClient` (`app.ai.observation.mode=http`) |
| 성공 | 200 + `ObservationGenerationResult` |
| 오류 | 401 `INVALID_INTERNAL_TOKEN` · 422 `INVALID_REQUEST`(analysisType≠FINAL) · 502 `AI_UPSTREAM_ERROR` |

## 2. 요청 — `ObservationGenerationRequest`

### 2.1 기존 필드 (변경 없음)

`requestId` · `analysisId` · `drawingSessionId` · `analysisType`("FINAL") · `questionDifficulty?` ·
`questionCount` · `answeredCount` · `skippedCount` · `unrecognizedSpeechCount` ·
`selectedEmotions[]` · `expressedEmotionText?` · `representativeUtterance?`

### 2.2 `subjectSummaries[]` — 주제별 그림 서술·문답 (S15P11B209-740 신설)

목적 흐름 "각 그림을 마칠 때마다 문답 → 문답과 그림을 근거로 리포트"를 계약 수준에서 잇는다.
기존 요청은 집계 수치·대표 발화 1건뿐이라 리포트 LLM이 그림·문답 내용을 보지 못했다.

```jsonc
"subjectSummaries": [
  {
    "drawingSubject": "HOUSE",            // HOUSE | TREE | PERSON | null(그림일기)
    "drawingDescription": "가운데에 집이 크게…",  // VLM 관찰 서술 (analysis_observation_results.overall_summary)
    "detectedObjectCodes": ["HOUSE", "HOUSE_DOOR"],
    "qaPairs": [
      { "question": "이 집에는 누가 살아?", "answerText": "엄마랑 나!", "answerType": "VOICE" }
    ]
  }
]
```

| 필드 | 필수 | 설명 |
|---|---|---|
| `drawingSubject` | X | HTP 주제. 그림일기는 `null` (HTP=최대 3건, 그림일기=1건) |
| `drawingDescription` | X | 해당 그림의 VLM 관찰 서술. 기본 `""` |
| `detectedObjectCodes[]` | X | 탐지 객체 내부 코드. 프롬프트 참고용 — 리포트 문장에 코드 원문 노출 금지 |
| `qaPairs[].question` | O | AI가 물은 질문 텍스트 |
| `qaPairs[].answerText` | X | 아이 답변(STT 텍스트 또는 선택 칩 라벨). **repr 은닉 — 로그 금지** |
| `qaPairs[].answerType` | X | BE 어휘(예: VOICE·OPTION·SKIPPED). AI는 `SKIPPED`만 프롬프트에 "(건너뛴 질문)"으로 구분 표기 — 아이가 스스로 넘긴 것은 무응답과 다른 관찰 사실. 그 외 값은 해석하지 않음 |

### 2.3 `behaviorMetrics` — 그리기 형식 지표 (S15P11B209-836 신설)

`[형식적 분석]` 블록의 입력이다. 확장 전에는 전달 수단이 없어 이 블록이 **운영 경로에서 한 번도
실리지 않았다** — 프롬프트(`report_common.txt` 첫 9줄)는 블록을 전제로 쓰여 있는데 데이터가
도착하지 않던 상태였다. BE `StrokeBehaviorSummary` 와 필드 1:1이며, 같은 값이 이미
`POST /analyze/drawing` 의 `BehaviorInput.summary` 로 나가고 있다.

```jsonc
"behaviorMetrics": {              // optional, 기본 null
  "drawingDurationMs": 720000,
  "activeDrawingMs":   480000,
  "strokeCount":       42,        // 975 신설
  "pauseCount":        4,
  "undoCount":         2,
  "eraseCount":        3,
  "toolChangeCount":   1,
  "colorChangeCount":  5,
  "colorsUsedCount":   4,         // 975 신설
  "pressureAvailable": true,
  "averagePressure":   null,      // 이번 단계에서 항상 null
  "truncated":         false,
  "subjectDurations": [           // 975 신설. optional, 기본 빈 목록
    { "drawingSubject": "HOUSE",  "drawingDurationMs": 480000, "activeDrawingMs": 160000 },
    { "drawingSubject": "TREE",   "drawingDurationMs": 240000, "activeDrawingMs":  90000 },
    { "drawingSubject": "PERSON", "drawingDurationMs": 180000, "activeDrawingMs":  50000 }
  ]
}
```

| 필드 | 필수 | 설명 |
|---|---|---|
| `drawingDurationMs` · `activeDrawingMs` | X | 없으면 `null`. **0으로 채우지 않는다** |
| `strokeCount` | X | 그은 획의 수(S15P11B209-975). ⚠️ **지우개 획을 포함하므로 `eraseCount` 와 세는 대상이 겹친다** — 두 값으로 '지우기 비율' 같은 파생 수치를 만들면 안 된다. 계약이 파생 필드를 싣지 않고 실측값 둘만 보내는 이유가 이것이고, 프롬프트도 같은 규칙을 건다. 블록 텍스트가 "(지우개로 그은 획 포함)"으로 겹침을 스스로 밝힌다 |
| `pauseCount` | X | 배치 경계 기반 **추정값** — 리포트는 "약 N번"으로 완화 표기 |
| `undoCount` · `eraseCount` | X | |
| `toolChangeCount` · `colorChangeCount` | X | **2026-08-05부터 프롬프트 블록에 실린다**("도구 바꾼 횟수 N회"·"색 바꾼 횟수 N회"). 관찰 사실로만 적히고, 해석은 `[형식적 분석]` 전체를 신호 하나로 세는 규칙을 따른다 |
| `colorsUsedCount` | X | 실제로 획을 그린 색의 **가짓수**(S15P11B209-975). 색을 바꾼 *횟수*와 다른 값이다. 고르기만 하고 한 획도 긋지 않은 색은 세지 않는다. ⚠️ HTP 합산은 세 단계의 색을 **합집합**으로 센다 — 세션별 가짓수를 더하면 세 장에 모두 쓴 색이 3가지로 계수된다. 색 코드 자체는 관찰 재료가 아니라 보내지 않는다 |
| `pressureAvailable` | O | **측정 가능 여부일 뿐** 필압의 강약도 감정 근거도 아니다 |
| `averagePressure` | X | **구조적으로 항상 `null`** — BE record `StrokeBehaviorSummary` 에 이 필드 자체가 없다. 필압 줄은 운영에서 한 번도 나온 적이 없고 나올 수도 없다. AI 쪽 분기는 계약 확장 대비로만 남아 있다. 값 도입은 BE 계약 확장이 선행 |
| `truncated` | O | `true`면 "저장된 캔버스 입력 구간 기준" — 활동 전체를 완전 집계한 것처럼 표현 금지 |
| `subjectDurations[]` | X | HTP 주제별 그리기 시간(S15P11B209-975). 그림일기·단독 세션은 **빈 목록**. 아래 전부-아니면-전무 규칙 참조 |
| `subjectDurations[].drawingSubject` | X | `HOUSE|TREE|PERSON` |
| `subjectDurations[].drawingDurationMs` · `activeDrawingMs` | X | 그 주제 **한 세션**의 값이며 합계가 아니다. 뜻과 한계는 위 동명 필드와 같다 |

**`null` 과 `0` 은 다른 뜻이다.** `null`은 '집계하지 못함'이라 프롬프트 블록에서 항목을 빼고,
`0`은 '0회'라는 관찰 사실이라 그대로 적는다. 멈춤 없이 몰입해 그린 활동(`pauseCount=0`)과
집계 실패(`null`)가 같은 문장이 되면 안 된다.

**HTP는 세 단계 합산값이다.** HOUSE·TREE·PERSON 이 모두 CANVAS 이고 집계 가능할 때만 합산해
보내고, UPLOAD 가 섞이거나 한 단계라도 집계 불가면 **전체를 `null`** 로 보낸다 — 부분 집계를
전체 활동으로 오인시키지 않기 위해서다.

#### `subjectDurations` — 비교 관찰의 재료 (S15P11B209-975)

836이 범위 밖으로 미뤄 뒀던 주제별 지표다. 합계만으로는 "어느 그림에 더 오래 머물렀는가"를
말할 수 없어, 세션별 값에 주제 이름을 붙여 보낸다.

🔴 **전부 아니면 전무다.** 이 목록의 쓸모는 **비교**이고, 비교는 대상이 전부 있을 때만 참이다.
한 주제가 사진 업로드라 빠지면 남은 둘로 "집을 그릴 때 가장 오래 머물렀어요"가 만들어지는데,
그것은 관찰이 아니라 없는 사실이다. 그래서 `behaviorMetrics` **전체가 `null` 이 아닐 때만**
채워진다 — 위의 전부-아니면-전무 규칙이 이 조건을 이미 보장하므로 부분 목록은 구조적으로
만들어질 수 없다(BE `StrokeBehaviorAggregate` 가 합계와 내역을 한 값에 담아 타입으로 막는다).

AI 쪽도 같은 규칙을 반대편에서 한 번 더 건다: 한 항목이라도 라벨을 모르거나 시간이 없으면
**남은 것만 적지 않고 줄 전체를 뺀다**(`report_client._format_subject_durations`).
시간은 `drawingDurationMs` 만 쓰고 없을 때 `activeDrawingMs` 로 대체하지 않는다 — 한 줄 안에서
서로 다른 측정이 섞이면 그 비교는 이미 거짓이다.

⚠️ **BE 구현 주의 — 주제 매핑의 출처.** 주제 라벨은 `subjectContexts`(서술·탐지 코드·문답이
모두 빈 주제를 걸러낸 목록)가 아니라 **필터링 전** 세션 목록에서 와야 한다. 걸러진 목록을 쓰면
그리기만 하고 대화가 없던 그림이 통째로 빠진 채 순위가 정해진다.

가드레일: 주제별 시간은 "어느 그림에 시간을 더 썼다"는 **활동 기록**으로만 쓴다. 오래 머문 그림을
'더 중요한/애착이 큰 그림'으로 읽는 것과, 오래·짧게 그린 **이유**를 심리 상태로 채우는 것을
프롬프트가 금지한다(`report_common` 2.3.0). 획 수·색 가짓수도 같다 — 많고 적음을 에너지·충동성·
집중력·성격과 잇지 않는다.

### 2.4 `subjectSummaries[].detectedObjects` — 탐지 기하 (S15P11B209-836 신설)

기존 `detectedObjectCodes`(라벨 문자열)와 **병렬로** 실린다. 기존 필드는 유지된다.

```jsonc
"detectedObjects": [              // optional, 기본 빈 목록
  { "objectCode": "HOUSE",      "x": 0.21, "y": 0.18, "width": 0.55, "height": 0.60,
    "areaRatio": 0.33,  "confidence": 0.94 },
  { "objectCode": "HOUSE_DOOR", "x": 0.42, "y": 0.55, "width": 0.09, "height": 0.16,
    "areaRatio": 0.014, "confidence": 0.81 }
]
```

| 필드 | 필수 | 설명 |
|---|---|---|
| `objectCode` | O | `analysis_detected_objects.object_code`. 리포트 문장에 원문 노출 금지(기존 규칙) |
| `x` `y` `width` `height` | **X** | **NORMALIZED(0~1) 만** 전달. 없으면 `null` — 아래 결함 이력 참조 |
| `areaRatio` | X | 없으면 `null`. **AI에서 `width*height` 로 보정하지 않는다** |
| `confidence` | X | 낮은 신뢰도 탐지를 확정 사실처럼 표현하지 않기 위한 값 |
| `evidenceSourceId` | X | DB 행 ID. **숫자(Long)·문자열 모두 받는다** — AI가 문자열로 정규화해 보관 |

**좌표계는 `NORMALIZED` 만.** AI는 캔버스 원본 크기를 모르므로 픽셀 좌표로는 용지 점유율을
계산할 수 없다. `coordinateSpace == PIXEL` 인 결과뿐이면 그 주제는 **빈 목록**으로 보낸다
(부분 전달 금지 — 좌표계가 섞이면 판단 불가).

#### ⚠️ 결함 이력 — 기하 필수 지정으로 인한 운영 전량 실패 (2026-08-05)

836이 `x·y·width·height` 를 **기본값 없는 필수 필드**로 뒀는데, 906 배포본이 실어 보내는 항목은
`{evidenceSourceId, objectCode}` 뿐이었다. 결과: `POST /internal/v1/observations` 가 운영에서
**2건 중 2건 422**(성공 0건). 탐지 객체가 하나라도 있으면 전량 실패라 리포트 파이프라인이 멈췄다.

오류 5건 — `x`·`y`·`width`·`height` 각 `Field required` +
`evidenceSourceId` `Input should be a valid string`(BE는 Long 숫자로 보냄).

**근인은 원칙 위반이다.** 이 계약은 곳곳에서 롤아웃 안전 패턴을 쓴다(§2.5 — "구 BE가 안 보내면
기존 경로가 그대로 동작한다"). 836이 자기 모델에서만 그 원칙을 어겨, BE·AI 배포 순서가 어긋나는
순간 파이프라인이 통째로 멈추게 만들었다.

수정(AI 쪽 — 배포 순서 무관하게):

1. 기하 4필드 전부 optional(`null` 허용).
2. 근거 식별자는 **숫자도 받아 문자열로 정규화**한다. `detectedObjects[].evidenceSourceId` ·
   `subjectSummaries[].observationEvidenceSourceId` · `selectedEmotionRefs[].evidenceSourceId`
   모두 같은 처리 — 전부 DB 행 ID라 같은 노출을 갖는다.
   ⚠️ 정규화가 검증 통과보다 중요하다. `_allowed_evidence_refs` 가 `(kind, id)` 튜플로 대조하는데
   한쪽이 int 로 남으면 형식은 통과해도 대조에서 어긋나 **그 근거가 조용히 사라진다**(422보다 나쁘다).
3. **기하가 없는 항목은 `[OO 크기·위치]` 블록에서 건너뛴다.** 좌표 없이 코드 이름만으로 줄을 세우면
   '관찰된 수치'가 있는 것처럼 읽힌다. 네 값 중 하나라도 없으면 위치를 계산하지 않는다
   (빠진 값을 0으로 치지 않는다 — `areaRatio` 를 `width*height` 로 보정하지 말라는 것과 같은 원칙).
   그 항목은 '탐지된 요소 코드' 줄로만 남고, 근거 식별자도 그대로 살아 있다.
4. 한 주제의 탐지가 **전부** 기하 없음이면 `[OO 크기·위치]` 블록 자체를 싣지 않는다
   (`_format_behavior` 가 적을 지표가 없을 때 빈 문자열을 돌려주는 것과 같은 원칙 — 빈 블록을
   실으면 모델이 채우려 든다).

가드레일: 크기·위치는 **관찰 사실로만** 쓴다. 단일 기하 신호 단정, 아동의 평소 성격·발달로의
일반화, 진단명·점수 생성, 낮은 신뢰도 탐지의 확정 표현은 프롬프트가 금지한다.

### 2.5 롤아웃 호환 (양방향)

- **전 필드 optional + 기본 빈 목록/`null`.** 구 BE가 안 보내면 기존(집계+대표 발화) 경로로 동일 동작 — `QuestionRequest.activityType`(713)과 같은 패턴. 836의 두 필드도 같다: `behaviorMetrics`가 없으면 `[형식적 분석]` 블록이 실리지 않고, `detectedObjects`가 비면 기존 코드 목록 경로가 그대로 쓰인다. 배포 순서 제약 없음.
- 975의 세 필드도 같다: `strokeCount`·`colorsUsedCount`는 기본 `null`, `subjectDurations`는 기본
  빈 목록이라, 구 BE가 안 보내면 해당 줄만 블록에서 빠지고 나머지는 그대로 실린다. 배포 순서 제약 없음.
- ⚠️ **이 원칙은 목록 단위가 아니라 필드 단위로 지켜야 한다.** `detectedObjects` 를 optional 로 두고도 그 **안의** 기하를 필수로 두면 원칙이 깨진다 — 목록이 비었을 때만 안전하고, 항목이 하나라도 있으면 전량 422다. 실제로 그렇게 났다(§2.4 결함 이력). 부분 전달을 받아 **부분만 쓰는** 것이 이 계약의 기본값이다.
- `subjectSummaries`가 비어 있지 않으면 프롬프트의 `[그림 관찰 서술]` 단일 블록 **대신** 주제별 블록(`[집 그림 관찰]`·`[집 그림 문답]` …)이 실린다. 레거시 `drawing_description` 인자(draft 경로 전용)와 동시 제공 시 주제별 블록이 우선.

## 3. 응답 — RAG 확장 (S15P11B209-614·615, 전부 optional — 구 BE는 무시)

`ObservationGenerationResult` 기존 필드 그대로 + 아래 3필드:

| 필드 | 값 | 설명 |
|---|---|---|
| `ragReferences[]` | `{sourceId, title}` | 리포트가 근거로 쓴 전문 자료 출처(자료 단위 중복 제거). 출처 표시는 라이선스 의무(KOGL-1) |
| `knowledgeBaseVersion` | `kb-<YYYY.MM>-<seq>` \| null | **근거를 실제로 썼을 때만** 싣는다 — 근거 없는 리포트에 버전이 붙으면 "이 지식에 기반했다"는 거짓 신호 |
| `ragSkippedReason` | 아래 코드 \| null | 근거를 싣지 못한 사유. 근거가 실렸으면 null |

`ragSkippedReason` 코드 (615 — 어떤 사유든 리포트 생성은 계속된다, 기능 저하이지 차단이 아님):

| 코드 | 의미 |
|---|---|
| `RAG_NO_QUERY` | 관찰 재료(그림 서술·탐지 객체)가 없어 검색을 시도하지 않음 |
| `RAG_NO_INDEX` | 인덱스 미배포(운영상 정상일 수 있는 상태) |
| `RAG_UNAVAILABLE` | 임베딩 호출 실패 등 검색 장애 |
| `RAG_LOW_SCORE` | 검색은 됐지만 전부 점수 임계값 미달 — 억지 근거를 싣지 않음 |
| `RAG_NOT_APPLICABLE` | 그림일기 리포트라 검색을 시도하지 않음 — 장애가 아니라 정책(아래) |

**RAG 적용 범위: HTP 리포트만.** 그림일기 프롬프트는 `[전문 자료 근거]`를 근거 화이트리스트에 두지 않으므로 검색해도 쓰이지 않는다. 코퍼스 자체는 활동유형 중립이지만(`docs/ai/rag-corpus-policy.md` §1-2 — HTP를 점수화·해석하지 않는다), 전문 자료 어휘가 필요한 쪽은 '검사처럼 읽히기 쉬운' HTP 리포트다. 판별은 `subjectSummaries[].drawingSubject` 유무 — 계약에 `activityType` 필드가 없어 추론한다(HTP는 항상 채워지고, 그림일기는 `null`, 구 BE는 빈 목록).

운영 관측: 검색 결과 비율은 Prometheus `dodam_rag_search_total{outcome=used|no_query|no_index|unavailable|low_score|not_applicable}` 카운터로 본다.

## 3-1. 응답 — 검토 상태·노출 범위 재정의 (2026-08-05, **BE 반영 필요**)

> ⚠️ **계약 초안이다.** AI 쪽은 아래대로 내보내지만, 실효는 BE 반영에 달려 있다. BE 미반영 상태에서도
> **동작은 지금과 같다**(BE가 `status`를 무시하고 `AI_DRAFT`로 저장 → 모든 관찰 카드 `EXPERT_ONLY`) —
> 배포 순서 제약은 없다.

**배경(4계층 실측).** "전문가가 리포트를 검토한다"는 독자는 존재한 적이 없다.

- `ObservationReviewStatus` enum 값이 `AI_DRAFT` 하나뿐 · 다른 상태로 가는 전이 코드 0건
- `AnalysisObservationResult` 가 생성 시 `reviewStatus = AI_DRAFT` 로 **하드코딩** — AI가 보낸 `status`를 안 읽는다
- 그래서 `ObservationReportPersistenceService` 의 `expertReviewed` 가 항상 `false` → `resolveVisibility` 가 항상 `EXPERT_ONLY`
- `report/` 패키지에 EXPERT 읽기 경로 0건 · 운영 `report_observed_features` 97건 **전량 `EXPERT_ONLY`**

결과적으로 프롬프트가 "전문가 검토용이니 공들여 쓰라"고 지시하던 7개 필드가 매번 통째로 버려지고 있었다.
→ 사람 전문가 대신 **AI 자체검토(2-pass)** 를 관문으로 두고, 통과분을 보호자에게 연다.

### 필드 의미 (어휘 유지 · 뜻만 재정의 — DB 마이그레이션 회피)

| 필드 | 값 | 새 의미 |
|---|---|---|
| `observationDraft.status` | `AI_DRAFT` | 자체검토를 통과하지 못했거나 검토하지 못함. **보호자 경로를 열지 않는다** |
| | `AI_REVIEWED` | 자체검토 통과. 관찰 카드가 `visibilityScope` 대로 노출된다 |
| `features[].visibilityScope` | `REVIEWED_GUARDIAN` | 자체검토 통과 시 **보호자에게 실제로 노출** |
| | `EXPERT_ONLY` | 보호자에게 바로 열지 않음 — **사람 상담 권유·안전 경로 전용** |
| `observationDraft.attentionPoints` | 문자열 | **보호자가 다음에 더 지켜볼 점**(구: 전문가가 추가 확인할 것). 보호자가 그대로 읽는다 |
| `observationDraft.expertReviewRequired` | bool | **사람 상담을 권할 신호**(아이 이야기). 리포트 품질 실패는 여기 오지 않는다 — 그건 `status`로 간다 |

### BE가 맞춰야 하는 것

1. `ObservationReviewStatus` enum에 `AI_REVIEWED` 추가.
2. `AnalysisObservationResult` 생성 시 하드코딩(`AI_DRAFT`) 대신 **AI가 보낸 `status`를 반영**.
   모르는 값이 오면 보수적으로 `AI_DRAFT`.
3. `resolveVisibility`의 `expertReviewed = reviewStatus != AI_DRAFT` 는 **그대로 두면 맞는다**(변경 불필요).
4. 보호자 조회(`ReportDetailQueryService`)가 `REVIEWED_GUARDIAN` 관찰 특징을 읽도록 확장 — 이게 없으면
   `AI_REVIEWED`가 저장돼도 화면에는 아무것도 안 열린다.
5. `Report.expertReviewRecommended` 는 뜻이 '사람 상담 권유'로 확정됐다. 현재 저장만 되고 읽는 곳이 없다 —
   화면에 노출한다면 '검토 대기'가 아니라 '상담 권유' 문구여야 한다.

### AI 쪽 판정 규칙 (as-built)

1. **1층 규칙 필터**(`report_safety`, 정규식) — 진단명·단정 종결·고정 특질 규정. 개별 feature는 `EXPERT_ONLY`로
   강등하고, 경향 카드는 제외한다(카드에는 `EXPERT_ONLY` 자리가 없다). 하나라도 걸리면 통과시키지 않는다.
2. **2층 자체검토**(`report_review.txt`, LLM, temperature=0) — 규칙으로 못 잡는 층:
   `DIAGNOSTIC` · `STIGMA` · `NO_EVIDENCE` · `OVERREACH` · `MIXED_EVIDENCE`.
   - 관찰 카드 지적 → 그 카드만 `EXPERT_ONLY` 강등 (리포트는 통과)
   - 경향 카드 지적 → 그 카드만 제외 + 고아 근거 정리 (리포트는 통과)
   - 서술 필드·활동 기록·조언 지적 → **담을 자리가 없어 리포트 전체를 `AI_DRAFT`** 로 남긴다
   - 모르는 `target`·`issue` 는 버린다(지어낸 값으로 리포트를 떨어뜨리지 못하게)
3. **검토 호출 실패는 차단이 아니라 기능 저하** — 리포트는 그대로 반환하되 `status`는 `AI_DRAFT`.
4. 위기 대응은 **AI가 대신하지 않는다.** `crisis_detection`·`crisis_guidance`·`DISCLAIMER`는 변경 없음.

운영 관측: `dodam_report_self_review_total{outcome=passed|contained|failed|unavailable}`.
재현성: 자체검토 프롬프트(`report_review`)가 `modelVersion`의 프롬프트 조합 다이제스트에 포함된다 —
검토 기준이 바뀌면 태그가 움직인다.

### ⚠️ 지연 예산 (BE와 함께 봐야 하는 값)

리포트 한 건이 이제 GMS를 **두 번** 부른다(생성 + 검토). BE `AI_OBSERVATION_READ_TIMEOUT` 은 **30초**이고
AI 공용 GMS timeout 은 60초라(`gms.py`), 두면 AI가 아직 검토 중일 때 BE가 먼저 포기해 **생성까지 버려진다.**

- AI 쪽 방어: 검토 호출에만 별도 timeout `REPORT_REVIEW_TIMEOUT_SEC`(기본 **10초**)을 건다.
  넘기면 '검토 못 함'으로 떨어뜨리고 리포트는 그대로 내보낸다(`status=AI_DRAFT`) — 차단이 아니라 기능 저하.
- **운영 투입 후 실측 필요:** 생성 p95가 20초를 넘으면 10초를 더해도 30초를 넘긴다.
  그때는 `AI_OBSERVATION_READ_TIMEOUT` 을 올리거나 `REPORT_REVIEW_TIMEOUT_SEC` 을 줄인다.
  ⚠️ 이 값은 실측 전이라 **추정치다.** 배포 후 `dodam_report_self_review_total{outcome=unavailable}`
  비율이 높으면 timeout이 짧은 것이고, 그러면 리포트가 계속 `AI_DRAFT`로 남아 아무것도 안 열린다.

## 3-2. 응답 — 확신도 등급 (S15P11B209-982, 2026-08-06 · optional)

`publicInterpretations[]` 에 필드 하나가 늘었다. 정본 정의·산출 규칙·금지 축은
`docs/S15P11B209-875-report-api-contract.md` **§3-1**이며, 여기서는 AI 쪽 as-built 동작만 적는다.

| 필드 | 값 | 설명 |
|---|---|---|
| `publicInterpretations[].confidence` | `STRONG` \| `MODERATE` \| `WEAK` \| `null` | 해석이 어느 **종류의 근거** 위에 서 있는지. 보호자에게 그대로 노출한다 |

**전 필드 optional + 기본 `null`.** 구 BE는 unknown 필드를 무시하므로 배포 순서 제약이 없다(§2.5).
BE는 이 값을 **필수로 만들면 안 된다** — 값이 없거나 모르는 문자열이면 등급 없음으로 두고 카드는 살린다.

### 🔴 등급은 코드가 정한다 — 모델에게 판정권을 주지 않았다

모델이 스스로 등급을 매기면 근거가 약한 해석도 `STRONG`이라 주장해 등급 체계가 장식이 된다.
그래서 **모델은 `evidenceRefs`(무엇을 근거로 삼았는지)까지만 대고, 등급은 코드가 근거 종류로 계산한다.**

as-built 동작(3중):

1. **프롬프트가 이 필드를 요구하지 않는다.** 어휘 자체를 주지 않는 것이 1차 방어다
   (`ai/prompts/report_common.txt` — "확신도는 네가 정하지 않는다"를 명시).
2. **조립이 모델 값을 읽지 않는다.** `report_client._public_interpretation()` 이 `confidence` 키를
   무시하고 경고 로그만 남긴다(프롬프트가 밀린 신호이므로 관측 대상). ⚠️ 값은 로그에 적지 않는다.
3. **게이트가 계산 결과로 덮어쓴다.** `interpretation_gate.apply()` 가 통과 카드에만 등급을 찍는다.
   등급이 붙는 **유일한 출구**라서 "등급 없는 공개 카드"가 원리적으로 생기지 않는다.
   ⚠️ 카드 객체를 사본으로 바꾸지 않고 **제자리에서** 찍는다 — 호출부가 카드 배열의 앞뒤를
   동일성(`is`)으로 맞춰 `subjectReports[].interpretationRefs` 를 재매핑하기 때문이다(875 §5-1).
   사본을 돌려주면 그 참조가 값은 같은 채로 전부 사라진다.

산출은 근거의 **통로 집합**만 보고 **개수를 보지 않는다** — 약한 근거를 여러 개 모아 등급을
올리는 길을 원천 차단한다(지표 합산이 HTP 해석이 실제로 무너진 경로다).

### 안전장치 3층의 역할 (2026-08-06 전환)

리포트가 해석을 담게 되면서 막는 대상이 '해석했다'에서 **'근거에 비해 세게 말했다'** 로 옮겨갔다.
진단명·의료적 단정·낙인 차단은 **그대로 유지**된다 — 해석을 하는 것과 진단이라 말하는 것은 다르다.

| 층 | 무엇을 보나 | 확신도 관련 역할 |
|---|---|---|
| **구조 게이트** (`interpretation_gate`) | 근거 참조의 구조 | 근거 미달 카드 제외 + **등급 산출** |
| **1층 규칙 필터** (`report_safety`, 정규식) | 고정 어휘 | 진단명·낙인(유지) + **점수화·등급·확률**·**필압**·확정 어휘 차단. 등급별 2계단(확정 어휘=전 등급, 일반화 어휘=`WEAK`) |
| **2층 자체검토** (`report_review.txt`, LLM) | 문장의 뜻 | `OVERCLAIM` 신설 — 등급 대비 과장. `STRONG`↔`MODERATE` 구분처럼 고정 어휘로 못 잡는 계단을 맡는다 |

⚠️ 1층이 등급을 두 계단만 나누는 것은 의도다. 정규식이 잘하는 일(고정 어휘)만 시키고,
의미 판단은 2층에 남긴다. 층마다 잘하는 일이 달라 분담을 흐리면 구멍이 생긴다.

## 4. 가드레일 (9절)

- `qaPairs.answerText`는 아이 발화 — `repr=False`, 로그·예외 메시지에 원문 금지 (기존 `representativeUtterance` 정책과 동일).
- 주제별 문답은 '관찰된 사실'로만 프롬프트에 실린다. **주제 간 상대 차이는 2026-08-06부터 해석 축으로
  허용된다**(같은 아이 안의 비교라 개인차·기기차가 상쇄) — 단, 차이 하나만으로 단정하지 않고 아이 발화와
  같은 방향일 때 이어 쓴다(875 §3-1). 구 규칙(교차 비교 전면 금지)은 폐기됐다.
- 진단 표현 강등(`_feature`)·disclaimer 상수 보장은 기존 그대로 적용 — **해석을 담게 된 뒤에도 불변이다.**
  해석을 제공하는 것과 진단이라 말하는 것은 다르고, 한계 고지 유지는 명시적 결정이다(CLAUDE.md 9절).
- 행동 데이터(`behaviorMetrics`)는 **관찰 프레임만** 허용된다 (S15P11B209-975). "집을 그릴 때 가장
  오래 머물렀어요"·"여러 색을 바꿔가며 그렸어요"는 관찰이지만, 지우기·획·시간을 불안·우울·충동성 같은
  심리 상태의 신호로 잇는 것은 여전히 금지다. ⚠️ 2026-08-06 방침 전환은 **해석을 허용했을 뿐 이 축을
  열지 않았다** — 지표–정서 직결은 문헌이 반증한 구간이라 '쓰지 않는 축'에 그대로 남는다(875 §3-1).
  규칙은 `ai/prompts/report_common.txt`(버전 추적 대상)에 카테고리 서술로 적는다 — 코드 문자열에
  적으면 promptVersion 밖이라 "크게 고쳤는데 버전 그대로"가 재발하고(323), 금지 예시문을 적으면
  앵커가 되어 모델이 복사한다(808).
- 확신도 등급은 **보호자에게 그대로 노출한다**(875 §3-1 규칙 3). 숨기면 약한 추측과 강한 근거가 같은
  무게로 읽힌다 — 등급을 감추는 것이 이 구조에서 가장 쉬운 후퇴 경로라 계약에 못 박는다.
- 요청에 아동 실명·생년월일 등 식별 정보는 여전히 없다 — 추가 금지.

## 5. 절차 기록

- 명세 §24.4 절차 준수: 이 문서(계약) 선반영 → AI(`internal_contracts.py`·`report_client.py`) → BE(741 실빌더) 순.
- `API_명세서_최종.md` §19에는 as-built 반영 이슈로 연결한다(740 코멘트).
- **S15P11B209-982(2026-08-06)** — 확신도 등급 신설(§3-2). AI(계약·게이트·프롬프트·규칙 필터) +
  BE(DTO·엔티티·마이그레이션·상세 응답) 동시 반영. FE 표기 화면은 범위 밖(별건).
  프롬프트 semver: `report_common` 2.3.0→**3.0.0** · `report_htp` 1.7.0→**2.0.0** ·
  `report_review` 1.1.0→**2.0.0**(전부 major — 지시의 뜻이 반대로 뒤집혔다).
  `report_diary` 는 내용 변경이 없어 유지하되, `report_common` 을 함께 쓰므로 조합 다이제스트는 움직인다.
