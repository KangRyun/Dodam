# 그림 분석 요청 및 결과 저장 API 설계

## 목표

`POST /api/v1/drawing-sessions/{drawingSessionId}/analyses`가 해당 세션의 최종 그림을 개발용 `DrawingAnalysisClient`로 분석하고, 분석 실행 이력과 객체 탐지 결과를 관계형 테이블에 저장한 뒤 `201 Created`로 반환한다.

## 기존 SQL 보존 원칙

- 적용된 V1~V4와 ERD Cloud v1.2 SQL은 수정하지 않는다.
- 기존 `analyses.analysis_type`의 `INTERMEDIATE`/`FINAL` 의미를 분석 시점으로 유지한다.
- API의 `OBJECT_DETECTION`은 새 `analysis_task_type` 컬럼에 저장한다.
- 서버가 생성하는 `requestId`는 이미 Unique인 `idempotency_key`에 저장한다. 같은 값을 보관하는 `request_id` 컬럼은 추가하지 않는다.
- DB의 성공 상태 `SUCCESS`를 유지하고 외부 API 응답에서 `SUCCEEDED`로 변환한다.
- 기존 데이터에 출처가 불명확한 값을 강제로 채우지 않는다. 새 컬럼은 Legacy 행을 위해 Nullable로 추가하되 신규 Application 저장 경로에서는 필수로 보장한다.

## Migration

V5는 `analyses`에 `drawing_asset_id`, `analysis_task_type`, 활성 분석 중복 방지용 생성 컬럼을 추가한다. 기존 Detection에서 한 개의 그림 파일만 명확히 추론되는 Legacy 분석은 `drawing_asset_id`를 안전하게 역채움하고, 그 외 행은 그대로 보존한다.

`analysis_detected_objects`의 Bounding Box는 픽셀 좌표를 저장할 수 있도록 `DECIMAL(12,3)`으로 확장한다. Nullable 정책은 Legacy 호환성을 위해 유지하고, 신규 Domain 생성 시 confidence와 좌표 범위를 검증한다.

동일 `(drawing_asset_id, analysis_task_type)`에 `PROCESSING` 또는 `SUCCESS`가 하나만 존재하도록 생성 컬럼 기반 Unique Index를 사용한다. `FAILED` 행은 생성 컬럼이 `NULL`이므로 재요청할 수 있다.

## Application 흐름

1. 짧은 시작 Transaction에서 삭제되지 않은 세션을 잠그고 세션 상태, 최종 그림 소속, 중복 분석을 검증한다.
2. UUID `requestId`와 `PROCESSING` 분석 행을 저장한다.
3. Transaction 밖에서 `DrawingAnalysisClient`를 호출한다.
4. 응답의 `requestId`, 상태, 모델, Detection 계약을 검증한다.
5. 별도 완료 Transaction에서 Detection과 모델 정보를 저장하고 상태를 `SUCCESS`로 바꾼다.
6. Client 또는 응답 검증이 실패하면 별도 실패 Transaction에서 상태를 `FAILED`로 남기고 안전한 공통 오류로 변환한다.
7. 결과 저장 Transaction이 실패해도 시작 행을 `FAILED`로 전환한 후 저장 오류를 반환한다.

## 유효성 및 공개 계약

- 요청 이미지는 현재 정책상 세션의 `FINAL` `DrawingAsset`만 허용한다.
- 삭제되었거나 분석 불가능한 세션은 거부한다. 그림 파일은 현재 Soft Delete 컬럼이 없으므로 존재하는 행만 대상으로 하며 실제 삭제된 행은 404로 처리한다.
- `confidence`는 0 이상 1 이하, `x`와 `y`는 0 이상, `width`와 `height`는 0보다 커야 한다.
- 빈 Detection 목록은 정상 성공이다.
- 응답과 로그에 `storageKey`, 내부 파일 경로, AI 원문 오류, Stack Trace를 노출하지 않는다.
- 기본 Client 설정은 기존 `mock`을 유지하며 Service는 `DrawingAnalysisClient` Interface에만 의존한다.

## 검증

- Domain, Service, Persistence, Controller 단위 테스트를 TDD로 작성한다.
- Testcontainers MySQL에서 V5 컬럼, FK, Check, Unique와 실패 후 재요청 가능성을 검증한다.
- 전체 `clean test`, `spotlessCheck`, `javadoc`을 실행하고 Javadoc 결과를 확인한다.
