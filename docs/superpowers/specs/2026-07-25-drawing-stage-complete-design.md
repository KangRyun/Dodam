# S15P11B209-538 그림 단계 완료 API 설계

## 1. 목적

Flutter가 그림 편집을 마친 시점에 최종 PNG를 저장하고 대화 준비용 객체 탐지를 수행한 뒤,
그림 세션을 감정 선택 및 대화가 가능한 단계로 전환한다.

이번 API는 기존 `POST /api/v1/drawing-sessions/{drawingSessionId}/complete`와 책임이 다르다.
기존 API는 감정·제목 저장과 대화 종료 이후 관찰 리포트 생성을 접수하는 전체 활동 완료 API이므로
변경하거나 대체하지 않는다.

## 2. 확정 API 계약

### 요청

```http
POST /api/v1/drawing-sessions/{drawingSessionId}/drawing-complete
Authorization: Bearer {accessToken}
Idempotency-Key: {8~100자 요청 키}
Content-Type: multipart/form-data
```

| Part | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `finalImage` | PNG/JPEG binary | 조건부 | CANVAS 세션의 최초 완료 요청에서는 필수다. 동일 요청 재시도 또는 유효한 기존 FINAL asset을 지정한 경우 생략할 수 있다. |
| `metadata` | JSON | 필수 | 완료 시각과 그림 작성 시간 및 선택적인 원본 asset·마지막 event 순번을 전달한다. |

`metadata` 필드:

| 필드 | 타입 | 필수 | 검증 |
| --- | --- | --- | --- |
| `sourceAssetId` | Long | 선택 | 지정 시 같은 세션의 FINAL asset이어야 한다. |
| `lastEventSequence` | Long | 선택 | 0 이상이어야 한다. 강제 flush 순서가 확정되기 전에는 서버 저장 순번과의 일치 검증에 사용하지 않는다. |
| `drawingDurationMs` | Long | 필수 | 1 이상이어야 한다. |
| `clientCompletedAt` | OffsetDateTime | 필수 | ISO-8601 시각이어야 한다. |

### 응답

동기 분석 처리까지 마친 뒤 `200 OK`와 기존 `ApiResponse<T>` 봉투를 반환한다.

```json
{
  "drawingSessionId": 100,
  "finalAssetId": 502,
  "sessionStatus": "IN_PROGRESS",
  "currentStage": "CONVERSING",
  "analysis": {
    "analysisId": 700,
    "analysisType": "OBJECT_DETECTION",
    "status": "SUCCEEDED"
  },
  "nextAction": "SELECT_EMOTION"
}
```

분석 서버 오류가 발생하면 분석 레코드는 `FAILED`로 남기고, 사용자가 그림을 잃거나 완료 화면에서
막히지 않도록 세션은 `CONVERSING`으로 전환한다. 이때 응답의 분석 상태는 `FAILED`이며
`nextAction`은 동일하게 `SELECT_EMOTION`이다. 이후 대화 질문 생성은 기존 폴백 정책을 사용한다.

## 3. 처리 흐름

1. 인증 사용자가 세션 아동에 접근할 수 있는지 확인한다.
2. `Idempotency-Key`를 검증하고 기존 분석 요청을 조회한다.
3. 같은 키로 완료된 동일 세션 요청이면 기존 FINAL asset과 분석 결과를 반환한다.
4. 최초 요청이면 세션이 `IN_PROGRESS/DRAWING`인지 확인한다.
5. 이미지 signature·크기·해상도를 검증한 뒤 `DrawingAssetType.FINAL`로 저장한다.
6. 저장된 이미지의 PNG/JPEG Header에서 추출한 실제 `widthPx`, `heightPx`를 asset에 기록한다.
7. `Idempotency-Key`를 분석 `requestId`로 사용해 `OBJECT_DETECTION` 분석을 한 번만 생성한다.
8. 분석 시작 시 세션을 `ANALYZING`, 성공 또는 실패 확정 시 `CONVERSING`으로 전환한다.
9. 실제 세션·asset·분석 상태를 조합해 응답한다.

## 4. 멱등성과 동시성

- 분석 테이블의 고유한 `requestId`를 완료 요청의 멱등성 기준으로 재사용한다.
- 동일 키가 다른 세션에 사용되면 `409 IDEMPOTENCY_KEY_REUSED`를 반환한다.
- 동일 세션의 동일 키 재시도는 최초 요청이 만든 FINAL asset과 분석 결과를 반환한다.
- 동일 세션에 서로 다른 완료 키가 동시에 도착하면 세션 상태 잠금과 FINAL asset 중복 검증으로
  한 요청만 처리하고 나머지는 `409`로 거절한다.
- 범용 HTTP 응답 재생과 Body fingerprint 저장은 별도 S15P11B209-527 범위이며, 이번 작업에서는
  분석 `requestId`와 영속 상태를 이용해 그림 완료 부수 효과의 중복을 방지한다.

## 5. 저장 및 보상 처리

- 실제 파일 저장은 기존 `ImageStorage` 추상화를 사용한다.
- DB 저장 실패 시 새로 저장한 파일을 보상 삭제한다.
- FINAL asset 저장이 완료된 뒤 AI 분석이 실패한 경우에는 최종 그림을 삭제하지 않는다.
  그림 보존과 폴백 대화를 위해 FINAL asset 및 FAILED 분석 이력을 유지한다.
- 파일 Byte, Base64, 원본 파일명 및 서버 절대 경로는 DB·로그·응답에 노출하지 않는다.

## 6. 상태 전이

```text
IN_PROGRESS / DRAWING
  -> FINAL 저장 및 분석 생성
IN_PROGRESS / ANALYZING
  -> 분석 성공 또는 실패 확정
IN_PROGRESS / CONVERSING
  -> 감정·제목 저장
IN_PROGRESS / REFLECTION
  -> 기존 /complete
IN_PROGRESS / REPORTING
```

그림 단계 완료는 `sessionStatus`를 `COMPLETED`로 변경하지 않는다. 최종 활동 완료는 관찰 리포트
생성까지 끝난 뒤 기존 완료 흐름에서 수행한다.

## 7. 코드 변경 범위

- 그림 단계 완료 Controller, 요청·응답 DTO, Application Service
- `DrawingSession`의 `DRAWING -> ANALYZING -> CONVERSING` 상태 전이
- 기존 FINAL snapshot 저장 흐름의 재사용 또는 최소 확장
- 기존 `DrawingAnalysisService`에 호출자 지정 `requestId` 및 결과 조회 경로 추가
- Controller, Service, Domain 및 필요한 Repository 테스트
- 최종 API 명세의 동기 응답 예시와 분석 타입 수정

## 8. 제외 범위

- 기존 전체 활동 완료 `/complete`의 리포트 생성 정책 변경
- 비동기 작업 큐와 별도 분석 polling API 신설
- AI 모델·가중치·탐지 알고리즘 변경
- 범용 Idempotency Framework 구현
- Flutter 화면 흐름 및 디자인 변경

## 9. 검증 기준

- multipart 정상 요청이 FINAL asset과 실제 이미지 크기를 저장한다.
- 세션이 `DRAWING -> ANALYZING -> CONVERSING`으로 전이한다.
- 분석 성공과 AI 실패 폴백 응답을 모두 검증한다.
- 동일 키 재요청에 FINAL asset과 분석이 중복 생성되지 않는다.
- 다른 세션에서 같은 키를 재사용하면 충돌 응답을 반환한다.
- 누락 Header, 잘못된 metadata, 권한 없음, 잘못된 세션 상태 및 event 순번 오류를 검증한다.
- `clean test`, `spotlessCheck`, `javadoc`을 통과한다.
