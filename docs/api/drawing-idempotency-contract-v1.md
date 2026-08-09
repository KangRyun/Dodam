# 그림 생성·완료 API 멱등성 계약 v1

> 기준 이슈: `S15P11B209-527`
>
> 적용 범위: 그림 활동의 세션 생성, 그림 단계 완료, 전체 활동 완료

## 1. 공통 규칙

- 아래 API의 `Idempotency-Key` Header는 필수다.
- 값은 8자 이상 100자 이하이며 공백 문자열과 제어 문자를 허용하지 않는다.
- 클라이언트는 한 업무 요청을 재전송할 때 최초 요청과 같은 키를 사용한다.
- 키를 새 업무 요청에 재사용하면 `409 DRAWING_409_002`를 반환한다.
- 키가 없으면 `400 DRAWING_400_003`, 형식이 잘못되면
  `400 DRAWING_400_004`를 반환한다.
- 서버가 최초 요청을 처리 중인 경우 완료되지 않은 상태를 성공으로 만들지 않고
  해당 API의 처리 충돌 응답을 반환한다.

## 2. API별 판정 기준

| API | 같은 요청으로 판정하는 기준 | 재전송 결과 |
| --- | --- | --- |
| `POST /api/v1/drawing-sessions` | `childId`, `drawingTypeId`, `inputMethod`가 기존 세션과 일치 | 기존 `drawingSessionId`를 포함한 HTTP 201 응답 |
| `POST /api/v1/drawing-sessions/{drawingSessionId}/drawing-complete` | 같은 Session에서 같은 키로 생성된 FINAL 객체 탐지 분석 | 저장·분석을 반복하지 않고 기존 Asset·분석 상태 반환 |
| `POST /api/v1/drawing-sessions/{drawingSessionId}/complete` | 같은 Session, `conversationSkipped`가 최초 접수와 일치하고 `requestReport=true` | 기존 분석·리포트 접수 상태를 포함한 HTTP 202 응답 |

`clientStartedAt`, Canvas 설정과 클라이언트 완료 시각은 서버의 공식 생성 시각이나
이미 저장된 결과를 바꾸지 않는 관측 정보다. 그림 단계 완료 재전송은 최초 처리에서
저장된 FINAL Asset과 분석 결과를 기준으로 응답하며 새 파일을 저장하지 않는다.

## 3. 저장 및 동시성

- 그림 세션 생성은 `drawing_sessions.idempotency_key` UNIQUE 제약과 아동 단위
  잠금으로 중복 세션을 방지한다.
- 그림 단계 완료와 전체 활동 완료는 `analyses.idempotency_key` UNIQUE 제약으로
  중복 분석을 방지한다.
- 애플리케이션의 선조회는 정상 재전송 응답을 만들기 위한 것이며, DB UNIQUE
  제약이 동시 요청의 최종 중복 방어선이다.
- 같은 키가 다른 Session 또는 다른 작업 유형에 사용되면 내부 Constraint 이름을
  노출하지 않고 도메인 충돌 응답으로 변환한다.

## 4. 제외 범위

- 대화 시작·질문·답변·종료 API는 Redis 기반 대화 멱등성 계약을 따른다.
- 분석 재시도 `POST /api/v1/analyses/{analysisId}/retry`는 현재 서버 생성
  `requestId`를 사용한다. Client `Idempotency-Key` 재생 계약은 이 문서의 적용
  범위가 아니며 별도 계약과 저장 구조 없이 구현된 것으로 간주하지 않는다.
