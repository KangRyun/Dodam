# S15P11B209-306 OAuth 로그인 및 JWT 구현 계획

## 목표

Kakao·Google·Naver authorization code를 서버에서 검증하고, 304번 계정 Provisioning을 재사용해 서비스 JWT를 발급한다.

## 작업

- [x] 현재 API 명세, V6 인증 스키마, 환경 변수 이름을 확인한다.
- [x] 자체 로그인 계약을 제외하고 세 Provider의 불변 Subject 기준을 확정한다.
- [x] Provider별 code 교환·UserInfo 응답 테스트를 먼저 작성한다.
- [x] 검증된 이메일만 선택적으로 전달하고 Naver 이메일은 신원에 사용하지 않는다.
- [x] 32 Byte 이상 Secret, issuer, 만료와 `token_type` Claim을 검증하는 JWT 테스트를 작성한다.
- [x] Provider 통신 밖에 DB Transaction 경계를 두고 로그인 시각을 갱신한다.
- [x] `/api/v1/auth/oauth/{provider}` 요청 검증과 공통 응답 Controller 테스트를 작성한다.
- [x] 전체 Test, Spotless, Javadoc과 민감 정보 검색을 실행한다.
- [ ] 검증 통과 후 Jira 코드가 포함된 Commit으로 `develop`에 병합한다.

## 후속 이슈 경계

- 307: Access JWT 검증과 인증 Principal 연결
- 308: Refresh JWT hash·기기 세션을 Redis에 저장하고 rotation·재사용 탐지 구현
- 309: 인증·인가 EntryPoint와 세부 예외 응답 보강
