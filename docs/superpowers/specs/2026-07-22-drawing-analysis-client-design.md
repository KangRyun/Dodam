# 그림 분석 AI Client 구조 설계

> Jira: `S15P11B209-145`

## 목적과 범위

Spring Boot가 그림 분석 AI 서버를 호출할 수 있도록 동기식 Client 경계와 `RestClient` HTTP 어댑터를 제공한다. `S15P11B209-144`의 `DrawingAnalysisRequest`와 `DrawingAnalysisResponse`를 그대로 사용하며, 실제 FastAPI 구현·Mock 결과·Application Service·Controller·DB 저장은 포함하지 않는다.

## 기존 구조와 선택 근거

기존 질문 생성 연동은 `infrastructure.ai` 패키지에서 Interface와 `RestClient` 구현을 분리하고 `MockRestServiceServer`로 테스트한다. 그림 분석도 이 방식은 따르되 기존 질문 Client의 하드코딩된 설정, 재시도, 내부 Token 정책을 공유하거나 리팩터링하지 않는다. 두 연동은 Endpoint, Timeout, 인증 및 오류 의미가 달라 현재 범위에서는 독립 구성이 안전하다.

## 구성 요소

패키지는 `com.ssafy.b209.infrastructure.ai.drawing`을 사용한다.

- `DrawingAnalysisClient`: 계약 DTO만 노출하며 `analyze(DrawingAnalysisRequest)`를 제공한다.
- `RestClientDrawingAnalysisClient`: 요청 검증, JSON 호출, HTTP/전송 오류 변환, 응답 검증을 담당한다.
- `DrawingAnalysisClientProperties`: Base URL, Endpoint Path, Connect/Read Timeout을 `app.ai.drawing-analysis`에서 Binding하고 검증한다.
- `DrawingAnalysisClientConfig`: 전용 `RestClient`를 생성한다. Bean 생성 과정에서는 네트워크를 호출하지 않는다.
- `DrawingAnalysisClientException`: HTTP 세부사항을 상위 계층에 노출하지 않고 `REQUEST_FAILED`, `TIMEOUT`, `INVALID_RESPONSE`, `SERVER_ERROR`로 분류한다.

## 설정

기본 설정은 다음과 같다.

```yaml
app:
  ai:
    drawing-analysis:
      base-url: ${AI_DRAWING_ANALYSIS_BASE_URL:http://localhost:8000}
      endpoint-path: ${AI_DRAWING_ANALYSIS_ENDPOINT_PATH:/internal/ai/v1/drawings/analysis}
      connect-timeout: ${AI_DRAWING_ANALYSIS_CONNECT_TIMEOUT:3s}
      read-timeout: ${AI_DRAWING_ANALYSIS_READ_TIMEOUT:30s}
```

Base URL은 절대 `http` 또는 `https` URI여야 하고 Query·Fragment를 허용하지 않는다. Endpoint Path는 `/`로 시작하는 비어 있지 않은 상대 경로여야 하며 완전한 URL을 허용하지 않는다. 두 Timeout은 0보다 커야 한다. 실제 운영 주소와 Secret은 저장소에 기록하지 않는다.

## 요청 흐름

1. Client가 Bean Validation으로 `DrawingAnalysisRequest`와 중첩 `DrawingImageReference`를 검증한다.
2. 유효한 요청만 설정된 Endpoint에 `application/json` POST로 전송한다.
3. 2xx Body를 `DrawingAnalysisResponse`로 역직렬화한다.
4. Body가 없거나 응답 Bean Validation이 실패하거나 응답 `requestId`가 요청과 다르면 `INVALID_RESPONSE`로 변환한다.
5. 유효한 `status=FAILED` 응답은 AI 서버가 계약에 따라 처리한 결과이므로 예외로 바꾸지 않고 반환한다.

`storageKey`는 144번에서 정의한 불투명 내부 식별자를 그대로 전송한다. Client는 절대 경로, URL, Base64 또는 multipart로 변환하지 않는다. 따라서 AI 서버가 Backend의 로컬 Storage를 공유하지 않으면 실제 파일 접근이 불가능하며, 이 전송 구조는 후속 배포 Architecture에서 해결해야 한다.

## 오류 처리

| 상황 | Client 오류 유형 |
| --- | --- |
| 로컬 요청 Validation 실패 | `REQUEST_FAILED` |
| AI 서버 3xx | `REQUEST_FAILED` |
| AI 서버 4xx | `REQUEST_FAILED` |
| AI 서버 5xx | `SERVER_ERROR` |
| Connect 또는 Read Timeout | `TIMEOUT` |
| 그 밖의 연결 실패 | `REQUEST_FAILED` |
| 빈 Body | `INVALID_RESPONSE` |
| 잘못된 JSON 또는 알 수 없는 Enum | `INVALID_RESPONSE` |
| 응답 필수값·범위·상태 조합 위반 | `INVALID_RESPONSE` |

Exception 메시지는 오류 유형의 안정적인 이름만 사용한다. AI 서버 응답 원문, URL, 내부 IP, 전체 Request/Response, Storage Key, Stack Trace 및 개인정보를 사용자용 메시지나 로그에 포함하지 않는다. 이번 Client에는 별도 성공·실패 로그를 추가하지 않아 원문 노출 가능성을 줄인다.

Retry, Circuit Breaker, Fallback과 비동기 처리는 구현하지 않는다.

## 테스트 전략

`MockRestServiceServer`로 실제 외부 네트워크 없이 다음을 검증한다.

- 요청 URI, Method, Content-Type과 JSON Body
- 일반 성공 및 빈 `detections` 성공 응답
- 계약상 `FAILED` 응답 반환
- 400과 500 오류 매핑
- 연결 실패, Connect Timeout, Read Timeout 분류
- 빈 Body, 잘못된 JSON, 알 수 없는 Enum, Bean Validation 위반 응답
- 요청 Validation 실패 시 HTTP 호출 없음
- 설정 Binding 및 잘못된 URL·경로·Timeout 거부
- Spring Context 시작 시 HTTP 요청 없음
- Exception에 요청·응답 원문과 서버 URL이 포함되지 않음

기존 전체 테스트, Spotless와 Javadoc을 마지막에 실행한다.

## 문서화와 제외 범위

`docs/api/ai-drawing-analysis-contract.md`에 Client Interface, 설정 환경 변수, Endpoint, Timeout, 오류 매핑, Mock HTTP 테스트 및 실제 AI 미연동 제한을 추가한다.

DB, Flyway, Entity, Repository, Controller, Application Service, FastAPI, Production Mock, 분석 저장, 상태 변경, Message Queue, Redis, 모델 추론은 변경하지 않는다. Mock 분석은 `S15P11B209-146`, 분석 요청·저장은 `S15P11B209-147` 범위로 유지한다.
