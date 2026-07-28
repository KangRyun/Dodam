# S15P11B209-143 그림 활동 완료 접수 설계

> 계약 변경: S15P11B209-645부터 전체 활동 완료는 관찰 리포트 생성을 포함하며 `requestReport=true`만 지원한다. 아래 초기 설계의 선택적 리포트 및 `false` 응답 설명은 현재 계약으로 사용하지 않는다.

## 범위

최신 API 명세의 DRAWING-11 계약에 따라 보호자가 그림 활동의 최종 분석과 선택적 리포트 생성을 접수하는 API를 구현한다.

- `POST /api/v1/drawing-sessions/{drawingSessionId}/complete`
- 필수 `Idempotency-Key` Header를 사용한다.
- 최종 그림, 대화 완료 또는 생략, 감정·제목 입력 단계를 검증한다.
- 최종 분석을 `PENDING` 상태로 등록한다.
- `requestReport=true`이면 리포트를 `GENERATING` 상태로 등록한다.
- 그림 활동 세션을 `IN_PROGRESS / REPORTING`으로 전환한다.
- 실제 AI 호출, 분석 결과 생성, 리포트 본문 생성, 세션의 최종 `COMPLETED` 전환은 후속 처리 범위로 남긴다.

## API 계약

요청 Body는 다음 두 필드를 모두 필수로 받는다.

```json
{
  "conversationSkipped": false,
  "requestReport": true
}
```

성공 시 HTTP 202와 공통 `ApiResponse` 안에 다음 데이터를 반환한다.

```json
{
  "drawingSessionId": 100,
  "sessionStatus": "IN_PROGRESS",
  "currentStage": "REPORTING",
  "analysisId": 701,
  "analysisStatus": "PENDING",
  "reportId": 900,
  "reportStatus": "GENERATING"
}
```

`requestReport=false`인 경우 `reportId`와 `reportStatus`는 `null`이다. 응답은 접수 상태만 나타내며 분석이나 리포트가 완료되었다는 뜻이 아니다.

## 사전 조건

- 인증 사용자는 해당 그림 활동 세션의 아동을 관리할 권한이 있어야 한다.
- 세션은 삭제되지 않은 `IN_PROGRESS / REFLECTION` 상태여야 한다.
- 해당 세션에 `FINAL` 그림 Asset이 존재해야 한다.
- `conversationSkipped=false`이면 해당 세션의 대화가 `COMPLETED` 상태여야 한다.
- `conversationSkipped=true`이면 해당 세션에 대화가 시작되지 않은 상태여야 한다.
- 142번 이슈에서 감정 선택을 생략한 경우에도 세션이 `REFLECTION` 단계이므로 완료 접수가 가능하다.

`conversationSkipped=true`인데 진행 중인 대화가 있거나, `conversationSkipped=false`인데 완료 대화가 없으면 요청과 저장 상태가 서로 모순되므로 409로 거절한다.

## 멱등성과 동시성

기존 `analyses.idempotency_key`의 UNIQUE 제약을 멱등성의 영속 기준으로 사용한다. 143번 이슈만을 위한 Redis Key를 추가하지 않는다. 이는 이미 적용된 DB 제약과 중복되는 인프라를 피하고 분석 요청과 멱등성 기록을 한 Transaction으로 원자적으로 저장하기 위함이다.

- 같은 `Idempotency-Key`와 같은 세션·요청으로 재호출하면 최초 생성한 분석과 리포트를 반환한다.
- 같은 Key를 다른 세션 또는 다른 `requestReport` 값에 재사용하면 409로 거절한다.
- 세션 행을 비관적 쓰기 잠금으로 조회해 서로 다른 Key의 동시 완료 접수도 하나만 성공하게 한다.
- 잠금 획득 전후로 멱등성 Key를 확인해 동시 재시도에서도 중복 분석과 리포트가 생성되지 않게 한다.
- DB UNIQUE 충돌은 내부 Constraint 이름을 노출하지 않고 도메인 충돌 응답으로 변환한다.

## Domain 및 저장 구조

### 분석

기존 `DrawingAnalysis`와 `analyses` Table을 재사용한다.

- 범위: `FINAL`
- 작업 유형: `ACTIVITY_REPORT`
- 상태: `PENDING`
- `idempotency_key`: 요청의 `Idempotency-Key`
- `trigger_reason`: 기존 DB CHECK가 허용하는 `ACTIVITY_COMPLETE`
- `requested_at`, `created_at`: 서버 접수 시각
- `started_at`, `completed_at`: 실제 처리가 시작되거나 끝나기 전까지 `null`

기존 즉시 실행용 `processing` Factory와 구분되는 대기 분석 Factory를 추가한다. 이 API에서는 `DrawingAnalysisClient`를 호출하지 않는다.

### 리포트

현재 Java 코드에는 `reports` Table을 표현하는 Domain이 없으므로 접수 상태만 책임지는 최소 `Report` Entity와 Repository를 추가한다.

- `drawing_session_id`: 완료 접수 대상 세션
- `analysis_id`: 이번에 생성한 최종 분석
- `report_version`: 해당 세션의 다음 버전이며 최초 요청은 1
- `report_status`: `GENERATING`
- `is_expert_review_recommended`: `false`
- `limitations_text`: 생성 완료 전 결과로 해석하지 말라는 고정 안내
- `pdf_status`: `NONE`

정규화된 리포트 상세 Table은 실제 결과가 없으므로 이 단계에서 생성하지 않는다. 기존 Flyway Migration은 수정하지 않는다.
기존 `analysis_task_type` CHECK가 `OBJECT_DETECTION`만 허용하므로 새 V7 Migration에서 `ACTIVITY_REPORT`를 허용해
Java Enum과 MySQL 계약을 일치시킨다.

### 그림 활동 세션

`DrawingSession`에 완료 접수 가능 여부와 `REPORTING` 전환 행위를 추가한다. 이 API는 `status`를 `COMPLETED`로 바꾸거나 `completed_at`을 기록하지 않는다.

## 처리 순서

1. 요청 필드와 `Idempotency-Key` 형식을 검증한다.
2. 인증 사용자와 그림 활동 세션의 접근 권한을 확인한다.
3. 세션을 비관적 쓰기 잠금으로 조회한다.
4. 동일 멱등성 요청이 이미 처리되었으면 저장된 접수 결과를 반환한다.
5. 세션 상태, 최종 그림, 대화 완료 또는 생략 상태를 검증한다.
6. 최종 분석을 `PENDING`으로 저장한다.
7. 요청된 경우 리포트를 `GENERATING`으로 저장한다.
8. 세션을 `REPORTING`으로 전환한다.
9. 생성된 ID와 접수 상태를 HTTP 202로 반환한다.

분석, 리포트, 세션 전환은 하나의 Transaction에서 처리한다. 어느 하나라도 저장에 실패하면 전체 변경을 Rollback한다.

## 오류 처리

기존 `BusinessException`, `GlobalExceptionHandler`, 공통 오류 응답을 사용한다.

- 잘못되거나 누락된 Header·Body: 400
- 세션 또는 접근 가능한 자원이 없음: 기존 권한 정책에 따라 404
- 최종 그림 없음: `FINAL_ASSET_REQUIRED`, 409
- 감정·제목 입력 단계 미완료: `REFLECTION_REQUIRED`, 409
- 대화 상태와 `conversationSkipped`가 불일치: 409
- 이미 완료 접수되었거나 완료된 세션: `DRAWING_SESSION_ALREADY_COMPLETED`, 409
- 멱등성 Key가 다른 요청에 재사용됨: 409

오류 응답에는 SQL, Constraint 이름, 서버 경로, 사용자 개인정보를 포함하지 않는다.

## 테스트

- 요청 DTO Validation: 필수 Boolean 누락, Header 누락·공백·길이 초과
- Service 단위 테스트: 정상 접수, 리포트 미요청, 동일 요청 재호출, Key 재사용 충돌
- Service 단위 테스트: 권한 없음, 최종 그림 없음, REFLECTION 미도달, 대화 미완료·생략 모순, 이미 REPORTING 또는 COMPLETED
- Controller MockMvc 테스트: URI, 필수 Header, 202 공통 응답, nullable 리포트 필드
- MySQL 통합 테스트: 분석·리포트·세션 상태 원자 저장, 동일 Key 재호출, 서로 다른 Key의 중복 접수 방지
- 전체 `clean test`, `spotlessCheck`, `javadoc` 검증
