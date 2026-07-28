# HTP 활동 계약 및 구현 기준

> 상태: 2026-07-28 출시 범위 기준 정본
> 관련 이슈: `S15P11B209-659`
> 적용 범위: Flutter ↔ Spring Boot ↔ AI 서버 ↔ DB
> 주의: 도담의 HTP 기능은 의료 진단이나 심리검사 판정을 제공하지 않는다. 그림과 대화를 바탕으로 관찰 자료 초안을 만들고 전문가 검토가 필요한 정보를 정리한다.

## 1. 출시 범위

이번 출시에서 HTP 활동은 집·나무·사람을 각각 한 장씩 그리는 **3단계 활동**으로 고정한다.

| 순서 | 화면 표시명 | 계약 코드 | AI 주제 |
| --- | --- | --- | --- |
| 1 | 집 | `HOUSE` | `HOUSE` |
| 2 | 나무 | `TREE` | `TREE` |
| 3 | 사람 | `PERSON` | `PERSON` |

- 남자 사람과 여자 사람을 별도 단계나 별도 AI 유형으로 나누지 않는다.
- 성별은 그림으로 추정하지 않는다.
- `HOUSE`, `TREE`, `PERSON`은 화면 순서나 파일명에서 추론하지 않고 영속화된 단계 정보로 전달한다.
- HTP와 그림일기는 서로 다른 활동이다. HTP 분석에 그림일기 모델을 사용하거나 그 반대로 라우팅하지 않는다.

기존 문서의 사람 성별을 분리한 4단계 안은 폐기한다. 현재 제품 범위와 AI의 실제 주제 분류 축이 모두 3종이므로 4단계를 유지하면 같은 `PERSON` 모델에 의미 없는 성별 단계를 중복 전달하게 된다.

## 2. 활동 유형 기준

HTP 기준 데이터는 다음 값으로 추가한다.

| 항목 | 값 |
| --- | --- |
| `drawing_types.code` | `HTP` |
| `drawing_types.name` | `집·나무·사람 그리기` |
| `activity_category` | `ASSESSMENT` |
| `selectable_by` | `GUARDIAN` |
| 권장 연령 | 만 4세 이상, 서비스의 아동 최대 연령 정책 이하 |
| 활성화 조건 | HTP 묶음 API·주제 저장·AI 라우팅이 모두 배포된 뒤 활성화 |

HTP를 단일 `drawingSession`으로 표현하지 않는다. 현재 그림 세션은 최종 그림 한 장을 소유하므로, HTP 활동 한 건은 HTP 묶음과 세 개의 그림 세션으로 구성한다.

```text
HtpAssessment
├─ HOUSE  → DrawingSession 1
├─ TREE   → DrawingSession 2
└─ PERSON → DrawingSession 3
```

같은 아동에게 진행 중인 HTP 묶음은 하나만 허용한다. 진행 중인 일반 그림 활동이 있으면 HTP를 새로 시작하지 않고 기존 활동의 재개 또는 종료를 먼저 안내한다.

## 3. 상태와 진행 순서

### 3.1 HTP 묶음 상태

`IN_PROGRESS`, `ANALYZING`, `COMPLETED`, `ABANDONED`, `EXPIRED`를 사용한다.

### 3.2 단계 상태

각 단계는 기존 `DrawingSession` 상태와 단계를 재사용한다. 한 단계의 기본 흐름은 다음과 같다.

```text
DRAWING
→ 그림 단계 완료 및 주제별 객체 탐지
→ CONVERSING
→ 대화 종료
→ REFLECTION 건너뛰기
→ HTP 단계 완료 처리
```

HTP 단계에서는 일반 활동의 `POST /drawing-sessions/{id}/complete`를 호출하지 않는다. 현재 일반 활동 완료 계약은 단계마다 리포트 생성을 요구하므로 그대로 사용하면 HTP 리포트가 세 개 생긴다. HTP Application Service가 Reflection 건너뛰기와 대화 종료를 검증한 뒤 단계 세션만 완료하고, 세 단계가 모두 끝났을 때 HTP 묶음 리포트 하나를 생성한다.

각 그림은 기존 `POST /internal/v1/analyses`로 한 번씩 분석한다. HTP 완료 시 새 다중 이미지 추론 API를 호출하지 않고, 주제별 저장 분석 결과와 대화를 묶어 하나의 활동 리포트를 조립한다. 출시 범위에서 근거 없는 그림 간 심리 해석을 추가하지 않는다.

### 3.3 확정된 진행 정책

- 순서는 `HOUSE → TREE → PERSON`으로 고정한다.
- 완료되지 않은 단계가 있으면 다음 단계 세션을 생성하지 않는다.
- 그림을 그리는 중에는 AI 대화를 시작하지 않는다.
- 그림 한 장을 완료한 뒤 해당 그림에 대한 질문을 최대 2개 제공한다.
- 대화는 건너뛸 수 있다. 건너뛴 사실은 분석의 `unusedInputs` 또는 대화 집계에 남긴다.
- 그림별 제목과 감정은 받지 않는다.
- 세 장을 모두 마친 뒤 활동 단위 감정을 1회 받을 수 있으며 건너뛰기도 허용한다.
- 진행 중 활동은 24시간 동안 재개할 수 있다. 24시간을 넘기면 새 분석에 사용하지 않고 `EXPIRED`로 정리한다.

기존 초안의 7일 유효기간은 폐기한다. HTP 자료를 한 시점의 관찰 자료로 묶는다는 전제와 맞지 않고, 출시 초기에는 장기 재개보다 데이터 일관성이 우선이다.

## 4. 공개 API 계약

기존 그림 API를 단계 내부에서 재사용하고, HTP 묶음을 관리하는 API만 추가한다.

| 기능 | Method | URI |
| --- | --- | --- |
| HTP 시작 | POST | `/api/v1/htp-assessments` |
| HTP 진행 상태 조회 | GET | `/api/v1/htp-assessments/{htpAssessmentId}` |
| 현재 단계 완료 및 다음 단계 생성 | POST | `/api/v1/htp-assessments/{htpAssessmentId}/steps/next` |
| 활동 단위 감정 저장 | PUT | `/api/v1/htp-assessments/{htpAssessmentId}/reflection` |
| HTP 완료 접수 | POST | `/api/v1/htp-assessments/{htpAssessmentId}/complete` |
| HTP 포기 | POST | `/api/v1/htp-assessments/{htpAssessmentId}/abandon` |

상태를 변경하는 POST 요청은 `Idempotency-Key`를 필수로 사용한다. 같은 Key와 같은 요청은 최초 결과를 반환하고, 같은 Key에 다른 요청 Body가 들어오면 `409`로 거부한다.

`steps/next`는 직전 단계의 FINAL 이미지, 분석 결과, 대화 종료 여부를 검증하고 직전 세션을 리포트 없이 완료한 뒤 다음 세션을 생성한다. 마지막 `PERSON` 단계에서는 다음 세션을 만들지 않고 단계 완료 결과만 반환한다. `complete`는 세 단계가 모두 끝났는지 확인한 뒤 기존 주제별 분석을 집계하고 HTP 리포트 하나만 접수한다.

### 4.1 단계 응답

클라이언트가 AI 주제를 임의로 정하지 않도록 서버가 현재 단계의 주제를 반환한다.

```json
{
  "htpAssessmentId": 41,
  "status": "IN_PROGRESS",
  "currentStep": {
    "stepOrder": 1,
    "drawingSubject": "HOUSE",
    "drawingSessionId": 100,
    "sessionStatus": "IN_PROGRESS",
    "currentStage": "DRAWING"
  }
}
```

- `drawingSubject`는 `HOUSE`, `TREE`, `PERSON` 중 하나다.
- `drawingSessionId`와 `drawingSubject`의 연결은 생성 후 변경할 수 없다.
- 이미지 업로드·그림 완료 요청에서 주제를 다시 받지 않는다. 서버는 단계 연결을 기준으로 주제를 확정한다.

## 5. BE → AI 내부 계약

현재 `POST /internal/v1/analyses` 요청에는 활동과 HTP 주제가 없다. HTP를 지원하기 전에 다음 두 필드를 추가한다.

```json
{
  "analysisId": 701,
  "drawingSessionId": 100,
  "activityType": "HTP",
  "drawingSubject": "HOUSE",
  "analysisType": "FINAL",
  "drawing": {
    "drawingAssetId": 502,
    "signedUrl": "http://backend:8080/internal/v1/ai-images/opaque-token",
    "mimeType": "image/png",
    "width": 1920,
    "height": 1080,
    "checksumSha256": "..."
  }
}
```

### 5.1 필드 규칙

| 필드 | 규칙 |
| --- | --- |
| `activityType` | HTP 단계 분석은 반드시 `HTP` |
| `drawingSubject` | HTP이면 필수이며 `HOUSE`, `TREE`, `PERSON`만 허용 |
| `analysisType` | 중간 분석은 `INTERMEDIATE`, 단계 완료 분석은 `FINAL` |
| `drawing.width/height` | 저장된 실제 이미지 크기 |
| `drawing.signedUrl` | 짧은 만료시간의 내부 읽기 전용 URL |

BE는 FE가 보낸 값이나 단계 순서를 그대로 신뢰하지 않는다. `drawingSessionId`가 연결된 HTP 단계의 영속화 값으로 `activityType`과 `drawingSubject`를 조립한다.

### 5.2 AI 모델 라우팅과 후처리

- `activityType=HTP`이면 `htp_best.pt`를 사용한다.
- `drawingSubject`는 모델 선택 이후 주제별 품질 검증과 교차 주제 오탐 제거에 사용한다.
- `HOUSE` 그림에서는 집 전체와 집 부위를, `TREE` 그림에서는 나무 전체와 나무 부위를, `PERSON` 그림에서는 사람 전체와 사람 부위를 우선 검증한다.
- 배경 객체는 주제와 별도로 유지할 수 있다.
- 탐지 응답의 `objectCode`는 기존 47개 세부 라벨 매핑을 유지한다. `drawingSubject`를 이유로 결과를 `HOUSE/TREE/PERSON` 세 개로 축약하지 않는다.
- Bounding Box는 0~1 정규화 좌표로 반환한다.
- AI가 주제를 발견하지 못해도 다른 주제로 자동 변경하지 않는다. 경고와 품질 상태를 반환한다.

## 6. 저장 모델

`drawing_assets.object_code`는 다중 객체 업로드 식별 목적으로 추가된 nullable 문자열이며 현재 생성 경로에서 채워지지 않는다. 이를 HTP 단계 주제의 정본으로 재사용하지 않는다.

HTP 전용 테이블을 다음처럼 둔다.

### 6.1 `htp_assessments`

| 컬럼 | 역할 |
| --- | --- |
| `id` | HTP 묶음 ID |
| `child_id` | 대상 아동 |
| `drawing_type_id` | `HTP` 유형 |
| `status` | 묶음 상태 |
| `current_step_order` | 현재 단계 1~3 |
| `expires_at` | 재개 만료 시각 |
| `created_at`, `completed_at` | 생성·완료 시각 |

진행 중 묶음의 유일성은 Service 잠금과 DB 제약 또는 동등한 원자적 생성 절차로 함께 방어한다.

### 6.2 `htp_assessment_steps`

| 컬럼 | 역할 |
| --- | --- |
| `id` | 단계 ID |
| `htp_assessment_id` | HTP 묶음 FK |
| `step_order` | 1~3 |
| `drawing_subject` | `HOUSE`, `TREE`, `PERSON` |
| `drawing_session_id` | 기존 그림 세션 FK |
| `subject_detected` | 기대 주제 전체 객체 탐지 여부 |
| `retry_count` | 품질 재시도 횟수 |

필수 제약:

- `UNIQUE (htp_assessment_id, step_order)`
- `UNIQUE (htp_assessment_id, drawing_subject)`
- `UNIQUE (drawing_session_id)`
- `CHECK (step_order BETWEEN 1 AND 3)`
- `CHECK (drawing_subject IN ('HOUSE', 'TREE', 'PERSON'))`

## 7. 품질 실패와 재시도

- 기대 주제의 전체 객체가 탐지되지 않으면 1회만 다시 그리기를 제안한다.
- 두 번째 결과도 미탐지이면 활동을 막지 않고 `subjectDetected=false`와 경고를 저장한다.
- 이미지 디코딩 실패, 빈 파일, 지원하지 않는 MIME Type은 재업로드가 필요한 요청 오류로 처리한다.
- AI 장애는 그림 저장을 되돌리지 않는다. 분석을 실패 상태로 저장하고 같은 원본으로 재시도한다.
- HTP 완료는 세 단계의 최종 이미지가 모두 저장됐을 때만 허용한다.

기존 초안의 주제별 2회 재시도는 폐기한다. 최대 6장의 추가 그림을 요구할 수 있어 아동 피로가 크고, 현재 모델의 주제 전체 탐지율을 고려하면 1회 재시도로 충분하다.

## 8. 리포트와 안전 규칙

- 세 단계 결과를 하나의 HTP 활동 리포트로 묶는다.
- 단계별 일반 활동 리포트는 생성하지 않는다.
- 보호자 화면에는 관찰한 객체와 아동의 실제 발화를 중심으로 표시한다.
- 진단명, 성격 단정, 질환 가능성, 가정환경 원인 추정, 사람 성별 추정은 표시하지 않는다.
- 전문가용 자료에도 AI 결과는 `AI_DRAFT`로 표시하고 모델·프롬프트·가중치 버전을 남긴다.
- 정량 특징은 객체 크기·배치·탐지된 부위처럼 재현 가능한 값만 제공한다.

## 9. 확정된 사안

| 사안 | 결정 |
| --- | --- |
| HTP 그림 수 | 3장 |
| 주제 | `HOUSE`, `TREE`, `PERSON` |
| 사람 성별 분리 | 하지 않음 |
| 주제 전달 방식 | BE가 단계 저장값으로 AI 요청에 명시 |
| 주제 저장 위치 | `htp_assessment_steps.drawing_subject` |
| 그림 중 대화 | 사용하지 않음 |
| 그림별 대화 | 완료 직후 최대 2개 |
| 그림별 감정·제목 | 받지 않음 |
| 활동 단위 감정 | 종료 시 1회, 건너뛰기 허용 |
| 유효기간 | 생성 후 24시간 |
| 품질 재시도 | 주제별 최대 1회 |
| 정량 특징 계산 | AI 서버 |
| 탐지 라벨 | 47개 세부 라벨 유지 |

## 10. 남은 구현 항목

다음은 정책 미결정이 아니라 이 문서대로 구현해야 하는 작업이다.

1. `HTP` 기준 데이터와 HTP 묶음·단계 Flyway Migration 추가
2. HTP 묶음 API와 상태 전이 구현
3. 세 단계 저장 분석 결과 집계와 단일 리포트 연결
4. HTP API·AI 계약·DB 제약·재개·멱등성 통합 테스트

위 여섯 항목이 모두 배포되기 전에는 `HTP` 유형을 활성화하지 않는다.
