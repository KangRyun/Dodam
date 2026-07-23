# S15P11B209-306 OAuth 로그인 및 JWT 설계

## 확정 계약

- 자체 이메일·비밀번호 가입과 로그인은 제공하지 않는다.
- 앱은 `POST /api/v1/auth/oauth/{provider}`에 Provider에서 받은 일회성 `authorizationCode`, 동일한 `redirectUri`, `deviceId`를 전달한다.
- `{provider}`는 `kakao`, `google`, `naver`이며 대소문자를 구분하지 않는다.
- Naver는 code 발급에 사용한 `state`도 전달한다.
- 앱이 Provider Access Token, 이메일, 전화번호 또는 Provider 사용자 ID를 직접 전달하는 계약은 허용하지 않는다.

## 신원 식별

| Provider | 영속 식별자 | 이메일 저장 조건 |
| --- | --- | --- |
| Kakao | 사용자 정보의 `id` | `is_email_valid=true` 및 `is_email_verified=true` |
| Google | UserInfo의 `sub` | `email_verified=true` |
| Naver | `response.id` | 검증 표시가 없어 이번 계약에서는 저장하지 않음 |

이메일과 전화번호는 변경되거나 제공되지 않을 수 있으므로 로그인 식별자로 사용하지 않는다. Provider Access Token은 사용자 정보 조회 직후 폐기하고 저장·응답·로그 출력하지 않는다.

## 처리 순서와 경계

1. JWT Secret과 만료 정책을 먼저 검증한다.
2. 요청 Redirect URI를 서버 환경 변수와 정확히 비교한다.
3. authorization code를 Provider Token으로 교환한다.
4. Provider UserInfo에서 불변 Subject를 확인한다.
5. 304번 Provisioning Service로 서비스 사용자를 조회하거나 생성한다.
6. `last_login_at`을 갱신하고 목적이 분리된 Access·Refresh JWT를 발급한다.

Provider 통신은 DB Transaction 밖에서 수행한다. Access Token은 `token_type=access`, Refresh Token은 `token_type=refresh` Claim을 가지며 서로 대신 사용할 수 없다. Refresh Token 저장·회전·재사용 탐지는 S15P11B209-308에서 Redis로 구현하고, Access Token 요청 인증은 S15P11B209-307에서 연결한다.

## 환경 변수

- `JWT_SECRET`: UTF-8 기준 32 Byte 이상, 기본값 없음
- `JWT_ISSUER`, `JWT_ACCESS_TOKEN_TTL`, `JWT_REFRESH_TOKEN_TTL`
- `KAKAO_CLIENT_ID`, `KAKAO_CLIENT_SECRET`, `KAKAO_REDIRECT_URI`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`
- `NAVER_CLIENT_ID`, `NAVER_CLIENT_SECRET`, `NAVER_REDIRECT_URI`
- `OAUTH_CONNECT_TIMEOUT`, `OAUTH_READ_TIMEOUT`

Secret과 실제 Redirect URI는 Git에 커밋하지 않는다. 누락된 설정에는 임시값을 사용하지 않고 HTTP 503으로 실패한다.
