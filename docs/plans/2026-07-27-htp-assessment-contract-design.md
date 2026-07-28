# HTP 검사(`HTP`) 계약 신규안 (초안)

**작성일:** 2026-07-27
**AI 한줄 요약:** HTP 검사 4장 묶음을 관리하는 신규 도메인 `htp-assessment`의 엔드포인트·DTO·Enum·오류 코드·Migration과 다중 그림 종합 분석용 내부 AI 계약을 작성했고, 기존 계약을 고치지 않는 순수 additive 설계임을 확인했다.
**상태:** **초안 — 정본 아님, 미구현.** 계약의 정본은 `공통작업/docs/api/API_명세서_최종.md`다. 정본과 어긋나면 정본이 우선한다.
**기반 기획:** `2026-07-27-htp-assessment-process-design.md`
**정본 기준선:** `API_명세서_최종.md` (origin/develop `949b3b0` 시점)

---

## 0. 이 계약이 기존 정본을 고치지 않는다는 근거

기획 확정본(그림 1장마다 대화)에서는 **기존 조항을 바꿀 일이 없다.** 확인한 것.

| 항목 | 정본 현황 | 판정 |
| --- | --- | --- |
| `DrawingCategory.ASSESSMENT` | §4 Enum 사전에 이미 존재 (`API_명세서_최종.md:273`) | 그대로 사용 |
| `GET /drawing-types?category=ASSESSMENT` | 이미 지원 (`:692`) | 그대로 사용 |
| step별 `REFLECTION` 생략 | `skipped=true`가 정식 기능 (`:879`) | 우회 아님, 계약대로 |
| 세션 중복 규칙 §10.4 | "복구 가능한 `IN_PROGRESS` 세션 1개" (`:725`) | **충돌 없음** — step N이 `COMPLETED`가 된 뒤 N+1을 만들므로 동시 개방이 항상 1개 |
| 세션 단계 흐름 | `DRAWING→ANALYZING→CONVERSING→REFLECTION→REPORTING→COMPLETED` (`:277`) | 우회·대기 없이 그대로 탄다 |

> 참고: 이전 개정(4장 일괄 그리기)에서는 step 세션 4개가 동시에 `IN_PROGRESS`라 §10.4 예외가 필수였다. 그림마다 대화하는 확정안에서는 그 요구가 사라졌다.

따라서 이 문서는 **§20(가칭) 신규 도메인 추가 + §4 Enum 추가 + AI-06 신규**로 구성된다. 기존 조항 수정 없음.

---

## 1. 신규 도메인 `htp-assessment`

### 1.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| HTP-01 | POST | `/htp-assessments` | 연결 보호자 | 검사 생성 (step1 세션 동시 생성) |
| HTP-02 | GET | `/htp-assessments/{htpAssessmentId}` | 연결 보호자, 공유 전문가 | 검사 진행 상태·step 목록 조회 |
| HTP-03 | POST | `/htp-assessments/{htpAssessmentId}/steps/next` | 연결 보호자 | 다음 step 세션 생성 (순서 강제 지점) |
| HTP-04 | PUT | `/htp-assessments/{htpAssessmentId}/emotions` | 연결 보호자 | 검사 단위 감정 선택 (1회) |
| HTP-05 | POST | `/htp-assessments/{htpAssessmentId}/complete` | 연결 보호자 | 검사 완료 및 4장 종합 분석·리포트 요청 |
| HTP-06 | POST | `/htp-assessments/{htpAssessmentId}/abandon` | 연결 보호자 | 검사 포기 |

- 공통 Envelope(`common-response-error-contract-v1.md`)를 따른다.
- HTP-01·HTP-03·HTP-05는 `Idempotency-Key` Header 필수 (기존 DRAWING-02·DRAWING-11 규칙과 동일).
- **step 안의 그리기·탐지·대화는 신규 API가 없다.** 전부 기존 `drawing-sessions`·`conversations` 계약을 그대로 쓴다.

### 1.2 신규 Enum (§4 Enum 사전 추가)

| Enum | 허용값 |
| --- | --- |
| `HtpAssessmentStatus` | `IN_PROGRESS`, `COMPLETED`, `EXPIRED`, `ABANDONED`, `DELETED` |
| `HtpStepSubject` | `HOUSE`, `TREE`, `PERSON_MALE`, `PERSON_FEMALE` |

**`phase`는 두지 않는다.** 그리기와 대화가 한 step 안에 있으므로 "지금 무엇을 하는 중인지"는 해당 step 세션의 `currentStage`가 이미 표현한다. 검사 묶음은 `currentStep` + `status`만 안다.

**검사 결과 상태를 위한 Enum도 만들지 않는다.** 리포트는 기존 `ReportStatus`를 쓴다.

---

## 2. 엔드포인트 상세

### 2.1 HTP-01 검사 생성

`POST /api/v1/htp-assessments` · Header `Idempotency-Key` 필수

```json
{
  "childId": 10,
  "inputMethod": "CANVAS"
}
```

| 필드 | 타입 | 필수 | 규칙 |
| --- | --- | --- | --- |
| `childId` | int64 | O | 연결 보호자 권한 검증 |
| `inputMethod` | `InputMethod` | O | `CANVAS` \| `UPLOAD`. **검사 중 변경 불가** |

- 활동 유형은 서버가 `HTP` 코드로 고정한다. 클라이언트가 `drawingTypeId`를 보내지 않는다 — 검사 유형을 클라이언트가 고르게 하면 잘못된 유형으로 검사가 만들어질 수 있다.
- **step1(`HOUSE`) 세션을 함께 생성한다.** 검사를 만들고 세션을 따로 만들게 하면 그 사이에 실패했을 때 빈 검사가 남는다.
- 같은 아동에게 `IN_PROGRESS` 검사가 있으면 `409`와 기존 `htpAssessmentId`를 반환한다(기존 `ACTIVE_DRAWING_SESSION_EXISTS` 패턴과 같은 형태).

#### 응답 `201`

```json
{
  "htpAssessmentId": 900,
  "childId": 10,
  "status": "IN_PROGRESS",
  "currentStep": 1,
  "inputMethod": "CANVAS",
  "expiresAt": "2026-08-03T01:00:00Z",
  "currentStepSession": {
    "step": 1,
    "subject": "HOUSE",
    "drawingSessionId": 100,
    "currentStage": "DRAWING",
    "guideText": "집을 그려볼까요?",
    "paperOrientation": "LANDSCAPE"
  },
  "startedAt": "2026-07-27T01:00:00Z"
}
```

`Location: /api/v1/htp-assessments/900`

### 2.2 HTP-02 검사 조회

`GET /api/v1/htp-assessments/{htpAssessmentId}`

```json
{
  "htpAssessmentId": 900,
  "childId": 10,
  "status": "IN_PROGRESS",
  "currentStep": 3,
  "inputMethod": "CANVAS",
  "expiresAt": "2026-08-03T01:00:00Z",
  "steps": [
    { "step": 1, "subject": "HOUSE",         "drawingSessionId": 100, "sessionStatus": "COMPLETED",   "currentStage": "COMPLETED", "subjectDetected": true,  "retryCount": 0, "thumbnailUrl": "…", "conversationId": 800, "answeredCount": 2 },
    { "step": 2, "subject": "TREE",          "drawingSessionId": 101, "sessionStatus": "COMPLETED",   "currentStage": "COMPLETED", "subjectDetected": false, "retryCount": 2, "thumbnailUrl": "…", "conversationId": 801, "answeredCount": 1 },
    { "step": 3, "subject": "PERSON_MALE",   "drawingSessionId": 102, "sessionStatus": "IN_PROGRESS", "currentStage": "DRAWING",   "subjectDetected": null,  "retryCount": 0, "thumbnailUrl": null, "conversationId": null, "answeredCount": 0 },
    { "step": 4, "subject": "PERSON_FEMALE", "drawingSessionId": null, "sessionStatus": null,          "currentStage": null,        "subjectDetected": null,  "retryCount": 0, "thumbnailUrl": null, "conversationId": null, "answeredCount": 0 }
  ],
  "emotion": null,
  "reportId": null,
  "startedAt": "2026-07-27T01:00:00Z",
  "completedAt": null
}
```

- `steps`는 항상 4개를 반환한다. 아직 시작하지 않은 step은 `drawingSessionId=null`이다. **개수가 상황에 따라 달라지면 클라이언트가 진행 표시를 그릴 수 없다.**
- `subjectDetected`는 §2.7 품질 게이트 결과다. 아직 판정 전이면 `null`.
- 전문가는 리포트 공유 권한이 있을 때만 조회한다(기존 DRAWING-03 권한 규칙과 동일).

### 2.3 HTP-03 다음 step 생성

`POST /api/v1/htp-assessments/{htpAssessmentId}/steps/next` · Header `Idempotency-Key` 필수

Body 없음. **순서 강제가 일어나는 지점이다.**

- 직전 step 세션이 `COMPLETED`가 아니면 `409`.
- `currentStep`이 이미 4면 `409`.
- 성공 시 `currentStep`을 +1 하고 새 세션을 만든다.

```json
{
  "htpAssessmentId": 900,
  "currentStep": 2,
  "currentStepSession": {
    "step": 2,
    "subject": "TREE",
    "drawingSessionId": 101,
    "currentStage": "DRAWING",
    "guideText": "이번엔 나무를 그려볼까요?",
    "paperOrientation": "PORTRAIT"
  }
}
```

**클라이언트가 step 번호를 보내지 않는다.** 서버가 현재 상태에서 다음을 계산한다. 번호를 받으면 잘못된 값으로 순서를 건너뛰려는 요청을 매번 검증해야 하고, 경합 시 두 클라이언트가 같은 step을 두 번 만들 수 있다.

### 2.4 HTP-04 검사 단위 감정 선택

`PUT /api/v1/htp-assessments/{htpAssessmentId}/emotions`

```json
{
  "selectedEmotions": ["CALM"],
  "expressedEmotionText": "그냥 그랬어",
  "skipped": false
}
```

- 기존 §10.9와 **동일한 검증 규칙**을 쓴다: 복수 선택 가능, `UNKNOWN`은 배타, `skipped=true`면 배열 `[]`·표현 `null`, 보호자 대리 입력 금지 안내.
- **제목은 받지 않는다.** 주제가 지정된 검사라 제목이 정보를 더하지 않는다.
- 4개 step 세션이 모두 `COMPLETED`인 상태에서만 호출 가능하다. 아니면 `409`.
- `PUT`이므로 재호출은 덮어쓴다.

**step 세션 4개의 `REFLECTION`은 서버가 `skipped=true`로 통과시킨다.** 클라이언트가 step마다 DRAWING-10을 부르게 하면 아이에게 감정을 5번 묻는 화면이 만들어질 위험이 있다. 검사 흐름에서는 서버가 처리한다.

### 2.5 HTP-05 검사 완료

`POST /api/v1/htp-assessments/{htpAssessmentId}/complete` · Header `Idempotency-Key` 필수

Body 없음. 4장 종합 분석과 리포트 생성을 요청한다.

- 전제: step 4개 모두 `COMPLETED`, 감정 선택 완료(또는 `skipped=true`).
- 응답 `202 Accepted` (공통 규칙상 `code`는 `COMMON_200`).

```json
{
  "htpAssessmentId": 900,
  "status": "IN_PROGRESS",
  "analysisId": 750,
  "reportId": null,
  "nextAction": "WAIT_REPORT"
}
```

분석·리포트가 끝나면 검사 `status=COMPLETED`가 되고 `reportId`가 채워진다. 완료 알림은 기존 `NotificationType.REPORT_COMPLETED`를 그대로 쓴다.

### 2.6 HTP-06 검사 포기

`POST /api/v1/htp-assessments/{htpAssessmentId}/abandon`

- `status=ABANDONED`. 그린 그림은 삭제하지 않고 **개별 활동 기록으로 남긴다.**
- 진행 중이던 step 세션은 기존 세션 정책에 따라 정리한다.

### 2.7 탐지 품질 게이트 — 신규 API 없음

step 완료(`POST /drawing-complete`, DRAWING-09) 응답의 탐지 결과를 서버가 검사 규칙으로 해석한다.

| step | 기대 탐지 | 미탐지 시 |
| --- | --- | --- |
| 1 | `HOUSE` | 재유도 |
| 2 | `TREE` | 재유도 |
| 3·4 | `PERSON` | 재유도 |

- 재시도 **최대 2회**. 초과하면 `[이대로 진행]`만 남는다.
- `[이대로 진행]`을 선택하면 진행을 막지 않고 검사 리포트 `limitations`에 사실을 남긴다.
- **탐지 실패 그림도 대화는 진행한다.** 근거가 빈약하므로 일반형 질문으로 대체한다.
- step3·4는 탐지 라벨이 같다(`PERSON`). **AI가 그림에서 성별을 판정하지 않는다** — 성별은 아동에게 준 지시로만 기록한다.

재시도 횟수는 `steps[].retryCount`로 노출한다(HTP-02).

---

## 3. step 안에서 기존 계약을 쓰는 방법

신규 API가 없는 구간이다. 호출 순서만 정리한다.

| 순서 | 호출 | 비고 |
| --- | --- | --- |
| 1 | `POST /stroke-batches` (DRAWING-04) / `POST /upload` (DRAWING-08) | 캔버스 / 종이 |
| 2 | `PUT /draft` (DRAWING-05) | 캔버스만 |
| 3 | `POST /drawing-complete` (DRAWING-09) | 최종 저장 + 탐지. 성공 시 세션 `CONVERSING` |
| 4 | `POST /drawing-sessions/{id}/conversations` (CONV-01) | `maxQuestionCount=2`, `analysisId`=그 step의 탐지 |
| 5 | `POST /conversations/{id}/next-question` (CONV-03) ×2 | 답변은 CONV-05/CONV-06 |
| 6 | `POST /conversations/{id}/end` (CONV-09) | 성공 시 세션 `REFLECTION` |
| 7 | (서버) step `REFLECTION`을 `skipped=true`로 통과 → 세션 `COMPLETED` | HTP-04 참조 |
| 8 | `POST /htp-assessments/{id}/steps/next` (HTP-03) | 다음 step |

**검사에서는 중간 탐지(`DRAFT + OBJECT_DETECTION`)를 쓰지 않는다.** 그리는 중 개입이 없으므로 필요가 없고, 그림일기의 동시 대화형 정책(`concurrent_conversation`)도 `HTP`에서는 `FALSE`다.

### 질문 생성 제약 (프롬프트 정책)

검사 오염 방지를 위해 그림일기와 다른 제약을 건다.

- 사실 확인·묘사 유도만. 심리 해석·평가·제안 금지.
- **다음 주제를 언급하지 않는다.** 집 대화에서 나무·사람을 꺼내지 않는다.
- 계약이 아니라 질문 생성 정책이므로 API 필드로 만들지 않는다. `drawing_types` 또는 프롬프트 템플릿 쪽에 활동별 제약으로 둔다.

---

## 4. 내부 AI 계약 — AI-06 신규 (다중 그림 종합 분석)

### 4.1 기존 AI-01을 확장하지 않는 이유

`POST /internal/v1/analyses`(AI-01)는 **세션 1개 스코프**다. 요청이 `drawingSessionId` 단수 + `drawing` 객체 하나이고(§19.3), 공개 조회 경로도 `/drawing-sessions/{id}/analyses/{analysisId}`로 세션에 묶여 있다.

여기에 다중 그림을 끼워 넣으면 `drawing`이 단수인지 배열인지 요청마다 달라져 **기존 호출자와 AI 서버 양쪽이 분기 처리를 하게 된다.** 신규 엔드포인트로 분리하면 AI-01은 손대지 않는다.

### 4.2 AI-06 요청

`POST /internal/v1/assessments/analyses` (§19.1 목록에 추가)

§19.2 공통 내부 규칙을 그대로 따른다 — `X-Internal-Api-Key`, `X-Request-Id`, 아동 이름·생년월일 미전달, 짧은 만료의 읽기 전용 URL.

```json
{
  "analysisId": 750,
  "htpAssessmentId": 900,
  "assessmentCode": "HTP",
  "childContext": { "age": 7, "ageGroup": "LOWER_ELEMENTARY", "questionDifficulty": "LOWER_ELEMENTARY" },
  "steps": [
    {
      "step": 1,
      "subject": "HOUSE",
      "drawingSessionId": 100,
      "drawing": {
        "drawingAssetId": 502,
        "signedUrl": "http://backend:8080/internal/v1/ai-images/opaque-one-time-token",
        "mimeType": "image/png",
        "width": 1920, "height": 1080,
        "checksumSha256": "sha256-value"
      },
      "detection": { "analysisId": 701, "subjectDetected": true },
      "behavior": { "drawingDurationMs": 240000, "pauseCount": 3, "undoCount": 1, "eraseCount": 2, "pressureAvailable": false },
      "conversation": {
        "messages": [
          { "messageId": 803, "senderType": "AI",    "messageType": "QUESTION",     "text": "이 집엔 누가 살아?" },
          { "messageId": 804, "senderType": "CHILD", "messageType": "VOICE_ANSWER", "text": "나랑 엄마랑 살아" }
        ]
      }
    }
  ],
  "reflection": { "selectedEmotions": ["CALM"], "expressedEmotionText": "그냥 그랬어" },
  "rag": { "knowledgeBaseVersion": "2026.07", "allowedSourceTypes": ["PEER_REVIEWED_PAPER", "PRACTICE_GUIDELINE"], "maxReferences": 5 }
}
```

- `steps`는 **항상 4개**를 순서대로 보낸다. 그림을 못 그린 step은 없다(검사 완료가 전제).
- `reflection`은 검사 단위 1회 값이다. step별 감정은 존재하지 않는다.
- `behavior`를 step별로 보낸다 — 논문은 4장 합계 1쌍만 재지만 우리는 세션 단위로 이미 분리 수집한다. 버릴 이유가 없다.

### 4.3 AI-06 응답

§19.4 종합 분석 응답 구조를 재사용하고 검사 단위 항목을 더한다.

```json
{
  "analysisId": 750,
  "status": "SUCCESS",
  "modelInfo": { "objectDetection": "…", "vision": "…", "language": "…", "knowledgeBaseVersion": "2026.07" },
  "stepResults": [
    { "step": 1, "subject": "HOUSE", "quantitativeMetrics": { "sizeRatio": 0.31, "placement": "CENTER", "requiredParts": { "HOUSE_ROOF": true, "HOUSE_WALL": true, "HOUSE_WINDOW": false, "HOUSE_DOOR": true } } }
  ],
  "assessmentObservation": { "reviewStatus": "AI_DRAFT", "expertReviewRequired": true, "draft": "…", "uncertainties": ["…"] },
  "unusedInputs": ["step2.conversation"],
  "warnings": ["step2.subjectDetected=false"]
}
```

**정량 척도는 점수로 환산하지 않는다.** 논문(박희진 2011 리커트 척도)처럼 점수화하면 진단형 산출물이 되어 §13.4 위반이다. raw feature로만 저장하고 전문가에게만 노출한다.

### 4.4 정량 척도 계산 위치

**AI 서버(`ai/`)에서 계산한다.** bbox와 이미지 크기를 이미 다루는 곳이다. BE에 두면 탐지 결과를 다시 해석하는 중복 로직이 생긴다.

| 항목 | 계산 | 대상 |
| --- | --- | --- |
| 크기 비율 | whole 박스 면적 / 용지 면적 | 집·나무·사람 |
| 용지 내 배치 | whole 박스 중심의 9분할 위치 | 집·나무·사람 |
| 필수 요소 유무 | `HOUSE_ROOF`/`HOUSE_WALL`/`HOUSE_WINDOW`/`HOUSE_DOOR` | 집 |
| 부위 비율 | `TREE_ROOT`:`TREE_TRUNK`:`TREE_CROWN` 높이 비 | 나무 |
| 부위 비율 | `PERSON_HEAD`:`PERSON_UPPER_BODY`:`PERSON_LEG` 높이 비 | 사람 |
| 부위 누락 | 눈·입·손·발 탐지 여부 | 사람 |

`bbox_norm_xywh`가 이미 0~1 정규화라 추가 모델이 필요 없다.

---

## 5. 리포트

기존 2계층(`ParentActivityReport` / `ExpertReviewMaterial`, §13.1)을 그대로 쓴다. **HTP 전용 리포트 타입을 만들지 않는다.** 검사 단위 리포트가 4개 세션을 참조하도록 확장한다.

| 대상 | 제공 | 금지 |
| --- | --- | --- |
| 보호자 | 4장 썸네일, 무엇을 그렸는지(탐지 객체명), 아이가 한 말, 활동 기록(시간·멈춤·지우기), 보호자 대화 가이드, 한계 고지 | AI 추정 감정·확률, 리커트 점수, 관찰 초안, RAG 해석 |
| 전문가(공유 동의 시) | 위 전부 + 정량 척도, 시각·행동 특징, `AI_DRAFT` 관찰 초안, 불확실성, `unusedInputs` | — |

`expertReviewRequired=true`를 유지한다(§2.4 원칙).

---

## 6. Migration

```sql
CREATE TABLE htp_assessments (
    htp_assessment_id BIGINT       NOT NULL AUTO_INCREMENT,
    child_id          BIGINT       NOT NULL,
    drawing_type_id   BIGINT       NOT NULL COMMENT 'HTP 코드 유형',
    status            VARCHAR(20)  NOT NULL COMMENT 'HtpAssessmentStatus',
    current_step      TINYINT      NOT NULL DEFAULT 1,
    input_method      VARCHAR(10)  NOT NULL COMMENT 'CANVAS | UPLOAD',
    report_id         BIGINT       NULL,
    expires_at        DATETIME(6)  NOT NULL,
    started_at        DATETIME(6)  NOT NULL,
    completed_at      DATETIME(6)  NULL,
    deleted_at        DATETIME(6)  NULL,
    PRIMARY KEY (htp_assessment_id),
    KEY idx_htp_assessments_child_status (child_id, status)
);

CREATE TABLE htp_assessment_steps (
    htp_assessment_step_id BIGINT      NOT NULL AUTO_INCREMENT,
    htp_assessment_id      BIGINT      NOT NULL,
    step_no                TINYINT     NOT NULL COMMENT '1..4',
    subject                VARCHAR(20) NOT NULL COMMENT 'HtpStepSubject',
    drawing_session_id     BIGINT      NULL COMMENT '아직 시작 전이면 NULL',
    subject_detected       BOOLEAN     NULL COMMENT '판정 전이면 NULL',
    retry_count            TINYINT     NOT NULL DEFAULT 0,
    created_at             DATETIME(6) NOT NULL,
    PRIMARY KEY (htp_assessment_step_id),
    UNIQUE KEY uk_htp_step (htp_assessment_id, step_no),
    UNIQUE KEY uk_htp_step_session (drawing_session_id)
);
```

- `uk_htp_step`이 **같은 step을 두 번 만드는 경합을 DB에서 최종 방어**한다(HTP-03 멱등 처리와 이중 방어).
- `uk_htp_step_session`은 한 세션이 두 검사에 속하는 것을 막는다.
- `HTP` 활동 코드 seed가 필요하다(`drawing_types`, `category=ASSESSMENT`, `concurrent_conversation=FALSE`).

### 6.1 검사 단위 감정 — 기존 테이블을 재사용할 수 없다

스키마를 확인한 결과, 기존 감정 테이블은 **세션에 강하게 묶여 있다.**

```sql
-- V3__normalize_json_columns.sql:355-370
CREATE TABLE drawing_session_emotions (
    drawing_session_id BIGINT NOT NULL,
    emotion_code       VARCHAR(20) NOT NULL,
    selection_order    SMALLINT NOT NULL DEFAULT 0,
    CONSTRAINT uk_drawing_session_emotions_session_emotion UNIQUE (drawing_session_id, emotion_code),
    CONSTRAINT fk_drawing_session_emotions_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE CASCADE,
    ...
);
```

`drawing_session_id`가 `NOT NULL` + FK다. 검사 단위 감정은 특정 그림 1장에 속하지 않으므로 여기에 넣을 자리가 없다. **step 세션 하나에 억지로 붙이면** 그 세션이 삭제될 때 `ON DELETE CASCADE`로 검사 전체의 감정이 사라지고, 리포트에서 그 감정이 해당 그림의 감정처럼 읽힌다.

따라서 검사 전용 테이블을 만든다.

```sql
CREATE TABLE htp_assessment_emotions (
    id                     BIGINT      NOT NULL AUTO_INCREMENT,
    htp_assessment_id      BIGINT      NOT NULL,
    emotion_code           VARCHAR(20) NOT NULL,
    selection_order        SMALLINT    NOT NULL DEFAULT 0,
    created_at             DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_htp_assessment_emotions PRIMARY KEY (id),
    CONSTRAINT uk_htp_assessment_emotions_emotion UNIQUE (htp_assessment_id, emotion_code),
    CONSTRAINT uk_htp_assessment_emotions_order   UNIQUE (htp_assessment_id, selection_order),
    CONSTRAINT fk_htp_assessment_emotions_assessment_id FOREIGN KEY (htp_assessment_id)
        REFERENCES htp_assessments (id) ON DELETE CASCADE,
    CONSTRAINT ck_htp_assessment_emotions_code
        CHECK (emotion_code IN ('HAPPY','SAD','ANGRY','SCARED','CALM','UNKNOWN'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='HTP 검사 단위 선택 감정';

ALTER TABLE htp_assessments
  ADD COLUMN expressed_emotion_text TEXT    NULL     COMMENT '검사 단위 직접 표현',
  ADD COLUMN emotion_skipped        BOOLEAN NOT NULL DEFAULT FALSE COMMENT '감정 선택 건너뜀';
```

`drawing_session_emotions`의 구조(감정 행 + 순서 + CHECK)를 그대로 복사한다. 검증 규칙이 같으므로 형태를 맞춰야 서비스 로직을 재사용할 수 있다.

**`emotion_skipped`를 컬럼으로 둔다.** 기존 세션 쪽은 `skipped`가 DB에 저장되지 않고 응답으로만 되돌아가는데(`DrawingReflectionService.java:86-87`), 검사에서는 "건너뜀"과 "아직 안 함"이 HTP-05 완료 가능 여부를 가르므로 반드시 저장돼야 한다.

### 6.2 그림일기 감정 2회 변경과의 관계

두 작업은 **같은 테이블을 건드리지 않는다.**

| | 그림일기 | HTP |
| --- | --- | --- |
| 대상 테이블 | `drawing_session_emotions` 변경 + `drawing_session_reflections` 신설 | `htp_assessment_emotions` 신설 |
| 성격 | 기존 UNIQUE 2개 교체 + backfill | 순수 신규 |
| 상호 의존 | 없음 | 없음 |

**병렬 진행 가능하다.** 다만 step 세션의 `REFLECTION`을 `skipped=true`로 통과시키는 처리(§2.4)는 그림일기 쪽에서 손대는 `saveReflection()`·`canSaveReflection()`과 같은 메서드를 쓰므로, **두 작업이 겹치면 머지 충돌이 난다.** 순서를 정하거나 같은 브랜치에서 처리한다.

---

## 7. 오류 코드 (제안)

`DOMAIN_HTTP_SEQUENCE` 형식(공통 계약 §6)을 따른다. 신규 도메인이라 `HTP_`로 시작하며 기존 코드와 충돌하지 않는다.

| code | HTTP | 의미 |
| --- | --- | --- |
| `HTP_404_001` | 404 | 검사를 찾을 수 없음 |
| `HTP_403_001` | 403 | 검사 접근 권한 없음 |
| `HTP_409_001` | 409 | 같은 아동에게 진행 중 검사가 있음 (`data.htpAssessmentId` 반환) |
| `HTP_409_002` | 409 | 직전 step이 완료되지 않아 다음 step을 만들 수 없음 |
| `HTP_409_003` | 409 | 이미 마지막 step (`currentStep=4`) |
| `HTP_409_004` | 409 | step이 모두 완료되지 않아 감정 선택·완료 불가 |
| `HTP_409_005` | 409 | 이미 완료·포기·만료된 검사 |
| `HTP_409_006` | 409 | 재시도 한도(2회) 초과 |
| `HTP_400_001` | 400 | 검사 중 `inputMethod` 변경 시도 |

`Idempotency-Key` 관련 오류는 기존 `IDEMPOTENCY_KEY_REUSED`를 그대로 쓴다.

---

## 8. 유효기간·중단·재개

| 상황 | 처리 |
| --- | --- |
| 그리는 중 중단 | `IN_PROGRESS`, `currentStep=N` 유지. 재진입 시 기존 draft 복구로 이어간다 |
| 대화 중 중단 | `IN_PROGRESS`, step 세션이 `CONVERSING`이므로 그 그림을 다시 보여주고 남은 질문부터 |
| 4장 완료 후 마무리 전 중단 | step 4개 `COMPLETED`. 재진입 시 감정 선택부터 |
| 유효기간 초과 | **7일** 경과 시 `EXPIRED`. 그림은 보존하되 종합 분석은 만들지 않는다 |
| 포기 | `ABANDONED`. 그림은 개별 활동 기록으로 남는다 |

7일은 **4장이 모두 완료되기 전까지**에 적용한다. HTP는 한 시점의 심리 상태를 보는 검사라 며칠 간격으로 그린 4장을 묶어 해석할 근거가 없다. 다만 아동이 한 번에 4장을 못 그리는 것은 정상이므로 하루 완료를 강제하지 않는다.

만료 판정은 배치로 처리한다(기존 세션 만료 정책이 있으면 그 주기에 얹는다 — **확인 필요**).

---

## 9. 배포 순서

| 순서 | 작업 | 선행 |
| --- | --- | --- |
| 1 | §4 Enum 2종 정본 추가 | — |
| 2 | Migration(테이블 2개) + `HTP` seed | 1 |
| 3 | HTP-01·02·03 (검사 생성·조회·step 진행) | 2 |
| 4 | 검사형 질문 생성 제약 | 3 |
| 5 | HTP-04·06 (감정·포기) | 3 |
| 6 | AI-06 계약 확정 → AI 서버 구현 → 정량 척도 계산 | 병렬 가능 |
| 7 | HTP-05 (완료·종합 분석·리포트) | 5, 6 |
| 8 | FE: 안내 화면 3종, 검사형 캔버스(검정 `PEN`·지우개) | 3 |

**기존 API를 고치지 않으므로 기존 기능 회귀 위험이 낮다.** 신규 도메인이 전부 추가되기 전까지 `HTP` 활동 코드를 seed하지 않으면 사용자에게 노출되지도 않는다.

---

## 10. 미결정

| # | 항목 | 필요한 것 |
| --- | --- | --- |
| ~~1~~ | ~~검사 감정 저장 위치~~ | **해결(2026-07-27).** 기존 테이블은 `drawing_session_id NOT NULL` + `ON DELETE CASCADE`라 재사용 불가 → `htp_assessment_emotions` 신설(§6.1) |
| 2 | 만료 배치 | 기존 세션 만료 처리 주기가 있는지 확인 후 얹기 |
| 3 | 검사 리포트가 4개 세션을 참조하는 방식 | 기존 `reports` 스키마 확인 필요(세션 1:1 전제인지) |
| 4 | 활동 기록 목록(§14)에서 검사 표기 | step 4개가 각각 항목으로 뜨면 목록이 지저분해진다. 묶어 보일지 결정 |
| 5 | `HTP` 권장 연령 | 기준 데이터 seed 값 (임상 HTP는 통상 만 4세 이상) |

---

**이 문서는 로컬 초안이며 계약 정본을 수정하지 않았다.** 정본 반영은 명세 담당자와 팀 결정 사항이다.
