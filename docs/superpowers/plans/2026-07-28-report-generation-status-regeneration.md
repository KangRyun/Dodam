# S15P11B209-293 구현 계획

1. Report와 DrawingSession에 재생성 상태 전이 도메인 테스트를 추가한다.
2. 상태 조회·재생성 Service 테스트를 먼저 실패시키고 최소 구현한다.
3. 상태 조회·재생성 Controller 계약 테스트를 추가한다.
4. Repository 잠금·최신 버전 조회와 공개 DTO·오류 코드를 구현한다.
5. API 명세서에 REPORT-06/07 계약과 오류·멱등성 규칙을 반영한다.
6. `spotlessCheck`, 관련 테스트, 전체 테스트, Javadoc을 실행한다.
7. 이슈 코드가 포함된 커밋과 MR을 만들고 `develop`에 병합한다.
