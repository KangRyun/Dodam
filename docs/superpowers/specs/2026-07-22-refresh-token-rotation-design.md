# S15P11B209-308 Refresh Token Redis rotation 설계

## 목적

OAuth 로그인에서 발급한 Refresh Token을 Redis 세션과 연결하고 `POST /api/v1/auth/reissue`에서 Access·Refresh Token을 함께 교체한다. MySQL에는 Refresh Token 테이블이나 Entity를 추가하지 않는다.

## 보안 계약

- Redis에는 Refresh Token 원문 대신 SHA-256 hash, 사용자 ID, 기기 ID를 저장한다.
- Refresh JWT에는 임의 `family_id`를 포함하고 Redis key는 이 family를 기준으로 생성한다.
- Lua Script 한 번으로 현재 hash 비교, 새 hash 저장, TTL 갱신을 수행한다.
- 같은 family의 현재 hash와 다른 유효한 Refresh JWT가 제시되면 과거 Token 재사용으로 판정하고 family key를 삭제한다.
- 기기 ID가 다르면 rotation하지 않는다.
- Redis 장애에서는 재발급을 허용하지 않는 fail-closed 정책을 사용한다.

## API

`POST /api/v1/auth/reissue`

요청은 `refreshToken`, `deviceId`를 사용한다. 성공 응답은 로그인과 같은 Token·사용자 응답 계약을 사용하며, 기존 Refresh Token은 성공 즉시 다시 사용할 수 없다.
