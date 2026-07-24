# AI Image Access URL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redis에서 한 번만 소비되는 짧은 만료 토큰으로 AI 서버가 Backend 로컬 이미지 저장소의 그림을 안전하게 HTTP GET할 수 있게 한다.

**Architecture:** `ImageStorage`에 읽기 경계를 추가하고, Redis Lua Script로 토큰 조회와 삭제를 원자적으로 수행한다. 내부 Controller가 토큰을 소비해 이미지 Stream을 반환하며 `DrawingAnalysisImageUrlProvider`가 AI 요청에 들어갈 내부 URL을 발급한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data Redis, Spring MVC, JUnit 5, Mockito, AssertJ

## Global Constraints

- Branch는 최신 `develop` 기반 `feature/S15P11B209-402-ai-image-access`를 사용한다.
- 공개 `/api/v1/**` Endpoint를 추가하지 않고 `/internal/v1/ai-images/{token}`만 추가한다.
- Token, signed URL, storageKey, 절대 경로, 이미지 Byte와 아동 개인정보를 로그에 남기지 않는다.
- Token 원문은 Redis Key로 사용하지 않고 SHA-256 digest만 저장한다.
- MinIO/S3 전환과 AI FastAPI 변경은 구현하지 않는다.
- 모든 새 Production Type과 공개 메서드에는 실제 동작에 맞는 한국어 Javadoc을 작성한다.

---

### Task 1: 이미지 저장소 읽기 경계

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/storage/image/StoredImageContent.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/image/ImageStorage.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/image/LocalImageStorage.java`
- Modify: `backend/src/main/java/com/ssafy/b209/storage/image/ImageStorageErrorCode.java`
- Test: `backend/src/test/java/com/ssafy/b209/storage/image/LocalImageStorageTest.java`

**Interfaces:**
- Produces: `StoredImageContent ImageStorage.read(String storageKey)`
- `StoredImageContent` contains `InputStream inputStream`, `String contentType`, `long size`

- [ ] **Step 1: 정상 읽기와 안전하지 않은 경로를 표현하는 실패 테스트 작성**

```java
@Test
void readsStoredImageWithoutExposingAbsolutePath() throws Exception {
  StoredImage stored = storage.store(pngCommand());

  try (StoredImageContent content = storage.read(stored.storageKey())) {
    assertThat(content.contentType()).isEqualTo("image/png");
    assertThat(content.size()).isEqualTo(PNG_BYTES.length);
    assertThat(content.inputStream().readAllBytes()).isEqualTo(PNG_BYTES);
  }
}

@Test
void rejectsSymbolicLinkWhenReading() throws Exception {
  Path link = root.resolve("linked.png");
  Files.createSymbolicLink(link, outsideFile);

  assertThatThrownBy(() -> storage.read("linked.png"))
      .isInstanceOfSatisfying(
          BusinessException.class,
          exception ->
              assertThat(exception.getErrorCode())
                  .isEqualTo(ImageStorageErrorCode.INVALID_STORAGE_PATH));
}
```

- [ ] **Step 2: 테스트가 `read` 계약 부재로 실패하는지 확인**

Run:

```powershell
.\gradlew.bat test --tests "*LocalImageStorageTest"
```

Expected: `ImageStorage.read` 또는 `StoredImageContent`를 찾을 수 없어 compile 실패.

- [ ] **Step 3: 읽기 계약과 로컬 구현 추가**

```java
public record StoredImageContent(InputStream inputStream, String contentType, long size)
    implements AutoCloseable {
  public StoredImageContent {
    Objects.requireNonNull(inputStream, "inputStream must not be null");
    Objects.requireNonNull(contentType, "contentType must not be null");
    if (size <= 0) {
      throw new IllegalArgumentException("size must be positive");
    }
  }

  @Override
  public void close() throws IOException {
    inputStream.close();
  }
}
```

`LocalImageStorage.read`는 `delete`와 같은 Segment·Root·Symbolic Link 검증을 거친 후
`Files.newInputStream(target, StandardOpenOption.READ)`을 열고 확장자를 저장 가능한 PNG/JPEG
형식에만 매핑한다. 없는 파일은 새 `IMAGE_NOT_FOUND` 오류로 처리한다.

- [ ] **Step 4: Storage 테스트 통과 확인**

Run:

```powershell
.\gradlew.bat test --tests "*LocalImageStorageTest" --tests "*ImageStorage*"
```

Expected: PASS.

---

### Task 2: Redis 1회성 토큰

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessTokenStore.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessTokenGenerator.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/image/SecureRandomAiImageAccessTokenGenerator.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/image/RedisAiImageAccessTokenStore.java`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/image/SecureRandomAiImageAccessTokenGeneratorTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/image/RedisAiImageAccessTokenStoreTest.java`

**Interfaces:**
- Produces: `String AiImageAccessTokenStore.issue(String storageKey, Duration ttl)`
- Produces: `Optional<String> AiImageAccessTokenStore.consume(String token)`
- Consumes: `StringRedisTemplate`, `AiImageAccessTokenGenerator`

- [ ] **Step 1: 토큰 형식·digest Key·TTL·원자적 소비 실패 테스트 작성**

```java
@Test
void storesOnlyTokenDigestWithTtl() {
  when(generator.generate()).thenReturn("A".repeat(43));
  when(valueOperations.setIfAbsent(anyString(), eq("2026/07/image.png"), eq(Duration.ofSeconds(60))))
      .thenReturn(true);

  String token = store.issue("2026/07/image.png", Duration.ofSeconds(60));

  assertThat(token).isEqualTo("A".repeat(43));
  verify(valueOperations)
      .setIfAbsent(
          argThat(key -> key.startsWith("ai:image-access:") && !key.contains(token)),
          eq("2026/07/image.png"),
          eq(Duration.ofSeconds(60)));
}

@Test
void consumesTokenAtomically() {
  when(redisTemplate.execute(any(DefaultRedisScript.class), anyList())).thenReturn("2026/07/image.png");

  assertThat(store.consume("A".repeat(43))).contains("2026/07/image.png");
}
```

- [ ] **Step 2: 새 Type 부재로 compile 실패 확인**

Run:

```powershell
.\gradlew.bat test --tests "*AiImageAccessToken*"
```

Expected: compile 실패.

- [ ] **Step 3: 256-bit Token Generator와 Redis Store 구현**

```java
public String generate() {
  byte[] bytes = new byte[32];
  secureRandom.nextBytes(bytes);
  return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
}
```

Redis 소비 Script:

```lua
local value = redis.call('GET', KEYS[1])
if value then redis.call('DEL', KEYS[1]) end
return value
```

Store는 Token 정규식 `[A-Za-z0-9_-]{43}`을 검증하고 SHA-256 digest로 Key를 만든다.
발급 충돌은 최대 세 번 다시 시도하고 성공하지 못하면 `IllegalStateException`을 발생시킨다.

- [ ] **Step 4: Token Store 테스트 통과 확인**

Run:

```powershell
.\gradlew.bat test --tests "*AiImageAccessToken*"
```

Expected: PASS.

---

### Task 3: 내부 이미지 API와 AI Provider

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessProperties.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessService.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessController.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessConfig.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/RedisDrawingAnalysisImageUrlProvider.java`
- Delete: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/UnavailableDrawingAnalysisImageUrlProvider.java`
- Modify: `backend/src/main/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientConfig.java`
- Modify: `backend/src/main/resources/application.yml`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessPropertiesTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessServiceTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/image/AiImageAccessControllerTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/RedisDrawingAnalysisImageUrlProviderTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/DrawingAnalysisClientConfigTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/infrastructure/ai/drawing/RestClientDrawingAnalysisClientTest.java`

**Interfaces:**
- Consumes: `AiImageAccessTokenStore`, `ImageStorage`, `AiImageAccessProperties`
- Produces: `URI AiImageAccessService.issueReadUrl(String storageKey)`
- Produces: `StoredImageContent AiImageAccessService.consume(String token)`
- Produces: `GET /internal/v1/ai-images/{token}`
- Produces: real `DrawingAnalysisImageUrlProvider` in HTTP mode

- [ ] **Step 1: Service·Controller·Provider 실패 테스트 작성**

```java
@Test
void issuesInternalReadUrlWithoutStorageKey() {
  when(tokenStore.issue("2026/07/image.png", Duration.ofSeconds(60))).thenReturn("A".repeat(43));

  URI result = service.issueReadUrl("2026/07/image.png");

  assertThat(result)
      .isEqualTo(URI.create("http://backend:8080/internal/v1/ai-images/" + "A".repeat(43)));
  assertThat(result.toString()).doesNotContain("2026/07/image.png");
}

@Test
void returnsImageOnceWithNoStoreHeaders() throws Exception {
  when(service.consume("A".repeat(43))).thenReturn(content);

  mockMvc
      .perform(get("/internal/v1/ai-images/{token}", "A".repeat(43)))
      .andExpect(status().isOk())
      .andExpect(header().string(CACHE_CONTROL, "no-store"))
      .andExpect(content().contentType("image/png"))
      .andExpect(content().bytes(PNG_BYTES));
}
```

- [ ] **Step 2: Type과 Bean 부재로 실패 확인**

Run:

```powershell
.\gradlew.bat test --tests "*AiImageAccess*" --tests "*RedisDrawingAnalysisImageUrlProvider*"
```

Expected: compile 실패.

- [ ] **Step 3: Properties·Service·Controller와 Provider 구현**

```java
@ConfigurationProperties("app.ai.image-access")
public record AiImageAccessProperties(URI internalBaseUrl, Duration tokenTtl) {
  public AiImageAccessProperties {
    if (internalBaseUrl == null
        || !internalBaseUrl.isAbsolute()
        || !Set.of("http", "https").contains(internalBaseUrl.getScheme())) {
      throw new IllegalArgumentException("internalBaseUrl must be an absolute HTTP URL");
    }
    if (tokenTtl == null || tokenTtl.isZero() || tokenTtl.isNegative()) {
      throw new IllegalArgumentException("tokenTtl must be positive");
    }
  }
}
```

Controller는 `InputStreamResource`와 명시적인 `Content-Type`, `Content-Length`,
`Cache-Control: no-store`를 반환하고 `@Hidden`으로 공개 Swagger에서 제외한다.
Service는 잘못된 토큰·없는 파일·안전하지 않은 경로를 `AI_IMAGE_NOT_FOUND(404)`로 통합하고
Redis `DataAccessException`을 `AI_IMAGE_ACCESS_UNAVAILABLE(503)`로 변환한다.

- [ ] **Step 4: HTTP mode Bean과 Client 요청 회귀 테스트 통과 확인**

Run:

```powershell
.\gradlew.bat test --tests "*AiImageAccess*" --tests "*DrawingAnalysisClient*" --tests "*RestClientDrawingAnalysisClient*" --tests "*RedisDrawingAnalysisImageUrlProvider*"
```

Expected: PASS.

---

### Task 4: 배포 설정·문서·전체 검증

**Files:**
- Modify: `.env.example`
- Modify: `README.md`
- Modify: `infra/docker-compose.yml`
- Modify: `docs/api/ai-drawing-analysis-contract.md`

**Interfaces:**
- Adds: `AI_IMAGE_ACCESS_BASE_URL`
- Adds: `AI_IMAGE_ACCESS_TOKEN_TTL`

- [ ] **Step 1: 배포 환경 변수와 제한 사항 문서화**

```yaml
AI_IMAGE_ACCESS_BASE_URL: ${AI_IMAGE_ACCESS_BASE_URL:-http://backend:8080}
AI_IMAGE_ACCESS_TOKEN_TTL: ${AI_IMAGE_ACCESS_TOKEN_TTL:-60s}
```

README와 AI 계약 문서에는 다음을 기록한다.

- HTTP mode에서 Redis와 내부 `backend:8080` 접근이 필요하다.
- URL은 60초 TTL의 1회성 읽기 전용이며 외부에 공개하지 않는다.
- MinIO/S3 전환은 S15P11B209-370 범위다.

- [ ] **Step 2: Spotless 적용과 변경 범위 테스트**

Run:

```powershell
.\gradlew.bat spotlessApply
.\gradlew.bat test --tests "*ImageStorage*" --tests "*AiImageAccess*" --tests "*DrawingAnalysisClient*" --tests "*RestClientDrawingAnalysisClient*" --tests "*RedisDrawingAnalysisImageUrlProvider*"
```

Expected: PASS.

- [ ] **Step 3: 전체 검증**

Run:

```powershell
.\gradlew.bat --no-daemon --build-cache test bootJar
.\gradlew.bat spotlessCheck
.\gradlew.bat javadoc
```

Expected: 모든 명령 exit code 0, `backend/build/docs/javadoc/index.html` 존재.

- [ ] **Step 4: 최종 Commit**

```bash
git add .
git commit -m "[S15P11B209-402] feat(ai): 일회성 이미지 접근 URL 구현"
```
