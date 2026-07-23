# 보호자 소유 자원 접근 권한 검증 설계

## 목적

`S15P11B209-323`은 인증된 보호자가 자신에게 연결된 아동과 해당 아동의 그림 활동에만 접근하도록 공통 검증 구조를 제공한다. 다른 보호자의 자원과 존재하지 않는 자원은 동일한 Domain 오류로 처리해 식별자 존재 여부를 노출하지 않는다.

`S15P11B209-316`의 아동 접근 검증은 이 이슈 범위에 포함되는 하위 요구사항으로 본다. 같은 역할의 구현을 별도로 중복 생성하지 않는다.

## 현재 구조

- Java 21, Spring Boot 3.5.16, Gradle 기반이다.
- Access Token 검증 결과는 `AuthenticatedUser`로 `SecurityContext`에 저장된다.
- 현재 사용자 ID는 `CurrentAuthenticatedUserResolver`가 제공한다.
- `ChildQueryService`, 동의 및 대화 기능에는 보호자 관계를 직접 확인하는 Query가 각각 존재한다.
- `children`, `guardian_child_relations`, `drawing_sessions` Table과 필요한 Foreign Key가 이미 존재한다.

## 설계

### Repository

`GuardianResourceAccessRepository`는 다음 존재 여부만 조회한다.

- 보호자와 삭제되지 않은 활성 아동의 연결 관계
- 보호자와 삭제되지 않은 그림 활동의 간접 연결 관계

그림 활동 검증은 `drawing_sessions`, `children`, `guardian_child_relations`를 연결한다. Repository는 `BusinessException`을 발생시키지 않고 `boolean`만 반환한다.

### Service

`GuardianResourceAccessValidator`는 다음 공개 메서드를 제공한다.

- `requireChildAccess(Long guardianUserId, Long childId)`
- `requireDrawingSessionAccess(Long guardianUserId, Long drawingSessionId)`

검증에 실패하면 각각 기존 `ChildErrorCode.CHILD_NOT_FOUND`, `DrawingErrorCode.DRAWING_SESSION_NOT_FOUND`를 사용한다. 권한이 없다는 이유로 `403`을 반환하지 않아 자원 존재 여부를 숨긴다. 검증은 상태를 변경하지 않는다.

### 적용 범위

현재 구현된 보호자용 Use Case 중 아동 또는 그림 활동 식별자로 자원에 접근하는 흐름에 Validator를 적용한다. Controller는 Repository를 호출하지 않으며, 인증 사용자 ID 확인과 Domain 검증은 Service 계층에서 조합한다.

기존 Query가 이미 동일한 소유권 조건을 원자적으로 적용하는 경우에는 보안 조건을 약화시키지 않는다. 공통 Validator 적용 때문에 조회가 중복되거나 동시성 일관성이 저하되는 경우 기존 원자적 Query를 유지한다.

## 오류와 개인정보 보호

- 인증 실패는 기존 `AuthErrorCode`와 전역 예외 처리를 사용한다.
- 자원 없음과 소유권 없음은 같은 `404` Domain 오류를 사용한다.
- Token, 사용자·아동 개인정보, SQL 및 Constraint 이름을 로그나 응답에 추가하지 않는다.

## DB 변경

Schema 변경과 Flyway Migration은 필요하지 않다. 기존 관계 Table과 Index를 사용한다.

## 테스트

- Validator 단위 테스트: 허용, 아동 거부, 그림 활동 거부
- Repository MySQL 통합 테스트: 연결 보호자, 비연결 보호자, 삭제 자원
- 적용 대상 Service 회귀 테스트: 인증 사용자 ID 전달과 실패 시 저장·외부 호출 미수행
- 전체 `clean test`, `spotlessCheck`, `javadoc` 검증

## 제외 범위

- 전문가 공유 승인과 ADMIN 접근 정책
- 아동·그림 활동 생성, 수정, 삭제 API 자체 구현
- Method Security, AOP 또는 신규 보안 Library 도입
- 기존 인증·동의·대화 기능의 관련 없는 Refactoring
