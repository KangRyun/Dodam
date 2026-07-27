# Apple Account Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apple 최초 검증 이메일을 보존해 동일 `sub` 재로그인에 재사용하고, 탈퇴 후에는 새 서비스 사용자로 가입시키는 계정 생명주기를 완성한다.

**Architecture:** `OAuthAccountProvisioningService`가 신규·기존 인증 계정에서 검증 이메일을 결정해 `ProvisionedOAuthAccount`에 포함한다. `OAuthLoginService`는 온보딩 이메일을 우선하고, 없으면 Provisioning 결과의 저장 이메일을 사용한다. 계정 식별은 `(provider, providerSubject)`만 사용하며 이메일 기반 Provider 간 병합은 하지 않는다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, MySQL 8.x, JUnit 5, Mockito, MockMvc, Gradle 8.14.3

## Global Constraints

- 기준 Branch는 `origin/develop`이며 작업 Branch는 `feature/S15P11B209-529-apple-account-lifecycle`이다.
- 기존 `ApiResponse`, `ApiErrorResponse`, `GlobalExceptionHandler`, OAuth Provider Token 계약을 유지한다.
- 적용된 Flyway Migration은 수정하지 않으며 이 작업은 DB Schema를 변경하지 않는다.
- 이메일로 서로 다른 Provider 계정을 자동 병합하지 않는다.
- `users.email` 저장·형식·중복 검증은 S15P11B209-531 범위이므로 변경하지 않는다.
- Token, raw nonce, 이메일 원문과 Claim 전체를 로그 또는 오류 응답에 남기지 않는다.
- Production public Type과 변경된 의미를 설명하는 Javadoc은 한국어로 유지한다.

---

### Task 1: Provisioning 결과에 저장된 Provider 이메일 포함

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/ProvisionedOAuthAccount.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthAccountProvisioningService.java`
- Modify: `backend/src/test/java/com/ssafy/b209/auth/service/OAuthAccountProvisioningServiceTest.java`

**Interfaces:**
- Consumes: `VerifiedOAuthIdentity.providerEmail()`, `AuthAccount.getProviderEmail()`
- Produces: `ProvisionedOAuthAccount(Long userId, AuthProvider provider, String providerEmail, boolean newUser, boolean needsOnboarding)`

- [ ] **Step 1: 기존 Apple 계정이 저장 이메일을 반환하는 실패 테스트 작성**

`OAuthAccountProvisioningServiceTest`의 기존 계정 테스트를 Apple 전용으로 작성하고 다음을 검증한다.

```java
@Test
void returnsStoredAppleEmailWhenRepeatedTokenOmitsEmail() {
  User user = User.pending(NOW);
  ReflectionTestUtils.setField(user, "id", 7L);
  AuthAccount account =
      AuthAccount.social(
          user,
          AuthProvider.APPLE,
          "apple-sub",
          "relay@privaterelay.appleid.com",
          NOW,
          NOW);
  when(authAccountRepository.findByProviderAndProviderSubject(
          AuthProvider.APPLE, "apple-sub"))
      .thenReturn(Optional.of(account));

  ProvisionedOAuthAccount result =
      service.provision(new VerifiedOAuthIdentity(AuthProvider.APPLE, "apple-sub", null));

  assertThat(result.userId()).isEqualTo(7L);
  assertThat(result.providerEmail()).isEqualTo("relay@privaterelay.appleid.com");
  assertThat(result.newUser()).isFalse();
  verify(userRepository, never()).save(any());
}
```

- [ ] **Step 2: 테스트를 실행해 RED 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.auth.service.OAuthAccountProvisioningServiceTest"
```

Expected: `ProvisionedOAuthAccount.providerEmail()`이 없어 컴파일 실패한다.

- [ ] **Step 3: Provisioning 결과와 Service를 최소 변경**

`ProvisionedOAuthAccount`에 Provider 이메일을 추가한다.

```java
public record ProvisionedOAuthAccount(
    Long userId,
    AuthProvider provider,
    String providerEmail,
    boolean newUser,
    boolean needsOnboarding) {}
```

기존 계정은 영속화된 이메일을, 신규 계정은 검증 신원의 이메일을 반환한다.

```java
new ProvisionedOAuthAccount(
    account.getUser().getId(),
    account.getProvider(),
    account.getProviderEmail(),
    false,
    !account.getUser().isOnboardingCompleted())
```

```java
return new ProvisionedOAuthAccount(
    user.getId(), identity.provider(), identity.providerEmail(), true, true);
```

- [ ] **Step 4: 신규 가입 이메일·이메일 미제공 회귀 테스트 보완**

기존 Parameterized Test에서 `result.providerEmail()`이 입력 신원과 일치하는지 검증한다. 이메일이 없는 Provider는 `null`, 검증 이메일이 있는 신규 가입은 정규화된 이메일을 반환해야 한다.

- [ ] **Step 5: 범위 테스트를 실행해 GREEN 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.auth.service.OAuthAccountProvisioningServiceTest"
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 6: Commit**

```powershell
git add backend/src/main/java/com/ssafy/b209/auth/service/ProvisionedOAuthAccount.java backend/src/main/java/com/ssafy/b209/auth/service/OAuthAccountProvisioningService.java backend/src/test/java/com/ssafy/b209/auth/service/OAuthAccountProvisioningServiceTest.java
git commit -m "feat(auth): [S15P11B209-529] Apple 저장 이메일 재사용"
```

### Task 2: 로그인 응답 이메일 우선순위 적용

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthLoginService.java`
- Modify: `backend/src/test/java/com/ssafy/b209/auth/service/OAuthLoginServiceTest.java`

**Interfaces:**
- Consumes: `ProvisionedOAuthAccount.providerEmail()`, `User.getEmail()`
- Produces: `OAuthLoginUser.email`, `OAuthLoginUser.emailRequired`

- [ ] **Step 1: 후속 Token에 이메일이 없어도 저장 이메일을 응답하는 실패 테스트 작성**

```java
@Test
void usesStoredAppleProviderEmailWhenRepeatedTokenOmitsEmail() {
  OAuthLoginRequest request =
      new OAuthLoginRequest(null, "apple-id-token", "raw-nonce", "device-1");
  OAuthProviderCredential credential =
      new OAuthProviderCredential(
          OAuthCredentialType.ID_TOKEN, "apple-id-token", "raw-nonce");
  VerifiedOAuthIdentity identity =
      new VerifiedOAuthIdentity(AuthProvider.APPLE, "apple-sub", null);
  User user = User.pending(LocalDateTime.of(2026, 7, 22, 11, 0));
  ReflectionTestUtils.setField(user, "id", 41L);
  when(providerClient.verify(AuthProvider.APPLE, credential)).thenReturn(identity);
  when(provisioningService.provision(identity))
      .thenReturn(
          new ProvisionedOAuthAccount(
              41L,
              AuthProvider.APPLE,
              "relay@privaterelay.appleid.com",
              false,
              true));
  when(userRepository.findById(41L)).thenReturn(Optional.of(user));
  when(tokenIssuer.issue(41L))
      .thenReturn(new IssuedTokenPair("access", 1800, "refresh", 1209600, "family-1"));

  OAuthLoginResult result = service.login(AuthProvider.APPLE, request);

  assertThat(result.user().email()).isEqualTo("relay@privaterelay.appleid.com");
  assertThat(result.user().emailRequired()).isFalse();
}
```

- [ ] **Step 2: 테스트를 실행해 RED 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.auth.service.OAuthLoginServiceTest"
```

Expected: 현재 신원 이메일이 `null`이라 응답 이메일 Assertion이 실패한다.

- [ ] **Step 3: 로그인 이메일 우선순위를 최소 구현**

```java
String email =
    user.getEmail() != null ? user.getEmail() : provisioned.providerEmail();
```

현재 Token의 `identity.providerEmail()`을 직접 사용하는 분기를 제거한다.

- [ ] **Step 4: 온보딩 이메일 우선 테스트 작성**

`User.completeOnboarding`으로 `guardian@example.com`을 저장하고 Provisioning 결과에는 Apple relay 이메일을 넣는다. 응답은 `guardian@example.com`이며 `emailRequired=false`임을 검증한다.

- [ ] **Step 5: 범위 테스트를 실행해 GREEN 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.auth.service.OAuthLoginServiceTest"
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 6: Commit**

```powershell
git add backend/src/main/java/com/ssafy/b209/auth/service/OAuthLoginService.java backend/src/test/java/com/ssafy/b209/auth/service/OAuthLoginServiceTest.java
git commit -m "feat(auth): [S15P11B209-529] Apple 재로그인 이메일 복원"
```

### Task 3: Apple 가입·재로그인·탈퇴 후 재가입 통합 검증

**Files:**
- Modify: `backend/src/test/java/com/ssafy/b209/auth/OAuthAuthenticationFlowIntegrationTest.java`

**Interfaces:**
- Consumes: `POST /api/v1/auth/oauth/apple`, `DELETE /api/v1/users/me`
- Produces: 동일 `sub` 사용자 재사용, 탈퇴 후 신규 사용자, Provider 간 이메일 비병합을 증명하는 E2E 테스트

- [ ] **Step 1: Apple 최초 가입 후 이메일 없는 재로그인 테스트 작성**

`OAuthProviderClient` Mock이 최초 호출에는 이메일을, 두 번째 호출에는 같은 `sub`와 `null` 이메일을 반환하도록 구성한다. 두 응답의 `userId`가 같고 두 번째 응답도 relay 이메일과 `emailRequired=false`를 반환하는지 검증한다.

```java
when(providerClient.verify(eq(AuthProvider.APPLE), any()))
    .thenReturn(
        new VerifiedOAuthIdentity(
            AuthProvider.APPLE, "apple-sub", "relay@privaterelay.appleid.com"),
        new VerifiedOAuthIdentity(AuthProvider.APPLE, "apple-sub", null));
```

요청 Body는 다음 계약을 사용한다.

```java
Map.of(
    "idToken", "apple-id-token",
    "rawNonce", "apple-raw-nonce",
    "deviceId", DEVICE_ID)
```

- [ ] **Step 2: 통합 테스트를 실행해 RED 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.auth.OAuthAuthenticationFlowIntegrationTest"
```

Expected: 두 번째 응답 이메일이 `null`이거나 `emailRequired=true`라 실패한다.

- [ ] **Step 3: 탈퇴 후 같은 Apple `sub` 재가입 테스트 작성**

첫 로그인 Access Token으로 다음 요청을 보내고 HTTP 204를 확인한다.

```java
delete("/api/v1/users/me")
    .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
    .contentType(MediaType.APPLICATION_JSON)
    .content("{\"confirmation\":\"DELETE\"}")
```

같은 Apple `sub`로 다시 로그인해 이전과 다른 `userId`, `newUser`에 대응하는 온보딩 필요 상태, 새 `users`·`auth_accounts` 행을 확인한다.

- [ ] **Step 4: 동일 이메일의 다른 Provider 비병합 테스트 작성**

Apple과 Google의 `VerifiedOAuthIdentity`가 같은 이메일을 반환하도록 설정해 각각 로그인한다. 서로 다른 `userId`와 두 개의 `auth_accounts` 행을 검증한다.

- [ ] **Step 5: 통합 테스트를 실행해 GREEN 확인**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.auth.OAuthAuthenticationFlowIntegrationTest"
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 6: Commit**

```powershell
git add backend/src/test/java/com/ssafy/b209/auth/OAuthAuthenticationFlowIntegrationTest.java
git commit -m "test(auth): [S15P11B209-529] Apple 계정 생명주기 검증"
```

### Task 4: 공개 계약과 운영 조건 문서화

**Files:**
- Modify: `README.md`
- Modify: `docs/api/public-api-contract-v1.md`
- Modify: `docs/api/API_명세서_최종.md`
- Modify: `docs/superpowers/plans/2026-07-27-apple-account-lifecycle.md`

**Interfaces:**
- Consumes: Task 1~3에서 확정한 실제 동작
- Produces: FE·운영 담당자가 사용할 Apple 재로그인·탈퇴 후 재가입 계약

- [ ] **Step 1: 문서에 확정 정책 반영**

다음을 명시한다.

- 같은 `(APPLE, sub)`는 같은 사용자다.
- 최초 검증 이메일은 후속 Token에 없어도 재사용한다.
- 다른 Provider와 이메일이 같아도 자동 병합하지 않는다.
- 탈퇴 후 같은 Apple 계정 로그인은 신규 가입이다.
- `users.email` 저장·중복 검증은 온보딩 계약을 따른다.

`public-api-contract-v1.md`의 “529에서 별도 확정” 문구를 확정 정책으로 교체한다.

- [ ] **Step 2: 문서와 코드 형식 검사**

Run:

```powershell
git diff --check
gradlew.bat spotlessCheck
```

Expected: 두 명령 모두 성공한다.

- [ ] **Step 3: Commit**

```powershell
git add README.md docs/api/public-api-contract-v1.md docs/api/API_명세서_최종.md docs/superpowers/plans/2026-07-27-apple-account-lifecycle.md
git commit -m "docs(auth): [S15P11B209-529] Apple 계정 정책 확정"
```

### Task 5: 전체 검증과 Apple 운영 설정 확인

**Files:**
- Verify only: `backend/build/docs/javadoc/index.html`
- External configuration: Apple Developer App ID `com.dodam.app`, Jenkins `APPLE_CLIENT_ID`

**Interfaces:**
- Consumes: 완료된 Backend 구현과 Apple Developer 권한
- Produces: 병합 가능한 검증 결과와 실기기 E2E 전제 조건 보고

- [ ] **Step 1: 전체 Backend 검증**

Run:

```powershell
gradlew.bat clean test
gradlew.bat spotlessCheck
gradlew.bat javadoc
```

Expected: 모든 명령이 성공하고 `backend/build/docs/javadoc/index.html`이 존재한다.

- [ ] **Step 2: 신규 코드 Javadoc 경고 확인**

Javadoc 출력에서 이번에 수정한 `ProvisionedOAuthAccount`, `OAuthAccountProvisioningService`, `OAuthLoginService` 관련 경고가 없는지 확인한다. 기존 경고는 파일과 개수를 별도로 보고한다.

- [ ] **Step 3: Apple Developer Console 확인**

- App ID Bundle ID: `com.dodam.app`
- Sign in with Apple Capability: 활성
- iOS Runner Signing Team과 Provisioning Profile: 동일 App ID 사용
- 불필요한 웹 Service ID와 Client Secret: 생성하지 않음

- [ ] **Step 4: Jenkins 환경 변수 확인**

Jenkins Secret 원문을 출력하지 않고 `APPLE_CLIENT_ID` 존재 여부와 값이 `com.dodam.app`인지 마스킹된 방식으로 확인한다. 설정 변경이 필요하면 사용자 로그인 세션에서 적용하고 배포 결과를 확인한다.

- [ ] **Step 5: 범위·상태 최종 확인**

```powershell
git diff --check origin/develop...HEAD
git status --short
git log --oneline origin/develop..HEAD
```

Expected: diff 오류와 미커밋 변경이 없고 모든 Commit에 `S15P11B209-529`가 포함된다.
