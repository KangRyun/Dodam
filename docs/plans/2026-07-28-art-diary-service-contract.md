# 그림일기 활동 계약 및 구현 기준

> 상태: 2026-07-28 출시 범위 기준 정본
> 관련 이슈: `S15P11B209-659`
> 활동 코드: `ART_DIARY`
> 적용 범위: Flutter ↔ Spring Boot ↔ AI 서버 ↔ DB

## 1. 출시 범위

그림일기는 아동이 한 장의 그림을 완성하고, 그림에 대해 대화한 뒤 제목과 감정을 남기는 일반 활동이다.

| 항목 | 값 |
| --- | --- |
| `drawing_types.code` | `ART_DIARY` |
| `drawing_types.name` | `그림 일기` |
| `activity_category` | `GENERAL` |
| `selectable_by` | `BOTH` |
| 그림 수 | 1장 |
| 입력 방식 | `CANVAS`, `UPLOAD` |
| HTP 주제 | 사용하지 않음 |

이번 출시의 활동 선택 화면에는 `ART_DIARY`와 구현이 완료된 `HTP`만 노출한다. 기존 시드의 `FREE_DRAWING`, `EMOTION_COLORING`, `WEATHER_MIND`는 삭제하지 않고 비활성화한다. 과거 데이터의 참조 무결성을 유지하기 위해 기존 코드를 다른 의미로 재사용하지 않는다.

## 2. 확정된 사용자 흐름

현재 구현된 단계 모델을 유지한다.

```text
1. 그림 유형 조회
2. 진행 중 세션 확인
3. 그림일기 세션 생성
4. 획 배치 저장과 Draft 자동 저장
5. 그림 단계 완료 및 FINAL 이미지 저장
6. 객체 탐지 결과 확인
7. 그림에 대한 대화
8. 대화 종료
9. 제목·감정 저장
10. 활동 완료 접수
11. 종합 분석과 리포트 생성
```

호출 순서는 다음과 같다.

```text
GET  /api/v1/drawing-types?childId={childId}&activeOnly=true
GET  /api/v1/drawing-sessions/active?childId={childId}
POST /api/v1/drawing-sessions
POST /api/v1/drawing-sessions/{id}/stroke-batches
PUT  /api/v1/drawing-sessions/{id}/draft
POST /api/v1/drawing-sessions/{id}/drawing-complete
POST /api/v1/drawing-sessions/{id}/conversations
POST /api/v1/conversations/{conversationId}/next-question
POST /api/v1/conversations/{conversationId}/answers/voice|option
POST /api/v1/conversations/{conversationId}/end
PUT  /api/v1/drawing-sessions/{id}/reflection
POST /api/v1/drawing-sessions/{id}/complete
```

### 2.1 단계 복구

활성 세션이 있으면 새 세션을 만들지 않고 서버의 `currentStage`에 맞는 화면으로 이동한다.

| `currentStage` | 재개 화면 |
| --- | --- |
| `DRAWING` | 최신 Draft를 불러와 캔버스 복원 |
| `ANALYZING` | 분석 진행 화면 |
| `CONVERSING` | 기존 `conversationId`로 대화 재개 |
| `REFLECTION` | 제목·감정 입력 화면 |
| `REPORTING` | 완료 접수 화면 |

세션 생성이 `ACTIVE_DRAWING_SESSION_EXISTS`로 실패했을 때 새 활동을 덮어쓰거나 임의로 폐기하지 않는다.

## 3. 이번 출시에서 제외하는 확장

기존 초안에 있던 다음 항목은 이번 출시 계약에서 제외한다.

- 그리는 중 실시간 AI 대화
- 질문 중에도 `DRAWING` 단계를 유지하는 `concurrent_conversation` 속성
- 활동 시작 전·종료 후 감정 2회 기록
- AI가 발화를 재작성해 일기 본문을 생성하는 기능
- 과거 날짜를 지정하는 별도 일기 날짜 필드

이 항목들은 현재 DB·상태 전이·API와 일치하지 않는다. 특히 대화 시작 후 세션이 `CONVERSING`으로 전환되므로 동시에 획과 Draft를 저장하는 흐름은 기존 검증과 충돌한다. 출시 범위에서는 그림을 완료한 뒤 대화를 시작해 이 충돌을 없앤다.

## 4. 세션과 저장 계약

### 4.1 세션 생성

- 선택한 `ART_DIARY`의 `drawingTypeId`를 전달한다.
- `childId`, `inputMethod`, `clientStartedAt`, `Idempotency-Key`를 기존 계약대로 사용한다.
- `canvas`는 선택 필드이며 임의의 1920×1080 값을 보내지 않는다.
- 실제 이미지 크기는 Draft와 FINAL 업로드 시 PNG/JPEG Header에서 추출해 `drawing_assets.width_px`, `height_px`에 저장한다.

### 4.2 획과 Draft

- 획은 `POST /stroke-batches`로 배치 전송한다.
- `width`는 Flutter 논리 픽셀 단위다.
- 좌표별 필압을 지원하지 않는 기기는 `pressure=null`, `pressureAvailable=false`로 유지한다.
- Draft는 마지막 전체 캔버스 이미지이며 새 버전이 이전 버전을 대체한다.
- 최신 Draft는 `assetVersion`이 가장 큰 유효 `DRAFT`다.
- Draft가 없으면 정상적인 빈 상태로 처리하고 새 캔버스를 표시한다.
- 이미지 조회는 인증이 적용된 Backend Proxy URL을 사용한다. Storage Key를 FE에 노출하지 않는다.

### 4.3 그림 단계 완료

`POST /drawing-sessions/{id}/drawing-complete`는 FINAL 이미지와 Metadata를 저장하고 객체 탐지를 요청한다.

- 성공 후 Flutter가 같은 FINAL 분석을 별도로 중복 요청하지 않는다.
- 그림 저장은 AI 장애와 분리한다. AI 호출이 실패해도 FINAL 자산을 삭제하지 않는다.
- 서버가 반환한 분석 ID와 상태를 기준으로 폴링한다.

### 4.4 대화와 활동 완료

- 질문은 그림 완료 후 최대 5개로 제한한다.
- 아이가 답하지 않으려면 대화를 종료할 수 있다.
- 대화 종료 후 세션 단위 Reflection 1회로 제목과 감정을 저장한다.
- 감정은 아동이 직접 선택한 값만 저장하며 AI가 감정을 추정해 채우지 않는다.
- 감정 선택을 건너뛰면 `skipped=true`, `selectedEmotions=[]`, `expressedEmotionText=null`을 사용한다.
- `POST /complete`는 `conversationSkipped`와 `requestReport=true`를 전달한다.
- `202 Accepted` 이후에는 완료 화면으로 이동할 수 있으며 리포트는 별도 상태 조회로 갱신한다.

## 5. BE → AI 내부 계약

그림일기 분석은 HTP와 다른 모델을 사용해야 하므로 공통 분석 요청에 활동 유형을 명시한다.

```json
{
  "analysisId": 801,
  "drawingSessionId": 200,
  "activityType": "ART_DIARY",
  "drawingSubject": null,
  "analysisType": "FINAL",
  "triggerReason": "ACTIVITY_COMPLETE",
  "drawing": {
    "drawingAssetId": 602,
    "signedUrl": "http://backend:8080/internal/v1/ai-images/opaque-token",
    "mimeType": "image/png",
    "width": 2048,
    "height": 1536,
    "checksumSha256": "..."
  }
}
```

| 필드 | 규칙 |
| --- | --- |
| `activityType` | `ART_DIARY` 필수 |
| `drawingSubject` | 보내지 않거나 `null`; HTP 주제 코드를 넣지 않음 |
| `analysisType` | 그림 단계 객체 탐지는 `FINAL`, 활동 완료 종합 분석도 저장된 FINAL 자산 사용 |
| `drawing.width/height` | 저장된 실제 이미지 크기 |

AI 라우팅은 다음처럼 고정한다.

- `ART_DIARY`는 `sketch` 모델을 사용한다.
- HTP 전용 47개 라벨 모델을 그림일기의 기본 탐지기로 사용하지 않는다.
- Sketch 모델이 준비되지 않았으면 HTP 모델로 조용히 대체하지 않고 `MODEL_NOT_READY` 또는 부분 성공으로 기록한다.
- 객체 탐지 결과와 대화·행동 입력을 구분해 저장한다.
- Bounding Box는 0~1 정규화 좌표로 반환한다.

현재 AI 코드에는 `sketch` 가중치 등록과 checksum 검증은 있지만 활동별 모델 라우팅은 아직 없다. `activityType` 계약과 라우팅 구현 전에는 실제 그림일기 객체 탐지가 준비됐다고 표시하지 않는다.

## 6. 도구와 캔버스 정책

이번 출시에서는 구현된 Flutter 도구와 서버 Enum의 교집합만 사용한다.

| 기능 | 계약 |
| --- | --- |
| 기본 펜 | `PEN` |
| 지우개 | 기존 지우개 이벤트와 `eraseCountDelta` 사용 |
| 되돌리기 | `UNDO` 이벤트와 `undoCountDelta`를 함께 저장 |
| 다시 실행 | FE가 제공할 때만 `REDO` 이벤트와 `redoCountDelta` 사용 |
| 색상 | `#RRGGBB` |
| 굵기 | Flutter 논리 픽셀 |

펜 5종, 12색 팔레트, 그라데이션 피커, 지우개 프리셋의 구체적인 UI 값은 FE 디자인 사양이다. API가 특정 팔레트나 버튼 크기를 강제하지 않는다.

## 7. 리포트와 안전 규칙

- 제목, 선택 감정, 아이의 실제 발화, 탐지된 객체와 행동 집계를 구분해 저장한다.
- AI 요약과 실제 발화를 같은 필드에 넣지 않는다.
- 대표 발화는 저장된 `messageId`를 함께 제공해 음성 재생 권한을 확인할 수 있게 한다.
- 보호자용 리포트는 진단형 표현과 전문가 전용 원시 특징을 노출하지 않는다.
- 그림일기 모델이 준비되지 않았거나 입력을 쓰지 못하면 `unusedInputs`와 `warnings`로 제한을 드러낸다.

## 8. 확정된 사안

| 사안 | 결정 |
| --- | --- |
| 그림 수 | 1장 |
| 그림 중 대화 | 이번 출시에서 사용하지 않음 |
| 대화 시작 | 그림 완료 후 |
| 감정 선택 | 종료 시 1회 |
| 제목 | 선택 입력 |
| HTP 주제 전달 | 하지 않음 |
| AI 모델 | `sketch` |
| Draft 복원 | 최신 유효 Draft |
| 이미지 크기 정본 | 업로드된 실제 이미지 Header 및 저장된 `width_px/height_px` |
| FINAL 분석 호출 | Backend가 그림 단계 완료·활동 완료 흐름에서 관리 |
| 비활성 활동 | 기존 행 유지, `is_active=false` |

## 9. 남은 구현 항목

다음은 정책 미결정이 아니라 이 문서대로 구현해야 하는 작업이다.

1. 출시 기준 데이터에서 `ART_DIARY`만 일반 활동으로 활성화하고 미출시 유형 비활성화
2. 공통 AI 요청에 `activityType`과 nullable `drawingSubject` 추가
3. AI 파이프라인에 `ART_DIARY → sketch` 라우팅 적용
4. Sketch 모델 부재·불일치 시 명시적 오류 또는 부분 성공 처리
5. 세션 생성부터 Draft 복원, 그림 완료, 대화, Reflection, 활동 완료까지 E2E 검증
6. 리포트의 대표 발화 `messageId`와 음성 재생 권한 계약 검증

위 구현이 끝나기 전에도 그림 저장·대화·리포트 기본 흐름은 사용할 수 있지만, 실제 그림일기 객체 탐지는 준비 완료로 표시하지 않는다.
