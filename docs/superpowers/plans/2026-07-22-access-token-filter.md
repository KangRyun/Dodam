# S15P11B209-307 Access Token 인증 Filter 구현 계획

- [x] Access·Refresh Token 목적 분리와 만료 검증 테스트 작성
- [x] 검증된 Subject를 `AuthenticatedUser`로 변환
- [x] 요청 처리 동안만 `SecurityContext`에 Principal 설정
- [x] 잘못된 Bearer Token의 공통 401 응답과 민감 오류 비노출 검증
- [x] `/api/v1/*` Servlet Filter 등록 통합 테스트
- [x] 아동·대화 보호자 Resolver를 Access Token Principal 우선으로 전환
- [x] 임시 보호자 Header를 Test Profile로 제한
- [x] Swagger `bearerAuth` JWT Scheme 추가 및 임시 Header 숨김
- [x] 전체 Test, Spotless, Javadoc 검증
- [ ] Jira 코드 포함 Commit과 `develop` 병합

309번에서 Token 누락 강제, 인증·인가 EntryPoint, 만료와 일반 위조 오류의 세부 응답 정책을 완성한다.
