# 푸시 발송·수신 계약 (FCM)

> Jira: `S15P11B209-616`(Firebase 프로젝트·앱 등록, 완료) · `619`(Backend Service Account Secret, 완료) · `617`(Android FCM 설정·실기기 수신 검증) · `556`(분석 완료 알림 이벤트 처리) · `631`(푸시 발송 Monitoring)
> 범위: 백엔드 → FCM → 앱으로 이어지는 **푸시 메시지 페이로드·발송 규약·앱 수신 규약**
> 선행 계약: `docs/api/notification-inbox-contract.md`(디바이스 Token 등록·알림함) — 이 문서는 그 위에 **발송**을 얹는다
> 최종 수정: 2026-07-28

알림함 계약(NOTI-01~05)이 Token 저장과 알림 목록까지 확정했지만, **그 Token으로 실제 무엇을 어떤 모양으로 보내는지는 어디에도 정의돼 있지 않다.** BE(556)와 앱(617)이 각자 구현하면 페이로드가 어긋나 실기기 검증 단계에서 재작업이 난다. 이 문서를 발송 경로의 단일 기준으로 사용한다.

**BE·앱 담당자는 구현 전에 §3 페이로드와 §4·§5 역할 규약을 먼저 읽는다.** §8에 회신이 필요한 미결이 있다.

## 0. 이 계약이 확정한 것

1. **FCM 메시지는 `data`-only로 보낸다. `notification` 필드를 쓰지 않는다.** `notification`이 있으면 앱이 백그라운드일 때 OS가 알림을 자동 표시해 버려서, 앱이 표시 여부·문구·클릭 라우팅·배지를 제어할 수 없다. 아동 민감정보 서비스라 **무엇이 화면에 뜨는지를 앱이 항상 통제해야 한다**(가드레일 9절).
2. **페이로드 필드명은 알림함 응답과 동일하게 쓴다** — `notificationId`·`type`·`title`·`content`·`relatedResourceType`·`relatedResourceId`. 같은 개념에 다른 이름을 쓰지 않는다.
3. **서버는 이동 URL·딥링크를 만들지 않는다.** 알림함 계약과 동일하게 `relatedResourceType`+`relatedResourceId`만 주고 **라우팅은 앱이 결정한다**. 클라이언트 라우트 변경이 서버 배포를 요구하지 않게 하기 위한 것이다.
4. **푸시는 알림함의 사본이지 원본이 아니다.** 발송 전에 `notifications` 행을 먼저 만들고, 푸시는 그 행의 `notificationId`를 실어 보낸다. 푸시 유실·차단·미수신이어도 앱은 알림함에서 같은 내용을 볼 수 있어야 한다.
5. **푸시 본문에 아동 이름·그림 내용·분석 결과 원문을 넣지 않는다.** 알림 표시는 잠금화면에서도 보이므로 알림함 본문보다 더 보수적으로 쓴다(§6).
6. **`APP_PUSH_FCM_ENABLED=false`면 발송은 조용히 건너뛴다.** 예외를 던지거나 알림 생성 자체를 실패시키지 않는다. 푸시는 선택 기능이고, 알림함 기록은 푸시 성공 여부와 무관하게 남아야 한다.
7. **발송 실패는 사용자 요청을 실패시키지 않는다.** 분석 완료 처리는 푸시가 죽어도 완료다.
8. **FCM이 `UNREGISTERED`·`INVALID_ARGUMENT`를 반환한 Token은 비활성화한다.** 죽은 Token으로 무한 재시도하지 않는다(§5.3).

## 1. 현재 배관 상태 (as-built, 2026-07-28)

인프라 쪽 선행은 **모두 끝나 있다.** 616·619 완료분이며 새로 준비할 것이 없다.

| 항목 | 상태 | 실체 |
| --- | --- | --- |
| Firebase 프로젝트 | ✅ | `dodam-mvp-90114` |
| Android 앱 등록 | ✅ | 패키지 `com.dodam.app` — 앱 `applicationId`와 일치 |
| `google-services.json` | ✅ | `frontend/mobile/android/app/google-services.json` (커밋됨) |
| Service Account 주입 | ✅ | 도커 시크릿 → 컨테이너 `/run/secrets/fcm-service-account.json` (read-only) |
| Token 암호화 키 | ✅ | `PUSH_DEVICE_TOKEN_ENCRYPTION_KEY` (AES-256-GCM) |
| 디바이스 Token API | ✅ | `POST`/`DELETE /api/v1/notifications/device-tokens` |
| 알림함 API | ✅ | NOTI-03~05 |
| **BE 발송 코드** | ❌ | `firebase-admin` 의존성 없음 — **556 범위** |
| **앱 FCM 배선** | ❌ | `firebase_messaging` 미도입, gradle 플러그인·알림 권한 없음 — **617 범위** |

### 환경변수 (compose에 이미 배선됨)

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `APP_PUSH_FCM_ENABLED` | `false` | 발송 스위치. 556 머지 후 `true` |
| `APP_PUSH_FCM_CREDENTIALS_PATH` | `/run/secrets/fcm-service-account.json` | 컨테이너 내부 고정 경로. BE는 `app.push.fcm.credentials-path`로 바인딩해 `FirebaseApp`을 초기화한다 |
| `FCM_CREDENTIALS_HOST_PATH` | `/dev/null` | 호스트 절대경로. **상대경로 금지**(S15P11B209-641 장애 사유) |
| `PUSH_DEVICE_TOKEN_ENCRYPTION_KEY` | 빈 값 | 미설정 시 Token 등록만 `503` |

> ⚠️ **`PUSH_DEVICE_TOKEN_ENCRYPTION_KEY`를 교체하면 기존 암호문은 복호화 불가**(GCM 인증 실패)이며 해당 기기는 재로그인으로 Token을 다시 등록해야 발송 대상이 된다. **556 발송이 붙기 전에 키를 확정해 둔다.**

## 2. 역할 경계

| 담당 | 이슈 | 책임 |
| --- | --- | --- |
| INFRA | 616·619 ✅ | Firebase 프로젝트, `google-services.json`, Service Account 시크릿 주입, 환경변수 배관 |
| BE | **556** | `firebase-admin` 도입, `FirebaseApp` 초기화, 알림 행 생성 → 발송, 실패 Token 비활성화 |
| APP | **617** | Firebase SDK 도입, 알림 권한, Token 등록·갱신, 수신·표시, 클릭 라우팅 |
| INFRA | 631 | 발송 성공·실패 지표 수집 |

**경계 원칙:** 앱은 Token을 등록만 하고 발송 대상 선정에 관여하지 않는다. BE는 표시 문구를 만들고 앱은 그것을 그대로 표시한다(앱이 문구를 재작성하지 않는다).

## 3. FCM 메시지 페이로드 계약

FCM `data` 메시지로만 보낸다. **모든 값은 문자열이다**(FCM data 제약).

```json
{
  "data": {
    "notificationId": "900",
    "type": "ANALYSIS_COMPLETED",
    "title": "분석이 완료됐어요",
    "content": "리포트를 확인해 보세요",
    "relatedResourceType": "REPORT",
    "relatedResourceId": "55"
  }
}
```

| 키 | 필수 | 설명 |
| --- | --- | --- |
| `notificationId` | ✅ | `notifications` 행 식별자. 앱은 이 값으로 알림함과 대조하고 중복 표시를 막는다 |
| `type` | ✅ | 알림 유형. 아래 9종만 허용 |
| `title` | ✅ | 표시 제목. BE가 만든 문구를 그대로 표시한다 |
| `content` | ✅ | 표시 본문 |
| `relatedResourceType` | ⭕ | `REPORT` · `DRAWING_SESSION` · `POST`. 연결 자원이 없으면 **키 자체를 넣지 않는다**(`null` 문자열 금지) |
| `relatedResourceId` | ⭕ | 위 자원 식별자. `relatedResourceType`과 항상 쌍으로 존재하거나 둘 다 없다 |

허용 `type` (알림함 계약과 동일): `ANALYSIS_COMPLETED`, `ANALYSIS_FAILED`, `REPORT_COMPLETED`, `NEW_EXPERT_POST`, `COMMENT_CREATED`, `CONSENT_UPDATED`, `RETENTION_NOTICE`, `ACTIVITY_REMINDER`, `RISK_REVIEW_GUIDE`.

**넣지 않는 것**
- `notification` 블록 (§0-1)
- 이동 URL·딥링크 문자열 (§0-3)
- 아동 이름·그림 내용·분석 원문·raw risk score (§6)
- Push Token 원문

## 4. 앱 규약 (617)

### 4.1 Token 등록
1. 알림 권한 획득 후 FCM 등록 Token을 얻는다.
2. `POST /api/v1/notifications/device-tokens`로 등록한다 — `deviceId`(설치 UUID, **재설치 전까지 고정**), `platform`(`ANDROID`), `pushToken`(원문), `appVersion`.
3. **Token 갱신 콜백(`onTokenRefresh`)에서도 같은 API를 호출한다.** 등록은 `(userId, deviceId)` upsert라 행이 누적되지 않는다.
4. 로그아웃 시 `DELETE /api/v1/notifications/device-tokens/{deviceId}`로 해제한다(행 삭제가 아니라 비활성화이며, 재로그인하면 다시 활성화된다).

> `deviceId`는 사용자마다 다른 값이 아니라 **설치 식별자**다. 매번 새로 만들면 upsert가 성립하지 않아 죽은 Token이 쌓인다.

### 4.2 권한
- Android 13(API 33)+ 는 `POST_NOTIFICATIONS` **런타임 권한**이 필요하다. 거부돼도 앱 기능은 정상 동작해야 하며, 알림함은 계속 쓸 수 있다.
- 권한 거부 상태에서 Token 등록을 강행하지 않는다.

### 4.3 표시·라우팅
- 포그라운드·백그라운드 모두 **앱이 직접 로컬 알림을 구성해 표시한다**(data-only이므로 자동 표시가 없다).
- 같은 `notificationId`를 두 번 받으면 한 번만 표시한다.
- 클릭 시 `relatedResourceType`으로 화면을 고른다: `REPORT`→리포트 상세, `DRAWING_SESSION`→활동 상세, `POST`→게시글. 두 필드가 없으면 **알림함 목록으로 보낸다**(임의 화면으로 보내지 않는다).
- 라우팅 구현은 `S15P11B209-501`(알림 클릭 시 관련 화면 이동)과 같은 규칙을 쓴다.

### 4.4 아동 모드
- **아동 모드 화면에서는 푸시 알림을 표시하지 않는다.** 활동 중 알림이 아이 화면을 덮으면 안 되고, 위험 관련 문구가 아이에게 노출될 위험이 있다(가드레일 9절·4절).

## 5. BE 규약 (556)

### 5.1 순서
1. `notifications` 행을 먼저 만든다(알림함 원본).
2. 대상 사용자의 **활성** 디바이스 Token을 조회해 복호화한다.
3. FCM으로 발송한다.
4. 결과를 `deliveryStatus`에 반영한다.

`APP_PUSH_FCM_ENABLED=false`거나 자격증명이 없으면 **1번까지만 하고 조용히 끝낸다**(§0-6).

### 5.2 발송 실패
- 발송 실패가 분석 완료 트랜잭션을 롤백시키지 않는다(§0-7).
- 일시 오류(네트워크·5xx)는 재시도 가능하되, 무한 재시도하지 않는다.

### 5.3 죽은 Token 정리
FCM이 아래를 반환하면 해당 Token을 **비활성화**한다(행 삭제 아님 — 재등록 시 되살아나는 알림함 계약과 동일).

| FCM 오류 | 처리 |
| --- | --- |
| `UNREGISTERED` (앱 삭제·Token 만료) | 비활성화 |
| `INVALID_ARGUMENT` (형식 오류) | 비활성화 |
| 그 외(일시 오류) | 유지, 재시도 대상 |

### 5.4 로그
- **Push Token 원문·암호문을 로그에 남기지 않는다.** 식별이 필요하면 `deviceId` 또는 `token_hash` 앞 8자만 쓴다.
- 발송 본문(`title`·`content`)도 아동 관련 알림에서는 로그에 남기지 않는다.

## 6. 가드레일 (아동 민감정보 · CLAUDE.md 9절)

푸시는 **잠금화면에 뜨는 공개 표면**이다. 알림함보다 더 보수적으로 쓴다.

- ❌ 아동 이름·생년월일 · 그림 내용 묘사 · 분석 결과·해석 문구 · raw risk score
- ✅ "분석이 완료됐어요" / "리포트를 확인해 보세요" 수준의 중립 문구
- **`RISK_REVIEW_GUIDE`는 푸시 본문에 위험 내용을 절대 쓰지 않는다.** 보호자가 앱에 들어와서 확인하도록 유도하는 문구만 보낸다. 아동 화면 비노출 원칙은 앱(§4.4)에서 한 번 더 막는다.
- 위험 관련 알림의 raw risk score는 `data`에 담지 않는다(명세 §15.4, 알림함 계약과 동일).

## 7. 검증

**단계 A — 앱 단독 (617, 556 없이 가능)**
1. 앱 빌드 → 실기기 설치 → 알림 권한 허용 → FCM Token 발급 확인
2. `POST /api/v1/notifications/device-tokens` 200 + `registered` 확인
3. **Firebase 콘솔에서 테스트 메시지 발송** → 단말 수신·표시 확인

**단계 B — E2E (556 머지 후)**
4. `.env`에 `APP_PUSH_FCM_ENABLED=true` + `FCM_CREDENTIALS_HOST_PATH` 설정
5. 분석 완료 유발 → 푸시 수신 → 클릭 → 리포트 상세 이동
6. 알림함에 같은 `notificationId`가 있는지 대조
7. 앱 삭제 후 재발송 → Token 비활성화 확인(§5.3)

**경계**
- 권한 거부 상태 — 앱 정상 동작, 알림함 사용 가능
- `APP_PUSH_FCM_ENABLED=false` — 알림함 행은 생기고 발송만 생략
- 같은 알림 2회 수신 — 1회만 표시

## 8. 미결 — 회신 필요

| # | 내용 | 회신 |
| --- | --- | --- |
| 1 | **556 범위에 실제 FCM 발송 코드가 포함되는가?** 아니면 알림함 행 생성까지이고 발송은 별도 이슈인가 | BE(556) |
| 2 | §3 페이로드에 이견이 있는가 (특히 data-only 결정) | BE·APP |
| 3 | 죽은 Token 정리(§5.3)를 556에 넣는가, 631로 미루는가 | BE(556)·INFRA |
| 4 | `PUSH_DEVICE_TOKEN_ENCRYPTION_KEY` 확정 시점 — 발송 전에 정해야 재등록 사태를 피한다 | INFRA·BE |

이견이 없으면 이 문서대로 구현한다. 변경이 필요하면 이 문서를 먼저 고치고 구현한다.
