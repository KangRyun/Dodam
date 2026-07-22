# Local Image Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** JPEG·PNG 이미지 Stream을 로컬 파일 시스템에 안전하게 저장하고 절대 경로가 없는 Metadata를 반환한다.

**Architecture:** `com.ssafy.b209.storage.image`에 Spring MVC와 분리된 `ImageStorage` 계약과 로컬 구현을 둔다. 기존 `Clock`, `ErrorCode`, `BusinessException`, `@ConfigurationProperties` Convention을 재사용하고 임시 파일 Streaming 후 덮어쓰기 없는 Move로 완성한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Java NIO, JUnit 5, AssertJ, Spring Boot ApplicationContextRunner

## Global Constraints

- Branch는 최신 `origin/develop` 기반 `feat/local-image-storage`이며 Jira 코드는 Branch 이름에 넣지 않는다.
- 실제 Commit, Push, Merge Request는 사용자가 별도로 요청하기 전까지 수행하지 않는다.
- 이미지 형식은 최신 API 공통 규약에 따라 JPEG와 PNG만 허용하고 최대 크기는 기본 10,485,760 Byte다.
- Controller, `MultipartFile`, Entity, Repository, Migration, AI Client와 외부 Storage SDK를 추가하지 않는다.
- 입력 Stream은 `store`가 소유하고 성공·실패 모두에서 닫는다.
- Production 공개 Type과 오해 가능성이 있는 공개 메서드에는 실제 동작과 일치하는 한국어 Javadoc을 작성한다.

---

### Task 1: Storage 계약과 오류 코드

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/storage/image/ImageStorage.java`
- Create: `backend/src/main/java/com/ssafy/b209/storage/image/StoreImageCommand.java`
- Create: `backend/src/main/java/com/ssafy/b209/storage/image/StoredImage.java`
- Create: `backend/src/main/java/com/ssafy/b209/storage/image/ImageStorageErrorCode.java`
- Test: `backend/src/test/java/com/ssafy/b209/storage/image/ImageStorageErrorCodeTest.java`

**Interfaces:**
- Produces: `StoredImage ImageStorage.store(StoreImageCommand command)`
- Produces: `StoreImageCommand(InputStream inputStream, long size, String contentType, String originalFilename)`
- Produces: `StoredImage(String storageKey, String storedFileName, String contentType, long size)`

- [ ] **Step 1: Write the failing error-contract test**

  `ImageStorageErrorCodeTest`에서 7개 Enum의 `HttpStatus`, Code와 사용자용 한국어 Message를 정확한 Map과 비교한다.

- [ ] **Step 2: Run the focused test and confirm red**

  Run: `gradlew.bat test --tests "*ImageStorageErrorCodeTest"`
  Expected: FAIL because `ImageStorageErrorCode` does not exist.

- [ ] **Step 3: Add the public contracts and error enum**

  위 Interface와 record Signature를 그대로 구현한다. `ImageStorage.store` Javadoc에는 Stream 소유권 이전, 단일 소비, 자동 종료와 `BusinessException` 조건을 명시한다. Enum은 설계 문서의 7개 오류 계약을 기존 `ErrorCode` 구현 형식으로 제공한다.

- [ ] **Step 4: Run the focused test and confirm green**

  Run: `gradlew.bat test --tests "*ImageStorageErrorCodeTest"`
  Expected: PASS.

### Task 2: 설정 Binding과 Bean 구성

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/storage/image/ImageStorageProperties.java`
- Create: `backend/src/main/java/com/ssafy/b209/storage/image/ImageStorageConfig.java`
- Modify: `backend/src/main/resources/application.yml`
- Test: `backend/src/test/java/com/ssafy/b209/storage/image/ImageStoragePropertiesTest.java`

**Interfaces:**
- Produces: `ImageStorageProperties(Path root, long maxSize)`
- Produces: `ImageStorage imageStorage(ImageStorageProperties properties, Clock clock)`

- [ ] **Step 1: Write failing Binding tests**

  `ApplicationContextRunner`로 기본값 `./storage/images`와 `10485760`, Property Override, `max-size=0`, 음수 값, 빈 Root를 각각 검증한다. 잘못된 값은 Context 시작 실패를 기대한다.

- [ ] **Step 2: Run the focused test and confirm red**

  Run: `gradlew.bat test --tests "*ImageStoragePropertiesTest"`
  Expected: FAIL because properties and configuration are absent.

- [ ] **Step 3: Implement immutable validated properties and registration**

  `@ConfigurationProperties(prefix = "app.storage.image")` record에서 Root를 정규화하고 `maxSize > 0`을 보장한다. `ImageStorageConfig`는 `@EnableConfigurationProperties(ImageStorageProperties.class)`로 등록하고 기존 `Clock`을 로컬 구현에 전달한다. `application.yml`에는 다음을 추가한다.

  ```yaml
  app:
    storage:
      image:
        root: ${LOCAL_IMAGE_STORAGE_ROOT:./storage/images}
        max-size: ${LOCAL_IMAGE_MAX_SIZE:10485760}
  ```

- [ ] **Step 4: Run the focused test and confirm green**

  Run: `gradlew.bat test --tests "*ImageStoragePropertiesTest"`
  Expected: PASS.

### Task 3: Streaming 저장과 이미지 검증

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/storage/image/LocalImageStorage.java`
- Test: `backend/src/test/java/com/ssafy/b209/storage/image/LocalImageStorageTest.java`

**Interfaces:**
- Consumes: Task 1의 `ImageStorage`, `StoreImageCommand`, `StoredImage`, `ImageStorageErrorCode`
- Consumes: Task 2의 `ImageStorageProperties`와 기존 `Clock`
- Produces: `LocalImageStorage implements ImageStorage`

- [ ] **Step 1: Write failing happy-path tests**

  최소 유효 PNG·JPEG Fixture를 `ByteArrayInputStream`으로 전달한다. 저장 결과가 `yyyy/MM/dd/{UUID}.png|jpg`, 상대 Key, 검증된 MIME, 실제 크기인지 확인하고 Root에서 읽은 Byte가 입력과 동일한지 검증한다. 같은 원본 이름을 두 번 저장해 서로 다른 파일이 생성되는지 확인한다.

- [ ] **Step 2: Run happy-path tests and confirm red**

  Run: `gradlew.bat test --tests "*LocalImageStorageTest"`
  Expected: FAIL because `LocalImageStorage` does not exist.

- [ ] **Step 3: Implement bounded one-pass Streaming**

  8192 Byte Buffer로 Root 내부 임시 파일에 복사하면서 실제 크기와 최대 크기를 검사하고 Header 8 Byte 이상을 수집한다. PNG `89 50 4E 47 0D 0A 1A 0A`, JPEG `FF D8 FF`를 판별한 뒤 MIME과 `.png`, `.jpg|.jpeg`를 교차 검증한다. 검증 결과로만 최종 확장자를 결정한다.

- [ ] **Step 4: Implement safe paths and finalization**

  UTC `Clock`의 날짜와 UUID만으로 Key를 생성한다. Root와 날짜 경로를 `toAbsolutePath().normalize()`하고 `NOFOLLOW_LINKS`로 Symbolic Link를 거부한다. `Files.move(temp, destination, ATOMIC_MOVE)`를 먼저 시도하고 `AtomicMoveNotSupportedException`이면 옵션 없는 `Files.move`로 대체한다. `REPLACE_EXISTING`은 사용하지 않는다.

- [ ] **Step 5: Run happy-path tests and confirm green**

  Run: `gradlew.bat test --tests "*LocalImageStorageTest"`
  Expected: PASS for PNG/JPEG happy paths.

- [ ] **Step 6: Add failing security and failure-path tests**

  0·음수 크기, 선언·실제 크기 불일치, 최대 크기 초과 Metadata와 Stream, MIME 위조, 확장자 위조, WEBP·GIF·임의 Binary, `../`와 Windows 경로가 든 원본 이름, Root 일반 파일, 가능한 OS에서 Symbolic Link 이탈, 충돌, 복사 실패를 검증한다. 각 실패 뒤 입력 Stream이 닫히고 `.tmp` 파일과 Root 외부 파일이 남지 않아야 한다.

- [ ] **Step 7: Implement exact failure mapping and cleanup**

  입력 조건은 대응하는 400/413 오류, 목적지 충돌은 409, 파일 시스템 실패는 500으로 변환한다. `finally`에서 임시 파일을 삭제하고 try-with-resources로 입력·출력 Stream을 닫으며 Exception 메시지에 경로와 원본 IOException을 넣지 않는다.

- [ ] **Step 8: Run all storage tests**

  Run: `gradlew.bat test --tests "*ImageStorage*" --tests "*LocalImageStorage*"`
  Expected: PASS.

### Task 4: 환경·문서와 Context 회귀

**Files:**
- Modify: `.env.example`
- Modify: `.gitignore`
- Modify: `README.md`
- Modify: `backend/src/test/java/com/ssafy/b209/B209ApplicationTests.java` only if a dedicated Context assertion is needed

**Interfaces:**
- Consumes: `LOCAL_IMAGE_STORAGE_ROOT`, `LOCAL_IMAGE_MAX_SIZE`
- Produces: 기본 저장 경로 `/storage/` Git 제외와 운영 주의사항

- [ ] **Step 1: Add environment and ignore rules**

  `.env.example`에 `LOCAL_IMAGE_STORAGE_ROOT=./storage/images`, `LOCAL_IMAGE_MAX_SIZE=10485760`을 추가한다. 저장소 Root의 `.gitignore`에는 `/storage/`를 한 번만 추가한다.

- [ ] **Step 2: Document the local storage contract**

  README에 기본 위치, PNG/JPEG, 10 MiB, Signature 검증, UUID 파일명, 상대 Key, 로컬 디스크 유실 가능성, Git 제외와 향후 Object Storage 전환을 기록한다. 이번 이슈가 HTTP 업로드와 AI 분석을 포함하지 않음을 명시한다.

- [ ] **Step 3: Verify Spring Context**

  Run: `gradlew.bat test --tests "*B209ApplicationTests" --tests "*ImageStoragePropertiesTest"`
  Expected: PASS with one `ImageStorage` Bean and no path created outside the test directory.

### Task 5: 전체 검증과 변경 검토

**Files:**
- Verify only: all changed files

- [ ] **Step 1: Apply and verify formatting**

  Run: `gradlew.bat spotlessApply` then `gradlew.bat spotlessCheck`
  Expected: BUILD SUCCESSFUL.

- [ ] **Step 2: Run the complete regression suite**

  Run: `gradlew.bat clean test`
  Expected: BUILD SUCCESSFUL, including H2, Flyway and Testcontainers MySQL tests while Docker is running.

- [ ] **Step 3: Generate Javadoc**

  Run: `gradlew.bat javadoc`
  Expected: BUILD SUCCESSFUL and `backend/build/docs/javadoc/index.html` exists with no malformed-tag failure.

- [ ] **Step 4: Audit scope and security**

  Run: `git status --short` and `git diff --check`.
  Confirm no Controller, Entity, Repository, Migration, AI integration, absolute path response, logged image content, build artifact or stored image is tracked.

- [ ] **Step 5: Stop before publishing**

  Report the exact changed files and verification output. Do not Commit, Push or create a Merge Request until the user explicitly asks.
