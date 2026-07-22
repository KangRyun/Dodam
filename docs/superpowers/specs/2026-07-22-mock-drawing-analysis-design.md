# Mock 그림 분석 결과 설계

## 목적

실제 AI 서버가 연결되지 않은 개발 환경에서도 후속 그림 분석 흐름을 개발하고 테스트할 수 있도록 `DrawingAnalysisClient`의 결정적인 Mock 구현을 제공한다. Mock 응답은 기존 S15P11B209-144 계약 DTO를 그대로 사용하며 실제 추론 결과나 심리 분석 결과를 의미하지 않는다.

## 기존 구조와 제약

- `DrawingAnalysisClient`와 HTTP 구현체 `RestClientDrawingAnalysisClient`를 그대로 유지한다.
- 요청·응답 DTO와 `DrawingAnalysisStatus`, `DrawingAnalysisType`을 수정하지 않는다.
- 탐지 Label 정책은 문자열이므로 별도 Java Enum을 추가하지 않는다.
- 기존 UTC `Clock` Bean과 Bean Validation `Validator`를 재사용한다.
- Controller, Service, Entity, Repository, Flyway Migration은 변경하지 않는다.
- 실제 AI 서버 호출, DB 저장, 재시도, 비동기 처리는 수행하지 않는다.

## Client 선택

`app.ai.drawing-analysis.mode` Property로 활성 구현체를 선택한다. 환경 변수는 `AI_DRAWING_ANALYSIS_MODE`이며 기본값은 `mock`이다. 허용 값은 `mock`, `http`뿐이다.

- `mock`: `MockDrawingAnalysisClient`만 `DrawingAnalysisClient` Bean으로 등록한다.
- `http`: 기존 `RestClientDrawingAnalysisClient`만 `DrawingAnalysisClient` Bean으로 등록한다.
- HTTP 전용 `RestClient`도 `http` 모드에서만 생성한다.
- 잘못된 mode는 `DrawingAnalysisClientProperties` Binding 과정에서 명확한 설정 오류로 Application Context 시작을 중단한다.
- Profile 기반 선택 방식을 함께 도입하지 않는다.

## Mock 응답

`MockDrawingAnalysisClient`는 `Validator`로 기존 요청 계약을 검증한다. 유효하지 않은 요청은 기존 `DrawingAnalysisClientException.Type.REQUEST_FAILED`로 거부하고 성공 응답을 만들지 않는다.

정상 요청은 다음 고정 결과를 반환한다.

- `requestId`: 요청 값을 그대로 사용
- `status`: `SUCCEEDED`
- 모델: `mock-drawing-detector`, 버전 `1.0`
- 탐지: `HOUSE`(0.95, 120/80/640/520), `TREE`(0.91, 820/120/380/700)
- `error`: `null`
- `processedAt`: 주입된 `Clock`의 현재 UTC Instant

Bounding Box는 기존 계약대로 원본 이미지의 픽셀 좌표로 표현하되, Mock 값이 실제 이미지 크기나 내용을 반영한다고 설명하지 않는다. 탐지 목록은 DTO 생성자의 방어적 복사를 통해 외부에서 변경할 수 없다. 동일 요청은 `processedAt`을 제외한 모든 분석 결과가 같으며, 고정 `Clock`을 사용하면 응답 전체가 동일하다.

## 보안과 Logging

요청·응답 전체, 이미지 데이터, `storageKey`, 서버 경로, Token 및 개인정보는 로그에 기록하지 않는다. 구현체 선택은 mode 설정과 Bean Type으로 확인할 수 있으므로 요청별 `INFO` 로그를 추가하지 않는다.

## 테스트

- Mock Client 단위 테스트에서 성공 상태, 요청 ID, 모델 정보, 탐지 Label, Confidence, Bounding Box, `error`, 고정 시각과 결정성을 검증한다.
- null 또는 Bean Validation 위반 요청이 기존 Client 예외로 거부되는지 검증한다.
- Application Context 테스트에서 `mock`과 `http` 모드별 단일 Bean 등록, 기본 `mock`, 잘못된 mode 실패 및 Context 시작 중 네트워크 호출이 없음을 검증한다.
- 기존 Jackson 계약 테스트 방식으로 Mock 응답의 직렬화·역직렬화와 Enum 문자열을 검증한다.
- 전체 테스트, Spotless와 Javadoc을 실행한다.

## 제외 범위

S15P11B209-147의 분석 Application Service, Controller, DB 저장과 그림 세션 상태 변경은 구현하지 않는다. 실패 Fixture, 실제 모델 추론, 이미지별 동적 결과, Retry, Circuit Breaker, Queue와 비동기 Job도 포함하지 않는다.
