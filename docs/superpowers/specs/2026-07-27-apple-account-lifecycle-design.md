# Apple 계정 가입·연결·재로그인 설계

## 1. 목적

S15P11B209-528에서 검증한 Apple Identity Token의 신원을 기존 OAuth 계정 구조에 안전하게 연결한다. Apple이 이메일을 최초 동의 시점에만 제공하더라도 같은 Apple 계정의 재로그인이 동일한 서비스 사용자와 최초 검증 이메일을 유지하도록 한다.

## 2. 현행 구조와 문제

- `OAuthAccountProvisioningService`는 `(provider, providerSubject)`로 기존 `AuthAccount`를 조회한다.
- 신규 신원은 `User.pending`과 `AuthAccount.social`을 생성하며, Provider가 검증한 이메일을 `auth_accounts.provider_email`에 저장한다.
- 기존 신원은 같은 `User`를 반환하지만 저장된 `provider_email`을 로그인 결과에 전달하지 않는다.
- `OAuthLoginService`는 `users.email`이 없으면 현재 Token의 `providerEmail`만 사용한다.
- Apple은 후속 로그인에서 이메일 Claim을 생략할 수 있으므로, 온보딩 전에 재로그인하면 저장된 이메일이 있는데도 `emailRequired=true`로 되돌아갈 수 있다.
- 회원 탈퇴는 `users`를 즉시 삭제하고 FK `ON DELETE CASCADE`로 `auth_accounts`도 제거한다.

## 3. 확정 정책

1. 계정 식별자는 이메일이 아니라 `(APPLE, Apple sub)` 조합이다.
2. 같은 Apple `sub`의 반복 로그인은 같은 서비스 사용자를 재사용한다.
3. Apple이 최초 로그인에서 제공한 검증 이메일은 `auth_accounts.provider_email`에 보존한다.
4. 후속 Token에 이메일이 없으면 저장된 `provider_email`을 로그인 응답의 보조 이메일로 사용한다.
5. `users.email`은 온보딩에서 확정한 연락 이메일이며 이 이슈에서 자동 기록하지 않는다.
6. 다른 Provider의 이메일이 같아도 자동으로 계정을 병합하지 않는다.
7. 회원 탈퇴 후에는 Apple 연결 행도 삭제되므로 같은 Apple `sub`의 다음 로그인은 신규 사용자로 처리한다.
8. 이메일 형식·중복 검증과 온보딩 저장은 S15P11B209-531 범위로 유지한다.

## 4. 설계

### 4.1 Provisioning 결과

`ProvisionedOAuthAccount`에 `providerEmail`을 추가한다.

- 신규 계정: 검증된 `VerifiedOAuthIdentity.providerEmail`
- 기존 계정: 영속화된 `AuthAccount.providerEmail`

Provisioning 계층이 인증 계정 저장 구조를 알고 있으므로 저장 이메일 선택 책임도 이 계층에 둔다. `OAuthLoginService`에서 `AuthAccountRepository`를 다시 조회하지 않는다.

### 4.2 로그인 응답

로그인 응답 이메일의 우선순위는 다음과 같다.

1. 온보딩에서 확정한 `User.email`
2. Provisioning 결과의 검증된 `providerEmail`
3. 둘 다 없으면 `null`

`emailRequired`는 최종 응답 이메일이 `null`인지를 기준으로 계산한다. 서비스 Access·Refresh Token 발급, 로그인 시각 갱신, Refresh Token Session 등록 흐름은 변경하지 않는다.

### 4.3 계정 연결과 중복

이 이슈에서 “연결”은 검증된 Apple `sub`와 서비스 `User`의 연결을 의미한다. 이메일을 근거로 기존 Kakao·Google·Naver 사용자와 자동 연결하지 않는다. 이메일은 변경 가능하고 Apple 비공개 릴레이 주소가 사용될 수 있으므로 인증 계정의 불변 식별자가 될 수 없다.

동시에 같은 Apple `sub`로 최초 로그인하여 UNIQUE 제약이 충돌하면 기존 `ACCOUNT_LINK_CONFLICT` 오류를 유지한다. 요청 중 재조회나 암묵적 계정 병합은 추가하지 않는다.

### 4.4 탈퇴 후 재가입

`DELETE /api/v1/users/me`의 즉시 삭제 정책을 변경하지 않는다. 사용자 삭제로 Apple `AuthAccount`도 제거되며, 같은 Apple `sub`로 다시 로그인하면 새 `User`와 `AuthAccount`가 생성된다. 이전 사용자 ID, 온보딩 상태, 서비스 JWT는 복원하지 않는다.

## 5. API 계약

기존 Endpoint를 유지한다.

```http
POST /api/v1/auth/oauth/apple
Content-Type: application/json
```

```json
{
  "idToken": "<apple-identity-token>",
  "rawNonce": "<original-random-nonce>",
  "deviceId": "<device-id>"
}
```

응답 형식은 기존 OAuth 로그인 응답과 동일하다. Apple 최초 검증 이메일이 저장돼 있으면 후속 Token에 이메일이 없어도 `data.user.email`에 저장 이메일을 반환하고 `data.user.emailRequired`는 `false`다.

## 6. 오류 처리

- Identity Token, issuer, audience, 만료, subject, nonce 오류: `AUTH_401_001`
- Apple JWK 조회 장애: `AUTH_502_001`
- `APPLE_CLIENT_ID` 누락: `AUTH_503_001`
- 동시 계정 연결 충돌: `AUTH_409_001`
- 정지·삭제 상태 사용자: 기존 계정 상태 오류 유지

Token, raw nonce, 이메일 원문, Claim 전체는 로그나 오류 응답에 노출하지 않는다.

## 7. 테스트

- 기존 Apple `AuthAccount`가 있으면 저장 이메일과 같은 사용자 ID를 반환한다.
- 후속 Apple Token에 이메일이 없어도 저장 이메일을 로그인 응답에 사용한다.
- 온보딩으로 확정한 `users.email`이 저장 Apple 이메일보다 우선한다.
- 다른 Provider가 같은 이메일을 제공해도 별도 사용자를 생성한다.
- 탈퇴 후 같은 Apple `sub`로 로그인하면 새 사용자 ID를 발급한다.
- 이메일이 최초부터 없으면 기존과 같이 `emailRequired=true`를 반환한다.
- Kakao·Google·Naver 가입·재로그인 회귀 테스트를 유지한다.

## 8. Apple Developer Console 및 운영 설정

- Apple Developer App ID의 Bundle ID는 `com.dodam.app`으로 유지한다.
- 해당 App ID에서 Sign in with Apple Capability를 활성화한다.
- iOS Runner의 Bundle ID와 Signing Team·Provisioning Profile이 같은 App ID를 사용해야 한다.
- Backend 배포 환경에는 `APPLE_CLIENT_ID=com.dodam.app`을 주입한다.
- 네이티브 앱 Identity Token 검증에는 별도의 웹 Service ID나 Client Secret을 추가하지 않는다.
- 실제 콘솔 설정은 Apple Developer 권한과 2FA 로그인이 확인된 세션에서 수행한다.

## 9. 제외 범위

- 이메일 기반 Provider 간 자동 계정 병합
- 사용자가 명시적으로 여러 Provider를 연결·해제하는 별도 API
- 온보딩 이메일 형식·중복 검증과 저장
- Apple 계정 연결 해제 또는 Token Revoke API
- Flutter `sign_in_with_apple` SDK·버튼 구현
- 웹용 Sign in with Apple Service ID와 Client Secret 발급
