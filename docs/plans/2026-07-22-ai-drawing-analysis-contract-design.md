# AI 그림 분석 요청·응답 계약 설계

## 범위

Spring Boot와 AI 서버 사이에서 교환할 그림 객체 탐지 JSON 구조만 정의한다. 실제 HTTP Client, FastAPI 호출, Mock 결과, 분석 저장, Controller 및 DB 변경은 후속 이슈로 남긴다.

## 설계 결정

- 계약은 `analysis.dto` 패키지의 Java `record`와 전용 Enum으로 구성한다.
- `DrawingSession` 및 `DrawingAsset`은 ID만 전달하며 Entity를 계약에 포함하지 않는다.
- `imageReference.storageKey`는 저장소 구현과 절대 경로를 노출하지 않는 불투명 내부 식별자다. AI가 실제 이미지 Byte에 접근하는 방법은 `S15P11B209-145`에서 정한다.
- 이번 `OBJECT_DETECTION`은 외부 분석 요청의 `INTERMEDIATE`/`FINAL`과 의미가 달라 전용 `DrawingAnalysisType`으로 분리한다.
- 이번 상태 `SUCCEEDED`는 DB 분석 상태 `SUCCESS`와 생명주기가 달라 전용 `DrawingAnalysisStatus`로 분리한다.
- Bounding Box는 기존 대화 계약의 0~1 정규화 좌표를 재사용하지 않고, 원본 이미지 기준 픽셀 좌표로 정의한다.
- 시간은 `Instant`로 표현하여 JSON에서 ISO-8601 UTC 형식으로 직렬화한다.
- 객체 Label은 확정 목록이 없으므로 비어 있지 않은 문자열로 유지한다.

## 검증 규칙

- 요청 ID는 비어 있을 수 없고 식별자 ID는 1 이상이어야 한다.
- `storageKey`는 비어 있을 수 없으며 절대 경로와 상위 경로 이동을 허용하지 않는다.
- `contentType`은 현 Storage가 지원하는 `image/png`, `image/jpeg`만 허용한다.
- `confidence`는 0 이상 1 이하, `x`와 `y`는 0 이상, `width`와 `height`는 0보다 커야 한다.
- 성공 응답은 빈 `detections`를 허용하며 모델 정보와 처리 완료 시각이 필요하고 `error`는 없어야 한다.
- 실패 응답은 안전한 오류 코드·메시지와 처리 완료 시각이 필요하고 탐지 결과는 비어 있어야 한다.
- `PENDING`과 `PROCESSING`은 모델·오류·완료 시각 없이 빈 탐지 목록을 갖는다.
- 알 수 없는 Enum은 Jackson 기본 동작에 따라 역직렬화에 실패하고, 알 수 없는 일반 필드는 현재 Spring Boot 기본 설정에 따라 무시한다.

## 대안 검토

- 접근 가능한 내부 URL은 제공 API와 인증 정책이 아직 없어 채택하지 않았다.
- Base64 또는 multipart 전달은 JSON 계약 범위를 벗어나고 이미지 원문 노출과 크기 증가 문제가 있어 채택하지 않았다.

## 보안과 경계

요청·응답에는 아동·보호자 개인정보, Token, 이미지 Byte/Base64, 서버 절대 경로, Stack Trace 및 Exception 클래스명을 포함하지 않는다. 이 계약은 외부 공개 REST API가 아니라 후속 내부 AI Client가 사용할 값 객체다.
