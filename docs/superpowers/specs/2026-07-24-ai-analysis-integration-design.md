# 실제 AI 그림 분석 연동 설계

## 목표

`S15P11B209-159`는 Spring Boot의 그림 분석 경계를 정본 내부 계약인
`POST /internal/v1/analyses`에 맞춘다. AI 이미지 접근 경로가 준비되기 전까지
기본 실행 모드는 `mock`으로 유지하며, 준비되지 않은 이미지를 임의 URL이나 서버 절대
경로로 전달하지 않는다.

## 확인된 충돌

- 기존 기본 경로 `/internal/ai/v1/drawings/analysis`는 AI 서버에 존재하지 않는다.
- 기존 요청은 `requestId`, `imageReference`, `OBJECT_DETECTION` 중심이지만 정본 요청은
  `analysisId`, `analysisType`, `drawing` 중심이다.
- 기존 HTTP Client는 내부 인증 Header를 전달하지 않는다.
- 기존 응답은 `model`, `detections`, 픽셀 Bounding Box를 사용하지만 정본 응답은
  `modelInfo`, `detectedObjects`, 0~1 정규화 Bounding Box를 사용한다.
- 기존 저장 로직은 `SUCCESS` 객체 탐지만 저장하고 `PARTIAL_SUCCESS` 및 종합 결과를
  처리하지 않는다.
- 현재 `ImageStorage`에는 짧은 만료의 읽기 전용 URL을 만드는 기능이 없다.

## 경계와 책임

### Application 계층

`DrawingAnalysisService`는 분석 행을 먼저 생성한 뒤, 저장소 상대 Key와 분석 식별자를
포함한 내부 명령을 `DrawingAnalysisClient`에 전달한다. 외부 AI JSON 구조나 URL 발급
방식을 직접 알지 않는다.

### AI Client 계층

HTTP Adapter는 내부 명령을 §19.3 JSON으로 변환한다. 호출 추적 UUID는 JSON에 넣지 않고
`X-Request-Id`로 전달하며, `AI_INTERNAL_TOKEN`은 `X-Internal-Token`으로 전달한다.
응답은 §19.4 구조로 역직렬화하고 `analysisId`가 요청과 같은지 검증한다.

이미지 접근 URL은 `DrawingAnalysisImageUrlProvider` 추상화로 분리한다. 이번 이슈에서는
실제 URL을 조작하거나 가짜 URL을 만들지 않는다. HTTP 모드에서 Provider가 URL을 만들지
못하면 네트워크 호출 전에 안전하게 실패한다. 실제 Provider 구현은
`S15P11B209-372`의 이미지 접근 방식 확정 후 연결한다.

### Mock

Mock도 HTTP와 같은 정본 응답 타입을 반환한다. Bounding Box는 0~1 정규화 좌표이며,
`PARTIAL_SUCCESS`와 `unusedInputs`, `warnings`를 포함해 실제 AI의 현재 동작을 재현한다.
외부 네트워크나 AI 성공 결과를 가장하는 운영 설정으로 사용하지 않는다.

### 저장

- `analyses`: 정본 상태와 객체 탐지 Model 대표 정보를 저장한다.
- `analysis_detected_objects`: `objectCode`, `objectName`, 정규화 Bounding Box,
  `areaRatio`, `detectionOrder`를 저장한다.
- 기존 시각·행동 특징, 대화 요약, 관찰 초안, 미사용 입력 테이블을 재사용한다.
- Model 구성요소, 경고, 복수 관찰 문장·후속 질문처럼 기존 Schema로 손실 없이 저장할 수
  없는 값은 새 정규화 테이블을 추가한다.
- 적용된 Migration은 수정하지 않는다. 픽셀 좌표로 변경했던 V5를 되돌리지 않고 새
  Migration에서 정규화 좌표 제약으로 전환한다.

## 상태와 오류

- `SUCCESS`: 전체 결과를 저장하고 분석을 `SUCCESS`로 전환한다.
- `PARTIAL_SUCCESS`: 저장 가능한 결과와 누락 사유를 함께 저장하고
  `PARTIAL_SUCCESS`로 전환한다.
- `FAILED`: AI가 200 응답으로 반환한 실패 상태를 안전한 내부 오류로 기록한다.
- 401·422는 요청 실패, 5xx는 AI 서버 실패, Timeout은 Timeout으로 분류한다.
- 외부 응답 본문, Token, signed URL, 이미지 원문, 아동 발화는 로그와 API 오류에
  포함하지 않는다.

## 공개 API 호환성

보호자 공개 API의 URI와 요청 형식은 변경하지 않는다. 내부 `PARTIAL_SUCCESS`는 기존
공개 상태 변환 정책에 따라 `SUCCEEDED`로 표시하지만, 상세 결과 저장에는 실제 상태를
보존한다.

## 제외 범위

- 운영 환경에서 `mode=http` 활성화
- 이미지 signed URL 또는 내부 이미지 다운로드 Endpoint 구현
- 배포 Volume에 주입된 YOLO 가중치의 운영 Health 검증
- 공개 분석 API의 동기/비동기 및 오류 코드 재설계
