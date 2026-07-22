# S15P11B209-310 회원가입 동의 이력 저장 설계

## 목적

`POST /api/v1/consents`에서 인증 사용자 또는 연결 아동의 최초 약관 동의를 검증하고 `consent_records`에 변경 불가능한 이력으로 저장한다.

## 기존 DB 사용

- 버전 약관: `consent_terms`
- 동의·철회 이력: `consent_records`
- 확장 증빙: `consent_record_evidences`

필요한 FK, 약관 버전 Unique, 대상·기록 시각 Index와 append-only 구조가 이미 마련돼 있어 Flyway Migration을 추가하지 않는다. 이번 API에는 확장 증빙 요청 필드가 없으므로 IP와 User-Agent만 기존 전용 컬럼에 기록하고 임의 증빙 항목을 만들지 않는다.

## 검증 규칙

- Access Token의 Subject를 `actor_user_id`로 사용하며 요청 Body에서 사용자 ID를 받지 않는다.
- `childId`가 있으면 `guardian_child_relations`로 연결 보호자인지 먼저 확인한다.
- 요청의 약관 ID는 중복될 수 없고 모두 존재하며 활성·시행 상태여야 한다.
- `CHILD` 약관에는 `childId`가 필요하고, 사용자 약관만 등록할 때는 `childId`를 받지 않는다.
- 현재 적용되는 필수 약관은 모두 요청에 포함되고 `AGREE`여야 한다.
- 기존 이력을 update하지 않고 요청 시각이 같은 새 행들을 하나의 Transaction에서 append한다.
- `subject_reference_hash`는 `USER:{userId}` 또는 `CHILD:{childId}`의 SHA-256 값으로 기록한다.
