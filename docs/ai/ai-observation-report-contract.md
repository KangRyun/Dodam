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

### 2.3 롤아웃 호환 (양방향)

- **전 필드 optional + 기본 빈 목록.** 구 BE가 안 보내면 기존(집계+대표 발화) 경로로 동일 동작 — `QuestionRequest.activityType`(713)과 같은 패턴.
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

운영 관측: 검색 결과 비율은 Prometheus `dodam_rag_search_total{outcome=used|no_query|no_index|unavailable|low_score}` 카운터로 본다.

## 4. 가드레일 (9절)

- `qaPairs.answerText`는 아이 발화 — `repr=False`, 로그·예외 메시지에 원문 금지 (기존 `representativeUtterance` 정책과 동일).
- 주제별 문답은 '관찰된 사실'로만 프롬프트에 실리고, 그림 간 차이의 심리 단정(교차 비교 해석)은 프롬프트가 금지한다.
- 진단 표현 강등(`_feature`)·disclaimer 상수 보장은 기존 그대로 적용 — 입력이 늘어도 출력 안전 규칙 불변.
- 요청에 아동 실명·생년월일 등 식별 정보는 여전히 없다 — 추가 금지.

## 5. 절차 기록

- 명세 §24.4 절차 준수: 이 문서(계약) 선반영 → AI(`internal_contracts.py`·`report_client.py`) → BE(741 실빌더) 순.
- `API_명세서_최종.md` §19에는 as-built 반영 이슈로 연결한다(740 코멘트).
