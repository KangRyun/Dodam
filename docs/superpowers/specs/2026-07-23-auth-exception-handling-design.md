# S15P11B209-309 인증·인가 예외 처리 설계

## 목적

기존 Access Token Filter의 선택적 검증을 운영 인증 경계로 완성한다. 공개 인증 Endpoint를 제외한 `/api/v1/**` 요청에 Access Token을 필수로 요구하고 인증·인가 실패를 공통 오류 응답으로 반환한다.

## 접근 정책

- 공개: `POST /api/v1/auth/oauth/{provider}`, `POST /api/v1/auth/reissue`, CORS `OPTIONS`
- 보호: 그 외 `/api/v1/**`
- 운영 기본값에서는 `Authorization: Bearer {accessToken}` 누락 시 `AUTH_401_006`을 반환한다.
- 잘못된 서명·발급자·만료·용도는 기존 `AUTH_401_002`를 사용한다.
- 인증 후 권한 부족은 `AUTH_403_002`로 변환한다. 역할별 허용 규칙은 확정된 도메인 요구사항 없이 이번 이슈에서 만들지 않는다.
- 기존 임시 사용자 Header 우회는 자동화 테스트 호환을 위해 `test`, `integration-test` Profile에서만 유지한다. 인증 Filter 통합 테스트는 이 값을 명시적으로 끄고 운영 차단을 검증한다.

## OpenAPI

`bearerAuth`를 v1 API의 기본 Security Requirement로 선언하고 OAuth 로그인·Token 재발급은 명시적으로 공개한다.
