# 관찰 리포트 생성 상태 조회·재생성 설계

## 목적

보호자가 관찰 리포트 생성 상태를 가볍게 폴링하고, 생성에 실패한 최신 리포트만 안전하게 재생성할 수 있도록 한다.

## 공개 계약

- `GET /api/v1/reports/{reportId}/generation-status`
  - 연결 보호자만 조회할 수 있다.
  - `reportId`, `drawingSessionId`, `analysisId`, `reportVersion`, `reportStatus`, `retryable`, `failureReason`, `createdAt`, `updatedAt`, `failedAt`을 반환한다.
  - `retryable`은 최신 리포트가 `FAILED`인 경우에만 `true`다.
- `POST /api/v1/reports/{reportId}/regenerate`
  - `Idempotency-Key` Header가 필수다.
  - 최신 리포트가 `FAILED`인 경우에만 접수한다.
  - 새 FINAL `ACTIVITY_REPORT` Analysis와 다음 `reportVersion`의 `GENERATING` Report를 생성한다.
  - 이전 Analysis와의 재시도 관계를 `retry_of_analysis_id`로 보존한다.
  - 접수 성공 시 HTTP 202와 새 생성 상태를 반환하고, 상태 조회 URI를 `Location`에 제공한다.

## 상태·멱등성

- `COMPLETED`, `GENERATING`, `HIDDEN` 리포트와 과거 버전은 재생성할 수 없다.
- 실패한 Session은 `FAILED/REPORTING`에서 `IN_PROGRESS/REPORTING`으로 복구한 뒤 생성 이벤트를 발행한다.
- 같은 `Idempotency-Key`와 같은 원본 리포트의 재요청은 기존 새 리포트를 반환한다.
- 같은 Key를 다른 요청에 재사용하면 409를 반환한다.
- 동시 요청은 `reports`와 `drawing_sessions` 잠금 및 기존 UNIQUE 제약으로 방어한다.

## 보안

- 리포트와 연결된 Drawing Session에 대한 보호자 관계를 확인한다.
- `failureReason`에는 기존에 저장된 내부 분류 코드만 노출하며 예외 메시지나 개인정보는 노출하지 않는다.
- 존재하지 않는 리포트는 404, 권한이 없는 리포트는 403으로 처리한다.
