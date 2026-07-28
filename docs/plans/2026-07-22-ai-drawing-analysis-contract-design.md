# AI 그림 분석 공통 경계

> 상태: 2026-07-28 현재 구현과 출시 대상 활동을 반영한 공통 기준
> 활동별 정본:
> - [HTP 활동 계약 및 구현 기준](./2026-07-28-htp-service-contract.md)
> - [그림일기 활동 계약 및 구현 기준](./2026-07-28-art-diary-service-contract.md)

## 1. 책임 경계

- Flutter는 Spring Boot 공개 API만 호출한다.
- Spring Boot는 사용자 권한, 동의, 세션 상태, 저장 이미지 Metadata를 검증한 뒤 AI 서버를 호출한다.
- AI 서버는 MySQL에 직접 접근하지 않고 분석 결과만 반환한다.
- Spring Boot는 AI 결과의 Schema와 안전 정책을 검증한 뒤 저장한다.
- 이미지 원본, signed URL, Token, 아동 발화는 로그에 기록하지 않는다.

## 2. 현재 내부 Endpoint

```text
POST /internal/v1/analyses
```

- 인증: `X-Internal-Token`
- 추적: `X-Request-Id`
- 본문: `application/json`
- 이미지 전달: 짧은 만료시간의 내부 읽기 전용 `drawing.signedUrl`
- Bounding Box: 0~1 정규화 좌표
- 결과: `detectedObjects`, `visualFeatures`, `behaviorFeatures`, `conversationSummary`, `observationDraft`, `unusedInputs`, `warnings`

과거 초안의 `imageReference.storageKey`, 픽셀 Bounding Box, `/internal/ai/v1/drawings/analysis` 계약은 사용하지 않는다. Storage Key는 AI에 노출하지 않고 Backend가 발급한 내부 URL로 변환한다.

## 3. 활동별 모델 라우팅

현재 공통 요청의 `analysisType`은 분석 시점(`INTERMEDIATE`, `FINAL`)만 나타내며 활동 종류를 구분하지 못한다. HTP와 그림일기의 가중치가 다르므로 다음 필드를 공통 요청에 추가한다.

| 필드 | 타입 | 규칙 |
| --- | --- | --- |
| `activityType` | `HTP`, `ART_DIARY` | 필수 |
| `drawingSubject` | `HOUSE`, `TREE`, `PERSON`, `null` | HTP이면 필수, 그림일기이면 `null` |

라우팅 규칙:

```text
activityType=HTP
  → htp 모델
  → drawingSubject로 HOUSE/TREE/PERSON 품질 검증

activityType=ART_DIARY
  → sketch 모델
  → drawingSubject 미사용
```

알 수 없는 활동이나 잘못된 조합은 다른 모델로 추측해 처리하지 않고 요청 오류로 거부한다.

## 4. 주제와 탐지 라벨의 차이

`drawingSubject`는 **무엇을 그리도록 요청했는지**를 나타내는 입력 맥락이다. `detectedObjects[].objectCode`는 **실제로 무엇이 탐지됐는지**를 나타내는 결과다.

- HTP의 `drawingSubject=HOUSE`라도 탐지 결과에는 `HOUSE_ROOF`, `HOUSE_WINDOW`, `SUN` 등이 포함될 수 있다.
- HTP의 47개 세부 라벨을 `HOUSE`, `TREE`, `PERSON` 세 개로 축약하지 않는다.
- AI가 기대 주제를 찾지 못해도 `drawingSubject`를 탐지 결과로 위조하지 않는다.
- 그림일기에는 HTP `drawingSubject`를 넣지 않는다.

## 5. 이미지와 좌표

- 이미지 크기의 정본은 업로드된 이미지 Header에서 추출한 실제 픽셀 크기다.
- Spring Boot는 이 값을 `drawing_assets.width_px`, `height_px`에 저장하고 AI 요청의 `drawing.width`, `height`로 전달한다.
- AI 응답 Bounding Box는 이미지 크기와 무관하게 0~1 범위로 정규화한다.
- 픽셀 좌표가 필요한 저장소는 실제 이미지 크기를 곱해 변환하되 원본 정규화 값과 의미를 섞지 않는다.

## 6. 실패 처리

- 이미지 저장 성공 후 AI 호출 실패가 발생해도 저장된 그림을 삭제하지 않는다.
- 모델 가중치가 준비되지 않았으면 다른 활동의 모델로 대체하지 않는다.
- 일부 입력만 사용하지 못한 경우 `PARTIAL_SUCCESS`와 `unusedInputs`로 이유를 반환한다.
- 이미지 디코딩 불가처럼 분석 자체가 불가능하면 `FAILED`로 반환한다.
- 인증·요청 Schema 오류는 HTTP 오류로 반환하고, 추론 결과 실패와 구분한다.

## 7. 안전 규칙

- 진단명, 질환 확률, 성격 단정, 보호자나 가정환경의 원인 추정은 생성하지 않는다.
- 사람의 성별을 그림으로 판정하지 않는다.
- 객체 탐지 confidence를 정서나 심리 상태의 confidence로 사용하지 않는다.
- 전문가 검토 전 관찰 결과는 `AI_DRAFT`로 표시한다.
- 실제 발화와 AI 요약을 분리하고 대표 발화에는 원본 메시지 식별자를 유지한다.

## 8. 구현 정합성

현재 구현:

- Spring Boot `AiDrawingAnalysisRequest`와 AI `AnalysisRequest`는 §19.3 기본 필드를 지원한다.
- `RestClientDrawingAnalysisClient`는 `X-Internal-Token`, `X-Request-Id`, signed URL을 사용한다.
- AI에는 `htp`와 `sketch` 가중치 등록·checksum 검증 경로가 있다.
- 실제 분석 파이프라인은 아직 HTP 모델을 기본으로 사용한다.

반영이 필요한 항목:

1. 양쪽 요청 DTO에 `activityType`, `drawingSubject`를 같은 배포 단위로 추가
2. 분석 실행 시 `DrawingSession → DrawingType.code`를 읽어 `activityType` 구성
3. HTP는 HTP 단계 저장값에서 `drawingSubject` 구성
4. AI의 활동별 모델 선택과 잘못된 필드 조합 검증
5. 활동별 Contract Test와 실제 가중치 종단 스모크

이 다섯 항목이 끝나기 전에는 활동별 객체 탐지가 완전히 연동됐다고 판단하지 않는다.
