# 알림 설정 조회 API 공개 계약 (as-built)

> Jira: `S15P11B209-554`
> 범위: 로그인 사용자 본인의 알림 수신 설정 조회
> 기준 명세: `API_명세서_최종.md` §6 사용자, `erd-cloud-schema-v1.2`
> 최종 수정: 2026-07-28

명세 §6이 정의하지 않은 **전용 조회 엔드포인트**를 as-built로 확정한다. 프론트엔드와 백엔드가 이 문서를 단일 기준으로 사용한다.

## 0. 이 계약이 확정한 것

명세 §6.1은 알림 설정에 대해 **변경** 엔드포인트(USER-04 `PATCH /users/me/notification-settings`)만 정의하고, 조회 전용 엔드포인트는 정의하지 않았다. 현재 명세상 알림 설정 조회는 USER-01 `GET /users/me` 응답의 `notificationSettings` 필드로만 노출된다.

USER-04(변경, `S15P11B209-555`)와 짝이 되는 조회 경로가 필요해 **`GET /users/me/notification-settings`를 신설**한다. 아래로 확정한다.

1. **임베드 조회(`GET /users/me` → `notificationSettings`)와 병존한다.** 전용 조회는 사용자 프로필 전체를 받지 않고 설정만 필요한 화면(알림 설정 화면)을 위한 경량 경로다. 두 경로의 값은 같은 소스(`user_notification_settings`)에서 나오므로 항상 일치한다.
2. **응답 스키마는 USER-01 응답의 `notificationSettings` 객체와 동일하다** — `analysisCompleted`, `community`, `serviceNotice`, `marketing`(모두 boolean). 별도 DTO를 만들지 않고 `NotificationSettingsResponse`를 재사용한다.
3. **설정 행이 없으면 404가 아니라 200과 기본값이다.** `user_notification_settings` 행이 없는 사용자에게는 컬럼 DEFAULT와 동일한 값(`analysisCompleted=true`, `community=true`, `serviceNotice=true`, `marketing=false`)을 반환한다. 임베드 조회(USER-01)와 같은 규약이다.
4. **정본(`API_명세서_최종.md`)에는 아직 반영하지 않았다.** 팀 공유 정본 갱신은 문서 담당자 몫으로 남긴다. 이 문서가 현재 유일한 as-built 기준이다.

## 1. GET 알림 설정 조회

```http
GET /api/v1/users/me/notification-settings
Authorization: Bearer {accessToken}
```

요청 본문·쿼리 파라미터는 없다. 대상 사용자는 Access Token Principal에서 해석한다.

### 성공 응답 `200 OK`

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {
    "analysisCompleted": true,
    "community": true,
    "serviceNotice": true,
    "marketing": false
  }
}
```

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `analysisCompleted` | boolean | 분석 완료 알림 수신 여부 |
| `community` | boolean | 커뮤니티 알림 수신 여부 |
| `serviceNotice` | boolean | 서비스 공지 수신 여부 |
| `marketing` | boolean | 마케팅 알림 수신 여부 |

설정 행이 없는 사용자에게는 위 기본값(`marketing`만 `false`)을 그대로 반환한다.

### 오류

| HTTP | 코드 | 조건 |
| --- | --- | --- |
| 401 | `AUTH_*` | Access Token 누락 또는 검증 오류 |

행 부재를 기본값으로 처리하므로 `404`는 발생하지 않는다.

## 2. DB 매핑

| 응답 | 테이블·컬럼 |
| --- | --- |
| 알림 설정 4필드 | `user_notification_settings(analysis_completed, community, service_notice, marketing)` (V3 생성) |

`user_notification_settings`는 별도 Entity가 아니라 읽기 전용 Projection(`UserNotificationSettingsProjection`)으로만 노출한다. 조회는 `UserNotificationSettingsReader.read(userId)`를 재사용하며, USER-01 응답 조립에 쓰이는 것과 동일한 경로다. 쓰기(USER-04, `S15P11B209-555`)는 별도 이슈에서 다룬다.

## 3. 검증

- `UserControllerTest`
  - 4필드 응답 매핑(사용자 지정 값 검증)
  - 설정 행이 없을 때 기본값(`analysisCompleted=true`, `community=true`, `serviceNotice=true`, `marketing=false`) 반환
  - Access Token 누락 시 401
