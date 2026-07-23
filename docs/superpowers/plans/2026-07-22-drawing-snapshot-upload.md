# Drawing Snapshot Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 특정 그림 활동 세션의 JPEG·PNG 중간본 또는 최종본을 로컬 Storage와 `drawing_assets`에 일관되게 저장하는 Multipart API를 구현한다.

**Architecture:** HTTP 계층은 Multipart를 Storage Command로 변환하고, `DrawingSnapshotService`는 세션 검증·파일 저장·Metadata 저장·실패 보상을 조정한다. 기존 `ImageStorage`는 SHA-256과 안전한 삭제 계약을 제공하고, MySQL V4 제약이 유형별 버전 중복과 세션별 FINAL 중복을 최종 차단한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring MVC, Validation, Spring Data JPA, Flyway, MySQL 8.4, H2, Testcontainers, JUnit 5, Mockito, AssertJ, Springdoc OpenAPI

## Global Constraints

- Jira는 `S15P11B209-141`이며 브랜치는 이슈 코드 없는 로컬 전용 `feat/drawing-snapshot-upload`을 사용한다.
- 사용자의 추가 요청 전까지 Commit, Push, Merge Request, Merge를 수행하지 않는다.
- 기존 V1~V3 Migration, 공통 응답·예외, Swagger·CORS와 Java·Gradle 버전을 수정하지 않는다.
- JPEG·PNG와 최대 10 MiB만 허용하며 WEBP, AI, S3, 인증, 활동 상태 전환을 추가하지 않는다.
- Production 공개 Type과 오해 가능한 공개 메서드에는 실제 동작과 일치하는 한국어 Javadoc을 작성한다.
- 모든 Production 동작은 실패하는 테스트를 먼저 확인한 뒤 최소 구현한다.

---

### Task 1: Storage Checksum과 보상 삭제

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/storage/image/ImageStorage.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/image/StoredImage.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/image/LocalImageStorage.java`
- Modify: `backend/src/test/java/com/ssafy/b209/storage/image/LocalImageStorageTest.java`

**Interfaces:**
- Produces: `StoredImage(String storageKey, String storedFileName, String contentType, long size, String checksumSha256)`
- Produces: `void ImageStorage.delete(String storageKey)`

- [ ] **Step 1: Checksum과 삭제의 실패 테스트를 작성한다**

  정상 PNG 저장 결과의 `checksumSha256`이 `MessageDigest.getInstance("SHA-256")` 결과와 같은지 검증한다. 저장된 Key 삭제, 없는 Key 삭제, 절대 Key와 `../` Key 거부, Symbolic Link 경로 거부를 각각 테스트한다.

- [ ] **Step 2: Storage 테스트의 RED를 확인한다**

  Run: `gradlew.bat test --tests "*LocalImageStorageTest"`
  Expected: `StoredImage.checksumSha256()`와 `ImageStorage.delete(...)` 부재로 컴파일 실패.

- [ ] **Step 3: 단일 Streaming Checksum과 안전한 삭제를 구현한다**

  `copyToTemporaryFile`의 반복문에서 SHA-256 `MessageDigest.update(buffer, 0, read)`를 호출하고 lowercase 64자 Hex를 `StoredImage`에 넣는다. `delete`는 상대 Key를 `/` Segment로 해석하고 Root 내부·NOFOLLOW_LINKS를 확인한 일반 파일만 `Files.deleteIfExists`로 제거한다.

- [ ] **Step 4: Storage 테스트의 GREEN을 확인한다**

  Run: `gradlew.bat test --tests "*ImageStorage*" --tests "*LocalImageStorage*"`
  Expected: 모든 Storage 테스트 통과.

### Task 2: V4 Drawing Asset 무결성

**Files:**
- Create: `backend/src/main/resources/db/migration/V4__add_drawing_asset_upload_constraints.sql`
- Modify: `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`

**Interfaces:**
- Produces: `drawing_assets.captured_at DATETIME(6) NOT NULL`
- Produces: `uk_drawing_assets_session_type_version`
- Produces: generated `final_drawing_session_id`와 `uk_drawing_assets_final_session`

- [ ] **Step 1: V4 Schema 기대 테스트를 작성한다**

  Flyway 현재 버전 4, `captured_at`, 복합 UNIQUE, generated FINAL UNIQUE를 `information_schema`로 검증한다. 같은 세션·유형·버전과 같은 세션의 두 번째 FINAL INSERT가 실패하고 다른 유형·세션은 성공하는 SQL 테스트를 추가한다.

- [ ] **Step 2: Migration 테스트의 RED를 확인한다**

  Run: `gradlew.bat test --tests "*DatabaseMigrationIntegrationTest"`
  Expected: Flyway current version 3 또는 `captured_at` 부재로 실패.

- [ ] **Step 3: V4 Migration을 구현한다**

  nullable `captured_at` 추가 → `created_at` Backfill → NOT NULL 변경 순서로 적용한다. `(drawing_session_id, asset_type, asset_version)` UNIQUE와 `CASE WHEN asset_type='FINAL' THEN drawing_session_id ELSE NULL END` generated column UNIQUE를 추가한다.

- [ ] **Step 4: Migration 테스트의 GREEN을 확인한다**

  Run: `gradlew.bat test --tests "*DatabaseMigration*"`
  Expected: clean Migration과 V3 안전성 테스트 모두 통과.

### Task 3: DrawingAsset Domain과 Repository

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingAsset.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingAssetType.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingAssetRepository.java`
- Create: `backend/src/test/java/com/ssafy/b209/drawing/domain/DrawingAssetDomainTest.java`
- Create: `backend/src/test/java/com/ssafy/b209/drawing/repository/DrawingAssetRepositoryTest.java`

**Interfaces:**
- Produces: `DrawingAsset.upload(DrawingSession, DrawingAssetType, int, StoredImage, LocalDateTime, LocalDateTime)`
- Produces: `existsByDrawingSessionIdAndAssetTypeAndAssetVersion(...)`
- Produces: `existsByDrawingSessionIdAndAssetType(... FINAL ...)`

- [ ] **Step 1: Entity Factory와 Repository 실패 테스트를 작성한다**

  `INTERMEDIATE`와 `FINAL` 생성, `DRAFT` 거부, 0 버전 거부, Storage Metadata와 시간 보존을 검증한다. DataJpaTest에서 저장·조회, 유형별 버전 중복, FINAL 존재 조회를 검증한다.

- [ ] **Step 2: Domain·Repository 테스트의 RED를 확인한다**

  Run: `gradlew.bat test --tests "*DrawingAsset*"`
  Expected: Production Type 부재로 컴파일 실패.

- [ ] **Step 3: 최소 Entity와 Repository를 구현한다**

  기존 Table Column을 모두 안전하게 매핑하되 API가 쓰지 않는 nullable 값은 `null`로 둔다. `final_drawing_session_id`는 `insertable=false, updatable=false` 읽기 전용으로 매핑하고 Repository 파생 Query는 DB 필터만 사용한다.

- [ ] **Step 4: Domain·Repository 테스트의 GREEN을 확인한다**

  Run: `gradlew.bat test --tests "*DrawingAsset*"`
  Expected: Entity와 Repository 테스트 통과.

### Task 4: Upload Service와 오류 변환

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/exception/DrawingErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingSnapshotService.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/request/UploadDrawingSnapshotRequest.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/UploadDrawingSnapshotResponse.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/domain/DrawingSessionDomainTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/exception/DrawingErrorCodeTest.java`
- Create: `backend/src/test/java/com/ssafy/b209/drawing/dto/request/UploadDrawingSnapshotRequestTest.java`
- Create: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingSnapshotServiceTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSession.java`

**Interfaces:**
- Produces: `UploadDrawingSnapshotResponse uploadSnapshot(long drawingSessionId, MultipartFile file, UploadDrawingSnapshotRequest request)`
- Produces: `UploadDrawingSnapshotRequest(DrawingAssetType assetType, Integer assetVersion, OffsetDateTime capturedAt)`
- Produces: `boolean DrawingSession.isUploadable()`

- [ ] **Step 1: Service 실패 테스트를 작성한다**

  Request Validation과 6개 오류 계약을 먼저 고정한다. 정상 PNG/JPEG 저장, 세션 미존재, Soft Delete, 완료·잘못된 단계, 빈 파일, 유형·버전 중복, FINAL 중복, Storage 실패 시 Repository 미호출, `saveAndFlush` 실패 시 `ImageStorage.delete` 호출, 삭제 실패 시 원래 409 유지, 상태 미변경을 각각 검증한다.

- [ ] **Step 2: Service 테스트의 RED를 확인한다**

  Run: `gradlew.bat test --tests "*DrawingSnapshotServiceTest"`
  Expected: Service·DTO·오류 Enum 부재로 컴파일 실패.

- [ ] **Step 3: 오류·업로드 조정·보상을 구현한다**

  `UploadDrawingSnapshotRequest`와 Response record, `DrawingErrorCode`의 6개 오류, `DrawingSession.isUploadable()`을 추가한다. Service는 `ImageStorage` Interface에만 의존하고 `saveAndFlush`의 `DataIntegrityViolationException`을 보상 삭제 후 `DRAWING_SNAPSHOT_CREATION_CONFLICT`로 변환한다. `capturedAt`은 Offset을 보존해 수신한 뒤 기존 UTC 정책에 맞는 `LocalDateTime`으로 변환해 Entity에 전달한다.

- [ ] **Step 4: Service 테스트의 GREEN을 확인한다**

  Run: `gradlew.bat test --tests "*DrawingSnapshotServiceTest" --tests "*DrawingErrorCodeTest"`
  Expected: Service와 오류 계약 테스트 통과.

### Task 5: Multipart Controller와 OpenAPI

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingSnapshotController.java`
- Create: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingSnapshotControllerTest.java`
- Create: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingSnapshotOpenApiTest.java`

**Interfaces:**
- Consumes: Task 4의 `UploadDrawingSnapshotRequest`와 `DrawingSnapshotService`
- Produces: `POST /api/v1/drawing-sessions/{drawingSessionId}/snapshots`

- [ ] **Step 1: DTO와 MockMvc 실패 테스트를 작성한다**

  Validation의 null·0 버전과 정상 Metadata를 검증한다. MockMvc Multipart로 `file`과 JSON `metadata`를 보내 201, Location, `COMMON_201`, 응답 필드와 Storage Key 미노출을 검증한다. Part 누락, Path 0, 404·409·413·500 매핑도 검증한다.

- [ ] **Step 2: Controller 테스트의 RED를 확인한다**

  Run: `gradlew.bat test --tests "*UploadDrawingSnapshot*" --tests "*DrawingSnapshotController*"`
  Expected: DTO·Controller 부재로 컴파일 실패.

- [ ] **Step 3: DTO·Controller·Swagger 문서를 구현한다**

  Controller는 `@RequestPart("file") MultipartFile`, `@Valid @RequestPart("metadata")`만 받고 Service 응답으로 `ResponseEntity.created(location)`을 조립한다. Springdoc에 201/400/404/409/413/500만 선언한다.

- [ ] **Step 4: Controller 테스트의 GREEN을 확인한다**

  Run: `gradlew.bat test --tests "*UploadDrawingSnapshot*" --tests "*DrawingSnapshotController*" --tests "*DrawingSnapshotOpenApiTest"`
  Expected: Multipart와 OpenAPI 테스트 통과.

### Task 6: 설정·통합 테스트·문서와 전체 검증

**Files:**
- Modify: `backend/src/main/resources/application.yml`
- Modify: `README.md`
- Create: `backend/src/test/java/com/ssafy/b209/drawing/DrawingSnapshotUploadIntegrationTest.java`
- Modify: `docs/superpowers/specs/2026-07-22-drawing-snapshot-upload-design.md`
- Modify: `docs/superpowers/plans/2026-07-22-drawing-snapshot-upload.md`

**Interfaces:**
- Consumes: Task 1~5의 공개 계약
- Produces: 실제 HTTP → 파일 → MySQL Metadata의 종단 검증

- [ ] **Step 1: Multipart 제한과 통합 실패 테스트를 작성한다**

  Testcontainers MySQL과 `@TempDir` Storage Root로 PNG 업로드 201, 파일 1건, Metadata 1행, 중복 409와 파일 증가 없음, 다른 버전 성공, AI Bean 부재·세션 상태 불변을 검증한다.

- [ ] **Step 2: 통합 테스트의 RED를 확인한다**

  Run: `gradlew.bat test --tests "*DrawingSnapshotUploadIntegrationTest"`
  Expected: Multipart 설정 또는 Endpoint 종단 동작 부재로 실패.

- [ ] **Step 3: 설정과 README를 완성한다**

  `spring.servlet.multipart.max-file-size=10MB`, `max-request-size=11MB`를 추가한다. README에 실제 Endpoint, `file`/`metadata`, `assetType`/`assetVersion`/`capturedAt`, JPEG·PNG, 로컬 저장과 인증·AI 제한을 추가한다.

- [ ] **Step 4: 통합 테스트의 GREEN을 확인한다**

  Run: `gradlew.bat test --tests "*DrawingSnapshotUploadIntegrationTest"`
  Expected: 실제 파일과 MySQL Metadata 저장 및 중복 보상 검증 통과.

- [ ] **Step 5: 전체 검증을 실행한다**

  Run: `gradlew.bat clean test`
  Expected: 전체 테스트 실패 0.

  Run: `gradlew.bat spotlessCheck`
  Expected: BUILD SUCCESSFUL.

  Run: `gradlew.bat javadoc`
  Expected: BUILD SUCCESSFUL, `build/docs/javadoc/index.html` 존재.

- [ ] **Step 6: 변경 범위와 Git 상태를 점검한다**

  Run: `git diff --check`와 `git status --short`
  Expected: Production Image Byte, Storage 파일, Build 산출물, 미확정 주석, 원격 Branch 변경이 없음. Commit·Push·Merge는 수행하지 않는다.
