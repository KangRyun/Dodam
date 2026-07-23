# S15P11B209-309 인증·인가 예외 처리 구현 계획

- [x] 공개 인증 Endpoint와 보호 API 경계를 확정한다.
- [x] 보호 API의 Access Token 누락을 공통 401로 차단한다.
- [x] 인증 예외와 권한 부족 예외를 공통 401·403 응답으로 변환한다.
- [x] 테스트 Profile의 legacy Header 우회는 운영과 분리해 유지한다.
- [x] OpenAPI 기본 Bearer 인증과 공개 인증 Endpoint 예외를 문서화한다.
- [x] 전체 Test, Spotless, Javadoc을 검증한다.
