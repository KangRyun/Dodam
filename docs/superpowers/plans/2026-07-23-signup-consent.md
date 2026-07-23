# S15P11B209-310 회원가입 동의 이력 저장 구현 계획

- [x] 최신 ERD와 API 명세의 동의 계약을 확인한다.
- [x] 기존 동의 테이블이 충분함을 확인하고 Migration 추가를 제외한다.
- [x] 약관·동의 이력 Entity와 Repository를 구현한다.
- [x] 보호자 관계, 활성 약관, 적용 범위와 필수 동의를 검증한다.
- [x] 인증 사용자·대상 hash·IP·User-Agent를 append-only 이력으로 저장한다.
- [x] `POST /api/v1/consents` 공통 응답과 OpenAPI 문서를 구현한다.
- [x] 전체 Test, Spotless, Javadoc을 검증한다.
