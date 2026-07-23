# Mobile OAuth Provider Token Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kakao·Naver의 `accessToken`과 Google의 `idToken`을 검증한 뒤 기존 서비스 Access·Refresh Token을 발급하도록 모바일 OAuth 계약을 정합화한다.

**Architecture:** Controller는 Provider Token 요청 형식만 검증하고, `OAuthLoginService`가 Provider별 Credential 조합을 내부 값으로 정규화한다. Kakao·Naver 검증은 `RestClientOAuthProviderClient`, Google ID Token 검증은 Nimbus 기반 전용 구현이 맡으며, 검증 이후의 계정 Provisioning·JWT 발급·Redis Refresh Session 흐름은 재사용한다.

**Tech Stack:** Java 21, Spring Boot 3.5, Spring MVC `RestClient`, Spring Security OAuth2 JOSE/Nimbus, Jakarta Validation, JUnit 5, Mockito, MockMvc, `MockRestServiceServer`, Gradle

## Global Constraints

- 최신 `develop`에서 생성한 `fix/S15P11B209-375-mobile-oauth-provider-token`에서만 작업한다.
- `.idea/**`와 `backend/local.properties`는 사용자 로컬 변경이므로 수정·Stage·Commit하지 않는다.
- `POST /api/v1/auth/oauth/{provider}`와 기존 성공 응답은 유지하고 Authorization Code 호환 경로는 만들지 않는다.
- Provider Token을 저장하거나 로그·오류 응답에 노출하지 않는다.
- DB·Flyway Migration과 Flutter 코드는 변경하지 않는다.
- Production public type과 public method에는 실제 역할에 맞는 한국어 Javadoc을 작성한다.

---

## Task 1: HTTP 요청을 Provider Credential로 정규화

**Files:**

- Modify: `backend/src/main/java/com/ssafy/b209/auth/dto/request/OAuthLoginRequest.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthCredentialType.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthProviderCredential.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthProviderClient.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthLoginService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/controller/OAuthController.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/exception/AuthErrorCode.java`
- Test: `backend/src/test/java/com/ssafy/b209/auth/controller/OAuthControllerTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/auth/service/OAuthLoginServiceTest.java`

- [ ] **Step 1: 실패하는 Controller 계약 테스트 작성**

Kakao·Naver는 `accessToken`, Google은 `idToken`을 받으며 Token 누락·동시 전달·Provider 불일치는 `AUTH_400_001`로 거부되는 MockMvc 테스트를 추가한다.

```json
{"accessToken":"kakao-token","deviceId":"device-1"}
```

```json
{"idToken":"google-id-token","deviceId":"device-1"}
```

- [ ] **Step 2: 실패하는 Service 정규화 테스트 작성**

`OAuthProviderClient.verify`가 다음 내부 계약을 받는지 검증하고, 조합 오류 시 Provider Client·Provisioning·JWT 발급을 호출하지 않는지 확인한다.

```java
new OAuthProviderCredential(OAuthCredentialType.ACCESS_TOKEN, "kakao-token")
new OAuthProviderCredential(OAuthCredentialType.ID_TOKEN, "google-id-token")
```

- [ ] **Step 3: 대상 테스트가 기존 코드에서 실패하는지 확인**

Run:

```powershell
cd backend
.\gradlew.bat test --tests "*OAuthControllerTest" --tests "*OAuthLoginServiceTest"
```

Expected: 기존 `authorizationCode` DTO와 Client 시그니처 때문에 컴파일 또는 assertion 실패.

- [ ] **Step 4: 최소 계약 구현**

`OAuthLoginRequest`를 아래 의미로 변경한다.

```java
public record OAuthLoginRequest(
    @Size(max = 4096) String accessToken,
    @Size(max = 4096) String idToken,
    @NotBlank @Size(max = 255) String deviceId) {}
```

`OAuthProviderCredential.from(provider, request)`는 Kakao·Naver에 정확히 하나의 non-blank `accessToken`, Google에 정확히 하나의 non-blank `idToken`만 허용하고 그 외에는 `OAUTH_REQUEST_INVALID`를 발생시킨다. `OAuthLoginService`는 정규화된 Credential만 `OAuthProviderClient`에 전달한다.

- [ ] **Step 5: 대상 테스트 통과 확인**

Run:

```powershell
cd backend
.\gradlew.bat test --tests "*OAuthControllerTest" --tests "*OAuthLoginServiceTest"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add backend/src/main/java/com/ssafy/b209/auth backend/src/test/java/com/ssafy/b209/auth
git commit -m "feat(auth): S15P11B209-375 Provider Token 요청 계약 적용"
```

---

## Task 2: Kakao·Naver Access Token 검증 구현

**Files:**

- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthProviderProperties.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/service/GoogleIdTokenVerifier.java`
- Modify: `backend/src/main/java/com/ssafy/b209/auth/service/RestClientOAuthProviderClient.java`
- Rewrite: `backend/src/test/java/com/ssafy/b209/auth/service/RestClientOAuthProviderClientTest.java`

- [ ] **Step 1: 실패하는 Kakao 테스트 작성**

다음을 `MockRestServiceServer`로 검증한다.

- `/v1/user/access_token_info`와 `/v2/user/me`가 같은 Bearer Token을 받는다.
- `expires_in > 0`, `app_id == KAKAO_APP_ID`, 두 응답의 사용자 ID가 일치한다.
- 검증·인증된 이메일만 `VerifiedOAuthIdentity`에 포함한다.
- Provider 4xx는 `AUTH_401_001`, 5xx·통신 오류·해석 불가 응답은 `AUTH_502_001`이다.
- App ID 설정 누락은 외부 호출 전에 `AUTH_503_001`이다.

- [ ] **Step 2: 실패하는 Naver 테스트 작성**

`/v1/nid/me`를 전달받은 Bearer Token으로 바로 호출하고 `resultcode=00` 및 non-blank `response.id`를 요구한다. 이메일은 계정 식별에 사용하지 않으며, Provider 4xx/5xx 매핑도 검증한다.

- [ ] **Step 3: 실패 확인**

Run:

```powershell
cd backend
.\gradlew.bat test --tests "*RestClientOAuthProviderClientTest"
```

Expected: Authorization Code 교환 요청이 발생해 테스트 실패.

- [ ] **Step 4: Provider 설정과 Client 구현 변경**

설정은 다음 최소 형태로 축소한다.

```java
public record OAuthProviderProperties(
    Kakao kakao, Google google, Duration connectTimeout, Duration readTimeout) {
  public record Kakao(String appId) {}
  public record Google(String clientId) {}
}
```

`RestClientOAuthProviderClient`의 책임은 아래와 같이 나눈다.

```java
return switch (provider) {
  case KAKAO -> verifyKakao(credential.value());
  case NAVER -> verifyNaver(credential.value());
  case GOOGLE -> googleIdTokenVerifier.verify(credential.value());
};
```

Kakao Token 정보 응답:

```java
private record KakaoTokenInfo(Long id, Long appId, Integer expiresIn) {}
```

HTTP 4xx는 `OAUTH_CREDENTIAL_INVALID`, 그 밖의 `RestClientException`은 `OAUTH_PROVIDER_ERROR`로 변환한다.

- [ ] **Step 5: Provider Client 테스트 통과 확인**

Run:

```powershell
cd backend
.\gradlew.bat test --tests "*RestClientOAuthProviderClientTest"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add backend/src/main/java/com/ssafy/b209/auth/service backend/src/test/java/com/ssafy/b209/auth/service
git commit -m "feat(auth): S15P11B209-375 Kakao Naver Token 검증 구현"
```

---

## Task 3: Google ID Token 로컬 검증 구현

**Files:**

- Create: `backend/src/main/java/com/ssafy/b209/auth/service/NimbusGoogleIdTokenVerifier.java`
- Create: `backend/src/test/java/com/ssafy/b209/auth/service/NimbusGoogleIdTokenVerifierTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/auth/service/RestClientOAuthProviderClientTest.java`

- [ ] **Step 1: 실패하는 Google 검증 테스트 작성**

주입 가능한 `JwtDecoder`와 `Clock`으로 다음을 검증한다.

- `iss`는 `accounts.google.com` 또는 `https://accounts.google.com`만 허용한다.
- `aud`는 설정한 `GOOGLE_CLIENT_ID`를 포함해야 한다.
- `exp`가 현재보다 미래이고 `sub`가 non-blank여야 한다.
- `email_verified=true`일 때만 이메일을 반환한다.
- 서명·Claim 검증 실패는 `AUTH_401_001`이다.
- JWK 조회의 `IOException` 계열 원인은 `AUTH_502_001`이다.
- Client ID 누락은 Decoder 호출 전 `AUTH_503_001`이다.

- [ ] **Step 2: 실패 확인**

Run:

```powershell
cd backend
.\gradlew.bat test --tests "*NimbusGoogleIdTokenVerifierTest"
```

Expected: 구현 클래스가 없어 컴파일 실패.

- [ ] **Step 3: Nimbus 검증 구현**

Production 생성자는 Google JWK Set URI를 사용하는 Decoder를 구성한다.

```java
private static final String GOOGLE_JWK_SET_URI =
    "https://www.googleapis.com/oauth2/v3/certs";
```

검증 순서는 설정 존재 확인 → `JwtDecoder.decode`로 서명 검증 → issuer·audience·expiration·subject 확인 → 검증된 이메일 선택이다. Provider Token 값이나 JWT Payload는 예외 메시지와 로그에 포함하지 않는다.

- [ ] **Step 4: Google 및 Provider Client 테스트 통과 확인**

Run:

```powershell
cd backend
.\gradlew.bat test --tests "*NimbusGoogleIdTokenVerifierTest" --tests "*RestClientOAuthProviderClientTest"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add backend/src/main/java/com/ssafy/b209/auth/service backend/src/test/java/com/ssafy/b209/auth/service
git commit -m "feat(auth): S15P11B209-375 Google ID Token 검증 구현"
```

---

## Task 4: 환경 설정·API 문서 정합화

**Files:**

- Modify: `backend/src/main/resources/application.yml`
- Modify: `.env.example`
- Modify: `README.md`
- Modify: `docs/database/social-auth-schema-v1.3.md`
- Modify: `backend/src/test/java/com/ssafy/b209/global/config/SwaggerEndpointTest.java`

- [ ] **Step 1: Swagger 계약 테스트 보완**

OAuth Endpoint가 기존 Bearer 인증을 요구하지 않고 Provider Token 요청 설명을 노출하는지 확인한다. Entity나 실제 Token 값은 Schema 예시에 넣지 않는다.

- [ ] **Step 2: 환경 변수 변경**

`application.yml`과 `.env.example`에는 다음만 OAuth Provider 검증 설정으로 남긴다.

```text
KAKAO_APP_ID
GOOGLE_CLIENT_ID
OAUTH_CONNECT_TIMEOUT
OAUTH_READ_TIMEOUT
```

Authorization Code 교환에만 쓰던 Client Secret·Redirect URI·Naver Client 설정은 제거한다.

- [ ] **Step 3: README와 DB 계약 문서 변경**

README에 Provider별 요청 예시, Google `serverClientId`와 `GOOGLE_CLIENT_ID` 일치 조건, Provider Token 비저장, 오류 코드를 기록한다. `social-auth-schema-v1.3.md`의 Authorization Code 설명을 Provider Token 검증 흐름으로 바꾸되 DB Schema는 변경하지 않는다.

- [ ] **Step 4: 문서·설정 관련 테스트 확인**

Run:

```powershell
cd backend
.\gradlew.bat test --tests "*SwaggerEndpointTest" --tests "*OAuthControllerTest"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add .env.example README.md docs/database/social-auth-schema-v1.3.md backend/src/main/resources/application.yml backend/src/test/java/com/ssafy/b209/global/config/SwaggerEndpointTest.java
git commit -m "docs(auth): S15P11B209-375 OAuth 환경 계약 정리"
```

---

## Task 5: 회귀 검증과 변경 범위 점검

- [ ] **Step 1: Authorization Code 잔재 검색**

Run:

```powershell
rg -n "authorizationCode|redirectUri|state|KAKAO_CLIENT_SECRET|GOOGLE_CLIENT_SECRET|NAVER_CLIENT_SECRET" backend/src/main README.md .env.example docs/database/social-auth-schema-v1.3.md
```

Expected: 현재 OAuth 로그인 계약에 관한 잔재 없음. 다른 기능의 일반적인 `state` 사용은 문맥을 확인한다.

- [ ] **Step 2: 전체 검증**

Run:

```powershell
cd backend
.\gradlew.bat clean test
.\gradlew.bat spotlessCheck
.\gradlew.bat javadoc
```

Expected: 세 명령 모두 exit code 0, Javadoc은 `backend/build/docs/javadoc/index.html` 생성.

- [ ] **Step 3: 변경 범위와 Secret 노출 확인**

Run:

```powershell
git status --short
git diff --check develop...HEAD
git diff --name-only develop...HEAD
```

Expected: Jira 범위 파일과 설계·계획 문서만 Commit되어 있으며 `.idea/**`, `backend/local.properties`, 실제 Token·Secret이 포함되지 않음.

- [ ] **Step 4: Jira와 Git 완료 처리**

검증이 모두 성공하면 남은 변경을 이슈 코드 포함 메시지로 Commit하고 Push·Merge Request 생성·Merge를 수행한다. Merge 후 원격 작업 브랜치는 삭제하고 로컬 브랜치는 유지한다. Jira에는 구현·검증 결과를 댓글로 남기고 완료 상태로 전환한다.

