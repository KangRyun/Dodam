# 모바일 OAuth Provider Token 계약 정합화 설계

## 1. 목적

`POST /api/v1/auth/oauth/{provider}`의 인증 입력을 모바일 SDK가 발급한 Provider Token 방식으로 변경한다.

- Kakao와 Naver는 `accessToken`을 전달한다.
- Google은 `idToken`을 전달한다.
- 백엔드는 전달받은 Credential이 해당 Provider와 서비스 App을 위해 발급됐는지 검증한다.
- 검증된 Provider 신원을 기존 계정 Provisioning과 서비스 Access·Refresh Token 발급 흐름에 연결한다.

Endpoint와 성공 응답은 유지한다. Authorization Code 교환 방식과 Provider Token 방식을 동시에 지원하지 않는다.

## 2. 배경과 충돌

### 기존 백엔드

- 요청 필드: `authorizationCode`, `redirectUri`, `state`, `deviceId`
- 백엔드가 Kakao·Google·Naver Token Endpoint에 Authorization Code를 전달한다.
- 교환받은 Access Token으로 Provider 사용자 정보를 조회한다.

### 모바일 계약

- Flutter 인증 도메인은 Kakao·Naver를 `accessToken`, Google을 `idToken`으로 구분한다.
- 모바일 SDK가 Provider 인증을 완료하고 Token을 앱에 반환한다.
- 앱은 Provider Token을 백엔드 로그인 Endpoint로 전달한다.

기존 DTO를 유지하면 모바일 요청은 필수 필드 검증에서 HTTP 400이 발생하며 Google ID Token을 검증할 경로가 없다.

## 3. 범위

### 포함

- OAuth 로그인 요청 DTO를 Provider Token 계약으로 변경
- Provider와 Token 종류 조합 검증
- Kakao Access Token 유효성·App 소속·사용자 신원 검증
- Naver Access Token 사용자 신원 검증
- Google ID Token 서명·발급자·대상·만료 검증
- 기존 계정 Provisioning, JWT 발급, Redis Refresh Token Session 등록 재사용
- 인증 오류 계약과 Swagger 문서 정합화
- OAuth 환경 변수, README와 현재 계약 문서 보완
- Controller, Service, Provider Client, Google ID Token 검증 테스트

### 제외

- Flutter OAuth SDK 실제 연동
- Kakao·Naver Provider Refresh Token 수집 또는 보관
- Provider Token 재발급
- OAuth Account DB Schema 변경
- 자체 이메일·비밀번호 로그인
- 기존 Authorization Code 방식과의 호환 모드
- 적용된 Flyway Migration 수정

## 4. API 계약

### Endpoint

```http
POST /api/v1/auth/oauth/{provider}
Content-Type: application/json
```

Path `provider`는 대소문자와 무관하게 `KAKAO`, `GOOGLE`, `NAVER`만 허용한다.

### Kakao·Naver 요청

```json
{
  "accessToken": "provider-access-token",
  "deviceId": "device-installation-id"
}
```

### Google 요청

```json
{
  "idToken": "google-id-token",
  "deviceId": "device-installation-id"
}
```

### 필드 규칙

| Provider | `accessToken` | `idToken` | `deviceId` |
| --- | --- | --- | --- |
| `KAKAO` | 필수 | 금지 | 필수 |
| `NAVER` | 필수 | 금지 | 필수 |
| `GOOGLE` | 금지 | 필수 | 필수 |

- Token은 공백일 수 없고 최대 4096자로 제한한다.
- `deviceId`는 기존 최대 255자 제한을 유지한다.
- 두 Token을 모두 보내거나 Provider에 맞지 않는 Token을 보내면 `AUTH_400_001`을 반환한다.
- 과거 `authorizationCode`, `redirectUri`, `state`만 보낸 요청은 Token 필수 조건을 충족하지 못하므로 `AUTH_400_001`을 반환한다.

### 성공 응답

기존 `ApiResponse<OAuthLoginResult>`와 HTTP 200을 유지한다.

- 서비스 Access Token
- 서비스 Refresh Token
- 각 Token 만료 시간
- 사용자 ID, 역할, 계정 상태와 온보딩 완료 여부

응답의 Token은 Provider Token이 아니라 서비스가 발급한 JWT다.

## 5. 요청 정규화

HTTP DTO는 `accessToken`, `idToken`, `deviceId`만 보관한다. Path의 Provider와 요청 Body를 함께 검증해야 하므로 Bean Validation만으로 Provider별 조합을 판단하지 않는다.

`OAuthLoginService` 진입 시 요청을 내부 `OAuthProviderCredential`로 정규화한다.

- Kakao·Naver: `ACCESS_TOKEN`
- Google: `ID_TOKEN`

`OAuthProviderClient`는 HTTP DTO 전체가 아니라 정규화된 Credential과 Provider를 전달받는다. Redirect URI와 Authorization Code 같은 제거된 HTTP 세부사항이 Provider 검증 계층으로 전파되지 않게 한다.

## 6. Provider별 검증

### 6.1 Kakao

1. `GET https://kapi.kakao.com/v1/user/access_token_info`를 Bearer Token으로 호출한다.
2. 응답의 `expires_in`이 양수인지 확인한다.
3. 응답의 `app_id`가 서버 설정 `KAKAO_APP_ID`와 같은지 확인한다.
4. `GET https://kapi.kakao.com/v2/user/me`를 같은 Token으로 호출한다.
5. Token 정보의 사용자 ID와 사용자 정보의 ID가 같은지 확인한다.
6. Provider Subject는 Kakao 사용자 ID 문자열을 사용한다.
7. 이메일은 `is_email_valid`와 `is_email_verified`가 모두 참일 때만 사용한다.

Kakao 공식 Token 정보 API는 Token 유효성과 Token이 발급된 App ID를 제공한다.

### 6.2 Naver

1. `GET https://openapi.naver.com/v1/nid/me`를 Bearer Token으로 호출한다.
2. `resultcode`가 `00`인지 확인한다.
3. 응답에 공백이 아닌 사용자 ID가 있는지 확인한다.
4. Provider Subject는 Naver 응답의 사용자 ID를 사용한다.
5. 검증 여부를 별도로 제공하지 않는 이메일은 인증 계정 식별에 사용하지 않는다.

기존 Naver 사용자 정보 응답 처리 규칙은 유지하고 Authorization Code 교환과 `state` 검증만 제거한다.

### 6.3 Google

Google ID Token은 운영 환경에서 `tokeninfo` Endpoint를 호출해 검증하지 않는다. Spring Security JOSE의 Nimbus Decoder를 사용해 Google 공개키로 로컬 검증한다.

필수 검증:

- JWT 서명
- `iss`가 `accounts.google.com` 또는 `https://accounts.google.com`
- `aud`에 서버 설정 `GOOGLE_CLIENT_ID`가 포함됨
- `exp`가 지나지 않음
- 공백이 아닌 `sub` 존재

Flutter가 Google ID Token을 요청할 때 사용하는 `serverClientId`와 백엔드 `GOOGLE_CLIENT_ID`는 동일한 Web Client ID여야 한다.

Provider Subject는 `sub`를 사용한다. `email_verified=true`일 때만 이메일을 사용한다.

Google 공개키는 공식 JWK Set에서 가져오며 Decoder Cache를 사용한다. 공개키를 Repository나 환경 변수에 직접 저장하지 않는다.

## 7. 구성 요소

### 변경

- `OAuthLoginRequest`
  - `accessToken`, `idToken`, `deviceId` 계약으로 변경
- `OAuthLoginService`
  - Provider별 Credential 조합 검증과 내부 Credential 정규화
  - 기존 Provisioning·JWT·Redis Session 흐름 유지
- `OAuthProviderClient`
  - Authorization Code 요청 DTO 의존 제거
- `RestClientOAuthProviderClient`
  - Kakao·Naver Provider Token 검증 구조로 변경
  - 역할과 구현에 맞는 이름으로 정리할 수 있으나 관련 없는 계층 변경은 하지 않음
- `OAuthProviderProperties`
  - Kakao App ID와 Google Audience 중심으로 정리
- `OAuthController`
  - Javadoc, Swagger 요청·오류 설명 변경
- `AuthErrorCode`
  - 내부 명칭을 Provider Credential 기준으로 정리
  - 외부 오류 코드 `AUTH_401_001`과 사용자 메시지는 유지

### 추가

- Provider와 Token 종류를 결합한 내부 불변 Credential
- Google ID Token Decoder와 검증 책임을 캡슐화한 Production Type

Google 검증 Type은 공개키, Claim 검증과 신원 변환만 담당한다. 계정 생성과 서비스 Token 발급을 수행하지 않는다.

## 8. 환경 변수

### 사용

```text
KAKAO_APP_ID
GOOGLE_CLIENT_ID
OAUTH_CONNECT_TIMEOUT
OAUTH_READ_TIMEOUT
```

- `KAKAO_APP_ID`: Kakao Token 정보 응답의 숫자 App ID와 비교한다.
- `GOOGLE_CLIENT_ID`: Flutter `serverClientId`와 같은 Web Client ID이며 Google ID Token의 Audience다.

### OAuth 로그인에서 더 이상 사용하지 않음

```text
KAKAO_CLIENT_SECRET
KAKAO_REDIRECT_URI
GOOGLE_CLIENT_SECRET
GOOGLE_REDIRECT_URI
NAVER_CLIENT_ID
NAVER_CLIENT_SECRET
NAVER_REDIRECT_URI
```

배포 환경에 남은 미사용 변수는 동작에 영향을 주지 않지만 README와 예시 환경 파일에서는 제거 대상임을 명확히 한다. 실제 Secret 값은 Repository에 기록하지 않는다.

필수 검증 설정이 없으면 외부 Provider를 호출하기 전에 `AUTH_503_001`을 반환한다. 설정 누락 상태에서 App 소속 검증을 생략하지 않는다.

## 9. 오류 처리

| 상황 | HTTP | 오류 코드 |
| --- | --- | --- |
| 지원하지 않는 Provider | 400 | `AUTH_400_001` |
| Provider와 Token 필드 불일치 | 400 | `AUTH_400_001` |
| Token 공백·길이 초과 | 400 | 공통 Validation 오류 |
| Token 만료·서명 실패·Provider 4xx | 401 | `AUTH_401_001` |
| Kakao App ID 또는 Google Audience 불일치 | 401 | `AUTH_401_001` |
| Provider 5xx·통신 실패·검증 불가능한 응답 | 502 | `AUTH_502_001` |
| Kakao App ID·Google Client ID 설정 누락 | 503 | `AUTH_503_001` |
| Redis Refresh Session 저장 실패 | 503 | `AUTH_503_002` |

Provider 오류 응답 Body, Token, Authorization Header, 사용자 개인정보와 Stack Trace는 API 오류 응답이나 로그에 포함하지 않는다.

## 10. 데이터 흐름

1. Controller가 Provider와 요청 Body를 받는다.
2. Service가 Provider별 Token 필드 조합을 검증하고 Credential을 정규화한다.
3. `OAuthProviderClient`가 Provider Token을 검증해 `VerifiedOAuthIdentity`를 반환한다.
4. `OAuthAccountProvisioningService`가 기존 사용자 또는 신규 OAuth 계정을 확정한다.
5. 계정 상태를 검사하고 로그인 시각을 갱신한다.
6. `JwtTokenIssuer`가 서비스 Access·Refresh Token을 발급한다.
7. Refresh Token hash와 기기 정보를 Redis Session에 등록한다.
8. Provider Token을 보관하지 않고 서비스 Token 응답을 반환한다.

Provider 검증이 실패하면 DB Provisioning과 서비스 Token 발급을 수행하지 않는다. Redis 등록이 실패하면 성공 응답을 반환하지 않는다.

## 11. 보안

- Provider Token을 DB, Redis와 파일에 저장하지 않는다.
- Provider Token과 Authorization Header를 로그에 기록하지 않는다.
- Google ID Token의 Payload를 서명 검증 전에 신뢰하지 않는다.
- 이메일은 계정의 불변 식별자가 아니라 선택적 Profile 정보로만 사용한다.
- Provider Subject를 OAuth 계정의 불변 식별자로 사용한다.
- Kakao는 App ID, Google은 Audience를 확인해 다른 App을 위해 발급된 Credential을 거부한다.
- HTTP Client의 연결·읽기 제한 시간을 유지한다.

## 12. 테스트

### 요청·Controller

- Kakao·Naver Access Token 요청 성공
- Google ID Token 요청 성공
- 지원하지 않는 Provider 400
- Token 누락, 두 Token 동시 전달과 Provider/Token 불일치 400
- Token 길이와 `deviceId` Validation
- 공통 응답과 Swagger 계약

### Service

- Provider별 내부 Credential 정규화
- 검증된 신원으로 기존 Provisioning과 JWT 발급 재사용
- Provider 검증 실패 시 Provisioning·JWT·Redis 미호출
- Redis Session에 Provider Token이 아닌 서비스 Refresh Token hash만 등록

### Kakao

- Token 정보와 사용자 정보가 모두 유효한 경우
- 만료 Token, App ID 불일치, 사용자 ID 불일치
- Provider 4xx, 5xx와 통신 오류
- 이메일 검증 여부 처리

### Naver

- `resultcode=00`과 사용자 ID가 있는 경우
- 오류 Result Code, 사용자 ID 누락
- Provider 4xx, 5xx와 통신 오류

### Google

- 유효한 서명·Issuer·Audience·만료·Subject
- 서명 실패
- 허용하지 않은 Issuer와 Audience
- 만료 Token과 Subject 누락
- 검증된 이메일과 미검증 이메일

테스트에서 실제 Provider 서버를 호출하지 않는다.

## 13. 문서화

- README의 Authorization Code 설명과 요청 예시를 Provider Token 방식으로 변경한다.
- Swagger 설명에 Provider별 필드와 검증 오류를 기록한다.
- `.env.example`과 `application.yml`의 OAuth 설정을 실제 사용 값과 일치시킨다.
- `docs/database/social-auth-schema-v1.3.md`의 Authorization Code 설명을 현재 계약으로 바로잡되 DB Schema 자체는 변경하지 않는다.
- 과거 설계·계획 문서는 당시 이력으로 보존하고 재작성하지 않는다.

## 14. 배포와 호환성

이 변경은 요청 Body의 Breaking Change다. 백엔드 배포 전에 다음을 확인한다.

1. Flutter가 Provider별 합의 Token을 취득할 수 있음
2. Flutter Google `serverClientId`와 서버 `GOOGLE_CLIENT_ID`가 같음
3. 운영 `KAKAO_APP_ID`가 등록됨
4. 프론트와 백엔드가 같은 배포 단위에서 계약을 전환함

Authorization Code와 Provider Token을 동시에 허용하는 임시 호환 계층은 보안 검증 경로와 제거 일정을 복잡하게 하므로 만들지 않는다.

## 15. 완료 조건

- Flutter의 Provider별 Token 종류와 백엔드 요청 계약이 일치한다.
- Kakao App ID와 Google Audience를 포함한 Provider 신원 검증이 구현된다.
- 기존 계정 Provisioning, JWT 발급과 Redis Refresh Token 흐름이 유지된다.
- Provider Token이 저장되거나 로그에 노출되지 않는다.
- DB 및 Flyway 변경이 없다.
- Swagger, README와 환경 변수 문서가 구현과 일치한다.
- `clean test`, `spotlessCheck`, `javadoc` 결과를 사실대로 보고한다.

## 16. 공식 참고 자료

- Kakao Login REST API: <https://developers.kakao.com/docs/en/kakaologin/rest-api>
- Google Android Backend Authentication: <https://developers.google.com/identity/sign-in/android/backend-auth>
