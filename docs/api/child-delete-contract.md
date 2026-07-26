# 아동 프로필 삭제 API 공개 계약

> Jira: `S15P11B209-569` (아동 삭제 Confirmation Body 계약 통일)
> 범위: 아동 프로필 삭제 공개 API (`DELETE /children/{childId}`, CHILD-05)
> 기준 명세: `API_명세서_최종.md` §8.5 삭제 규칙·오류, `erd-cloud-schema-v1.2`
> 최종 수정: 2026-07-26

보호자가 연결된 아동 프로필을 삭제하는 공개 API의 요청·응답·오류 계약을 정의한다. 프론트엔드와 백엔드가 이 문서를 단일 기준으로 사용한다.

## 0. 이 계약이 확정한 것

명세 §8.5는 "`cascade` Query는 받지 않는다", "Body의 `confirmation:\"DELETE\"`로 재확인한다"만 규정하고 **요청이 계약을 어겼을 때의 응답을 정의하지 않았다.** 그 공백 때문에 구현이 세 갈래로 흩어져 있었으므로 아래로 통일한다.

1. **확인 값 오류는 요청 형태와 무관하게 하나의 코드로 응답한다** — 본문 누락, `confirmation` 누락·공백, `DELETE` 이외의 값 모두 `400 CHILD_400_002`. 이전에는 본문 누락이 `COMMON_400_003`, 공백이 `COMMON_400_001`, 오값만 `CHILD_400_002`로 갈렸다. 클라이언트는 "오작동 방지 장치를 통과하지 못했다"는 사실 하나만 알면 되므로 나누지 않는다.
2. **`cascade` Query는 무시하지 않고 거부한다** — `400 COMMON_400_001`. 무시하면 클라이언트가 삭제 범위를 지정할 수 있다고 오해한 채로 동작하게 되며, 그 오해는 데이터 삭제 범위에 관한 것이라 조용히 남겨둘 수 없다.
3. **`CHILD_400_002`는 명세 §8.5 오류 목록에 없다** — 명세는 `CHILD_AGE_OUT_OF_RANGE`, `CHILD_NOT_FOUND`, `CHILD_ACCESS_DENIED`, `CHILD_ALREADY_REGISTERED`, `CHILD_HAS_OTHER_GUARDIAN`만 열거한다. 확인 값 오류 코드는 as-built로 이 문서가 정의하며, 명세 §8.5 오류 목록 보강은 문서 담당자 몫으로 남긴다.
4. **`cascade` 거부에 전용 오류 코드를 만들지 않는다** — 공통 `COMMON_400_001`(요청 값이 올바르지 않습니다)을 사용한다. 새 도메인 코드를 추가하면 3번과 같은 "명세에 없는 코드"를 또 만들게 된다.

## 1. 엔드포인트

```http
DELETE /api/v1/children/{childId}
```

- 역할: 연결 보호자
- 인증: `Authorization: Bearer {accessToken}` (정식 JWT 전환 전까지 임시 `X-Guardian-User-Id` 경계가 남아 있을 수 있으며 최종 보안 계약이 아니다)
- Content-Type: `application/json`
- `Idempotency-Key` 사용하지 않음. 재호출은 이미 삭제된 아동을 `404`로 처리한다
- **지원하지 않는 Query**: `cascade` (값이 오면 `400`)

## 2. 요청

```json
{
  "confirmation": "DELETE"
}
```

| 필드 | 타입 | 필수 | 규칙 |
| --- | --- | --- | --- |
| `confirmation` | string | O | 정확히 `DELETE`. 대소문자·공백 차이를 허용하지 않는다 |

- 본문 자체가 필수다. 다만 본문 누락을 별도 오류로 구분하지 않고 확인 값 오류로 응답한다(§0-1).
- 삭제 범위는 서버 정책으로 고정한다. 클라이언트가 범위를 지정하는 필드·Query는 없다.

## 3. 성공 응답

```http
HTTP/1.1 204 No Content
```

본문 없음. 처리 내용:

- `children.profile_status = 'DELETED'`, `children.deleted_at` 설정 (Soft Delete)
- 연관 파일 삭제를 `storage_deletion_jobs`에 `PENDING`으로 예약
- 그림·음성·대화·리포트 실제 삭제는 예약된 작업이 수행한다(동기 삭제하지 않음)

## 4. 오류

| HTTP | 코드 | 조건 |
| --- | --- | --- |
| 400 | `CHILD_400_002` | 본문 누락, `confirmation` 누락·공백, `DELETE` 이외의 값 |
| 400 | `COMMON_400_001` | 지원하지 않는 `cascade` Query가 전달됨 |
| 400 | `COMMON_400_001` | `childId`가 양수가 아님 |
| 404 | `CHILD_404_001` | 아동이 없거나 이미 삭제됐거나 요청 보호자에게 연결되지 않음 |
| 409 | `CHILD_409_001` | 다른 보호자가 연결되어 단독 삭제 불가 |

- **존재 은닉**: 남의 아동과 없는 아동을 모두 `404`로 응답한다. 접근 권한 오류(`403`)로 구분하면 아동의 존재 여부가 드러난다.
- **검증 순서**: `cascade` 거부 → 확인 값 → 접근 가능 여부(비관 잠금) → 다른 보호자 연결 여부. 확인 값이 틀리면 DB를 조회하지 않는다.

## 5. 클라이언트 영향

Flutter `remote_child_repository.dart`가 현재 **본문 없이 `?cascade=true`** 로 호출하고 있어, 이 계약 이전에도 이후에도 아동 삭제가 성공하지 않는다. 다음과 같이 맞춰야 한다.

```dart
// 변경 전
await _apiClient.delete<void>('children/$childId', queryParameters: {'cascade': cascade});

// 변경 후
await _apiClient.delete<void>('children/$childId', data: {'confirmation': 'DELETE'});
```

`cascade` 파라미터는 인터페이스에서도 제거해야 한다. 삭제 범위는 서버 정책이므로 클라이언트가 전달할 값이 없다. 이 수정은 FE 담당 영역이며 BE 변경분에는 포함하지 않았다.

## 6. DB 매핑

| 응답·동작 | 테이블·컬럼 |
| --- | --- |
| Soft Delete | `children.profile_status`, `children.deleted_at` |
| 접근 가능 판정 | `guardian_child_relations(guardian_user_id, child_id)` |
| 단독 삭제 판정 | `guardian_child_relations` 의 `child_id` 건수 |
| 파일 삭제 예약 | `storage_deletion_jobs(resource_type, resource_id, storage_key, deletion_status)` |

스키마 변경 없음. 마이그레이션 없음.

## 7. 검증

- `ChildDeletionServiceTest` — 본문 누락·공백·`null`·오값이 모두 같은 오류이며 확인 실패 시 DB를 조회하지 않음
- `ChildControllerTest` — 본문 누락 `CHILD_400_002`, `cascade` 전달 시 `COMMON_400_001` 및 서비스 미호출
- `ChildListIntegrationTest` — 실 MySQL로 Soft Delete·삭제 예약, 본문 누락 거부 후 `ACTIVE` 유지, `cascade` 거부 후 `ACTIVE` 유지, 다른 보호자 연결 시 `409`
