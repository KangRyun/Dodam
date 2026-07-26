# 진행 중 그림 재개 및 Draft 복원 통합 설계

## 목적

아동이 완료하지 않은 그림 활동에 다시 진입할 때 새 세션 생성으로 인한
`ACTIVE_DRAWING_SESSION_EXISTS` 충돌을 방지하고, 최신 Draft 이미지를 인증된
Backend API를 통해 내려받아 Canvas 배경으로 복원한다.

## 현재 구현과 계약

- Flutter는 그림 활동 시작 시 항상 그림 유형을 조회하고 새 세션을 생성한다.
- Backend는 아동별 활성 세션을 한 건만 허용하므로 기존 세션이 있으면 생성 요청이
  `409`로 실패한다.
- Flutter의 Draft 복원 화면과 상태 모델은 이미 존재하지만 `NetworkImage`로
  `previewUrl`을 직접 요청하여 Access Token 갱신 및 공통 API 처리를 재사용하지
  못한다.
- Backend는 최신 Draft 조회 시 `previewUrl`을
  `/api/v1/drawing-assets/{drawingAssetId}/file` 형식으로 반환한다.
- 이미지 조회 API는 Access Token을 요구하고 응답에
  `Cache-Control: private, no-store`를 사용한다.
- 활성 세션 없음과 최신 Draft 없음의 오류 코드는 각각
  `DRAWING_404_005`, `DRAWING_404_004`이다.

## 설계

### 세션 시작 및 재개

그림 시작 동작을 화면에서 분리한 Application Controller가 다음 순서로 세션을
결정한다.

1. `GET /api/v1/drawing-sessions/active?childId={childId}`를 호출한다.
2. 활성 세션이 있으면 기존 `drawingSessionId`를 반환한다.
3. `DRAWING_404_005`이면 그림 유형을 조회하고 새 세션을 생성한다.
4. 조회와 생성 사이에 다른 요청이 세션을 만들 수 있으므로 생성이
   `ACTIVE_DRAWING_SESSION_EXISTS`로 실패하면 활성 세션을 한 번 다시 조회한다.
5. 재조회에도 세션이 없거나 다른 오류가 발생하면 실패를 상위 화면에 전달한다.

활성 세션 응답은 기존 상세 세션 DTO와 필드 구성이 다르므로
`ActiveDrawingSessionDto`로 별도 역직렬화한다. 화면은 신규 생성과 재개를
구분하지 않고 결정된 `sessionId`로 기존 `DrawingScreen`에 진입한다.

### 최신 Draft 조회

`DrawingRepository.getDraft`는 `DRAWING_404_004`를 `null`로 변환한다. 그 외
인증, 권한, 서버 오류는 그대로 전달하여 복원 화면에서 조회 실패 상태로
표시한다. 성공 응답은 공통 응답의 `data`를 벗긴 뒤 `DraftRecoveryDto`로
역직렬화한다.

### 인증 이미지 다운로드

`DrawingRepository`에 Draft 미리보기 바이트를 내려받는 메서드를 추가한다.
Remote 구현은 기존 `ApiClient`를 사용하여 Access Token과 401 토큰 갱신·재시도
동작을 그대로 적용한다.

서버가 반환한 URL은 다음 조건을 모두 만족할 때만 요청한다.

- 상대 경로이며 scheme, authority, query, fragment가 없다.
- 정확히 `/api/v1/drawing-assets/{양의 정수}/file` 형식이다.
- 상위 경로 이동이나 다른 API 리소스를 포함하지 않는다.

검증이 끝난 URL에서 `/api/v1/`만 제거하여 `ApiClient`의 base URL과 결합한다.
응답은 `ResponseType.bytes`로 받고 비어 있지 않은 `Uint8List`로 변환한다.
잘못된 URL이나 빈 응답은 복원 실패로 처리하며 외부 호스트로 요청하지 않는다.

### Canvas 복원

`DrawingDraftRestoreController.continueDrawing`을 비동기로 변경한다.

1. Repository로 Draft 이미지를 다운로드한다.
2. 성공한 바이트를 `MemoryImage`로 변환한다.
3. 기존 화면이 이미지 로딩 완료를 통지하면 `restored` 상태가 된다.
4. 다운로드 또는 이미지 디코딩 실패 시 배경을 제거하고 `imageFailed` 상태로
   전환한다.

복원 이미지는 기존처럼 새 Stroke 아래의 배경으로 사용한다. 서버의 벡터 Stroke
이력을 재구성하거나 복원 이미지에 대한 Undo를 제공하지 않는다.

## 오류 처리

- 활성 세션 없음과 Draft 없음만 정상적인 분기로 취급한다.
- 인증, 권한, 네트워크, 역직렬화 오류는 일반 실패로 노출한다.
- 새 세션 생성의 `409`는 활성 세션 재조회로 한 번만 복구한다.
- 이미지 URL 검증 실패 시 네트워크 요청을 보내지 않는다.
- 오류 메시지나 로그에 Token, 이미지 원본, 아동 개인정보를 포함하지 않는다.

## 테스트

- 활성 세션 공통 응답 역직렬화와 없음 오류 변환
- 활성 세션 재개, 신규 생성, 생성 경쟁 상태 복구
- Draft 없음 오류 변환과 공통 응답 역직렬화
- 허용된 미리보기 URL의 인증 API 다운로드 및 바이트 반환
- 외부 URL, query 포함 URL, 잘못된 Asset 경로 차단
- Draft 조회 후 다운로드, `MemoryImage` 복원, 재시도와 실패 상태
- 기존 Stroke Batch, Draft 업로드, Drawing Complete 회귀 테스트

## 제외 범위

- Stroke Batch DTO와 sequence 정책
- Draft 업로드 multipart 구조
- Drawing Complete multipart 및 FINAL 분석 위임
- 서버 Draft 삭제를 동반하는 새로 그리기 정책
- 복원 전 Stroke 벡터 이력과 Undo 이력 재생
- Backend Storage 구현 및 이미지 Proxy Endpoint 변경
