# 그림 분석 진행 상태 및 결과 조회 API 설계

## 목표

`GET /api/v1/drawing-sessions/{drawingSessionId}/analyses/{drawingAnalysisId}`로 이미 저장된 분석 상태와 객체 탐지 결과를 조회한다. 조회 과정은 AI Client, 파일 저장소, 재시도 로직을 호출하지 않고 DB 상태를 변경하지 않는다.

## 현재 프로젝트 기준

- `S15P11B209-147`의 `DrawingAnalysis`, `DrawingDetectedObject`, 응답 DTO를 재사용한다.
- DB 상태 `SUCCESS`만 공개 상태 `SUCCEEDED`로 변환한다.
- `analyses`와 `analysis_detected_objects`에는 Soft Delete 컬럼이 없으므로 존재하지 않는 조건이나 Migration을 추가하지 않는다. `drawing_sessions.deleted_at`만 기존 정책대로 조회에서 제외한다.
- 그림 API 공통 인증·소유권 검증이 아직 없으므로 임시 Header나 사용자 ID를 도입하지 않는다.
- 기존 `analysis_id` 인덱스로 단일 분석의 Detection을 조회할 수 있고 결과 수가 제한적이므로 조회 API만을 위한 Migration은 추가하지 않는다.

## 구조

- 기존 `DrawingAnalysisController`에 GET Endpoint를 추가한다.
- `DrawingAnalysisQueryService`가 읽기 전용 Transaction과 상태별 응답 조립을 담당한다.
- `DrawingAnalysisRepository`는 Session, Asset, Detection을 한 번에 Fetch Join하고 Session ID와 Analysis ID를 동시에 조건으로 사용한다.
- `DrawingAnalysisDetailResponse`와 `DrawingAnalysisFailureResponse`만 새로 만들고 Model, Detection, Bounding Box DTO는 재사용한다.

## 상태 계약

- `PENDING`, `PROCESSING`: Model·완료 시각·실패 정보가 없고 Detection이 비어 있어야 한다.
- `SUCCESS`: Model과 완료 시각이 있어야 하며 Detection은 0건 이상이다. API에는 `SUCCEEDED`로 반환한다.
- `FAILED`: 완료 시각과 저장된 안전한 실패 정보가 있어야 하며 Model과 Detection은 없어야 한다. 공개 실패 값은 `AI_ANALYSIS_FAILED`와 고정된 안전한 메시지로 반환한다.
- `PARTIAL_SUCCESS`: 현재 공개 API 계약에 없으므로 데이터 무결성 오류로 처리한다.
- 상태와 저장 데이터가 모순되거나 Legacy Nullable 필수 데이터가 없으면 `DRAWING_ANALYSIS_RESULT_INCONSISTENT`를 반환한다.

## 오류 및 보안

- Analysis가 없거나 다른 Session에 속하거나 Session이 삭제된 경우 모두 `DRAWING_ANALYSIS_NOT_FOUND` 404로 통일해 존재 여부를 노출하지 않는다.
- Entity, Storage Key, 파일 경로, 이미지 Byte, AI 원문 오류, 내부 Exception을 응답에 포함하지 않는다.
- 조회 API는 `DrawingAnalysisClient`에 의존하지 않는다.

## 검증

- Service 테스트로 네 상태, Detection 순서, 빈 결과, 정합성 오류와 읽기 전용 동작을 검증한다.
- Repository·통합 테스트로 Session 관계, 삭제된 Session 제외, 저장 결과 조회와 정렬을 검증한다.
- Controller 테스트로 HTTP 200·400·404·500 및 공통 응답 직렬화를 검증한다.
- `clean test`, `spotlessCheck`, `javadoc`을 실행한다.
