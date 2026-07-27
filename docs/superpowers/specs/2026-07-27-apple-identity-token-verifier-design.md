# Apple Identity Token 검증 Adapter 설계

## 1. 목적

`POST /api/v1/auth/oauth/{provider}`가 모바일 Sign in with Apple에서 받은
Identity Token을 신뢰하기 전에 서명과 필수 Claim을 검증할 수 있게 한다.

기준 이슈는 `S15P11B209-528`이다. 이 이슈는 Apple Token 검증 경계와
Provider 연결에 집중한다. Apple 계정의 최초 이메일 처리, 재로그인 및 탈퇴 후
재가입 정책은 `S15P11B209-529`에서 보강한다.

## 2. 현재 구조와 제약

- Kakao·Naver는 `RestClientOAuthProviderClient`가 Access Token을 검증한다.
- Google은 `NimbusGoogleIdTokenVerifier`가 공개 JWK로 ID Token을 검증한다.
- `OAuthLoginRequest`에는 `accessToken`, `idToken`, `deviceId`만 존재한다.
- `AuthProvider`와 DB Check Constraint는 APPLE을 허용하지 않는다.
- 검증된 Provider 신원은 `VerifiedOAuthIdentity`를 거쳐 기존 Provisioning 및
  서비스 JWT 발급 흐름으로 전달된다.

APPLE을 Enum에만 추가하면 MySQL의 `ck_auth_accounts_provider`와 충돌한다.
따라서 기존 Migration을 수정하지 않고 새 Migration에서 APPLE을 추가한다.

## 3. API 계약

Apple 로그인 요청은 다음 필드를 사용한다.

```json
{
  "idToken": "apple-identity-token",
  "rawNonce": "client-generated-random-value",
  "deviceId": "device-installation-id"
}
```

- APPLE은 `idToken`, `rawNonce`, `deviceId`가 모두 필수다.
- APPLE 요청에는 `accessToken`을 허용하지 않는다.
- GOOGLE은 기존처럼 `idToken`, `deviceId`만 사용하며 `rawNonce`를 허용하지
  않는다.
- KAKAO·NAVER는 기존처럼 `accessToken`, `deviceId`만 사용한다.
- `rawNonce`는 공백이 아니어야 하고 최대 512자로 제한한다.
- Provider별 필드 조합 오류는 기존 `AUTH_400_001`을 사용한다.
- Token과 nonce 원문은 로그, DB 및 오류 응답에 기록하지 않는다.

## 4. Apple 검증 규칙

`NimbusAppleIdTokenVerifier`는 Apple 공개 JWK Set
`https://appleid.apple.com/auth/keys`를 사용하는 `JwtDecoder`로 다음을
검증한다.

1. JWT 서명
2. `iss`가 `https://appleid.apple.com`인지
3. `aud`에 서버 설정 `APPLE_CLIENT_ID`가 포함되는지
4. `exp`가 현재 시각 이후인지
5. `sub`가 공백이 아닌지
6. `SHA-256(rawNonce)`의 lowercase hex 값과 Token의 `nonce` Claim이
   상수 시간 비교로 일치하는지

Decoder 검증 실패는 `AUTH_401_001`, Apple JWK 조회 장애는
`AUTH_502_001`, `APPLE_CLIENT_ID` 누락은 `AUTH_503_001`로 변환한다.

검증에 성공하면 Provider Subject는 `sub`를 사용한다. `email_verified`가
Boolean `true` 또는 문자열 `"true"`인 경우에만 `email` Claim을
`providerEmail`로 전달한다. Apple의 비공개 Relay 이메일도 별도로 배제하지
않는다.

## 5. 구성 요소 변경

- `AuthProvider`: `APPLE` 추가
- `OAuthLoginRequest`: `rawNonce` 추가
- `OAuthProviderCredential`: ID Token과 raw nonce를 함께 보관하도록 확장하고
  Provider별 조합 검증
- `OAuthProviderProperties`: Apple Client ID 설정 추가
- `AppleIdTokenVerifier`: 외부 시스템 검증 추상화
- `NimbusAppleIdTokenVerifier`: Apple 공개키와 Claim 검증 구현
- `RestClientOAuthProviderClient`: APPLE 검증을 전용 Adapter에 위임
- `application.yml`, `.env.example`, README/API 문서: `APPLE_CLIENT_ID`와 요청
  계약 추가
- 새 Flyway Migration: `ck_auth_accounts_provider`에 APPLE 추가

기존 Controller, Provisioning, JWT 발급 및 Redis Refresh Token Session
구조는 재사용한다. 새로운 인증 Endpoint나 Token 저장소는 만들지 않는다.

## 6. 테스트

- Apple Adapter 정상 Token에서 Subject와 검증된 이메일 반환
- 잘못된 issuer, audience, 만료, subject, nonce 거절
- 미검증 이메일 제외
- Decoder 오류와 JWK 통신 장애 오류 매핑
- Apple Client ID 누락 시 Decoder 호출 전 설정 오류
- APPLE의 Provider Credential 조합과 raw nonce 필수 검증
- Provider Client가 Apple Adapter에 ID Token과 raw nonce를 정확히 위임
- Controller 요청 직렬화 및 오류 응답 계약
- MySQL Migration에서 APPLE Provider 저장 가능 여부

실제 Apple Sandbox 호출은 Apple Developer 설정과 실기기 로그인이 필요한
외부 검증으로 분리하며, Repository 테스트에서는 공개키 네트워크 호출 대신
주입된 `JwtDecoder`로 결정적인 단위 테스트를 수행한다.

## 7. 제외 범위

- Apple Developer Console의 App ID, Capability 및 Provisioning 설정
- Authorization Code 교환과 Apple Refresh Token 저장
- Apple 계정 연결 해제 및 Token revoke
- Flutter Sign in with Apple UI와 SDK 배선
- 서버 발급 nonce Challenge API와 Redis 일회성 nonce 저장
- 529번의 탈퇴·재가입·중복 계정 정책
