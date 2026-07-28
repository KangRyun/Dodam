# 알림 설정 수정 API 공개 계약 (as-built)

> Jira: `S15P11B209-555`
> 범위: 로그인 사용자 본인의 알림 수신 설정 변경
> 기준 명세: `API_명세서_최종.md` §6 사용자(USER-04), `erd-cloud-schema-v1.2`
> 형제 계약: `notification-settings-read-contract.md`(`S15P11B209-554`, 조회)
> 최종 수정: 2026-07-28

명세 §6.1은 USER-04 `PATCH /users/me/notification-settings`(알림 수신 설정 변경)를 정의하고, §6.2는 요청 필드를 네 boolean으로 명시한다. 이 문서는 그 엔드포인트의 as-built 동작을 확정한다. 프론트엔드와 백엔드가 이 문서를 단일 기준으로 사용한다.

## 0. 이 계약이 확정한 것

1. **PATCH이지만 부분 수정이 아니라 전체 교체다.** 네 필드(`analysisCompleted`, `community`, `serviceNotice`, `marketing`)를 **모두 필수(required)** 로 받는다. 하나라도 누락하면 `400`이다. 명세 §6.2가 네 필드를 모두 요청 본문으로 정의한 문면을 따른 결정이며, "전달한 필드만 반영"하는 프로필 수정(USER-02)과 다르다.
2. **저장은 upsert다.** `user_notification_settings` 행이 있으면 UPDATE, 없으면 INSERT한다. 행 존재 여부를 애플리케이션에서 조회·분기하지 않고 `INSERT ... ON DUPLICATE KEY UPDATE` 한 문장으로 처리한다. `user_id`가 PK이므로 동시 요청이 겹쳐도 중복 INSERT 없이 단일 행으로 수렴한다.
3. **응답은 조회(USER-04 짝인 GET)와 동일한 스키마다.** 저장 후 최신 네 값을 `NotificationSettingsResponse`(554에서 신설)로 반환한다. 별도 응답 DTO를 만들지 않는다. 저장 직후 조회 경로(`UserNotificationSettingsReader.read`)로 다시 읽어 응답을 만들므로 읽기·쓰기 응답이 어긋나지 않는다.
4. **정본(`API_명세서_최종.md`)에는 아직 반영하지 않았다.** 팀 공유 정본 갱신은 문서 담당자 몫으로 남긴다. 이 문서가 현재 유일한 as-built 기준이다.

## 1. PATCH 알림 설정 수정

```http
PATCH /api/v1/users/me/notification-settings
Authorization: Bearer {accessToken}
Content-Type: application/json

{
  "analysisCompleted": false,
  "community": true,
  "serviceNotice": true,
  "marketing": false
}
```

대상 사용자는 Access Token Principal에서 해석한다(경로에 사용자 식별자를 받지 않아 IDOR을 차단).

| 요청 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `analysisCompleted` | boolean | 예 | 분석 완료 알림 수신 여부 |
| `community` | boolean | 예 | 커뮤니티 알림 수신 여부 |
| `serviceNotice` | boolean | 예 | 서비스 공지 수신 여부 |
| `marketing` | boolean | 예 | 마케팅 알림 수신 여부 |

### 성공 응답 `200 OK`

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {
    "analysisCompleted": false,
    "community": true,
    "serviceNotice": true,
    "marketing": false
  }
}
```

`data`는 저장 후 최신 네 값이며 조회 API 응답과 동일한 구조다.

### 오류

| HTTP | 코드 | 조건 |
| --- | --- | --- |
| 400 | `COMMON_400_001` | 네 필드 중 하나라도 누락(`@NotNull` 위반) 또는 본문 형식 오류 |
| 401 | `AUTH_401_006` | Access Token 누락 또는 검증 오류 |

## 2. DB 매핑

| 요청·응답 | 테이블·컬럼 |
| --- | --- |
| 알림 설정 4필드 | `user_notification_settings(analysis_completed, community, service_notice, marketing)` (V3 생성) |
| 수정 일시 | `user_notification_settings.updated_at` — 컬럼의 `ON UPDATE CURRENT_TIMESTAMP`로 UPDATE 시 자동 갱신 |

- 테이블 PK는 `user_id`이며, 이 단일성이 upsert의 동시성 안전을 보장한다.
- `user_notification_settings`는 별도 Entity가 아니라 읽기 전용 Projection(`UserNotificationSettingsProjection`)과 Native Query로만 노출한다. 스키마 변경은 없으며 새 Flyway Migration을 추가하지 않았다(최신 `V17`).

## 3. 구현 경로

- Controller `UserController#updateMyNotificationSettings` — `@Valid @RequestBody NotificationSettingsUpdateRequest`, `requireUserId()`로 대상 확정.
- Service `UserNotificationSettingsUpdateService#update` — `@Transactional`, upsert 후 조회기로 최신 값 반환.
- Repository `UserNotificationSettingsRepository#upsert` — `@Modifying` Native `INSERT ... ON DUPLICATE KEY UPDATE`.
- Request DTO `NotificationSettingsUpdateRequest` — 네 필드 각각 `@NotNull Boolean`(누락과 명시적 `false`를 구분).

## 4. 검증

- `UserControllerTest`
  - 네 필드 정상 수정 → 200 + 응답 4필드 매핑 + 서비스에 전달된 값 검증
  - 필드 누락(`marketing` 없음) → 400 `COMMON_400_001`, 서비스 미호출
  - Access Token 누락 → 401
- `UserAccountAndConsentIntegrationTest`(Testcontainers, 실 MySQL)
  - 행이 없을 때 INSERT되어 행 1개 생성·값 반영
  - 행이 있을 때 UPDATE되어 행 1개 유지·값 갱신
  - 필드 누락 → 400, 행 미생성
