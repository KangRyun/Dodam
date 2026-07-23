# S15P11B209-144 DRAFT 객체 탐지 허용 설계

## 목적

프론트엔드가 자동 저장한 `DRAFT` 그림을 대상으로 객체 탐지를 요청할 수 있게 한다. 기존 `FINAL` 객체 탐지와 활동 완료 분석 계약은 유지하며, 자동 저장 후 3초 대기 정책은 프론트엔드 debounce 책임으로 둔다.

## 현재 충돌

`POST /api/v1/drawing-sessions/{drawingSessionId}/analyses`는 `drawingAssetId`와 `analysisType`을 받지만 Persistence Service가 `DrawingAssetType.FINAL`만 허용하고 분석 범위를 항상 `FINAL`로 저장한다. 따라서 자동 저장 API가 생성한 `DRAFT` 식별자를 전달하면 `DRAWING_ANALYSIS_NOT_ALLOWED`로 거부된다.

DB의 `analyses.analysis_type`은 이미 `INTERMEDIATE`, `FINAL` 값을 지원하므로 Schema 변경은 필요하지 않다.

## 공개 API 계약

URI와 요청 형식은 변경하지 않는다.

```http
POST /api/v1/drawing-sessions/{drawingSessionId}/analyses
Content-Type: application/json
```

```json
{
  "drawingAssetId": 200,
  "analysisType": "OBJECT_DETECTION"
}
```

허용 조합은 다음과 같다.

| DrawingAssetType | DrawingAnalysisType | 저장할 DrawingAnalysisScope | 결과 |
| --- | --- | --- | --- |
| `DRAFT` | `OBJECT_DETECTION` | `INTERMEDIATE` | 허용 |
| `FINAL` | `OBJECT_DETECTION` | `FINAL` | 허용 |
| `INTERMEDIATE` | 모든 유형 | 해당 없음 | 거부 |
| `UPLOADED`, `THUMBNAIL`, `TIMELAPSE` | 모든 유형 | 해당 없음 | 거부 |
| `DRAFT` | `ACTIVITY_REPORT` | 해당 없음 | 거부 |
| `FINAL` | `ACTIVITY_REPORT` | 해당 없음 | 공개 분석 요청에서는 거부 |

`ACTIVITY_REPORT`는 그림 활동 완료 Service가 생성하는 내부 최종 분석 요청에만 사용한다. 공개 객체 탐지 API가 리포트 생성을 우회할 수 없게 한다.

## 검증과 데이터 흐름

1. Access Token에서 현재 보호자 식별자를 확인한다.
2. 보호자가 그림 활동에 접근할 수 있는지 검증한다.
3. 삭제되지 않은 세션을 쓰기 잠금으로 조회한다.
4. 세션이 `IN_PROGRESS/DRAWING`인지 확인한다.
5. Asset이 같은 세션에 속하는지 확인한다.
6. 작업 유형이 `OBJECT_DETECTION`인지 확인한다.
7. Asset 유형을 분석 범위로 변환한다.
   - `DRAFT` → `INTERMEDIATE`
   - `FINAL` → `FINAL`
8. 같은 Asset과 작업 유형에 `PROCESSING` 또는 `SUCCESS` 분석이 있으면 `409`를 반환한다.
9. 계산한 분석 범위로 `analyses` Row를 저장하고 기존 AI Client를 호출한다.

3초 대기는 서버가 예약 작업으로 처리하지 않는다. 프론트엔드는 마지막 자동 저장 성공 후 3초 동안 추가 변경이 없을 때 해당 응답의 `drawingAssetId`로 분석을 요청한다.

## 오류 처리

- 다른 세션의 Asset, 허용하지 않는 Asset 유형 또는 `ACTIVITY_REPORT` 공개 요청은 기존 `DRAWING_ANALYSIS_NOT_ALLOWED` 오류를 사용한다.
- Asset이 없으면 기존 `DRAWING_ANALYSIS_TARGET_NOT_FOUND`를 사용한다.
- 같은 Asset의 중복 객체 탐지는 기존 `DRAWING_ANALYSIS_ALREADY_EXISTS`를 사용한다.
- AI Client 실패, 응답 검증 실패 및 결과 저장 실패 정책은 변경하지 않는다.

## 구현 범위

- Persistence Service의 Asset 유형·작업 유형 검증과 분석 범위 결정
- Service와 Controller Javadoc 및 Swagger 설명 수정
- AI 그림 분석 계약 문서에 허용 조합과 debounce 책임 추가
- Persistence 단위 테스트
- MySQL 통합 테스트에서 `DRAFT` 요청과 `INTERMEDIATE` 저장 검증
- 기존 `FINAL` 요청 회귀 테스트

다음 항목은 제외한다.

- 프론트엔드 debounce 구현
- 새로운 Endpoint 또는 요청 필드
- Flyway Migration
- 실제 AI 서버 연결 방식 변경
- `INTERMEDIATE` 스냅샷 분석 허용
- 자동 분석 Scheduler 또는 Queue

## 완료 조건

- `DRAFT + OBJECT_DETECTION` 요청이 성공한다.
- DRAFT 분석은 DB에 `INTERMEDIATE`로 저장된다.
- `FINAL + OBJECT_DETECTION`은 기존처럼 `FINAL`로 저장된다.
- DRAFT 또는 FINAL의 `ACTIVITY_REPORT` 공개 요청은 거부된다.
- 허용하지 않은 Asset과 다른 세션 Asset은 계속 거부된다.
- API 문서가 실제 허용 범위 및 프론트 debounce 책임과 일치한다.
- 전체 테스트, Spotless와 Javadoc이 성공한다.
