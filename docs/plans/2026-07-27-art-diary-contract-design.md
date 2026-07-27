# 그림일기(ART_DIARY) 계약 변경안 (초안)

**작성일:** 2026-07-27
**AI 한줄 요약:** 그림일기의 "그리면서 대화" 흐름과 감정 2회 기록을 지원하기 위해 필요한 계약 정본 변경 4건을 엔드포인트·필드·오류 코드·Migration 수준으로 작성했다.
**상태:** **초안 — 정본 아님, 미구현.** 이 문서는 제안이며 계약의 정본은 `공통작업/docs/api/API_명세서_최종.md`다. 정본과 어긋나면 정본이 우선한다.
**기반 기획:** `2026-07-27-art-diary-process-design.md`
**정본 기준선:** `API_명세서_최종.md` (origin/develop `949b3b0` 시점)

---

## 0. 변경 요약

| # | 변경 | 대상 | 성격 | 이유 |
| --- | --- | --- | --- | --- |
| 1 | 동시 대화형 활동은 대화 중에도 `DRAWING` 단계를 유지 | §10.1, §12.2, DRAWING-01 | **Breaking 아님(조건 완화 + 신규 필드)** | 대화 시작 시 `CONVERSING`이 되면 획 저장·임시 저장·중간 탐지가 모두 막힌다(§1) |
| 2 | 감정 기록에 시점(`checkpoint`) 도입 | §10.9 / DRAWING-10, §10.4 응답 | **Additive**(기존 필드 의미 유지) | 그림일기는 시작·종료 2회 기록한다 |
| 3 | 도구·이벤트 코드 목록을 명세 부록으로 고정 | §10.5 | **계약 변경 없음**(문서 등재) | 서버가 이미 임의 문자열을 받는다. 합의 없으면 행동 분석이 잡음이 된다 |
| 4 | `width` 단위 = Flutter 논리 픽셀임을 명시 (+ 좌표별 `pressure` 예시 보강) | §10.5 | **문서 보강**(현행 명문화, Breaking 아님) | 팀 정책은 이미 논리 픽셀. FE에 문서화 요청 TODO까지 있다(§4) |

**1·2번만 정본 수정이 필요하다.** 3·4번은 이미 있는 것을 글로 고정하는 일이다.

---

## 1. 변경 1 — 동시 대화형 활동의 단계 유지

### 1.1 문제: 대화가 시작되면 그리기 관련 API 3개가 동시에 막힌다

기획 문서(§4.1)는 "중간 탐지가 막힌다"고 적었으나, 코드를 확인하니 **차단 범위가 더 넓다.** 세 API가 모두 같은 판정을 공유한다.

```java
// DrawingSession.java:138-142
public boolean isSnapshotUploadable() {
  return deletedAt == null
      && sessionStatus == DrawingSessionStatus.IN_PROGRESS
      && currentStage == DrawingStage.DRAWING;
}

// DrawingSession.java:150-152 — 획 배치
public boolean canAcceptStrokeBatch() {
  return inputMethod == DrawingInputMethod.CANVAS && isSnapshotUploadable();
}

// DrawingSession.java:160-162 — 분석 요청
public boolean isAnalysisRequestable() {
  return isSnapshotUploadable();
}
```

한편 대화를 시작하면 단계가 바뀐다.

```java
// ConversationStartDrawingSession.java:45-54
public boolean canStartConversation() {
  return deletedAt == null
      && sessionStatus == DrawingSessionStatus.IN_PROGRESS
      && (currentStage == DrawingStage.ANALYZING || currentStage == DrawingStage.CONVERSING);
}
public void moveToConversing() { currentStage = DrawingStage.CONVERSING; }
```

| API | 판정 | 대화 시작 후 |
| --- | --- | --- |
| `POST /stroke-batches` (DRAWING-04) | `canAcceptStrokeBatch()` | **차단** |
| `PUT /draft` (DRAWING-05) | `isSnapshotUploadable()` | **차단** |
| `POST /analyses` (ANALYSIS) | `isAnalysisRequestable()` | **차단** |

즉 첫 질문이 나가는 순간부터 **아이가 계속 그려도 획이 서버에 저장되지 않는다.** 획 단위 자동 저장 요구와 정면으로 부딪힌다. 기획 문서의 판정을 이 범위로 정정해야 한다.

### 1.2 이미 있는 탈출구와 그것을 쓰면 안 되는 이유

정본에 `CONVERSING → DRAWING` 전이가 이미 있다(§10.1 말미). 진입점은 **CONV-08 건너뛰기 하나뿐**이다.

```json
// §12.8 건너뛰기 요청
{ "questionMessageId": 803, "reason": "CHILD_REQUEST", "returnToDrawing": true }
```
> `returnToDrawing=true`이면 세션의 `currentStage=DRAWING`

기술적으로는 이걸로 왕복이 돈다. 그러나 **의미가 다르다.** 이 API는 "질문을 건너뛰고 다시 그리러 간다"이며 `reason`이 필수다. 아이가 **답을 한 뒤** 계속 그리는 정상 흐름에 이걸 쓰면 답변한 질문이 건너뛴 것으로 기록되고(`isSkipped`, §12.9), 대화 요약 `skippedQuestionCount`가 실제와 달라진다. 리포트에 들어가는 값이므로 데이터 오염이다.

**따라서 "무손실 그리기 복귀" 경로가 필요하다.** 건너뛰기를 우회로로 쓰지 않는다.

### 1.3 제안: 활동 유형에 동시 대화 속성을 두고, 그 유형은 단계를 바꾸지 않는다

#### (a) `drawing_types`에 속성 추가

| 항목 | 값 |
| --- | --- |
| 컬럼 | `concurrent_conversation BOOLEAN NOT NULL DEFAULT FALSE` |
| 의미 | 그리는 도중 대화를 허용하는 활동인지 |
| `TRUE` | `ART_DIARY` |
| `FALSE` | 그 외 전부 (HTP 포함) |

**클라이언트 요청 필드로 두지 않는다.** HTP에서 그리는 중 대화를 막는 것은 검사 타당성 문제라 클라이언트 판단에 맡길 수 없다. 서버가 활동 유형으로 강제한다.

DRAWING-01 응답 항목에 `concurrentConversation`(boolean)을 추가한다. FE가 화면 구성을 미리 정하려면 필요하다. 기존 필드는 건드리지 않는다.

#### (b) §12.2 대화 시작 조건 완화

| | 현행 | 변경안 |
| --- | --- | --- |
| 시작 가능 단계 | `ANALYZING` 또는 `CONVERSING` | `ANALYZING`, `CONVERSING`, **그리고 `concurrentConversation=true`이면 `DRAWING`** |
| 시작 시 단계 전환 | 항상 `CONVERSING` | `concurrentConversation=true`이면 **전환하지 않는다**(`DRAWING` 유지) |

```java
// 변경안 의사코드
public boolean canStartConversation(boolean concurrentConversation) {
  if (deletedAt != null || sessionStatus != IN_PROGRESS) return false;
  return currentStage == ANALYZING
      || currentStage == CONVERSING
      || (concurrentConversation && currentStage == DRAWING);
}
public void onConversationStarted(boolean concurrentConversation) {
  if (!concurrentConversation) currentStage = CONVERSING;
}
```

이 방향을 택한 이유는 **고칠 곳이 한 군데**이기 때문이다. 반대로 "중간 탐지·획 저장을 `CONVERSING`에서도 허용"하는 방향은 `isSnapshotUploadable()` 하나를 완화하는 것이라 코드는 더 짧지만, **HTP를 포함한 모든 활동에서 대화 중 그림 변경이 열린다.** 검사 오염 방지 설계와 충돌하므로 쓰지 않는다.

#### (c) 응답·조회 영향

- CONV-01 응답은 그대로다. `status`는 대화 자체의 상태(`CONVERSING`)이고 세션 단계와 다른 값이라 혼동이 없다.
- DRAWING-03 세션 조회의 `currentStage`가 그림일기에서는 대화 중에도 `DRAWING`으로 보인다. **의도된 값이다** — 아이는 실제로 그리는 중이다. 이 의미를 §10.1에 한 줄로 명시한다.

#### (d) §10.1 상태 전이 문서 보강

기존 문장 뒤에 추가한다.

> 동시 대화형 활동(`concurrentConversation=true`)은 대화가 진행 중이어도 `currentStage=DRAWING`을 유지한다. 이 활동에서 `CONVERSING`은 **그림 완료 후 마무리 대화 구간**만 의미한다.

### 1.4 오류 코드

새 코드가 필요 없다. 조건이 완화되는 방향이라 기존 `409`가 나던 자리에서 성공하는 것이 전부다. 비허용 활동에서 `DRAWING` 단계 대화 시작을 시도하면 지금과 동일하게 처리한다.

### 1.5 하위 호환

| 대상 | 영향 |
| --- | --- |
| 기존 활동(`concurrentConversation=FALSE`) | **동작 변화 없음.** 기본값이 `FALSE`라 기존 seed·기존 세션 전부 현행 유지 |
| 기존 FE | 신규 응답 필드 1개 추가뿐. 무시하면 현행대로 동작 |
| 기존 데이터 | Migration은 컬럼 추가 + `ART_DIARY` 1행 `TRUE` 갱신 |

---

## 2. 변경 2 — 감정 2회 기록 (`checkpoint`)

### 2.1 문제

§10.9(DRAWING-10)는 세션당 1벌이고, 호출하면 단계가 전환된다.

> 성공 시 `currentStage=REPORTING` 직전 준비 상태인 `REFLECTION`을 반환한다.

시작 시점에 그대로 부르면 **한 획도 안 그렸는데 마무리 단계로 넘어간다.**

### 2.2 제안: 요청에 시점을 넣고, `PRE`는 단계를 바꾸지 않는다

#### 요청 (DRAWING-10 `PUT /drawing-sessions/{drawingSessionId}/reflection`)

```json
{
  "checkpoint": "POST",
  "title": "우리 가족의 공원",
  "selectedEmotions": ["HAPPY", "CALM"],
  "expressedEmotionText": "다 같이 있어서 좋았어",
  "skipped": false
}
```

| 필드 | 타입 | 필수 | 규칙 |
| --- | --- | --- | --- |
| `checkpoint` | `EmotionCheckpoint` | X | `PRE` \| `POST`. **생략 시 `POST`** — 기존 클라이언트가 그대로 동작한다 |
| `title` | string | X | **`checkpoint=PRE`이면 반드시 `null`**. 값이 있으면 `400` |
| `selectedEmotions` | `EmotionType[]` | O | 기존 규칙 동일(`UNKNOWN` 배타, 복수 선택) |
| `expressedEmotionText` | string | X | 기존과 동일 |
| `skipped` | boolean | O | 기존과 동일. `true`면 배열 `[]`, 표현 `null` |

`checkpoint`를 선택 필드로 두고 기본값을 `POST`로 잡는 것이 이 설계의 핵심이다. **기존 호출자는 Body를 한 글자도 바꾸지 않아도 된다.**

#### 단계 전환 규칙

| `checkpoint` | 호출 가능 단계 | 성공 후 단계 |
| --- | --- | --- |
| `PRE` | `DRAWING` | **전환 없음**(`DRAWING` 유지) |
| `POST` | 기존과 동일 | `REFLECTION` (기존과 동일) |

#### 중복 호출

같은 `checkpoint`로 다시 부르면 **마지막 값으로 덮어쓴다**(시점당 1건). `PUT`이므로 멱등이 자연스럽고, 아이가 감정을 바꾸는 것은 정상 동작이다.

#### 신규 Enum

| Enum | 허용값 |
| --- | --- |
| `EmotionCheckpoint` | `PRE`, `POST` |

§4 Enum 사전에 추가한다.

### 2.3 조회 응답 — 기존 필드를 건드리지 않는 것이 핵심

`selectedEmotions`는 **4곳**에서 쓰인다.

| 위치 | 근거 |
| --- | --- |
| 세션 상세 (DRAWING-03) | §10.4 응답 필드 목록 |
| 활동 기록 목록 | §14 목록 항목 |
| 리포트 목록 | §13 목록 항목 |
| 리포트 상세 | §13 상세 |

**기존 `selectedEmotions`는 `POST` 값을 그대로 담는다.** 배열의 배열로 바꾸거나 의미를 바꾸면 이 4곳과 그것을 읽는 FE가 전부 깨진다. 시점별 데이터는 새 필드로 덧붙인다.

```json
{
  "selectedEmotions": ["HAPPY", "CALM"],
  "expressedEmotionText": "다 같이 있어서 좋았어",
  "emotionCheckpoints": [
    { "checkpoint": "PRE",  "selectedEmotions": ["SAD"],           "expressedEmotionText": null,               "skipped": false, "recordedAt": "2026-07-27T01:00:00Z" },
    { "checkpoint": "POST", "selectedEmotions": ["HAPPY","CALM"], "expressedEmotionText": "다 같이 있어서 좋았어", "skipped": false, "recordedAt": "2026-07-27T01:35:00Z" }
  ]
}
```

- `emotionCheckpoints`는 `recordedAt` 오름차순, 기록된 시점만 담는다(건너뛴 시점은 `skipped=true`로 존재, 아예 호출 안 한 시점은 배열에 없음).
- 세션 상세와 리포트 상세에만 추가한다. **목록 응답에는 넣지 않는다** — 목록은 이미 필드가 많고 시점별 비교는 상세 화면의 일이다.

### 2.4 리포트 표기 제약

두 시점을 **나란히 사실로만** 노출한다. `sad → happy`에 대한 인과·개선 해석은 §13.4가 금지하는 진단형 산출물이므로 생성하지 않는다. `PRE`가 없으면(건너뜀·미호출) 비교 UI 자체를 표시하지 않는다.

### 2.5 오류 코드

| 제안 code | HTTP | 의미 |
| --- | --- | --- |
| `DRAWING_400_012` | 400 | `checkpoint=PRE`인데 `title`이 있음 |
| `DRAWING_409_011` | 409 | 현재 단계에서 허용되지 않는 `checkpoint` (예: `REFLECTION`에서 `PRE`) |

> **번호는 재확인 대상.** 구현 시점의 `DrawingErrorCode`에서 실제 최대 일련번호를 다시 세고 붙인다. 조사 시점(2026-07-27) 기준 `DRAWING_400_*`은 011까지, `DRAWING_409_*`은 010까지 사용 중이었으나 다른 패키지에 추가 정의가 있을 수 있다.

### 2.6 실제 스키마 확인 결과 — 이 변경은 컬럼 하나 추가가 아니다

스키마를 확인했다. 감정은 **별도 테이블에 저장되지만**, 그 테이블의 제약과 주변 코드가 "세션당 감정 1벌"을 여러 겹으로 못 박고 있다. 걸림돌 5개를 전부 풀어야 한다.

```sql
-- V3__normalize_json_columns.sql:355-370
CREATE TABLE drawing_session_emotions (
    id BIGINT NOT NULL AUTO_INCREMENT,
    drawing_session_id BIGINT NOT NULL,
    emotion_code VARCHAR(20) NOT NULL,
    selection_order SMALLINT NOT NULL DEFAULT 0,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT uk_drawing_session_emotions_session_emotion UNIQUE (drawing_session_id, emotion_code),
    CONSTRAINT uk_drawing_session_emotions_session_order   UNIQUE (drawing_session_id, selection_order),
    CONSTRAINT ck_drawing_session_emotions_code
        CHECK (emotion_code IN ('HAPPY','SAD','ANGRY','SCARED','CALM','UNKNOWN')),
    ...
);
```
```sql
-- V1__create_initial_schema.sql:209-210 (drawing_sessions)
title                  VARCHAR(200) NULL,
expressed_emotion_text TEXT         NULL,
```

| # | 걸림돌 | 근거 | 결과 |
| --- | --- | --- | --- |
| 1 | `UNIQUE (drawing_session_id, emotion_code)` | V3:362 | **`PRE=SAD` + `POST=SAD`가 저장 불가.** 같은 감정을 두 시점에 고를 수 없다 |
| 2 | `UNIQUE (drawing_session_id, selection_order)` | V3:363 | 두 시점 모두 `selection_order=0`부터 시작 → **첫 감정끼리 충돌** |
| 3 | `expressed_emotion_text`가 세션 컬럼 | V1:210 | 단수 값. 두 시점의 직접 표현을 담을 수 없다 |
| 4 | `skipped`가 **저장되지 않는다** | `DrawingReflectionService.java:86-87`이 응답에 그대로 되돌려줄 뿐 | "건너뜀"과 "아예 기록 안 함"을 구분할 수 없다. §2.3 `emotionCheckpoints[].skipped`가 성립하지 않는다 |
| 5 | 저장 시 세션 전체 삭제 | `DrawingReflectionService.java:79` `emotionRepository.deleteAllByDrawingSessionId(...)` | **`POST`를 저장하면 `PRE`가 지워진다** |

걸림돌 4가 특히 중요하다. 지금 `skipped`는 검증에만 쓰이고 DB에 흔적이 남지 않는다. 시점 개념을 넣는 순간 "PRE를 건너뛴 아이"와 "PRE를 아직 안 부른 클라이언트"가 구분돼야 하므로 **저장이 필요해진다.**

### 2.7 Migration 제안

```sql
-- (1) 감정 행에 시점 추가
ALTER TABLE drawing_session_emotions
  ADD COLUMN checkpoint VARCHAR(10) NOT NULL DEFAULT 'POST' COMMENT '감정 기록 시점(PRE|POST)';

ALTER TABLE drawing_session_emotions
  ADD CONSTRAINT ck_drawing_session_emotions_checkpoint
      CHECK (checkpoint IN ('PRE','POST'));

-- (2) 충돌하는 UNIQUE 2개를 시점 포함으로 교체  ← 걸림돌 1·2
ALTER TABLE drawing_session_emotions
  DROP INDEX uk_drawing_session_emotions_session_emotion,
  DROP INDEX uk_drawing_session_emotions_session_order,
  ADD CONSTRAINT uk_drawing_session_emotions_ckpt_emotion
      UNIQUE (drawing_session_id, checkpoint, emotion_code),
  ADD CONSTRAINT uk_drawing_session_emotions_ckpt_order
      UNIQUE (drawing_session_id, checkpoint, selection_order);

-- (3) 시점 단위 메타(직접 표현·건너뛰기·기록 시각) 테이블 신설  ← 걸림돌 3·4
CREATE TABLE drawing_session_reflections (
    id                     BIGINT       NOT NULL AUTO_INCREMENT,
    drawing_session_id     BIGINT       NOT NULL,
    checkpoint             VARCHAR(10)  NOT NULL COMMENT 'PRE | POST',
    expressed_emotion_text TEXT         NULL,
    skipped                BOOLEAN      NOT NULL DEFAULT FALSE,
    recorded_at            DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_drawing_session_reflections PRIMARY KEY (id),
    CONSTRAINT uk_drawing_session_reflections_ckpt UNIQUE (drawing_session_id, checkpoint),
    CONSTRAINT fk_drawing_session_reflections_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE CASCADE,
    CONSTRAINT ck_drawing_session_reflections_checkpoint CHECK (checkpoint IN ('PRE','POST'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 시점별 감정 회고';

-- (4) 기존 데이터 backfill — 지금까지의 기록은 전부 종료 시점이다
INSERT INTO drawing_session_reflections (drawing_session_id, checkpoint, expressed_emotion_text, skipped, recorded_at)
SELECT id, 'POST', expressed_emotion_text, FALSE, COALESCE(completed_at, updated_at)
  FROM drawing_sessions
 WHERE deleted_at IS NULL;
```

- 기존 감정 행은 `DEFAULT 'POST'`로 자동 분류된다. **데이터 손실 없음.**
- `title`은 `drawing_sessions`에 그대로 둔다. `PRE`는 제목을 받지 않으므로 시점별로 나눌 이유가 없다.
- **`drawing_sessions.expressed_emotion_text`를 이번 Migration에서 삭제하지 않는다.** 리포트 조회 계층(`ReportDrawingSessionView`, `ReportChildExpressionResponse` 등)이 읽고 있어 함께 고치지 않으면 깨진다. `POST` 저장 시 새 테이블과 함께 갱신하는 **이중 기록**으로 두고, 읽는 쪽을 모두 옮긴 뒤 별도 Migration에서 제거한다.

### 2.8 서버 코드 변경 지점

| 파일 | 변경 |
| --- | --- |
| `DrawingReflectionService.java:79` | `deleteAllByDrawingSessionId` → **시점 범위로 축소**(`deleteAllByDrawingSessionIdAndCheckpoint`). 안 고치면 `POST` 저장이 `PRE`를 지운다 |
| `DrawingSessionEmotionRepository.java:44` | 위 메서드 추가 |
| `DrawingSession.canSaveReflection()` (`:200-204`) | 현재 `CONVERSING`·`REFLECTION`만 허용. **`PRE`는 `DRAWING`에서 호출되므로 시점별 분기 필요** |
| `DrawingSession.saveReflection()` (`:232-238`) | 현재 무조건 `currentStage = REFLECTION`. `PRE`는 단계를 바꾸지 않아야 한다 |
| `SaveDrawingReflectionRequest` | `checkpoint` 필드 추가(기본 `POST`), `PRE`일 때 `title` 금지 검증 |

`canSaveReflection()`과 `saveReflection()`이 **단계 전환을 도메인 안에 하드코딩**하고 있다는 점이 핵심이다. 시점 개념은 서비스가 아니라 이 두 메서드까지 내려가야 한다.

---

## 3. 변경 3 — 도구·이벤트 코드 목록 고정 (계약 변경 아님)

서버는 이미 새 코드를 받는다.

```java
// StrokeEventRequest.java:28-39
@NotBlank @Size(max=30) @Pattern(regexp="[A-Z][A-Z0-9_]*") String eventType,
@Size(max=30)           @Pattern(regexp="[A-Z][A-Z0-9_]*") String tool,
@Pattern(regexp="^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")      String color,
```
```sql
-- V3__normalize_json_columns.sql:183-184
event_type VARCHAR(30) NOT NULL,  tool VARCHAR(30) NULL
```

CHECK 제약도 없다. **필요한 것은 코드 승인이 아니라 목록 합의**다. 합의 없이 FE가 임의 문자열을 보내면 `tool_change_count`·색상 통계가 집계 불가능해진다.

§10.5에 부록 표로 등재를 제안한다.

#### `tool` 허용값

| 표시 | 코드 | 사용 활동 |
| --- | --- | --- |
| 연필 | `PENCIL` | 그림일기 |
| 볼펜 | `PEN` | 그림일기, **HTP(검정 고정)** |
| 크레용 | `CRAYON` | 그림일기 |
| 붓 | `BRUSH` | 그림일기 |
| 색연필 | `COLORED_PENCIL` | 그림일기 |
| 지우개 | `ERASER` | 전부 |

볼펜에 신규 코드를 만들지 않고 기존 `PEN`을 재사용한다 — §10.5 예시가 이미 `"tool": "PEN"`이고, 새 코드를 파면 같은 도구가 두 갈래가 된다.

#### `eventType` 허용값

| 코드 | 의미 | `points` | `tool`/`color`/`width` |
| --- | --- | --- | --- |
| `STROKE` | 획 | 좌표 목록 | 값 있음 |
| `ERASE` | 영역 지우기 | 좌표 목록 | `tool=ERASER`, `width`=지우개 크기 |
| `CLEAR_ALL` | 전체 지우기 | **`[]`** | 전부 `null` |
| `UNDO` | 되돌리기 | **`[]`** | 전부 `null` |

- `points`는 `@NotNull`이라 좌표가 없는 이벤트도 `[]`를 실어야 한다. 생략하면 `400`이다.
- `UNDO`는 `metrics.undoCountDelta`에도 반영한다(기존 필드).
- **되돌리기가 `sequence`를 되감지 않는다.** 취소는 "취소 이벤트 추가"로 기록한다. 되감으면 `STROKE_SEQUENCE_GAP` 검증과 `batchSequence` 멱등성이 깨진다.

---

## 4. 변경 4 — `width` 단위 = **Flutter 논리 픽셀** (확정)

§10.5 예시는 `"width": 8.0`인데 단위가 정본에 적혀 있지 않다. 같은 절에서 `x`·`y`는 `0~1` 정규화라고 명시하므로 읽는 사람마다 해석이 갈릴 수 있다. **확인 결과 팀 정책은 이미 정해져 있었고, 명세에 옮겨 적히지 않았을 뿐이다.**

### 4.1 근거

```dart
// drawing_event_journal.dart:156-158
// Team policy uses the same Flutter logical pixel value as Paint.strokeWidth.
// TODO(API): Document logical pixels as the final backend unit.
thickness: includeStyle ? stroke.thickness : null,
```

FE 코드에 **이 문서화를 요청하는 TODO가 이미 달려 있다.**

전송 경로도 확인했다.

| 단계 | 값 | 근거 |
| --- | --- | --- |
| 캔버스 | `Paint.strokeWidth` (Flutter 논리 픽셀) | `drawing_event_journal.dart:156` |
| 저널 | `StrokeEventDto.thickness` | `:158` |
| 배치 변환 | `StrokeBatchEventDto(width: start.thickness)` | `drawing_sync_coordinator.dart:331` |
| 전송 JSON | `"width"` | `drawing_dtos.dart:315` |
| 서버 수신 | `StrokeEventRequest.width` (`BigDecimal`, `> 0`) | `StrokeEventRequest.java:40-41` |
| 저장 | `stroke_events.width DECIMAL(8,3)` | `V3:186` |

**DDL이 결정적이다.** 좌표는 `DECIMAL(8,6)`(정수부 2자리·소수 6자리 = 0~1 정규화용)인데 `width`는 `DECIMAL(8,3)`(정수부 5자리)다. 정규화 값이라면 정수부 5자리가 필요 없다. 픽셀 값을 담도록 설계된 컬럼이다.

### 4.2 제안: §10.5에 한 문장 추가

> `width`는 클라이언트의 논리 픽셀 값이다(Flutter `Paint.strokeWidth`와 동일). `x`·`y`와 달리 정규화하지 않는다.

**해석을 바꾸는 것이 아니라 현행을 적는 것이므로 Breaking이 아니다.** 저장된 데이터도 그대로 유효하다.

### 4.3 그래서 지우개 크기를 확정할 수 있다

논리 픽셀이므로 기획(§5.1)의 값을 그대로 쓴다 — 버튼 프리셋 `8` / `24` / `56`, 슬라이더 `4~80`. 기기 물리 해상도가 달라도 Flutter 논리 픽셀은 기기 독립적이라 같은 굵기로 보인다.

`DECIMAL(8,3)`이므로 소수 3자리까지 저장된다. 슬라이더가 연속값을 만들어도 잘리지 않는다.

### 4.4 겸사겸사 확인한 것 — 필압은 좌표별로 저장된다

펜 5종 중 연필·붓·색연필이 필압을 쓰므로 확인했다. 정본 §10.5 예시는 `pressure`를 이벤트 레벨에 두지만, **실제 구현은 좌표별로도 받는다.**

| 위치 | 필드 | 근거 |
| --- | --- | --- |
| 이벤트 레벨 | `StrokeEventRequest.pressure` | `StrokeEventRequest.java:42` |
| 좌표 레벨 | `StrokePointRequest.pressure` | `StrokePointRequest.java:30-31` |
| DB | `stroke_events.pressure DECIMAL(6,5)` + `stroke_event_points.pressure DECIMAL(6,5)` | `V3:187`, `V3:206` |
| FE 전송 | `StrokePointDto.pressure` (좌표별) | `drawing_dtos.dart:290` |

FE는 좌표별로 보내고 서버·DB가 그것을 받는다. **붓처럼 한 획 안에서 굵기가 변하는 도구를 표현할 재료가 이미 있다.** 정본 §10.5 예시에 좌표별 `pressure`가 빠져 있으므로 예시 보강을 함께 제안한다(계약 변경 아님, 예시 누락).

---

## 5. 배포 순서

계약 변경 2건은 서로 독립이라 따로 나갈 수 있다.

| 순서 | 작업 | 선행 조건 |
| --- | --- | --- |
| 1 | 3번(코드 목록) 명세 부록 등재 | 없음 — 즉시 가능 |
| 2 | 4번 `width` 단위 명시 + `pressure` 예시 보강 | 없음 — 확인 완료, 즉시 가능 |
| 3 | 1번 Migration(`concurrent_conversation`) + 서버 조건 완화 | 정본 §10.1·§12.2 확정 |
| 4 | 1번 DRAWING-01 응답 필드 추가 → FE 반영 | 3 |
| 5 | 2번 Migration(§2.7 4단계) | 정본 §10.9 확정 |
| 6 | 2번 서버 코드 5개 지점 변경(§2.8) + DRAWING-10 확장 | 5 |
| 7 | 2번 조회 응답 `emotionCheckpoints` 추가 → FE 반영 | 6 |
| 8 | 리포트 조회 계층을 새 테이블로 이전 | 7 |
| 9 | `drawing_sessions.expressed_emotion_text` 제거 (별도 Migration) | 8 |

**1번과 2번 모두 서버가 먼저 나가도 기존 FE가 깨지지 않는다.** 신규 필드는 전부 선택이고 기본값이 현행 동작이다.

**작업량은 1번 ≪ 2번이다.** 1번은 컬럼 하나 + 조건문 완화지만, 2번은 UNIQUE 제약 2개 교체 + 신규 테이블 + backfill + 도메인 메서드 2개 수정 + 이중 기록 정리까지 간다. **Jira 이슈를 나눠야 한다.**

---

## 6. 미해결

| # | 항목 | 필요한 것 |
| --- | --- | --- |
| ~~1~~ | ~~감정 저장 실제 스키마~~ | **해결(2026-07-27).** `drawing_session_emotions` 별도 테이블이나 UNIQUE 2개·세션 컬럼·미저장 `skipped`·전체 삭제 로직이 걸린다 — §2.6~§2.8 참조 |
| ~~2~~ | ~~`width` 단위~~ | **해결(2026-07-27).** Flutter 논리 픽셀. FE 코드 주석·전송 경로·`DECIMAL(8,3)` DDL로 확인 — §4 |
| 3 | 오류 코드 일련번호 | 구현 시점 `DrawingErrorCode` 최대값 재확인(§2.5) |
| 4 | `emotionCheckpoints` 리포트 노출 범위 | 보호자용에 두 시점 모두 노출할지, 전문가용만인지 — §13.4 검토 필요 |
| 5 | 아이 주도 발화([이야기하기]) | 기존 CONV-03으로 커버되는지, `triggerReason=USER_REQUEST` 전달 경로가 있는지 확인 |
| 6 | `expressed_emotion_text` 읽는 지점 전수 | §2.7 (4)의 이중 기록을 언제 끝낼지 정하려면 리포트·조회 계층에서 이 컬럼을 읽는 곳을 모두 찾아야 한다 |

---

**이 문서는 로컬 초안이며 계약 정본을 수정하지 않았다.** 정본 반영은 명세 담당자와 팀 결정 사항이다.
