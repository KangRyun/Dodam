# S15P11B209-370 MinIO File Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 그림·음성 Storage 계약을 유지하면서 Local/S3(MinIO) 저장·조회·삭제를 설정으로 전환할 수 있게 한다.

**Architecture:** Storage Interface에 닫을 수 있는 Stream 읽기 결과를 추가한다. S3 Adapter는 기존 Local 검증 구현을 staging 용도로 합성해 검증 로직 중복을 피하고, 검증된 파일만 `dodam/images` 또는 `dodam/audio` Prefix에 업로드한다. Spring Bean은 `app.storage.mode=local|s3` 조건으로 하나의 구현만 선택한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Gradle 8.14.3, AWS SDK for Java 2.49.3, JUnit 5, Mockito, Testcontainers, MinIO

## Global Constraints

- 기존 Java, Spring Boot, Gradle 버전을 변경하지 않는다.
- AWS SDK는 BOM `2.49.3`으로 모듈 버전을 통일한다.
- `ImageStorage`와 `AudioStorage` 사용 Service는 구체 Local/S3 구현을 알지 않는다.
- Secret, Bucket 내부 Key, 로컬 절대 경로를 로그와 API 오류 응답에 노출하지 않는다.
- 전체 파일을 `byte[]`로 읽지 않고 Stream으로 전송한다.
- 기본 `app.storage.mode`는 `local`로 유지한다.
- DB Schema와 `drawing_assets.storage_key` 값 형식은 변경하지 않는다.

---

## File Structure

- `storage/image/StoredImageContent.java`: 기존 그림 읽기 Stream 계약 재사용
- `storage/audio/StoredAudioContent.java`: 음성 읽기 Stream과 Metadata의 소유권 계약
- `storage/audio/AudioStorage.java`: 음성 `read` 공개 계약
- `storage/image/LocalImageStorage.java`, `storage/audio/LocalAudioStorage.java`: 안전한 Local 읽기
- `storage/s3/S3StorageProperties.java`: Endpoint, Region, Bucket, 자격증명, Prefix 설정
- `storage/s3/S3StorageConfig.java`: `S3Client`와 S3 Adapter Bean 구성
- `storage/s3/S3ImageStorage.java`: 검증된 그림의 S3 저장·조회·삭제
- `storage/s3/S3AudioStorage.java`: 검증된 음성의 S3 저장·조회·삭제
- `storage/image/ImageStorageConfig.java`, `storage/audio/AudioStorageConfig.java`: Local 모드 조건
- `application.yml`, `infra/docker-compose.yml`: 배포 환경 변수 배선

### Task 1: 기존 그림 read 회귀와 Local 음성 스트리밍 읽기 계약

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/storage/audio/StoredAudioContent.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/audio/AudioStorage.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/audio/LocalAudioStorage.java`
- Test: `backend/src/test/java/com/ssafy/b209/storage/image/LocalImageStorageTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/storage/audio/LocalAudioStorageTest.java`

**Interfaces:**
- Reuses: `StoredImageContent ImageStorage.read(String storageKey)`
- Produces: `StoredAudioContent AudioStorage.read(String storageKey)`

- [ ] **Step 1: 기존 그림 Local read 회귀 테스트 확인**

```java
@Test
void readsStoredImageWithoutLoadingTheWholeFile() throws Exception {
  StoredImage stored = storage.store(pngCommand());

  try (StoredImageContent resource = storage.read(stored.storageKey())) {
    assertThat(resource.contentType()).isEqualTo("image/png");
    assertThat(resource.size()).isEqualTo(PNG_BYTES.length);
    assertThat(resource.inputStream().readAllBytes()).isEqualTo(PNG_BYTES);
  }
}
```

- [ ] **Step 2: 기존 그림 테스트 GREEN 확인**

Run:

```powershell
gradlew.bat test --tests '*LocalImageStorageTest' --no-daemon
```

Expected: PASS.

- [ ] **Step 3: 음성 Local read 실패 테스트 작성**

```java
@Test
void readsPromotedAudioAsAStream() throws Exception {
  StoredAudio stored = storage.promote(storage.stage(wavCommand()));

  try (StoredAudioContent resource = storage.read(stored.storageKey())) {
    assertThat(resource.contentType()).isEqualTo("audio/wav");
    assertThat(resource.size()).isEqualTo(WAV_BYTES.length);
    assertThat(resource.inputStream().readAllBytes()).isEqualTo(WAV_BYTES);
  }
}
```

- [ ] **Step 4: RED 확인 후 음성 읽기 최소 구현**

Run:

```powershell
gradlew.bat test --tests '*LocalAudioStorageTest' --no-daemon
```

Expected: `AudioStorage.read`와 `StoredAudioResource`가 없어 compile 실패.

`StoredAudioContent`는 그림과 같은 소유권 계약을 사용한다. `LocalAudioStorage.read`는
기존 Key·Symbolic Link 검증을 재사용하고 확장자를 `wav`, `mp3`, `m4a`, `webm`
Content-Type으로 매핑한다.

- [ ] **Step 5: Local Storage GREEN 및 회귀 확인**

Run:

```powershell
gradlew.bat test --tests '*LocalImageStorageTest' --tests '*LocalAudioStorageTest' --no-daemon
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add backend/src/main/java/com/ssafy/b209/storage backend/src/test/java/com/ssafy/b209/storage
git commit -m "[S15P11B209-370] feat(storage): 로컬 파일 스트리밍 조회 지원"
```

### Task 2: S3 설정과 Bean 선택

**Files:**
- Modify: `backend/build.gradle`
- Create: `backend/src/main/java/com/ssafy/b209/storage/s3/S3StorageProperties.java`
- Create: `backend/src/main/java/com/ssafy/b209/storage/s3/S3StorageConfig.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/image/ImageStorageConfig.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/audio/AudioStorageConfig.java`
- Modify: `backend/src/main/resources/application.yml`
- Test: `backend/src/test/java/com/ssafy/b209/storage/s3/S3StorageConfigTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/storage/image/ImageStoragePropertiesTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/storage/audio/AudioStoragePropertiesTest.java`

**Interfaces:**
- Produces: `S3Client`
- Produces: `S3StorageProperties`
- Consumes later: `S3ImageStorage`, `S3AudioStorage`

- [ ] **Step 1: 의존성 선언**

```groovy
dependencies {
    implementation platform('software.amazon.awssdk:bom:2.49.3')
    implementation 'software.amazon.awssdk:s3'
    implementation 'software.amazon.awssdk:url-connection-client'
}
```

- [ ] **Step 2: Bean 선택 실패 테스트 작성**

```java
@Test
void localModeRegistersOnlyLocalStorageBeans() {
  contextRunner
      .withPropertyValues("app.storage.mode=local")
      .run(context -> {
        assertThat(context.getBean(ImageStorage.class)).isInstanceOf(LocalImageStorage.class);
        assertThat(context.getBean(AudioStorage.class)).isInstanceOf(LocalAudioStorage.class);
        assertThat(context).doesNotHaveBean(S3Client.class);
      });
}

@Test
void s3ModeRejectsBlankCredentials() {
  contextRunner
      .withPropertyValues(
          "app.storage.mode=s3",
          "app.storage.s3.endpoint=http://localhost:9000",
          "app.storage.s3.bucket=dodam",
          "app.storage.s3.access-key=",
          "app.storage.s3.secret-key=")
      .run(context -> assertThat(context).hasFailed());
}
```

- [ ] **Step 3: RED 확인**

Run:

```powershell
gradlew.bat test --tests '*StorageConfigTest' --tests '*StoragePropertiesTest' --no-daemon
```

Expected: S3 설정 Type과 조건부 Bean이 없어 실패.

- [ ] **Step 4: 설정 Type과 조건부 Bean 구현**

```java
@ConfigurationProperties("app.storage.s3")
public record S3StorageProperties(
    URI endpoint,
    String region,
    String bucket,
    String accessKey,
    String secretKey,
    String imagePrefix,
    String audioPrefix,
    boolean pathStyleAccessEnabled) {
}
```

`ImageStorageConfig`와 `AudioStorageConfig`에는 다음 조건을 적용한다.

```java
@ConditionalOnProperty(
    prefix = "app.storage",
    name = "mode",
    havingValue = "local",
    matchIfMissing = true)
```

`S3StorageConfig`는 `mode=s3`일 때만 활성화하며
`StaticCredentialsProvider`, `endpointOverride`, `Region.of`,
`S3Configuration.pathStyleAccessEnabled(true)`로 Client를 만든다.

- [ ] **Step 5: 설정 GREEN 확인**

Run:

```powershell
gradlew.bat test --tests '*StorageConfigTest' --tests '*StoragePropertiesTest' --no-daemon
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add backend/build.gradle backend/src/main/java/com/ssafy/b209/storage backend/src/main/resources/application.yml backend/src/test/java/com/ssafy/b209/storage
git commit -m "[S15P11B209-370] feat(storage): Local MinIO 모드 설정 추가"
```

### Task 3: S3 그림 Storage 구현

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/storage/s3/S3ImageStorage.java`
- Create: `backend/src/test/java/com/ssafy/b209/storage/s3/S3ImageStorageTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/s3/S3StorageConfig.java`

**Interfaces:**
- Consumes: `ImageStorage`, `StoredImageContent`, `S3Client`, `S3StorageProperties`
- Produces: S3 모드의 `ImageStorage`

- [ ] **Step 1: 저장·읽기·삭제 실패 테스트 작성**

```java
@Test
void storesValidatedImageUnderImagesPrefix() {
  StoredImage stored = storage.store(pngCommand());

  verify(s3Client).putObject(
      argThat(request ->
          request.bucket().equals("dodam")
              && request.key().equals("images/" + stored.storageKey())
              && request.contentType().equals("image/png")),
      any(RequestBody.class));
}

@Test
void readsS3ImageAsResponseStream() throws Exception {
  when(s3Client.getObject(any(GetObjectRequest.class)))
      .thenReturn(imageResponseStream(PNG_BYTES));

  try (StoredImageContent resource = storage.read("2026/07/25/image.png")) {
    assertThat(resource.contentType()).isEqualTo("image/png");
    assertThat(resource.size()).isEqualTo(PNG_BYTES.length);
  }
}

@Test
void rejectsTraversalBeforeCallingS3() {
  assertBusinessError(
      () -> storage.read("../secret"),
      ImageStorageErrorCode.INVALID_STORAGE_PATH);
  verifyNoInteractions(s3Client);
}
```

- [ ] **Step 2: RED 확인**

Run:

```powershell
gradlew.bat test --tests '*S3ImageStorageTest' --no-daemon
```

Expected: `S3ImageStorage`가 없어 compile 실패.

- [ ] **Step 3: 최소 S3 그림 Adapter 구현**

`store`는 `LocalImageStorage.store`로 형식·크기·checksum을 검증한 뒤 Local
`read` Stream을 `PutObjectRequest`로 업로드한다. 성공·실패 모두 staging Local
파일을 삭제한다. `read`는 `GetObjectResponse`의 Content-Type과 Content-Length를
사용하고, `delete`는 `DeleteObjectRequest`를 호출한다.

S3 예외는 SDK 메시지·Bucket·Key를 외부로 전달하지 않고
`IMAGE_STORAGE_FAILED`로 변환한다.

- [ ] **Step 4: GREEN과 보상 정리 확인**

Run:

```powershell
gradlew.bat test --tests '*S3ImageStorageTest' --tests '*LocalImageStorageTest' --no-daemon
```

Expected: PASS, 업로드 실패 테스트에서 Local staging 파일이 남지 않음.

- [ ] **Step 5: Commit**

```powershell
git add backend/src/main/java/com/ssafy/b209/storage/s3 backend/src/test/java/com/ssafy/b209/storage/s3
git commit -m "[S15P11B209-370] feat(storage): MinIO 그림 저장소 구현"
```

### Task 4: S3 음성 Storage 구현

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/storage/s3/S3AudioStorage.java`
- Create: `backend/src/test/java/com/ssafy/b209/storage/s3/S3AudioStorageTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/s3/S3StorageConfig.java`

**Interfaces:**
- Consumes: `AudioStorage`, `StoredAudioContent`, `S3Client`, `S3StorageProperties`
- Produces: S3 모드의 `AudioStorage`

- [ ] **Step 1: stage·promote·read·delete 실패 테스트 작성**

```java
@Test
void promotesValidatedAudioToAudioPrefix() {
  StagedAudio staged = storage.stage(wavCommand());
  StoredAudio stored = storage.promote(staged);

  verify(s3Client).putObject(
      argThat(request ->
          request.bucket().equals("dodam")
              && request.key().equals("audio/" + stored.storageKey())
              && request.contentType().equals("audio/wav")),
      any(RequestBody.class));
}

@Test
void removesLocalPromotedFileWhenS3UploadFails() {
  when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
      .thenThrow(S3Exception.builder().message("failed").build());

  assertBusinessError(
      () -> storage.promote(storage.stage(wavCommand())),
      AudioStorageErrorCode.AUDIO_STORAGE_FAILED);
  assertThat(localStorageRoot).isEmptyDirectory();
}
```

- [ ] **Step 2: RED 확인**

Run:

```powershell
gradlew.bat test --tests '*S3AudioStorageTest' --no-daemon
```

Expected: `S3AudioStorage`가 없어 compile 실패.

- [ ] **Step 3: 최소 S3 음성 Adapter 구현**

`stage`와 `discard`는 `LocalAudioStorage`에 위임한다. `promote`는 Local
검증 결과를 임시로 promote하고 `audio/` Prefix에 업로드한 뒤 Local 파일을
삭제한다. `read`와 `delete`는 그림 Adapter와 동일한 Stream·오류 정책을 사용하되
Audio ErrorCode로 변환한다.

- [ ] **Step 4: GREEN과 Local 회귀 확인**

Run:

```powershell
gradlew.bat test --tests '*S3AudioStorageTest' --tests '*LocalAudioStorageTest' --no-daemon
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add backend/src/main/java/com/ssafy/b209/storage/s3 backend/src/test/java/com/ssafy/b209/storage/s3
git commit -m "[S15P11B209-370] feat(storage): MinIO 음성 저장소 구현"
```

### Task 5: MinIO 종단 통합과 배포 배선

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/storage/s3/S3StorageIntegrationTest.java`
- Modify: `backend/src/main/resources/application.yml`
- Modify: `infra/docker-compose.yml`
- Modify: `README.md`

**Interfaces:**
- Verifies: 실제 MinIO Container의 put/get/delete
- Produces: Jenkins/Compose용 환경 변수 계약

- [ ] **Step 1: MinIO 통합 테스트 작성**

```java
@Testcontainers(disabledWithoutDocker = true)
class S3StorageIntegrationTest {

  @Container
  static final GenericContainer<?> minio =
      new GenericContainer<>("minio/minio:RELEASE.2025-04-22T22-12-26Z")
          .withExposedPorts(9000)
          .withEnv("MINIO_ROOT_USER", "integration-user")
          .withEnv("MINIO_ROOT_PASSWORD", "integration-password")
          .withCommand("server", "/data");

  @Test
  void storesReadsAndDeletesImageAndAudio() throws Exception {
    S3Client client = minioClient(minio);
    client.createBucket(request -> request.bucket("dodam"));
    ImageStorage imageStorage = imageStorage(client, tempDir.resolve("images"));
    AudioStorage audioStorage = audioStorage(client, tempDir.resolve("audio"));

    StoredImage image =
        imageStorage.store(
            new StoreImageCommand(
                new ByteArrayInputStream(PNG_BYTES),
                PNG_BYTES.length,
                "image/png",
                "drawing.png"));
    try (StoredImageContent resource = imageStorage.read(image.storageKey())) {
      assertThat(resource.inputStream().readAllBytes()).isEqualTo(PNG_BYTES);
    }

    StoredAudio audio =
        audioStorage.promote(
            audioStorage.stage(
                new StoreAudioCommand(
                    new ByteArrayInputStream(WAV_BYTES),
                    WAV_BYTES.length,
                    "audio/wav",
                    "answer.wav")));
    try (StoredAudioContent resource = audioStorage.read(audio.storageKey())) {
      assertThat(resource.inputStream().readAllBytes()).isEqualTo(WAV_BYTES);
    }

    imageStorage.delete(image.storageKey());
    audioStorage.delete(audio.storageKey());

    assertThat(client.listObjectsV2(request -> request.bucket("dodam")).contents()).isEmpty();
  }
}
```

- [ ] **Step 2: 통합 테스트 RED 확인**

Run:

```powershell
gradlew.bat test --tests '*S3StorageIntegrationTest' --no-daemon
```

Expected: Bucket 준비 또는 Adapter 배선 누락으로 실패. Docker 미설치 환경이면
skipped 결과와 사유를 기록한다.

- [ ] **Step 3: application.yml과 Compose 배선**

```yaml
app:
  storage:
    mode: ${STORAGE_MODE:local}
    s3:
      endpoint: ${S3_ENDPOINT:http://localhost:9000}
      region: ${S3_REGION:ap-northeast-2}
      bucket: ${S3_BUCKET:dodam}
      access-key: ${MINIO_BE_USER:}
      secret-key: ${MINIO_BE_PASSWORD:}
      image-prefix: images
      audio-prefix: audio
      path-style-access-enabled: true
```

Compose Backend에는 `S3_ENDPOINT=http://minio:9000`과 Secret 환경 변수를
추가한다. README에는 Secret 값 없이 Local/S3 선택법, 기존 파일 이관·검증,
Local Volume 1주 보존 절차를 기록한다.

- [ ] **Step 4: 통합 테스트 GREEN 확인**

Run:

```powershell
gradlew.bat test --tests '*S3StorageIntegrationTest' --no-daemon
```

Expected: Docker 사용 가능 시 PASS. Docker 사용 불가 시 테스트 보존 및 미실행
사유 보고.

- [ ] **Step 5: Commit**

```powershell
git add backend/src/main/resources/application.yml backend/src/test/java/com/ssafy/b209/storage/s3 infra/docker-compose.yml README.md
git commit -m "[S15P11B209-370] chore(storage): MinIO 배포 설정과 검증 추가"
```

### Task 6: 최종 검증과 이슈 완료

**Files:**
- Modify only if verification exposes defects.

- [ ] **Step 1: Storage 집중 테스트**

```powershell
gradlew.bat test --tests '*ImageStorage*' --tests '*AudioStorage*' --tests '*S3Storage*' --no-daemon
```

Expected: PASS 또는 Docker 전용 Test만 명시적 skip.

- [ ] **Step 2: 전체 검증**

```powershell
gradlew.bat clean test --no-daemon
gradlew.bat spotlessCheck --no-daemon
gradlew.bat javadoc --no-daemon
```

Expected: 세 명령 모두 성공. 기존 MySQL/Flyway Testcontainers 대기가 재현되면
Process 상태와 Thread Dump를 근거로 분리 보고하고 성공으로 표시하지 않는다.

- [ ] **Step 3: 생성 문서 확인**

```powershell
Test-Path build/docs/javadoc/index.html
git diff --check
git status --short
```

Expected: Javadoc index가 존재하고 diff 오류가 없으며 의도한 파일만 변경됨.

- [ ] **Step 4: Push, MR, Merge**

```powershell
git push -u origin codex/feature/S15P11B209-370-minio-storage
```

MR 제목:

```text
[S15P11B209-370] [BE] 파일 스토리지 S3(MinIO) 전환
```

Target은 반드시 `develop`, Source Branch 자동 삭제를 사용한다. Pipeline과
Merge 가능 상태를 확인한 뒤 Merge한다.

- [ ] **Step 5: Jira 완료 기록**

Jira S15P11B209-370에 설정 계약, 테스트 결과, MR, Merge Commit, Docker
통합 테스트 실행 여부를 댓글로 남기고 `완료`로 전환한다. 이후 S371을 최신
`develop`에서 시작한다.
