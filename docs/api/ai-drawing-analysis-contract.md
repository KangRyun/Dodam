# AI 그림 분석 요청·응답 계약

> Jira: `S15P11B209-144`
> 범위: Spring Boot와 AI 서버 사이의 그림 객체 탐지 JSON 계약

이 문서는 내부 AI 연동에서 사용할 값 구조만 정의한다. 현재 실제 AI 서버 호출과 외부 공개 Endpoint는 구현되어 있지 않다.

## 요청

```json
{
  "requestId": "550e8400-e29b-41d4-a716-446655440000",
  "drawingSessionId": 100,
  "drawingAssetId": 200,
  "imageReference": {
    "storageKey": "drawings/2026/07/22/example.png",
    "contentType": "image/png"
  },
  "analysisType": "OBJECT_DETECTION"
}
```

| 필드 | 필수 | 규칙 |
| --- | --- | --- |
| `requestId` | O | 비어 있지 않은 호출 추적 식별자 |
| `drawingSessionId` | O | 1 이상의 그림 활동 세션 ID |
| `drawingAssetId` | O | 1 이상의 그림 파일 Metadata ID |
| `imageReference.storageKey` | O | 내부 저장소의 안전한 상대 Key. 절대 경로와 `..` 경로 이동 금지 |
| `imageReference.contentType` | O | `image/png` 또는 `image/jpeg` |
| `analysisType` | O | 현재 `OBJECT_DETECTION`만 지원 |

`storageKey`는 공개 URL이나 서버 파일 경로가 아닌 불투명 식별자다. AI 서버에 이미지 Byte를 전달하거나 Key를 해석하는 방식은 AI Client 구현 시 별도로 결정한다.

## 성공 응답

```json
{
  "requestId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "SUCCEEDED",
  "model": {
    "name": "yolo-model",
    "version": "1.0"
  },
  "detections": [
    {
      "label": "HOUSE",
      "confidence": 0.93,
      "boundingBox": {
        "x": 120.0,
        "y": 80.0,
        "width": 640.0,
        "height": 520.0
      }
    }
  ],
  "error": null,
  "processedAt": "2026-07-22T05:00:00Z"
}
```

탐지된 객체가 없는 정상 결과는 `detections: []`로 표현한다. `null`로 대체하지 않는다.

## 실패 응답

```json
{
  "requestId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "FAILED",
  "model": null,
  "detections": [],
  "error": {
    "code": "AI_ANALYSIS_FAILED",
    "message": "그림 분석을 완료하지 못했습니다."
  },
  "processedAt": "2026-07-22T05:00:00Z"
}
```

`error`에는 호출자가 분기할 수 있는 코드와 안전한 메시지만 포함한다. Stack Trace, 서버 경로, 내부 Exception 클래스와 Token은 포함하지 않는다.

## 응답 필드와 상태

| 필드 | 규칙 |
| --- | --- |
| `requestId` | 요청의 `requestId`와 동일한 값 |
| `status` | `PENDING`, `PROCESSING`, `SUCCEEDED`, `FAILED` 중 하나 |
| `model` | `SUCCEEDED`에서 필수, 나머지 상태에서 `null` |
| `detections` | 항상 배열. `SUCCEEDED`에서도 빈 배열 허용 |
| `error` | `FAILED`에서 필수, 나머지 상태에서 `null` |
| `processedAt` | `SUCCEEDED`·`FAILED`에서 ISO-8601 UTC 문자열, 진행 상태에서는 `null` |

`PENDING`과 `PROCESSING`에서는 `model`, `error`, `processedAt`이 `null`이고 `detections`는 빈 배열이어야 한다. Enum은 모두 `UPPER_SNAKE_CASE` 문자열로 직렬화하며 알 수 없는 Enum 값은 역직렬화 오류로 처리한다. 그 밖의 알 수 없는 JSON 필드는 현재 Spring Boot Jackson 기본 설정을 따른다.

## 탐지 결과 좌표와 신뢰도

- `label`: 객체 목록이 확정되기 전까지 비어 있지 않은 문자열을 사용한다.
- `confidence`: 0.0 이상 1.0 이하이며 양 끝값을 포함한다.
- `boundingBox.x`, `boundingBox.y`: 원본 이미지 좌측 상단을 원점으로 하는 0 이상의 픽셀 좌표다.
- `boundingBox.width`, `boundingBox.height`: 0보다 큰 픽셀 크기다.

대화 질문 생성 계약의 Bounding Box는 0~1 정규화 좌표이므로 이 계약의 픽셀 좌표 타입과 서로 대체할 수 없다.

## 개인정보와 Entity 경계

계약에는 `DrawingSession`과 `DrawingAsset` Entity를 포함하지 않고 ID만 사용한다. 아동 이름·생년월일, 보호자 정보, Token, 이미지 Byte와 Base64도 포함하지 않는다.

## 후속 이슈

- `S15P11B209-145`: AI HTTP Client와 실제 이미지 전달 방식
- `S15P11B209-146`: 외부 호출 없는 Mock 분석 결과
- `S15P11B209-147`: 분석 결과 저장 Application Service와 DB 연동

이번 범위에서는 Timeout, Retry, Circuit Breaker, Message Queue, 분석 저장, 그림 활동 상태 변경, 대화·감정·리포트 생성을 구현하지 않는다.
