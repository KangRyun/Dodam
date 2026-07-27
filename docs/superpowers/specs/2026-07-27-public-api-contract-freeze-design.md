# Flutter-Backend 공개 API 계약 목록 동결 설계

## 1. 목적

S15P11B209-525는 Flutter와 Spring Boot가 참조할 외부 공개 API 목록을
2026-07-27의 `develop` 구현 기준으로 동결한다. 이번 작업은 새로운 기능을
구현하는 작업이 아니라, 현재 사용할 수 있는 계약과 아직 정합화가 필요한
계약을 한 문서에서 구분할 수 있게 만드는 작업이다.

## 2. 확인된 충돌

현재 `docs/api/API_명세서_최종.md`, Spring Boot Controller/OpenAPI, Flutter
Remote Repository 사이에는 다음과 같은 차이가 있다.

- 전체 명세의 성공·오류 응답에는 `timestamp`, `requestId`, `errors`가 있지만
  현재 공통 응답은 `success`, `code`, `message`, `data`를 사용한다.
- 전체 명세는 그림 활동 리소스를 `drawing-sessions`로 통일했지만 Flutter의
  활동 이력 Repository는 `activities` URI를 호출한다.
- Flutter의 일반 그림 업로드는 `/upload`를 호출하지만 Backend는
  `/snapshots`를 제공한다.
- 리포트 화면의 Remote Repository가 호출하는 공개 조회 API는 Backend
  Controller가 아직 제공하지 않는다.

공통 응답 변경은 S15P11B209-526, 각 기능 구현과 Flutter 정합화는 해당
도메인 Jira에서 처리한다. S15P11B209-525에서는 서로 다른 계약을 동시에
공식 계약으로 선언하지 않는다.

## 3. 계약 기준과 우선순위

동결 문서는 다음 순서로 사실을 판정한다.

1. 최신 `develop`의 실제 Spring Boot Controller와 DTO
2. `/v3/api-docs/api-v1`에 노출되는 Springdoc OpenAPI
3. 최신 `develop`의 Flutter Remote Repository와 DTO
4. `docs/api/API_명세서_최종.md`

Backend에 구현된 API는 Controller/OpenAPI를 정본으로 기록한다. 명세에는
있지만 Backend에 없는 API는 `미구현`으로, Flutter가 다른 URI나 응답 형식을
사용하면 `불일치`로 기록한다. 미구현·불일치 항목을 구현된 것처럼 표현하지
않는다.

## 4. 산출물

`docs/api/public-api-contract-v1.md`를 Flutter-Backend 공개 API 목록의
동결본으로 추가한다. 문서에는 다음 정보를 포함한다.

- 동결 기준일과 기준 Git commit
- 공통 Base URL, 인증, 요청 Header, Content-Type, 응답 Envelope
- 도메인별 Method와 URI
- Backend 구현 상태와 Flutter 사용 상태
- 불일치 사유와 후속 처리 범위
- 계약 변경 절차

API 목록은 인증, 사용자·동의·아동, 그림·분석, 대화, 알림, 커뮤니티,
리포트 순으로 나눈다. 내부 `/internal/v1/**` API는 Flutter 계약이 아니므로
목록에서 제외한다.

## 5. 변경 관리

동결 이후 공개 API를 변경할 때는 다음을 함께 변경한다.

1. 관련 Jira 이슈와 API 계약 문서
2. Backend Controller·DTO·OpenAPI
3. Flutter Remote Repository·DTO
4. 정상·오류·권한·경계 조건 테스트

기존 URI를 호환 목적으로 중복 구현하지 않는다. 계약을 교체할 때는 한 URI를
정본으로 확정한 뒤 소비자 코드를 함께 정합화한다.

## 6. 검증

- 문서의 Backend 구현 항목을 실제 Controller Mapping과 대조한다.
- Flutter 연동 항목을 실제 Remote Repository 호출 경로와 대조한다.
- 동일한 Method와 URI가 중복 선언되지 않았는지 확인한다.
- 모든 외부 URI가 `/api/v1` 기준이며 내부 API가 섞이지 않았는지 확인한다.
- `gradlew.bat clean test`, `gradlew.bat spotlessCheck`,
  `gradlew.bat javadoc`을 실행한다.
- Flutter 변경은 없지만 기준선 회귀 확인을 위해 `flutter test`를 실행한다.

## 7. 제외 범위

- 공통 성공·오류 Envelope의 구조 변경
- 미구현 Controller, Service, Repository, DTO 생성
- Flutter Remote Repository 경로 또는 응답 파싱 수정
- DB Schema와 Flyway Migration 변경
- 내부 AI API 계약 변경
- 기존 전체 API 명세서의 전면 재작성
