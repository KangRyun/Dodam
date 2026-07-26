# 알림 API 공개 계약 (디바이스 토큰·목록·읽음)

> Jira: `S15P11B209-549`(NOTI-01) · `550`(NOTI-02) · `551`(NOTI-03) · `552`(NOTI-04)
> 범위: 푸시 디바이스 Token 등록·해제, 알림 목록 조회, 단건 읽음 처리
> 기준 명세: `API_명세서_최종.md` §15 알림, `erd-cloud-schema-v1.2`
> 최종 수정: 2026-07-26

명세 §15가 정의하지 않은 응답 본문·오류 코드·경계 동작을 as-built로 확정한다. 프론트엔드와 백엔드가 이 문서를 단일 기준으로 사용한다. NOTI-05(`PATCH /notifications/read-all`, S15P11B209-553)는 이 계약 범위 밖이다.

## 0. 이 계약이 확정한 것

명세 §15는 요청 스키마(§15.2)·목록 항목 목록(§15.3)·오류 어휘 3종(§15.5)만 규정하고 **응답 본문 구조, 위반 시 응답, 상태 전이 경계를 정의하지 않았다.** 아래로 확정한다.

1. **§15.5에 없는 오류 코드 3종을 추가한다** — `DEVICE_TOKEN_NOT_FOUND`(404), `DEVICE_TOKEN_STORAGE_UNAVAILABLE`(503), `DEVICE_TOKEN_ALREADY_REGISTERED`(409). 명세 오류 목록 보강은 문서 담당자 몫으로 남긴다.
2. **잘못된 등록 요청은 형태와 무관하게 `DEVICE_TOKEN_INVALID` 하나로 응답한다** — 본문 누락, 필드 누락·공백, 미허용 `platform`, 길이 초과 전부 같은 코드다. 클라이언트가 다르게 행동해야 할 이유가 없다.
3. **등록은 `(userId, deviceId)` 기준 upsert이며 신규·갱신 모두 `200`이다.** 어느 쪽인지는 응답 `registered`로 구분한다. 자원을 새로 만드는 의미가 아니므로 `201`·`Location`을 쓰지 않는다.
4. **해제는 행 삭제가 아니라 비활성화이며, 같은 기기가 재등록하면 다시 활성화된다.** 해제 후 재로그인은 정상 경로다.
5. **읽음 처리는 멱등하다.** 재호출 시 최초 `readAt`을 유지하고 `200`으로 응답한다.
6. **남의 자원은 `403`이 아니라 `404`로 응답한다**(존재 은닉). 알림 ID·기기 식별자의 실재 여부를 노출하지 않는다.
7. **응답에 Push Token 원문·암호문·hash를 포함하지 않는다.** 클라이언트가 이미 아는 값이며, 응답에 실으면 로그·프록시에 남을 경로만 늘어난다.
8. **목록 응답에 `unreadCount` 같은 추가 필드를 넣지 않는다.** §15.3 항목 목록을 그대로 따른다. 미열람 건수는 `unreadOnly=true&size=1`의 `totalElements`로 얻는다.

## 1. 스키마 전제 (V14)

`notification_device_tokens`에 설치 식별자가 없어 upsert가 성립하지 않았다. FCM Token은 주기적으로 갱신되므로 `token_hash`만으로는 같은 기기의 이전 행을 찾을 수 없고, 행이 누적되며 죽은 Token으로 발송이 계속된다.

```sql
ALTER TABLE notification_device_tokens
    ADD COLUMN device_id VARCHAR(100) NOT NULL COMMENT '클라이언트 설치 식별자' AFTER user_id,
    ADD COLUMN app_version VARCHAR(20) NULL COMMENT '등록 시점 앱 버전' AFTER push_provider,
    ADD CONSTRAINT uk_notification_device_tokens_user_device UNIQUE (user_id, device_id);
```

**두 UNIQUE를 함께 유지한다. 각각 다른 사고를 막는다.**

| 제약 | 막는 것 |
| --- | --- |
| `uk_..._user_device` (`user_id`, `device_id`) | Token 갱신이 행 누적이 되는 것 |
| `uk_..._hash` (`token_hash`) | 같은 Token이 여러 계정에 등록되어 **알림이 다른 보호자에게 배달**되는 것 |

`app_version`은 §15.2 요청 필드다. 저장할 곳이 없으면 받고 버리는 거짓 계약이 되므로 함께 추가했다.

## 2. Push Token 저장 방식

발송에 원문이 필요하므로 해시가 아니라 복호화 가능한 형태로 보관한다(Refresh Token은 검증만 필요해 해시만 저장한다).

- 알고리즘: **AES-256-GCM**
- 저장 형식: `Base64(IV(12바이트) || ciphertext || tag(16바이트))` 한 덩어리를 `token_ciphertext`에 넣는다
- IV는 매 암호화마다 새로 만든다. 따라서 **같은 Token도 저장 값이 매번 달라 암호문으로 동일성을 비교할 수 없다.** 동일 Token 판별은 `token_hash`(SHA-256 hex 64자)로만 수행한다
- 키: `app.push.device-token.encryption-key` (Base64 32바이트), 환경변수 `PUSH_DEVICE_TOKEN_ENCRYPTION_KEY`
- **키 미구성 시 등록 API만 `503`으로 거부하고 애플리케이션은 정상 부팅한다.** 평문 저장으로 후퇴하지 않는다

## 3. NOTI-01 디바이스 Token 등록·갱신

```http
POST /api/v1/notifications/device-tokens
Authorization: Bearer {accessToken}
Content-Type: application/json
```

### 요청 (명세 §15.2)

```json
{
  "deviceId": "installation-uuid",
  "platform": "ANDROID",
  "pushToken": "fcm-registration-token",
  "appVersion": "1.0.0"
}
```

| 필드 | 타입 | 필수 | 규칙 |
| --- | --- | --- | --- |
| `deviceId` | string | O | 클라이언트 설치 식별자, 최대 100자. 같은 값은 갱신으로 처리 |
| `platform` | string | O | `ANDROID`, `IOS`, `WEB` |
| `pushToken` | string | O | Push Provider 발급 Token 원문 |
| `appVersion` | string | X | 최대 20자 |

`pushProvider`는 요청에 없다. 현재는 iOS도 Firebase가 발급한 등록 Token을 사용하므로 서버가 `FCM`으로 고정한다. APNs 직접 연동을 도입하면 Platform에 따라 분기한다.

### 성공 응답 `200 OK`

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {
    "deviceId": "installation-uuid",
    "platform": "ANDROID",
    "pushProvider": "FCM",
    "active": true,
    "registered": true,
    "updatedAt": "2026-07-26T12:00:00"
  }
}
```

- `registered`: 새로 등록했으면 `true`, 기존 기기를 갱신했으면 `false`
- `updatedAt`: 서버가 요청을 수신한 시각. DB의 `ON UPDATE CURRENT_TIMESTAMP`는 flush 후 Entity에 반영되지 않아 갱신 경로에서 이전 값이 나가므로 서버 시각을 쓴다
- **Token 원문·암호문·hash는 응답에 없다**

### 오류

| HTTP | 코드 | 조건 |
| --- | --- | --- |
| 400 | `DEVICE_TOKEN_INVALID` | 본문 누락, `deviceId`·`platform`·`pushToken` 누락·공백, 미허용 `platform`, 길이 초과 |
| 401 | `AUTH_*` | Access Token 누락·검증 오류 |
| 409 | `DEVICE_TOKEN_ALREADY_REGISTERED` | 같은 Token이 **다른 계정**에 등록되어 있음 |
| 503 | `DEVICE_TOKEN_STORAGE_UNAVAILABLE` | 암호화 키 미구성 또는 형식 오류 |

409에 관해: 한 기기에서 계정을 전환하면 같은 FCM Token이 두 계정에 붙을 수 있고, 그러면 이전 사용자에게 갈 알림이 새 사용자 기기로 배달된다. 정상 경로는 로그아웃 시 NOTI-02로 해제하는 것이다. 소유권 자동 이전은 하지 않는다.

## 4. NOTI-02 디바이스 Token 해제

```http
DELETE /api/v1/notifications/device-tokens/{deviceId}
Authorization: Bearer {accessToken}
```

### 성공 응답 `204 No Content`

본문 없음. `is_active = false`로 전환하며 행은 남긴다(발송 이력·감사 목적). 이미 비활성인 기기 재호출도 `204`다.

### 오류

| HTTP | 코드 | 조건 |
| --- | --- | --- |
| 401 | `AUTH_*` | Access Token 누락·검증 오류 |
| 404 | `DEVICE_TOKEN_NOT_FOUND` | 요청자에게 등록된 기기가 없음(남의 기기 포함) |

## 5. NOTI-03 알림 목록 조회

```http
GET /api/v1/notifications?type=&unreadOnly=false&page=0&size=20
Authorization: Bearer {accessToken}
```

| Query | 기본값 | 규칙 |
| --- | --- | --- |
| `type` | 없음(전체) | DB `notifications.notification_type` CHECK 값만 허용. 공백은 미적용 |
| `unreadOnly` | `false` | `true`면 `read_at IS NULL`만 |
| `page` | `0` | 0 이상 |
| `size` | `20` | 1~100 |

허용 `type`: `ANALYSIS_COMPLETED`, `ANALYSIS_FAILED`, `REPORT_COMPLETED`, `NEW_EXPERT_POST`, `COMMENT_CREATED`, `CONSENT_UPDATED`, `RETENTION_NOTICE`, `ACTIVITY_REMINDER`, `RISK_REVIEW_GUIDE`.

정렬은 `createdAt DESC, notificationId DESC`로 고정한다. tie-breaker가 없으면 같은 시각의 행이 페이지 경계에서 중복·누락된다.

### 성공 응답 `200 OK`

```json
{
  "data": {
    "content": [
      {
        "notificationId": 900,
        "type": "ANALYSIS_COMPLETED",
        "title": "분석이 완료됐어요",
        "content": "리포트를 확인해 보세요",
        "relatedResourceType": "REPORT",
        "relatedResourceId": 55,
        "data": { "analysisId": "77" },
        "deliveryStatus": "SENT",
        "readAt": null,
        "sentAt": "2026-07-26T11:00:00",
        "createdAt": "2026-07-26T10:00:00"
      }
    ],
    "page": 0,
    "size": 20,
    "totalElements": 1,
    "totalPages": 1,
    "first": true,
    "last": true,
    "hasNext": false
  }
}
```

- 커뮤니티 목록과 같은 공통 페이지 형식이다. 결과가 없으면 `404`가 아니라 `200`과 빈 `content`다
- **서버는 이동 URL을 만들지 않는다.** `relatedResourceType`·`relatedResourceId`만 제공하고 라우팅은 클라이언트가 결정한다(명세 §15.3). 클라이언트 라우트 변경이 서버 배포를 요구하지 않게 하기 위한 것이다
- `relatedResourceType`: `REPORT`, `DRAWING_SESSION`, `POST`. DB에 관련 자원 컬럼이 셋으로 나뉘어 있고 동시에 채워질 수 있어 **`REPORT` > `DRAWING_SESSION` > `POST` 우선순위**로 하나를 고른다. 연결된 자원이 없으면 두 필드 모두 `null`
- `data`: `notification_attributes`(key/value)를 평탄화한 `Map<String,String>`이며 없으면 `{}`. V1의 `notifications.data_json`은 V3에서 정규화되며 제거됐다. `value_type`은 노출하지 않는다
- 위험 관련 알림(`RISK_REVIEW_GUIDE`)의 raw risk score는 `data`에 담지 않는다(명세 §15.4). 발송 측(556·557)이 저장 단계에서 지켜야 하는 규칙이다

### 오류

| HTTP | 코드 | 조건 |
| --- | --- | --- |
| 400 | `COMMON_400_001` | 허용하지 않는 `type`, `page` 음수, `size` 범위 초과 |
| 401 | `AUTH_*` | Access Token 누락·검증 오류 |

## 6. NOTI-04 단건 알림 읽음 처리

```http
PATCH /api/v1/notifications/{notificationId}/read
Authorization: Bearer {accessToken}
```

### 성공 응답 `200 OK`

```json
{
  "data": {
    "notificationId": 900,
    "readAt": "2026-07-26T12:00:00"
  }
}
```

- **멱등하다.** 이미 읽은 알림을 다시 호출하면 최초 `readAt`을 그대로 반환하고 DB를 갱신하지 않는다. 목록 재진입이나 네트워크 재시도로 처음 읽은 시각이 바뀌면 그 값은 의미를 잃는다
- 클라이언트가 목록을 다시 받지 않고 배지를 갱신할 수 있도록 시각을 함께 준다

### 오류

| HTTP | 코드 | 조건 |
| --- | --- | --- |
| 401 | `AUTH_*` | Access Token 누락·검증 오류 |
| 404 | `NOTIFICATION_NOT_FOUND` | 알림이 없거나 **요청자의 알림이 아님** |

`403 NOTIFICATION_ACCESS_DENIED`(§15.5)는 조회·읽음 경로에서 사용하지 않는다. 권한 오류로 구분하면 알림 ID의 실재 여부가 드러나 ID를 훑어 지도를 만들 수 있다. 코드 자체는 향후 다른 경로(예: 전문가 공유 알림)를 위해 정의만 두었다.

## 7. DB 매핑

| 응답·동작 | 테이블·컬럼 |
| --- | --- |
| 기기 upsert | `notification_device_tokens(user_id, device_id)` UNIQUE |
| Token 저장 | `token_ciphertext`(봉인), `token_hash`(SHA-256 CHAR(64), UNIQUE) |
| 해제 | `is_active` |
| 목록 조건 | `notifications(recipient_user_id, notification_type, read_at)`, 인덱스 `idx_notifications_recipient_created_at` |
| `data` | `notification_attributes(notification_id, attribute_key, value_text)` |
| 읽음 | `notifications.read_at` |

`token_hash`는 DB가 `CHAR(64)`다. JPA에서 `length`만 지정하면 `VARCHAR`로 검증돼 `ddl-auto: validate`가 기동을 거부하므로 `columnDefinition = "CHAR(64)"`로 매핑해야 한다.

## 8. 운영

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `PUSH_DEVICE_TOKEN_ENCRYPTION_KEY` | 빈 값 | Base64(32바이트) AES-256 키. **미설정 시 NOTI-01만 503** |

키는 인프라가 시크릿으로 주입한다(619 FCM Service Account와 같은 분담). 키가 없어도 목록·읽음·해제는 정상 동작한다.

## 9. 검증

- `DeviceTokenCipherTest` — 왕복 복원, 같은 Token의 암호문이 매번 다름, 키 미구성·비32바이트·비Base64·변조 암호문 거부
- `DeviceTokenServiceTest` — 평문 미저장, 같은 기기 갱신 시 행 누적 없음·재활성화, 타 계정 Token 409, 잘못된 요청 5종이 같은 코드, 해제는 비활성화
- `NotificationQueryServiceTest` — 정렬 tie-breaker, 자원 우선순위, 부가 속성 조립, 빈 페이지에서 속성 조회 생략, `type`·페이지 범위 거부
- `NotificationReadServiceTest` — 멱등성(최초 시각 유지·쓰기 생략), 남의 알림 404
- `NotificationControllerTest` — Token 미노출, 오류 코드, 명세 기본 Query 값 전달
- `NotificationIntegrationTest` — 실 MySQL 관통 14건. 암호문 왕복, V14 UNIQUE가 upsert를 성립시키는지, 해제 후 행 유지·재활성화, 필터 조합, 빈 페이지 200, 읽음 멱등, 존재 은닉
- `DatabaseMigrationIntegrationTest` — V14 컬럼과 **두 UNIQUE 공존** 단언
