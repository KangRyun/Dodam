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

## Spring Boot AI Client

`S15P11B209-145`에서 다음 동기식 Client 경계를 제공한다.

```java
public interface DrawingAnalysisClient {
    DrawingAnalysisResponse analyze(DrawingAnalysisRequest request);
}
```

- HTTP 구현체: `RestClientDrawingAnalysisClient`
- HTTP Client: Spring `RestClient`
- Method/Endpoint: `POST /internal/ai/v1/drawings/analysis`
- Request/Response: 이 문서의 144번 계약 DTO를 그대로 사용
- 인증 Header: 현재 추가하지 않음
- 자동 Retry, Circuit Breaker, Fallback: 구현하지 않음

### 설정 환경 변수

| 환경 변수 | 기본값 | 용도 |
| --- | --- | --- |
| `AI_DRAWING_ANALYSIS_MODE` | `mock` | 사용할 Client 구현. `mock` 또는 `http` |
| `AI_DRAWING_ANALYSIS_BASE_URL` | `http://localhost:8000` | 그림 분석 AI 서버 Base URL |
| `AI_DRAWING_ANALYSIS_ENDPOINT_PATH` | `/internal/ai/v1/drawings/analysis` | 그림 분석 내부 Endpoint Path |
| `AI_DRAWING_ANALYSIS_CONNECT_TIMEOUT` | `3s` | 연결 제한 시간 |
| `AI_DRAWING_ANALYSIS_READ_TIMEOUT` | `30s` | 응답 대기 제한 시간 |

Base URL은 Query와 Fragment가 없는 HTTP 또는 HTTPS 절대 URI여야 한다. Endpoint Path는 `/` 하나로 시작해야 하며 Timeout은 0보다 커야 한다. Client Bean 생성 시 AI 서버 연결을 시도하지 않으므로 서버가 꺼져 있어도 Application Context를 시작할 수 있다.

### Client 오류 매핑

| 상황 | `DrawingAnalysisClientException.Type` |
| --- | --- |
| 요청 Validation 실패, AI 서버 3xx·4xx, 일반 연결 실패 | `REQUEST_FAILED` |
| Connect 또는 Read Timeout | `TIMEOUT` |
| 빈 Body, JSON·Enum 오류, 응답 계약 위반 | `INVALID_RESPONSE` |
| AI 서버 5xx | `SERVER_ERROR` |

HTTP 2xx의 유효한 `status=FAILED` 응답은 통신 실패가 아니므로 Exception으로 변환하지 않는다. 응답 `requestId`가 요청 값과 다르면 다른 호출의 결과로 판단해 `INVALID_RESPONSE`로 처리한다. Client는 전체 Request/Response, Storage Key, 서버 URL, AI 오류 원문을 로그나 Exception 메시지에 기록하지 않는다.

### 현재 연동 제한

현재 실제 FastAPI 서버와의 정상 동작은 검증하지 않았으며 HTTP Client 테스트는 `MockRestServiceServer`만 사용한다. `storageKey`는 계약대로 전달되지만 AI 서버가 Backend의 로컬 Storage를 공유하지 않으면 이미지 파일을 읽을 수 없다. Client에서 절대 경로, Base64, URL 또는 multipart로 임의 변환하지 않으며 실제 이미지 접근 방식은 배포 Architecture에서 별도로 해결해야 한다.

## Mock 그림 분석 Client

`S15P11B209-146`에서는 실제 AI 서버가 없는 개발 환경에서 후속 흐름을 확인할 수 있도록 `MockDrawingAnalysisClient`를 제공한다. 기본 mode는 `mock`이며 다음 환경 변수로 명시할 수 있다.

```dotenv
AI_DRAWING_ANALYSIS_MODE=mock
```

Mock mode에서는 HTTP 전용 `RestClient`와 `RestClientDrawingAnalysisClient`가 생성되지 않으며 실제 AI 서버로 네트워크 요청을 전송하지 않는다. HTTP 연동을 사용할 환경에서는 다음과 같이 전환한다.

```dotenv
AI_DRAWING_ANALYSIS_MODE=http
```

허용되지 않은 mode 값은 Application Context 시작 시 설정 오류로 처리한다. `mock`과 `http` 구현체는 동시에 `DrawingAnalysisClient` Bean으로 등록되지 않는다.

### 고정 Mock 결과

- 상태: `SUCCEEDED`
- 모델: `mock-drawing-detector`, 버전 `1.0`
- 탐지 Label: `HOUSE`, `TREE`
- Confidence: 각각 `0.95`, `0.91`
- Bounding Box: 각각 `(120, 80, 640, 520)`, `(820, 120, 380, 700)`
- `requestId`: 요청 값을 그대로 반환
- `processedAt`: Spring의 UTC `Clock`을 기준으로 생성
- `error`: `null`

탐지 목록과 수치는 모든 정상 요청에 동일한 결정적 Fixture로 반환된다. Bounding Box는 계약상 픽셀 좌표 형식을 따르지만 실제 요청 이미지의 크기나 내용을 반영하지 않는다. 이 결과는 개발·계약 검증용이며 실제 객체 탐지 성능, 분석 정확도 또는 아동 심리 분석 결과를 의미하지 않는다.
