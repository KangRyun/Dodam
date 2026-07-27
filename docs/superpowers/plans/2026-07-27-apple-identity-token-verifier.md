# Apple Identity Token Verifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apple Identity Token의 서명·Claim·raw nonce를 검증하고 기존 OAuth 로그인 경계에 안전하게 연결한다.

**Architecture:** 기존 Google Nimbus 검증 패턴과 `OAuthProviderClient` 경계를 재사용한다. Apple 전용 Adapter가 공개 JWK와 Claim을 검증하고, Provider별 Credential 정규화가 APPLE 요청에만 raw nonce를 요구한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Security JOSE/Nimbus, JUnit 5, AssertJ, Mockito, Flyway, MySQL 8

## Global Constraints

- Branch는 `feature/S15P11B209-528-apple-token-verifier`를 사용한다.
- 기존 Migration은 수정하지 않고 `V16__support_apple_auth_provider.sql`을 추가한다.
- Token과 raw nonce 원문을 로그·DB·오류 응답에 기록하지 않는다.
- 기존 `ApiResponse`, `AuthErrorCode`, Provisioning, JWT 및 Redis Session 구조를 재사용한다.
- Apple 계정 탈퇴·재가입 정책과 Flutter SDK 배선은 구현하지 않는다.

---

### Task 1: Apple Provider 요청 계약과 DB 허용

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/auth/service/OAuthProviderCredentialTest.java`
- Create: `backend/src/main/resources/db/migration/V16__support_apple_auth_provider.sql`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/domain/AuthProvider.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/dto/request/OAuthLoginRequest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthProviderCredential.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthProviderProperties.java`
- Modify: `backend/src/test/java/com/ssafy/b209/auth/service/OAuthLoginServiceTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/auth/service/NimbusGoogleIdTokenVerifierTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/auth/service/RestClientOAuthProviderClientTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`

**Interfaces:**
- Produces: `AuthProvider.APPLE`
- Produces: `OAuthProviderCredential(OAuthCredentialType type, String value, String rawNonce)`
- Produces: `OAuthProviderProperties.Apple(String clientId)`

- [ ] **Step 1: Write failing credential tests**

```java
@Test
void createsAppleIdTokenCredentialWithRawNonce() {
  OAuthLoginRequest request = new OAuthLoginRequest(null, "apple-token", "raw-nonce", "device");
  OAuthProviderCredential credential = OAuthProviderCredential.from(AuthProvider.APPLE, request);
  assertThat(credential.type()).isEqualTo(OAuthCredentialType.ID_TOKEN);
  assertThat(credential.rawNonce()).isEqualTo("raw-nonce");
}

@Test
void rejectsAppleCredentialWithoutRawNonce() {
  OAuthLoginRequest request = new OAuthLoginRequest(null, "apple-token", null, "device");
  assertThatThrownBy(() -> OAuthProviderCredential.from(AuthProvider.APPLE, request))
      .isInstanceOfSatisfying(BusinessException.class,
          exception -> assertThat(exception.getErrorCode())
              .isEqualTo(AuthErrorCode.OAUTH_REQUEST_INVALID));
}
```

- [ ] **Step 2: Run RED**

Run:

```powershell
gradlew.bat test --tests com.ssafy.b209.auth.service.OAuthProviderCredentialTest
```

Expected: compile failure because APPLE, rawNonce and the four-argument request do not exist.

- [ ] **Step 3: Implement the minimal request contract**

Add APPLE, add `rawNonce` with `@Size(max = 512)`, and normalize APPLE to an
ID Token credential only when access token is absent and raw nonce is present. Reject raw nonce
for Google, Kakao and Naver. Update the four existing `OAuthLoginRequest` test constructors with
an explicit `null` raw nonce and add Apple properties to the two existing
`OAuthProviderProperties` test fixtures so the complete test source still compiles.

Add `OAuthProviderProperties.Apple`:

```java
public record OAuthProviderProperties(
    Kakao kakao,
    Google google,
    Apple apple,
    Duration connectTimeout,
    Duration readTimeout) {

  public record Apple(String clientId) {}
}
```

Add Migration:

```sql
ALTER TABLE auth_accounts
    DROP CHECK ck_auth_accounts_provider,
    ADD CONSTRAINT ck_auth_accounts_provider
        CHECK (provider IN ('KAKAO', 'GOOGLE', 'NAVER', 'APPLE'));
```

Update the MySQL integration assertion to require APPLE and continue rejecting LOCAL.

- [ ] **Step 4: Run GREEN**

Run the credential test and `DatabaseMigrationIntegrationTest`. If Docker is unavailable, retain
the integration test and record the exact reason.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(auth): [S15P11B209-528] Apple OAuth 요청 계약 추가"
```

### Task 2: Nimbus Apple Identity Token Adapter

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/auth/service/AppleIdTokenVerifier.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/service/NimbusAppleIdTokenVerifier.java`
- Create: `backend/src/test/java/com/ssafy/b209/auth/service/NimbusAppleIdTokenVerifierTest.java`

**Interfaces:**
- Consumes: `OAuthProviderProperties.apple().clientId()`
- Produces: `VerifiedOAuthIdentity verify(String idToken, String rawNonce)`

- [ ] **Step 1: Write failing Adapter tests**

Use an injected `JwtDecoder` and fixed `Clock`. A valid fixture contains:

```java
Jwt.withTokenValue("apple-id-token")
    .header("alg", "RS256")
    .issuer("https://appleid.apple.com")
    .audience(List.of("com.dodam.app"))
    .subject("apple-subject")
    .expiresAt(NOW.plusSeconds(300))
    .claim("nonce", "<literal SHA-256 hex for raw-nonce>")
    .claim("email", "relay@privaterelay.appleid.com")
    .claim("email_verified", "true")
    .build();
```

Add separate tests for wrong issuer, audience, expired token, blank subject, wrong nonce,
unverified email, decoder validation error, JWK `IOException`, and missing client ID.

- [ ] **Step 2: Run RED**

```powershell
gradlew.bat test --tests com.ssafy.b209.auth.service.NimbusAppleIdTokenVerifierTest
```

Expected: compile failure because the Apple verifier types do not exist.

- [ ] **Step 3: Implement minimal Adapter**

Use `NimbusJwtDecoder.withJwkSetUri("https://appleid.apple.com/auth/keys")`.
Calculate `SHA-256(rawNonce)` using UTF-8, encode lowercase hex, and compare UTF-8 bytes using
`MessageDigest.isEqual`. Return:

```java
new VerifiedOAuthIdentity(AuthProvider.APPLE, jwt.getSubject(), verifiedEmail)
```

Map malformed/invalid tokens to `OAUTH_CREDENTIAL_INVALID`, JWK I/O failure to
`OAUTH_PROVIDER_ERROR`, and missing client ID to `AUTH_CONFIGURATION_INVALID`.

- [ ] **Step 4: Run GREEN**

```powershell
gradlew.bat test --tests com.ssafy.b209.auth.service.NimbusAppleIdTokenVerifierTest
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(auth): [S15P11B209-528] Apple Identity Token 검증 구현"
```

### Task 3: Provider Client와 HTTP 계약 연결

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/RestClientOAuthProviderClient.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/controller/OAuthController.java`
- Modify: `backend/src/test/java/com/ssafy/b209/auth/service/RestClientOAuthProviderClientTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/auth/controller/OAuthControllerTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/global/config/SwaggerEndpointTest.java`

**Interfaces:**
- Consumes: `AppleIdTokenVerifier.verify(String idToken, String rawNonce)`
- Produces: `POST /api/v1/auth/oauth/apple`

- [ ] **Step 1: Write failing delegation and Controller tests**

Assert that APPLE passes the exact token and raw nonce to the Apple Adapter and returns its real
`VerifiedOAuthIdentity`. Add a MockMvc request containing `idToken`, `rawNonce`, `deviceId` and
assert HTTP 200 with the existing response envelope. Add an invalid missing nonce request and
assert `AUTH_400_001`.

- [ ] **Step 2: Run RED**

Run the three modified test classes and confirm failure comes from missing APPLE delegation or
stale request schema.

- [ ] **Step 3: Implement minimal wiring**

Inject `AppleIdTokenVerifier`, route APPLE before REST calls, and require ID Token credentials for
GOOGLE and APPLE. Update Controller Javadoc/OpenAPI text to include Apple without creating a new
Endpoint.

- [ ] **Step 4: Run GREEN**

Run the three modified test classes and the existing `OAuthLoginServiceTest`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(auth): [S15P11B209-528] Apple OAuth 검증 흐름 연결"
```

### Task 4: 환경 변수와 계약 문서

**Files:**
- Modify: `backend/src/main/resources/application.yml`
- Modify: `.env.example`
- Modify: `README.md`
- Modify: `docs/api/API_명세서_최종.md`

**Interfaces:**
- Produces: `APPLE_CLIENT_ID`

- [ ] **Step 1: Add configuration and documentation**

Bind:

```yaml
apple:
  client-id: ${APPLE_CLIENT_ID:}
```

Document Apple request fields, fail-closed behavior, JWK/issuer/audience/nonce verification, and
that `APPLE_CLIENT_ID` is the bundle identifier `com.dodam.app` for the native app. Do not add a
real Secret or personal path.

- [ ] **Step 2: Contract review**

Confirm README, Swagger and API master document all describe the same four Providers and Provider
field matrix. Confirm no Authorization Code wording remains in the OAuth request section.

- [ ] **Step 3: Commit**

```bash
git commit -m "docs(auth): [S15P11B209-528] Apple OAuth 운영 계약 추가"
```

### Task 5: Full verification and integration

**Files:**
- Verify all issue files

**Interfaces:**
- Produces: merge-ready Jira 528 branch

- [ ] **Step 1: Run formatting**

```powershell
gradlew.bat spotlessApply
gradlew.bat spotlessCheck
```

- [ ] **Step 2: Run full tests**

```powershell
gradlew.bat clean test
```

- [ ] **Step 3: Generate Javadoc**

```powershell
gradlew.bat javadoc
```

Confirm `backend/build/docs/javadoc/index.html` exists and report warnings without hiding them.

- [ ] **Step 4: Review scope**

Run `git diff origin/develop...HEAD --check`, inspect the complete diff, and verify no Token,
Secret, local path, unrelated refactor, or 529 account policy was committed.

- [ ] **Step 5: Push, create develop-targeted MR and merge**

Use an MR title containing `S15P11B209-528`, keep `remove_source_branch=false`, merge only when
conflict-free, verify the commit is an ancestor of `origin/develop`, then delete only the remote
feature branch and complete Jira 528.
