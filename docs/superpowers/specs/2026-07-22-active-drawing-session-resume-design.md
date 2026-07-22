# 진행 중 그림 활동 조회 및 재개 설계

## 목표

앱 재진입 시 특정 아동의 진행 중 그림 활동과 가장 최근 자동 저장 초안 Metadata를 한 번에 조회할 수 있게 한다. 조회만 수행하며 세션 상태, 초안, AI 분석 결과를 생성하거나 변경하지 않는다.

## 선행 구현과 경계

- `S15P11B209-138`의 `DrawingSession`, 생성 API와 활성 세션 중복 검사 구조를 재사용한다.
- `S15P11B209-279`의 `DrawingAssetType.DRAFT`, `assetVersion DESC` 최신 초안 기준과 `DrawingAssetRepository.findLatestDraft`를 재사용한다.
- 생성 Transaction과 조회 Transaction을 섞지 않도록 기존 `DrawingSessionService`는 변경하지 않고 조회 전용 `DrawingSessionQueryService`를 추가한다.
- 기존 `GET /drawing-sessions/{drawingSessionId}/draft`는 특정 세션의 초안 Metadata 조회 책임을 유지한다.
- 이번 API는 아동 기준으로 활성 세션을 발견하고 재개 화면에 필요한 세션·초안 요약을 조립하는 책임만 갖는다.

## API 계약

```http
GET /api/v1/drawing-sessions/active?childId={childId}
```

- 기존 `DrawingSessionController`의 Resource 중심 URI Convention을 따른다.
- `childId`는 필수이며 1 이상의 정수다.
- 별도 `/resume`, `/current`, 아동 중첩 Endpoint를 만들지 않는다.
- 성공은 HTTP 200과 기존 `ApiResponse<T>`를 사용한다.
- 진행 중 세션이 없으면 HTTP 404 `ACTIVE_DRAWING_SESSION_NOT_FOUND`를 반환한다.
- 같은 아동에게 활성 세션이 두 건 이상이면 HTTP 500 `MULTIPLE_ACTIVE_DRAWING_SESSIONS`를 반환한다.

## 응답

`ActiveDrawingSessionResponse`는 다음 필드를 반환한다.

```json
{
  "drawingSessionId": 100,
  "childId": 1,
  "drawingType": {
    "drawingTypeId": 2,
    "code": "FREE_DRAWING",
    "name": "자유화 활동"
  },
  "inputMethod": "CANVAS",
  "sessionStatus": "IN_PROGRESS",
  "currentStage": "DRAWING",
  "startedAt": "2026-07-22T04:00:00Z",
  "latestDraft": {
    "drawingAssetId": 210,
    "assetVersion": 3,
    "lastEventSequence": 17,
    "contentType": "image/png",
    "fileSize": 245810,
    "clientSavedAt": "2026-07-22T05:30:00Z",
    "savedAt": "2026-07-22T05:30:01Z",
    "previewUrl": null
  }
}
```

- `drawingType`은 기존 `DrawingTypeSummaryResponse`를 재사용한다.
- `latestDraft`는 이 API에 필요한 최소 필드만 가진 `LatestDrawingDraftResponse`로 분리한다. 이로써 이슈 279의 상세 초안 응답 계약을 변경하지 않는다.
- 초안이 없으면 `latestDraft`는 `null`이며 조회는 성공한다.
- 이미지 다운로드 API가 없으므로 `previewUrl`은 `null`이다.
- 내부 Storage Key, 절대 경로, 원본 파일명, 이미지 Byte, Base64는 반환하지 않는다.
- 아동 이름·생년월일, 보호자 정보, `startedByUserId`, 분석·대화·감정·리포트 정보는 반환하지 않는다.

## 조회 흐름

1. Controller가 `childId`의 양수 Validation을 수행한다.
2. `DrawingSessionQueryService`가 읽기 전용 Transaction을 시작한다.
3. Repository가 `child_id`, `IN_PROGRESS`, `deleted_at IS NULL` 조건으로 활성 세션과 `Child`, `DrawingType`을 Fetch Join 조회한다.
4. 조회 결과가 0건이면 404, 2건 이상이면 명시적인 500 데이터 무결성 오류로 변환한다.
5. 한 건이면 기존 `findLatestDraft`로 해당 세션의 가장 높은 `DRAFT.assetVersion` 한 건을 조회한다.
6. Entity를 응답 DTO로 변환하고 반환한다.

`currentStage`가 `DRAWING`이 아니더라도 `sessionStatus=IN_PROGRESS`이면 실제 단계를 그대로 반환한다. 별도 `resumable` 필드나 상태 전이는 추가하지 않는다.

## Repository와 데이터 무결성

- 생성용 `findActiveByChildId`의 `PESSIMISTIC_WRITE` 의미는 유지한다.
- 조회 API에는 잠금 없는 `List<DrawingSession> findActiveSessionsByChildId(...)`를 별도로 추가한다.
- `List`를 사용하는 이유는 손상된 데이터에서 여러 활성 세션을 임의로 첫 번째 한 건으로 숨기지 않기 위해서다.
- 정상 생성 경로는 Child Row 잠금으로 동시 생성을 직렬화한다.
- `idx_drawing_sessions_active_child(child_id, session_status, deleted_at)`가 이미 있으므로 새 Migration은 만들지 않는다.
- `drawing_assets`에는 Soft Delete Column이 없고 초안 삭제 API도 아직 없다. 따라서 현재 최신 초안 조회는 `DRAFT` 유형과 버전 기준을 적용하며 존재하지 않는 삭제 조건을 임의로 추가하지 않는다.

## 오류 처리

- `ACTIVE_DRAWING_SESSION_NOT_FOUND`: 404, 활성 세션 없음
- `MULTIPLE_ACTIVE_DRAWING_SESSIONS`: 500, 동일 아동 활성 세션 데이터 무결성 오류
- Query Parameter 누락·0·음수: 기존 공통 400 Validation 응답
- 오류 응답과 로그에 아동 개인정보, SQL, Constraint 이름, Entity와 내부 경로를 포함하지 않는다.

## 인증과 외부 시스템

- 현재 인증 인프라가 없으므로 가짜 Principal, 사용자 Header나 하드코딩 사용자 ID를 추가하지 않는다.
- Service는 `ImageStorage`와 파일 시스템에 의존하지 않는다.
- AI Client를 주입하거나 호출하지 않는다.
- 인증과 보호자-아동 소유권 검증은 인증 인프라 도입 이슈에서 연결한다.

## 테스트

- Repository: 활성 세션 한 건, 완료·실패·삭제 세션 제외, 다른 아동 분리, Fetch Join 조회를 검증한다.
- Service: 활성 세션과 최신 초안, 초안 없는 성공, 404, 다중 세션 500, 최신 `assetVersion` 사용을 검증한다.
- Controller: HTTP 200, `latestDraft=null`, Validation 400, 404·500 전달, 개인정보·내부 경로 미노출을 검증한다.
- OpenAPI: 확정 URI, Query Parameter, 200·400·404·500 응답과 인증 Scheme 미노출을 검증한다.
- 전체 `clean test`, `spotlessCheck`, `javadoc`을 실행한다.

## 제외 범위

- 별도 세션 `/resume` Endpoint
- 이미지 다운로드와 Byte 응답
- Canvas·Stroke 복원
- 프론트엔드 재개 화면
- 초안 저장·삭제·목록·특정 버전 조회
- Session 상태·Stage 변경
- AI 분석, 대화, 감정, 활동 완료, 리포트
- 인증·소유권 검증 인프라
- DB Migration과 새 Table
