# 데이터 보관 정책 조회·수정 API 공개 계약 (as-built)

> Jira: `S15P11B209-564`, `S15P11B209-565`
> 범위: 로그인 사용자 본인에게 적용 중인 데이터 보관 정책 조회·전체 교체
> 기준 명세: `API_명세서_최종.md` §6 사용자, `erd-cloud-schema-v1.2`, `docs/인프라/파일-수명주기-정책.md`(622)
> 최종 수정: 2026-07-31

명세 §6이 정의하지 않은 **데이터 보관 정책 조회·수정 엔드포인트**를 as-built로 확정한다. 프론트엔드와 백엔드가 이 문서를 단일 기준으로 사용한다.

## 0. 이 계약이 확정한 것

`API_명세서_최종.md`에는 데이터 보관 정책을 조회·변경하는 엔드포인트가 없다. 보관 정책 관련 서술은 "데이터 정책을 따른다"·"동의 설정에 따른다" 수준의 참조뿐이고(§ 그림 초안 삭제, § 음성 원본), 사용자에게 노출할 계약은 정의하지 않았다. `S15P11B209-564`와 `S15P11B209-565`로 **`GET`·`PATCH /users/me/data-retention`을 신설**하고 아래 계약으로 확정한다.

1. **사용자별로 조회·변경 가능한 정책이다.** 값의 소유자는 서비스 전역 상수가 아니라 인증 사용자 본인의 `user_data_retention_settings`(V24) 행이다.
2. **설정 행이 없으면 404가 아니라 200과 기본값이다.** 컬럼 DEFAULT와 동일한 값(`retentionDays=180`, `noticeDaysBefore=30`)을 반환한다. 알림 설정 조회(554)와 같은 규약이다.
3. **보관 기간 수치는 확정값이 아니라 잠정값이다.** 응답에 `policyStatus="PROVISIONAL"`을 항상 포함해 확정 전임을 명시한다(§3 근거).
4. **삭제 집행을 보장하는 문구를 응답에 넣지 않는다.** "N일 후 삭제됩니다" 같은 약속은 현재 집행되지 않는다(§5 한계 ①). 응답은 현재 적용 중인 보관 기간·안내 시점·확정 여부만 나타낸다.
5. **`PATCH`는 두 값을 모두 받는 전체 교체다.** 두 필드는 필수이며 `retentionDays >= 1`, `noticeDaysBefore >= 0`, `noticeDaysBefore < retentionDays`를 만족해야 한다. 확정 근거가 없는 별도 최대 일수는 두지 않는다.
6. **정본(`API_명세서_최종.md`)에는 반영하지 않았다.** 팀 공유 정본 갱신은 문서 담당자 몫으로 남긴다. 이 문서가 현재 유일한 as-built 기준이다.

## 1. GET 데이터 보관 정책 조회

```http
GET /api/v1/users/me/data-retention
Authorization: Bearer {accessToken}
```

요청 본문·쿼리 파라미터는 없다. 대상 사용자는 Access Token Principal에서 해석하며(`requireUserId()`), 다른 사용자의 정책을 조회할 경로는 제공하지 않는다.

### 성공 응답 `200 OK`

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {
    "retentionDays": 180,
    "noticeDaysBefore": 30,
    "policyStatus": "PROVISIONAL"
  }
}
```

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `retentionDays` | int | 데이터를 보관하는 기간(일) |
| `noticeDaysBefore` | int | 보관 만료 며칠 전에 안내하는지(일) |
| `policyStatus` | string | 보관 정책 수치의 확정 상태. 현재 항상 `PROVISIONAL` |

설정 행이 없는 사용자에게는 위 기본값을 그대로 반환한다. 조회는 행을 생성하지 않는다.

### 오류

| HTTP | 코드 | 조건 |
| --- | --- | --- |
| 401 | `AUTH_401_006` | Access Token 누락 또는 검증 오류 |

행 부재를 기본값으로 처리하므로 `404`는 발생하지 않는다.

### 보관 항목을 세분화하지 않은 이유

`images`/`audio`/`reports`처럼 자산별로 보관 기간을 나누지 않고 **전체 보관 기간 단일 값**으로 둔다. 근거는 다음 실측이다.

- `docs/인프라/파일-수명주기-정책.md`는 세 프리픽스의 보존기간을 모두 같은 `[결정 대기]`로 두고 항목별 차이를 정의하지 않았다.
- 같은 문서의 2026-07-28 실태 표에 따르면 구현에 존재하는 프리픽스는 `images`(동작 중)·`audio`(데이터 0건) 2종이며 `reports`·`evidences`·`tts-cache`는 미구현이다.
- DB에도 자산별 보관 기간 컬럼이 없다.

항목별 구조를 먼저 내보내면 근거 없는 항목명과 값 차이를 계약으로 굳히게 되므로, 항목 축은 실제 정책이 확정되고 자산별 값이 갈릴 때 도입한다.

### `policyStatus`가 저장값이 아닌 이유

`policyStatus`는 컬럼이 아니라 응답 조립 시 항상 `PROVISIONAL`로 채우는 파생값이다. 사용자가 565로 값을 바꿀 수 있어도 그것은 **팀 차원의 정책 수치 확정**을 뜻하지 않으므로, 사용자 조작으로 상태가 `CONFIRMED`가 되어서는 안 된다.

## 2. PATCH 데이터 보관 정책 수정

```http
PATCH /api/v1/users/me/data-retention
Authorization: Bearer {accessToken}
Content-Type: application/json
```

대상 사용자는 Access Token Principal의 `requireUserId()`로 해석한다. 다른 사용자 ID를 요청으로 받지 않는다.

### 요청 본문

```json
{
  "retentionDays": 365,
  "noticeDaysBefore": 14
}
```

| 필드 | 타입 | 필수 | 검증 |
| --- | --- | --- | --- |
| `retentionDays` | int | O | 1 이상 |
| `noticeDaysBefore` | int | O | 0 이상이고 `retentionDays`보다 작음 |

두 필드를 모두 전달하는 **전체 교체**다. 한 필드만 보내는 부분 수정은 지원하지 않는다. 정책에서 확정하지 않은 별도 최대 일수는 두지 않는다.

### 성공 응답 `200 OK`

GET과 같은 `ApiResponse<DataRetentionPolicyResponse>`를 반환한다.

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {
    "retentionDays": 365,
    "noticeDaysBefore": 14,
    "policyStatus": "PROVISIONAL"
  }
}
```

설정 행이 없으면 INSERT, 있으면 두 기간 컬럼을 UPDATE하는 원자적 upsert다. 응답의 `policyStatus`는 저장값이 아니며 변경 후에도 항상 `PROVISIONAL`이다.

### 오류

| HTTP | 코드 | 조건 |
| --- | --- | --- |
| 400 | `COMMON_400_001` | 필수 필드 누락, 최솟값 위반, `noticeDaysBefore >= retentionDays` |
| 401 | `AUTH_401_006` | Access Token 누락 또는 검증 오류 |

검증 실패 시 저장하지 않는다. 사용자별 설정 행이 없다는 이유로 404를 반환하지 않는다.

## 3. 잠정값의 근거

보관 기간을 새로 창작하지 않았다.

- `docs/인프라/파일-수명주기-정책.md`는 `images`/`audio`/`reports` 보존기간을 `[결정 대기]`로 두고 **"임의 수치 금지"**(§D-1, 팀·심리상담 자문 대기)라고 못박았다.
- 그래서 이미 코드에 존재하는 기준값 — 보관 만료 임박 알림(`S15P11B209-557`)의 `RetentionNoticeProperties`(`retention-days=180`, `notice-days-before=30`) — 을 **그대로 잠정 기본값으로 승격**했다. 557 as-built도 이 값을 "임시 기준값"으로 기록하고 있다.
- 팀이 수치를 확정하면 **값만 교체**한다. 교체 지점은 두 곳이다.
  1. `V2x` 마이그레이션으로 `user_data_retention_settings` 컬럼 DEFAULT 변경(기존 V24 수정 금지)
  2. `DataRetentionPolicyResponse.DEFAULT_RETENTION_DAYS`·`DEFAULT_NOTICE_DAYS_BEFORE`
- 확정 시 `policyStatus`의 값 어휘도 같이 정한다(예: `CONFIRMED` 추가). 어휘를 늘리는 시점에 FE와 합의가 필요하다.

## 4. DB 매핑

| 응답 | 테이블·컬럼 |
| --- | --- |
| `retentionDays` | `user_data_retention_settings.retention_days` (V24 생성, DEFAULT 180) |
| `noticeDaysBefore` | `user_data_retention_settings.notice_days_before` (V24 생성, DEFAULT 30) |
| `policyStatus` | 컬럼 없음. 응답 조립 시 `PROVISIONAL` 고정 |

V24 `user_data_retention_settings`:

- PK `user_id`, FK → `users(id)` `ON DELETE CASCADE` (탈퇴 시 설정 동반 삭제)
- `CHECK retention_days > 0`
- `CHECK notice_days_before >= 0`
- `CHECK notice_days_before < retention_days` — 만료 후에 안내하는 조합을 DB에서 차단
- `updated_at DATETIME(6)` `ON UPDATE CURRENT_TIMESTAMP(6)`

`user_notification_settings`와 같이 **별도 Entity로 매핑하지 않는다.** 조회는 읽기 전용 Projection(`UserDataRetentionSettingsProjection`)과 `UserDataRetentionPolicyReader.read(userId)`, 쓰기는 Native upsert가 담당한다. CHECK 제약은 최소 방어선이며, PATCH 요청 값은 Bean Validation으로 같은 불변식을 먼저 검증한다.

## 5. 알려진 한계

① **보관 기간이 지난 데이터를 실제로 지우는 소비자가 없다.**
`storage_deletion_jobs` 큐에 적재하는 쪽(`ChildDeletionRepository`, `DrawingSessionDeletionRepository`, `DrawingDraftDeletionRepository`)만 있고, 큐를 소비해 MinIO 객체·Mongo 문서를 물리 삭제하는 워커(`@Scheduled` 소비자)는 존재하지 않는다. 현재 `@Scheduled`는 `SttPendingRecoveryScheduler`와 `RetentionNoticeScheduler` 둘뿐이다. 삭제 실행은 `S15P11B209-373` 소관이다(622 문서 §역할 분담).
→ 그래서 이 API는 **삭제 시점을 약속하지 않는다.** `expiresAt`·`deleteAt` 같은 필드를 두지 않은 이유이며, 집행 없는 삭제 공시를 만들지 않기 위한 의도적 결정이다.

② **보관 기간 값이 두 소스로 이원화되어 있다.**
| 소비자 | 값 출처 |
| --- | --- |
| 조회 API(564, 이 문서) | `user_data_retention_settings`(없으면 기본값) |
| 보관 만료 임박 알림 스케줄러(557) | `app.notification.retention.*` 프로퍼티 |

557의 `RetentionNoticeScheduler`·`RetentionNoticeProperties`·`RetentionExpiryRepository`는 565에서도 **변경하지 않았다.** 스케줄러는 `enabled` 기본 `false`로 꺼져 있어 현재 실사용 충돌은 없으나, PATCH로 사용자별 값이 저장되기 시작했으므로 스케줄러가 사용자별 값을 읽도록 맞추는 정합 작업은 후속 범위다.

③ **`policyStatus` 어휘가 현재 한 값뿐이다.** FE는 `PROVISIONAL` 외의 값이 추가될 수 있음을 전제로 다뤄야 한다(알 수 없는 값에서 깨지지 않게).

## 6. 564·565 구현 분담

| 항목 | 소유 |
| --- | --- |
| 응답 DTO(`DataRetentionPolicyResponse`)·필드 어휘 | **564** |
| `user_data_retention_settings` 스키마(V24) | **564** |
| 행 부재 시 GET 기본값 규약 | **564** |
| `PATCH` 요청 DTO·공통 검증 오류 | **565** |
| 요청 값 검증(최솟값, 안내 시점 < 보관 기간, 별도 최대값 없음) | **565** |
| 인증 사용자 기준 원자적 upsert 저장 경로 | **565** |
| 557 스케줄러와 사용자별 DB 값의 정합 | **후속 범위** |

565는 564의 응답 스키마와 V24를 변경하지 않고 쓰기 경로만 추가했다. DB Migration과 새 라이브러리도 추가하지 않았다.

## 7. 검증

- `UserControllerTest`
  - GET 저장 값·기본값·401 응답
  - PATCH 성공 시 GET과 같은 3필드 응답
  - 두 필드 필수, 각 최솟값, `noticeDaysBefore < retentionDays` 검증
  - Access Token 누락 시 401이며 변경 서비스를 호출하지 않음
- `UserDataRetentionPolicyReaderTest`
  - 행 존재 시 저장 값 반환 / 행 부재 시 컬럼 DEFAULT 반환
  - 저장 값이 있어도 `policyStatus`는 `PROVISIONAL` 유지
- `UserDataRetentionPolicyUpdateServiceTest`
  - 두 값을 upsert하고 공용 조회기의 응답을 그대로 반환
- `UserDataRetentionSettingsRepositoryIntegrationTest`(실 MySQL)
  - 행 부재 시 INSERT / 행 존재 시 UPDATE / PK 단일 행 유지
  - 별도 정책 최대값을 만들지 않고 MySQL `INT` 표현 범위의 최댓값 저장
- `UserAccountAndConsentIntegrationTest`(실 MySQL)
  - GET 기본값·인증 사용자 격리
  - PATCH insert·update와 GET 동일 응답
  - 검증 실패 시 기존 저장값 불변
- `DatabaseMigrationIntegrationTest`(실 MySQL)의 V24 보관 설정 검증
  - `user_data_retention_settings` 생성·PK·사용자 FK `ON DELETE CASCADE`
  - 컬럼 DEFAULT 180/30이 응답 기본값과 일치
  - `retention_days = 0`, `notice_days_before >= retention_days` CHECK 위반

> 검증 기준선 주의: 현재 실제 최신 Migration은 V27이지만 기준선 `DatabaseMigrationIntegrationTest`는 V26을 기대한다. 이 선행 불일치 때문에 전체 `clean test`가 실패했으며, 이 문서는 현재 최신 버전이나 전체 테이블 수를 단언하지 않는다.
