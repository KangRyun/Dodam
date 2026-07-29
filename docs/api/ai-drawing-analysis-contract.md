# AI 그림 분석 요청·응답 계약

> Jira: `S15P11B209-144`
> **정본: `docs/api/API_명세서_최종.md`** (S15P11B209-400)
> 범위: Spring Boot와 AI 서버 사이의 그림 객체 탐지 JSON 계약

이 문서는 Spring Boot와 AI 서버 사이의 값 구조 및 저장된 분석 상태를 조회하는 공개 API 계약을 정의한다.

## ⚠️ 정본과의 관계

이 문서는 **as-built 기록**이다. 계약의 정본은 `API_명세서_최종.md`이며, 아래 내용과 정본이 어긋나면 정본이 우선한다. 정본 §24.4에 따라 API 변경은 먼저 정본을 고친 뒤 FE·BE·AI가 함께 검토한다.

### 내부 BE↔AI 계약 — 대체됨

이 문서가 규정하던 `POST /internal/ai/v1/drawings/analysis`는 **AI 서버에 구현된 적이 없다.** 정본 §19를 따르는 `POST /internal/v1/analyses`가 이를 대신하며 구현·배포까지 완료됐다(S15P11B209-398). BE는 `AI_DRAWING_ANALYSIS_ENDPOINT_PATH`를 새 경로로 교체하고 응답 DTO를 §19.4 형태로 맞춰야 한다.

`S15P11B209-159`에서 Backend Client도 정본 §19.3·§19.4로 전환했다. `X-Internal-Token`과
`X-Request-Id`를 전송하고, 객체 탐지뿐 아니라 구성요소별 Model, 시각·행동 특징, 대화 요약,
관찰 초안, 미사용 입력, 경고와 근거를 정규화 Table에 저장한다. 기존 픽셀 Bounding Box는
`coordinate_space=PIXEL`, 새 종합 분석 결과는 `NORMALIZED`로 구분하며 대화 질문에는 정규화
결과만 전달한다.

주요 차이는 다음과 같다.

| 항목 | 이 문서(구) | 정본 §19 (현행) |
| --- | --- | --- |
| 경로 | `/internal/ai/v1/drawings/analysis` | `/internal/v1/analyses` |
| 분석 범위 | 객체 탐지만 | 객체·시각·행동·대화 종합 |
| 좌표계 | 픽셀 | **0~1 정규화** (대화 질문 계약과 동일) |
| 탐지 필드 | `detections[]{label, ...}` | `detectedObjects[]{objectCode, objectName, areaRatio, detectionOrder, ...}` |
| 모델 정보 | `model{name, version}` | `modelInfo{objectDetection, vision, language, knowledgeBaseVersion}` |
| 인증 헤더 | `X-Internal-Token` | `X-Internal-Api-Key` (전환 기간 동안 구 헤더도 함께 수용) |

좌표계 차이가 특히 중요하다. 픽셀 좌표는 이미 운영 중인 대화 질문 계약(0~1 정규화)과 호환되지 않아, 같은 서버가 같은 이름의 필드로 두 가지 좌표계를 내보내게 된다.

### Health — 정본 §19.8 준수

`GET /internal/v1/health`는 정본 §19.8 형태로 응답한다. 398에서는 축약형(`status: "ok"` + `objectDetectionReady`)이었으나 소비자가 생기기 전에 맞췄다(S15P11B209-400).

```json
{
  "status": "UP",
  "models": {
    "objectDetection": "READY",
    "vision": "READY",
    "language": "READY",
    "stt": "READY",
    "tts": "READY",
    "rag": "NOT_READY"
  },
  "knowledgeBaseVersion": null,
  "timestamp": "2026-07-24T04:30:00.000Z",
  "pipelineVersion": "0.1.0"
}
```

판정 근거는 구성요소마다 다르다. `objectDetection`은 가중치 파일 존재 여부, `vision`·`language`·`stt`·`tts`는 GMS 키 설정 여부(원격 모델이라 실제 호출로 확인하면 조회마다 비용이 든다), `rag`는 지식베이스 버전 설정 여부다. 정본이 정의한 값은 `READY`뿐이라 미준비는 `NOT_READY`로 표기한다. `pipelineVersion`은 정본에 없는 확장 필드로, 재현·재분석 추적용이다.

### 외부 공개 API — 미정합, 팀 결정 대기

아래 "공개 분석 상태 및 결과 조회"·"실패 분석 재시도"·"공개 분석 요청의 Asset 정책" 절은 **현재 구현을 기술한 것이며 정본 §11과 다르다.** 어느 쪽으로 통일할지는 팀 안건으로 남아 있다.

- 동기 `201` 즉시 완료 ↔ 정본은 비동기 `202` 접수 + 폴링(§3.6·§11.2)
- 조회 경로가 세션 하위 ↔ 정본은 `GET /analyses/{analysisId}`(§11.1)
- `SUCCEEDED` ↔ 정본 Enum은 `SUCCESS`(§4)
- 오류 코드 체계 `ANALYSIS_404_001` ↔ 정본은 의미 기반 코드명(§11.6)
- 보호자 응답에 `confidence` 포함 ↔ 정본은 raw score 비노출(§2.4·§27-7)

차이 전체와 이슈 분해는 노션 문서 「AI 분석 API 계약 불일치 — 정합화 안건 및 이슈 분해」에 정리돼 있다.

## 공개 분석 상태 및 결과 조회

```http
GET /api/v1/drawing-sessions/{drawingSessionId}/analyses/{drawingAnalysisId}
```

분석 요청 API가 반환한 `drawingAnalysisId`로 저장된 상태를 Polling한다. 조회 API는 모든 정상 상태에서 HTTP 200을 반환하며 DB에 저장된 결과만 사용한다. AI 서버를 다시 호출하거나 실패한 분석을 자동 재시도하지 않는다.

| 저장 상태 | 공개 상태 | 응답 정책 |
| --- | --- | --- |
| `PENDING` | `PENDING` | `model=null`, `detections=[]`, `processedAt=null`, `failure=null` |
| `PROCESSING` | `PROCESSING` | `model=null`, `detections=[]`, `processedAt=null`, `failure=null` |
| `SUCCESS` | `SUCCEEDED` | 저장된 Model, Detection과 완료 시각 반환 |
| `PARTIAL_SUCCESS` | `SUCCEEDED` | 사용 가능한 Model·Detection과 완료 시각 반환 |
| `FAILED` | `FAILED` | HTTP 200, `detections=[]`, 안전한 `failure` 반환 |

성공 분석에서 탐지된 객체가 없어도 `detections=[]`가 정상 응답이다. Detection은 저장된 `detection_order` 오름차순으로 반환한다. 다른 Session의 분석, 삭제된 Session의 분석 또는 존재하지 않는 분석은 동일한 404 응답으로 처리한다.

현재 `analyses`와 `analysis_detected_objects`에는 Soft Delete 컬럼이 없으며 `drawing_sessions.deleted_at`만 기존 조회 정책에 따라 제외한다. 그림 API 공통 인증이 도입되기 전까지 임시 사용자 Header나 사용자 ID를 사용하지 않는다.

## 실패 분석 재시도

```http
POST /api/v1/analyses/{analysisId}/retry
Idempotency-Key: analysis-retry-550e8400
```

```json
{
  "reason": "USER_REQUEST",
  "useLatestInputs": true
}
```

FAILED 분석만 재시도할 수 있다. 원본 행을 다시 PROCESSING으로 변경하지 않고 새 분석 행을 생성해
`retry_of_analysis_id`로 원본과 연결하며 `trigger_reason=RETRY`를 기록한다. `useLatestInputs=false`는
원본 그림을, `true`는 같은 Session·Asset 유형의 가장 높은 버전을 선택한다.

`Idempotency-Key` Header는 8~100자의 값으로 필수다. 같은 Key와 같은 원본 분석으로 재호출하면
최초 재시도 결과를 반환하고 AI Client를 다시 호출하지 않는다. 같은 Key를 다른 원본 분석에
사용하면 `ANALYSIS_409_004`로 거부한다. 재시도 이력은 원본에서 한 갈래로만 이어지며 최초 분석
이후 최대 3회까지 허용한다. 네 번째 재시도는 `ANALYSIS_409_005`로 거부한다.

재시도도 현재 공개 분석 요청과 동일한 동기식 AI Client 경계를 사용한다. 성공 응답은 HTTP 201이며
`Location`은 현재 저장 결과 조회 URI인
`/api/v1/drawing-sessions/{drawingSessionId}/analyses/{drawingAnalysisId}`다. FAILED가 아닌 원본은
`ANALYSIS_409_003`, 선택된 그림에 PROCESSING 또는 SUCCESS 분석이 존재하면 `ANALYSIS_409_002`로
거부한다. 자동 Retry와 리포트 재생성은 수행하지 않는다.

## 공개 분석 요청의 Asset 정책

`POST /api/v1/drawing-sessions/{drawingSessionId}/analyses`는 다음 조합만 허용한다.

| Asset 유형 | 요청 가능 작업 | 저장 분석 범위 |
| --- | --- | --- |
| `DRAFT` | `OBJECT_DETECTION` | `INTERMEDIATE` |
| `FINAL` | `OBJECT_DETECTION` | `FINAL` |

`INTERMEDIATE`, `UPLOADED`, `THUMBNAIL`, `TIMELAPSE` Asset과 공개 API의 `ACTIVITY_REPORT`
요청은 거부한다. `ACTIVITY_REPORT`는 그림 활동 완료 Service의 내부 처리에서만 생성한다.

자동 저장 그림은 DRAFT 저장 응답의 `drawingAssetId`를 사용한다. 마지막 자동 저장 성공 후 3초 동안
추가 변경이 없을 때 분석을 요청하는 debounce는 프론트엔드가 담당하며, Backend는 지연 실행용
Scheduler나 Timer를 생성하지 않는다.

공개 분석 요청의 `triggerReason`은 `PAUSE`, `USER_REQUEST`만 허용한다. 3초 무입력 자동 분석은
`PAUSE`를 전달하고, 필드를 생략한 기존 Client 요청은 `USER_REQUEST`로 저장한다. 그림 단계 완료,
활동 완료, 재시도 흐름은 Backend가 각각 `DRAWING_COMPLETE`, `ACTIVITY_COMPLETE`, `RETRY`로
확정하며, 저장한 값을 내부 AI 분석 요청에도 동일하게 전달한다.

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

## AI 장애 Fallback 정책

AI 서버 Timeout, 연결 실패, 5xx 응답 또는 계약에 맞지 않는 응답은 성공 분석으로 간주하지 않는다.
Backend는 분석을 `FAILED`로 저장하고 호출 유형에 따라 다음과 같이 응답한다.

| 호출 유형 | 처리 |
| --- | --- |
| 공개 분석 요청 | 실패 이력을 저장한 뒤 안전한 `502` 오류를 반환한다. 저장 결과 조회는 `200 OK`와 `status=FAILED`를 반환한다. |
| 그림 단계 완료 | 저장한 FINAL 그림과 실패 이력을 유지하고 `currentStage=CONVERSING`으로 전이한 뒤 `200 OK`를 반환한다. 응답의 `analysis.status`는 `FAILED`이며 후속 대화는 활성화된 Fallback 질문 템플릿을 사용한다. |
| 명시적 재시도 | `POST /api/v1/analyses/{analysisId}/retry`에서만 수행하며 자동 Retry는 하지 않는다. |

그림 단계 완료 요청을 동일한 `Idempotency-Key`로 다시 호출하면 저장된 동일 결과를 반환하고 AI 서버를
다시 호출하지 않는다. AI 실패 이력 자체를 저장하지 못한 경우에는 정상 Fallback 응답으로 숨기지 않고
안전한 서버 오류를 반환한다.

동기식 AI Client에는 자동 Retry, Circuit Breaker 또는 실행 중 Mock 전환을 적용하지 않는다. 장애 시
Fallback은 Application Service가 저장된 실패 상태를 기준으로 수행한다.

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

자동 Retry, Circuit Breaker와 Message Queue는 현재 범위에 포함하지 않는다. 그림 단계 완료의
저장 기반 Fallback과 `CONVERSING` 전이는 위 정책을 따르며, 감정·리포트 생성은 각 도메인 계약에서
별도로 처리한다.

## Spring Boot AI Client

`S15P11B209-145`에서 다음 동기식 Client 경계를 제공한다.

```java
public interface DrawingAnalysisClient {
    AiDrawingAnalysisResponse analyze(DrawingAnalysisClientCommand command);
}
```

- HTTP 구현체: `RestClientDrawingAnalysisClient`
- HTTP Client: Spring `RestClient`
- Method/Endpoint: `POST /internal/v1/analyses`
- Request/Response: 정본 §19.3의 JSON 요청과 §19.4 응답
- 인증 Header: `X-Internal-Token` 필수
- 상관관계 Header: `X-Request-Id`
- 자동 Retry, Circuit Breaker, 실행 중 Mock 전환: Client 계층에는 구현하지 않음
- 저장 기반 Fallback: 그림 단계 완료 Application Service에서 `FAILED` 분석을 기준으로 처리

### 설정 환경 변수

| 환경 변수 | 기본값 | 용도 |
| --- | --- | --- |
| `AI_DRAWING_ANALYSIS_MODE` | `mock` | 사용할 Client 구현. `mock` 또는 `http` |
| `AI_DRAWING_ANALYSIS_BASE_URL` | `http://localhost:8000` | 그림 분석 AI 서버 Base URL |
| `AI_DRAWING_ANALYSIS_ENDPOINT_PATH` | `/internal/v1/analyses` | 그림 분석 내부 Endpoint Path |
| `AI_INTERNAL_TOKEN` | 없음 | HTTP mode 내부 인증 Token. Secret 저장소에서 주입 |
| `AI_DRAWING_ANALYSIS_CONNECT_TIMEOUT` | `3s` | 연결 제한 시간 |
| `AI_DRAWING_ANALYSIS_READ_TIMEOUT` | `30s` | 응답 대기 제한 시간 |
| `AI_IMAGE_ACCESS_BASE_URL` | `http://backend:8080` | AI 서버에서 Backend로 접근할 Docker 내부 Base URL |
| `AI_IMAGE_ACCESS_TOKEN_TTL` | `60s` | 이미지 조회 일회성 Token 유효 시간. 최대 5분 |

Base URL은 Query와 Fragment가 없는 HTTP 또는 HTTPS 절대 URI여야 한다. Endpoint Path는 `/` 하나로 시작해야 하며 Timeout은 0보다 커야 한다. Client Bean 생성 시 AI 서버 연결을 시도하지 않으므로 서버가 꺼져 있어도 Application Context를 시작할 수 있다.

### Client 오류 매핑

| 상황 | `DrawingAnalysisClientException.Type` |
| --- | --- |
| 요청 Validation 실패, AI 서버 3xx·4xx, 일반 연결 실패 | `REQUEST_FAILED` |
| Connect 또는 Read Timeout | `TIMEOUT` |
| 빈 Body, JSON·Enum 오류, 응답 계약 위반 | `INVALID_RESPONSE` |
| AI 서버 5xx | `SERVER_ERROR` |

HTTP 2xx의 유효한 `status=FAILED` 응답은 통신 실패가 아니므로 Exception으로 변환하지 않는다. 응답
`analysisId`가 요청 값과 다르면 다른 호출의 결과로 판단해 `INVALID_RESPONSE`로 처리한다. Client는
전체 Request/Response, Storage Key, 읽기 URL, 내부 Token과 AI 오류 원문을 로그나 Exception
메시지에 기록하지 않는다.

### 이미지 접근과 현재 연동 제한

정본 요청은 `storageKey`를 전달하지 않고 짧은 만료의 읽기 전용 `signedUrl`을 사용한다. Backend는
256-bit 일회성 Token을 발급하고 Redis에 Token의 SHA-256 digest와 `storageKey`를 기본 60초 동안
저장한다. AI 서버는 Docker 내부망의 `GET /internal/v1/ai-images/{token}`으로 이미지를 한 번만
조회한다. 소비는 Lua `GET`·`DEL`로 원자적으로 처리하며 Nginx는 외부 `/internal/` 요청을 404로
차단한다.

HTTP Client와 내부 이미지 조회는 단위·구성 테스트로 검증했다. 실제 FastAPI 추론의 정상 동작과
YOLO 가중치 배치는 별도 운영 검증 범위이므로, 준비 전에는 기본
`AI_DRAWING_ANALYSIS_MODE=mock`을 유지한다.

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
