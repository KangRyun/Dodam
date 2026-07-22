# 아동 정보 조회 API 설계

## 목적

연결된 보호자가 `GET /api/v1/children/{childId}`로 삭제되지 않은 아동의 상세 프로필을 조회한다. 응답은 공통 `ApiResponse<T>` 계약을 사용하고 조회 과정에서 상태를 변경하지 않는다.

## 확정 계약

- Path: `/api/v1/children/{childId}`
- Method: `GET`
- 성공: HTTP 200
- 실패: 잘못된 식별자는 400, 인증 정보가 없거나 잘못되면 401, 아동이 없거나 삭제됐거나 연결되지 않았으면 동일한 404
- 응답 필드: `childId`, `nickname`, `birthDate`, `age`, `profileImageUrl`, `preferredCharacter`, `questionDifficulty`, `responseModes`, `tutorialStatus`, `profileStatus`, `relationshipType`, `createdAt`, `updatedAt`
- `age`는 서버 조회일을 기준으로 만 나이를 계산한다.
- `responseModes`는 `child_response_modes.display_order`, `id` 순서로 반환한다.

## 인증과 소유권

정식 JWT 인증은 아직 구현되지 않았다. 이번 이슈에서는 기존 `TemporaryGuardianResolver`가 사용하는 `Authorization`과 `X-Guardian-User-Id` 임시 계약을 재사용한다. 신규 인증 방식이나 가짜 Principal은 만들지 않는다. 정식 인증 도입 시 Controller의 보호자 식별 경계만 교체할 수 있도록 Service에는 해석된 `guardianUserId`를 전달한다.

아동 존재 여부와 소유권 실패를 구분하지 않는 조회 Query를 사용한다. 따라서 다른 보호자가 임의의 `childId` 존재 여부를 추측할 수 없다.

## 데이터 접근

기존 `Child` Entity는 그림 활동에 필요한 최소 쓰기 모델이므로 상세 조회 필드를 억지로 추가하지 않는다. `ChildDetailProjection`을 통해 `children`과 `guardian_child_relations`를 읽고, 응답 방식은 별도 정렬 Query로 조회한다.

조회 조건은 다음과 같다.

- `children.id = childId`
- `guardian_child_relations.guardian_user_id = guardianUserId`
- `children.deleted_at IS NULL`
- `children.profile_status = 'ACTIVE'`

Schema 변경과 Flyway Migration 추가는 필요하지 않다.

## 계층 책임

- `ChildController`: Header/Path Validation, 보호자 식별, 공통 응답 조립, OpenAPI 계약
- `ChildQueryService`: 조회 Use Case, 만 나이 및 UTC 시각 변환, 응답 DTO 조립
- `ChildRepository`: 소유권을 포함한 상세 Projection과 응답 방식 조회
- `ChildDetailResponse`: 외부 공개 필드만 보유
- `ChildErrorCode`: 아동 상세 조회의 404 계약

## 테스트

- Service: 정상 매핑, 만 나이 경계, 404, 응답 방식 순서 보존
- Controller: 200, 식별자 400, 인증 401, Service 404
- Repository: 연결 보호자만 조회, 삭제/비활성 제외, 응답 방식 정렬
- OpenAPI: Path Parameter와 200/400/401/404/500 응답 문서화

## 제외 범위

- JWT 발급·검증 및 Spring Security 도입
- 아동 등록·목록·수정·삭제·Tutorial API
- 프론트 Header 처리 변경
- `responseModes` Enum 또는 DB 제약 변경
- DB Schema 및 Migration 변경
