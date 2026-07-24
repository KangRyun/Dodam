# 로그인 후 아동 목록 상태 동기화 설계

## 배경

운영 앱은 `AuthBootstrapScreen`에서 저장된 인증 세션을 복원하지만, 현재
`DodamApp.initState()`는 세션 복원보다 먼저 `GuardianChildController.loadChildren()`을
호출한다. 따라서 `GET /api/v1/children`이 Access Token 없이 전송될 수 있고, 이때
생긴 `ChildListStatus.error`가 OAuth 로그인이나 세션 복원 이후에도 남는다.

Backend `GET /api/v1/children` 응답과 Flutter `ChildSummaryDto`는 현재 정합하므로
API 또는 DB 계약은 변경하지 않는다.

## 결정

아동 목록은 보호자 인증이 확정된 시점에 앱 계층에서 동기화한다.

- 기존 보호자 OAuth 로그인 성공 후 목록을 조회한다.
- 신규 보호자 onboarding 완료 후 목록을 조회한다.
- 유효한 저장 세션 복원 또는 Access Token 재발급 성공 후 목록을 조회한다.
- 인증 bootstrap 경로에서는 앱 초기화 중 목록을 선조회하지 않는다.
- 인증을 사용하지 않는 기존 Mock 및 화면 단위 테스트의 기본 보호자 홈 경로에서는
  기존처럼 초기 목록을 조회한다.
- 로그아웃 시 선택 아동뿐 아니라 목록, 조회 상태, 등록 상태도 모두 초기화한다.

## 상태 및 화면

- 조회 성공 + 1명 이상: 기존 아동 카드 목록을 표시한다.
- 조회 성공 + 0명: `ChildListStatus.empty`로 처리하여 기존 아동 등록 안내를 표시한다.
- 조회 실패: 인증 성공 상태는 유지하고 기존 재시도 화면을 표시한다.
- 로그아웃: `ChildListStatus.idle`, 빈 목록, 선택 없음, 등록 상태 초기값으로 되돌린다.

아동 목록 실패를 OAuth 실패로 변환하지 않는다. `loadChildren()`은 자체적으로 오류
상태를 기록하고 완료되므로 인증 화면에는 Provider 인증 오류가 표시되지 않는다.

## 변경 범위

- `frontend/mobile/lib/app/app.dart`
  - 인증 bootstrap에서 인증 전 아동 조회를 막는다.
  - 로그인, onboarding, 세션 복원 성공 뒤 보호자 목록을 동기화한다.
  - 로그아웃 시 아동 상태 전체를 초기화한다.
- `frontend/mobile/lib/app/state/guardian_child_controller.dart`
  - 계정 경계를 위한 전체 상태 초기화 연산을 제공한다.
- Flutter 테스트
  - 인증 전 조회 방지와 세션 복원 후 조회를 검증한다.
  - 빈 목록이 등록 안내로 연결되는지 검증한다.
  - 로그아웃 시 이전 계정의 목록과 선택이 제거되는지 검증한다.

## 제외 범위

- Backend Controller, Service, DTO, Entity 변경
- Flyway Migration 또는 ERD 변경
- 아동 등록·수정·삭제 API 계약 변경
- OAuth Provider Token 계약 변경
- 보호자 홈 UI 재설계
