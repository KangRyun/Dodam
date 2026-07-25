# S15P11B209-371 그림 파일 프록시 구현 계획

> 실행 기준: `codex/feature/S15P11B209-371-drawing-asset-proxy` 브랜치에서 테스트를 먼저 추가하고, 각 실패를 확인한 뒤 최소 구현으로 통과시킨다.

**목표:** 보호자가 소유한 그림 파일을 JWT 인증 기반으로 스트리밍하고, 활성 세션 및 최신 Draft 응답에 동일한 상대 `previewUrl`을 제공한다.

**구조:** `DrawingAssetFileQueryService`가 현재 사용자와 그림 세션 접근 권한을 검증한 뒤 `ImageStorage`에서 파일을 연다. `DrawingAssetFileController`는 파일을 버퍼 단위로 전송하고 캐시 금지 헤더를 적용한다. `DrawingAssetFileUrlFactory`는 응답 DTO에서 사용하는 상대 URL 생성을 한 곳으로 통일한다.

**기술:** Java 21, Spring Boot 3.5, Spring MVC `StreamingResponseBody`, JUnit 5, Mockito, AssertJ

---

## Task 1: Draft 조회 응답에 공통 previewUrl 적용

**Files**

- Create: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingAssetFileUrlFactory.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingDraftService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingSessionQueryService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingDraftResponse.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/LatestDrawingDraftResponse.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingDraftServiceTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingSessionQueryServiceTest.java`

1. 최신 Draft와 활성 세션 응답이 `/api/v1/drawing-assets/{id}/file`을 반환해야 한다는 실패 테스트를 작성한다.
2. 관련 테스트만 실행해 기존 `null` 응답 때문에 실패하는지 확인한다.
3. 상대 URL 생성 전용 Component를 추가하고 두 Service에 주입해 동일한 URL을 사용한다.
4. DTO Javadoc을 실제 동작에 맞게 수정한다.
5. 관련 테스트를 다시 실행해 통과를 확인한다.

## Task 2: 인증·소유권을 검증하는 파일 조회 Service 구현

**Files**

- Create: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingAssetFileQueryService.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingAssetFileResource.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/exception/DrawingErrorCode.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingAssetFileQueryServiceTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/exception/DrawingErrorCodeTest.java`

1. 정상 조회, 존재하지 않는 Asset, 타인 세션 접근 거부, 인증 사용자 부재를 검증하는 실패 테스트를 작성한다.
2. 관련 테스트를 실행해 Production Type 부재로 실패하는지 확인한다.
3. 현재 사용자 확인 → Asset Metadata 조회 → 세션 접근 검증 → `ImageStorage.read` 순서로 구현한다.
4. Asset 미존재 오류 `DRAWING_ASSET_NOT_FOUND`를 기존 코드와 중복되지 않는 `DRAWING_404_006`으로 추가한다.
5. 타인 접근은 기존 자원 존재 은닉 정책에 따라 `DRAWING_SESSION_NOT_FOUND(404)`를 유지한다.
6. 관련 테스트를 다시 실행해 통과를 확인한다.

## Task 3: 그림 파일 스트리밍 Controller 구현

**Files**

- Create: `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingAssetFileController.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingAssetFileControllerTest.java`

1. 응답 본문, `Content-Type`, `Content-Length`, `Cache-Control: private, no-store`를 검증하는 실패 테스트를 작성한다.
2. 관련 테스트를 실행해 Controller 부재로 실패하는지 확인한다.
3. `GET /api/v1/drawing-assets/{drawingAssetId}/file`을 구현하고 `StoredImageContent`를 스트리밍 완료 시 닫는다.
4. Controller와 공개 메서드에 실제 인증·스트리밍 책임을 설명하는 한국어 Javadoc과 Swagger 설명을 작성한다.
5. 관련 테스트를 다시 실행해 통과를 확인한다.

## Task 4: Controller 응답 계약 및 회귀 검증

**Files**

- Modify: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingDraftControllerTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingSessionControllerTest.java`
- Modify: `README.md` (기존 API 안내가 있는 경우에만 최소 보완)

1. 최신 Draft와 활성 세션 Controller JSON에 상대 `previewUrl`이 직렬화되는지 기대값을 갱신한다.
2. Storage Key와 서버 절대 경로가 응답에 포함되지 않는지 확인한다.
3. 관련 Drawing 테스트를 실행한다.

## Task 5: 전체 검증과 통합

1. `gradlew.bat clean test --no-daemon`을 실행한다.
2. `gradlew.bat spotlessCheck --no-daemon`을 실행한다.
3. `gradlew.bat javadoc --no-daemon`을 실행한다.
4. `backend/build/docs/javadoc/index.html` 생성 여부를 확인한다.
5. `git diff --check`, `git status --short`, 변경 파일과 Secret 노출 여부를 점검한다.
6. 이슈 코드를 포함한 Commit을 생성하고 원격 Branch에 Push한다.
7. `develop` 대상 Merge Request를 생성해 Pipeline을 확인한 뒤 이상이 없으면 Merge한다.
8. Jira S15P11B209-371에 구현·검증 결과와 기존 403 요구를 404로 유지한 보안 사유를 기록하고 완료 처리한다.

## 제외 범위

- Stroke Batch URI·DTO·sequence 변환
- Draft 업로드 multipart JSON MIME
- Drawing Complete metadata 및 stage 처리
- Flutter Draft 다운로드·화면 복원
- Presigned URL과 공개 URL
