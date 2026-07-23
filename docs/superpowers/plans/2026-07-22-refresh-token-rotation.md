# S15P11B209-308 Refresh Token Redis rotation 구현 계획

- [x] Refresh JWT에 `family_id` Claim을 추가하고 전용 Decoder를 구현한다.
- [x] Refresh Token SHA-256 hash와 Redis 저장소 추상화를 구현한다.
- [x] Lua Script로 최초 등록과 rotation·재사용 폐기를 원자화한다.
- [x] OAuth 로그인 성공 시 사용자·기기 family 세션을 등록한다.
- [x] `POST /api/v1/auth/reissue`와 공통 오류 응답을 구현한다.
- [x] JWT 목적 분리, 성공 rotation, 재사용, 기기 불일치와 HTTP 계약을 테스트한다.
- [x] 전체 Test, Spotless, Javadoc을 검증한다.
