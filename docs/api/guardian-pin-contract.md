# 보호자 PIN API 공개 계약 (as-built)

> Jira: `S15P11B209-879` (보호자 PIN 설정·검증·잠금)
> 범위: `/api/v1/users/me/guardian-pin` 5개 endpoint
> 기준: 현재 구현 코드(`GuardianPinController`·`GuardianPinService`·`UserGuardianPin`·`GuardianPinErrorCode`)와 Migration `V35__create_user_guardian_pins.sql`
> 최종 수정: 2026-08-04

아동 모드에서 보호자 화면으로 복귀할 때 요구하는 4자리 PIN 의 요청·응답·오류·잠금 규칙을 정의한다. **`API_명세서_최종.md` 에 이 기능의 절이 없어** 이 문서가 as-built 정본 역할을 하며, 정본 명세 보강은 문서 담당자 몫으로 남긴다(이 문서는 정본을 수정하지 않는다).

이 문서의 모든 수치·코드·필드는 문서 작성 시점의 코드에서 읽은 값이다. 추정한 값은 §9에 따로 적었다.

## 0. 이 계약이 확정·정정하는 것

1. **Bean Validation 실패는 `PIN_INVALID` 가 아니라 `COMMON_400_001` 이고, `data` 에 `ValidationErrorData` 가 실린다.** 요청 DTO(`GuardianPinRequest`·`GuardianPinChangeRequest`)의 `@NotBlank @Pattern(regexp = "^\\d{4}$")` 와 Controller 의 `@Valid` 가 먼저 걸러 `GlobalExceptionHandler.handleMethodArgumentNotValidException` 이 응답한다. **Jira 879 의 오류 표에 적힌 `PIN_INVALID | 400 | data 없음` 은 사실과 다르다** — `PIN_INVALID` 는 HTTP 경로로 **도달하지 않는다**(§4.1).
2. **`PIN_INVALID` 코드 자체는 유지한다.** DTO 의 `@Pattern` 을 제거하지 않고, 서비스의 형식 가드도 남긴다. 서비스 내부 직접 호출(다른 Use Case 가 서비스를 부르는 경우)에 대한 방어로만 유효하다는 사실을 코드 javadoc 에 명시했다.
3. **실패 카운터는 요청 경계를 넘어 누적된다.** `remainingAttempts` 는 회차마다 4→3→2→1 로 줄고 5회째에 `423 PIN_LOCKED` 다. 최초 구현은 실패 기록이 예외와 함께 롤백돼 이 값이 **항상 4로 고정**되고 잠금이 영구히 걸리지 않았다(879 결함). 클라이언트는 `remainingAttempts` 감소를 신뢰해도 된다.
4. **성공·실패 응답이 같은 구조체다.** `401`·`423` 응답도 `data` 에 성공과 동일한 `GuardianPinStatusResponse` 를 싣는다. 남은 시도·해제 시각을 위해 별도 조회를 하지 않는다.
5. **검증 성공 시 해제 증표(토큰)를 발급하지 않는다.** 보호자 모드 해제 상태는 서버가 들지 않는다(§7).

## 1. 엔드포인트

| # | Method | Path | 용도 | 성공 |
| --- | --- | --- | --- | --- |
| PIN-01 | `GET` | `/api/v1/users/me/guardian-pin` | 설정 여부·잠금 상태 조회 | `200` |
| PIN-02 | `POST` | `/api/v1/users/me/guardian-pin` | 최초 설정 | `200` |
| PIN-03 | `PATCH` | `/api/v1/users/me/guardian-pin` | 변경(현재 PIN 확인) | `200` |
| PIN-04 | `POST` | `/api/v1/users/me/guardian-pin/verifications` | 검증 | `200` |
| PIN-05 | `DELETE` | `/api/v1/users/me/guardian-pin` | 초기화 | `200` |

- 인증: `Authorization: Bearer {accessToken}` 필수. 대상 사용자는 Access Token Principal 에서 해석한다. **경로·본문에 사용자 식별자를 받지 않아** IDOR 을 구조로 차단한다.
- Path Variable·Query Parameter **없음**. 지원하지 않는 Query 는 무시된다(별도 거부 규칙 없음).
- Content-Type: `application/json` (PIN-02·03·04). PIN-01·05 는 본문 없음.
- 아동별 PIN 은 없다. `user_guardian_pins.user_id` 가 PK 라 **보호자 계정당 PIN 하나**가 구조로 보장된다.
- 삭제(PIN-05)도 성공 시 `204` 가 아니라 `200` + 상태 본문이다(`pinConfigured=false`).

## 2. 요청

### PIN-02 설정 / PIN-04 검증

```json
{ "pin": "1234" }
```

| 필드 | 타입 | 필수 | 규칙 |
| --- | --- | --- | --- |
| `pin` | string | O | 숫자 4자리(`^\d{4}$`). 공백·`null` 불가 |

### PIN-03 변경

```json
{ "currentPin": "1234", "newPin": "5678" }
```

| 필드 | 타입 | 필수 | 규칙 |
| --- | --- | --- | --- |
| `currentPin` | string | O | 숫자 4자리 |
| `newPin` | string | O | 숫자 4자리. **현재 PIN 과 같아도 거부하지 않는다** |

- PIN 원문은 **본문으로만** 받는다. Query Parameter 로 받지 않는다(URL 은 접근 로그·프록시·이력에 남는다).
- PIN 원문·해시는 **어떤 응답에도 포함되지 않는다.**

## 3. 성공 응답

공통 봉투(`ApiResponse<GuardianPinStatusResponse>`)다.

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {
    "pinConfigured": true,
    "locked": false,
    "remainingAttempts": 5,
    "retryAfterSeconds": null,
    "lockedUntil": null,
    "serverTime": "2026-08-04T07:25:30.123456Z"
  }
}
```

| 필드 | 타입 | Null | 의미 |
| --- | --- | --- | --- |
| `pinConfigured` | boolean | X | PIN 설정 여부 |
| `locked` | boolean | X | 지금 잠겨 있는지(`locked_until > serverTime`) |
| `remainingAttempts` | int | X | 잠기기 전까지 남은 시도 횟수. 잠금 중이면 `0` |
| `retryAfterSeconds` | number | O | 잠금 해제까지 남은 초. 잠금 중이 아니면 `null` |
| `lockedUntil` | string(ISO-8601 UTC) | O | 잠금 해제 시각. 잠금 중이 아니면 `null` |
| `serverTime` | string(ISO-8601 UTC) | X | 응답 생성 서버 시각 |

- **PIN 미설정 상태**(PIN-01, PIN-05 직후): `pinConfigured=false`, `locked=false`, `remainingAttempts=5`, `retryAfterSeconds=null`, `lockedUntil=null`. 잠금 개념이 없으므로 시도 횟수는 상한 그대로 준다.
- **검증·변경 성공 직후**: `remainingAttempts=5`, `retryAfterSeconds=null`, `lockedUntil=null` (실패 이력·백오프 단계가 함께 0으로 초기화된다).
- 5개 endpoint 의 성공 응답이 모두 이 구조다. 응답 필드만 보고 어떤 endpoint 였는지 구분할 수 없다.

## 4. 오류

`data` 열은 오류 본문의 `data` 필드에 무엇이 실리는지다.

| HTTP | 코드 | `data` | 조건 | 해당 endpoint |
| --- | --- | --- | --- | --- |
| 400 | `COMMON_400_001` | `ValidationErrorData` | PIN 형식 위반(4자리 숫자 아님·누락·공백) | PIN-02·03·04 |
| 400 | `COMMON_400_003` | 없음 | 본문 누락·JSON 파싱 실패 | PIN-02·03·04 |
| 401 | `AUTH_401_006` | 없음 | 인증 Principal 없음 | 전체 |
| 401 | `PIN_MISMATCH` | `GuardianPinStatusResponse` | PIN 불일치(잠기지 않은 상태) | PIN-03·04 |
| 404 | `USER_404_001` | 없음 | 사용자 없음 | PIN-05 |
| 409 | `PIN_NOT_CONFIGURED` | 없음 | 설정된 PIN 없이 검증·변경 시도 | PIN-03·04 |
| 409 | `PIN_ALREADY_CONFIGURED` | 없음 | 이미 설정된 상태에서 재설정 시도 | PIN-02 |
| 409 | `PIN_RESET_REQUIRED` | 없음 | 소셜 재인증 창을 벗어남 | PIN-05 |
| 423 | `PIN_LOCKED` | `GuardianPinStatusResponse` | 잠금 중이거나 이번 시도로 잠김 | PIN-03·04 |
| 503 | `PIN_UNAVAILABLE` | 없음 | `pepper` 미구성 | 전체 |

- `data` 가 실리는 오류는 **`PIN_MISMATCH`·`PIN_LOCKED` 둘뿐**이다(`GuardianPinException` 경로). 나머지는 `data: null` 이다.
- `423 Locked` 를 쓴 이유: 요청 자체는 올바르지만 자원이 일시적으로 잠겨 있다는 뜻이라 이 상황에 정확히 맞는다. `429` 는 요청 속도 제한이라 의미가 다르다.
- `PIN_UNAVAILABLE` 은 기동을 막지 않고 이 API 만 거부한다. PIN 과 무관한 기능까지 멈추면 손실이 더 크다(기기 Token 암호화 키 미구성과 같은 처리).

### 4.1 `PIN_INVALID` 는 HTTP 경로로 도달하지 않는다

`GuardianPinErrorCode.PIN_INVALID`(400)는 열거되어 있으나 **HTTP 요청으로는 반환되지 않는다.** 형식 위반은 Controller 의 `@Valid` 단계에서 걸려 아래 형태로 응답한다.

```json
{
  "success": false,
  "code": "COMMON_400_001",
  "message": "요청 값이 올바르지 않습니다.",
  "data": {
    "fieldErrors": [{ "field": "pin", "message": "..." }],
    "globalErrors": []
  }
}
```

- `fieldErrors[].field` 는 요청 필드명(`pin`·`currentPin`·`newPin`)이다. `message` 는 Bean Validation 기본 메시지이며 **요청한 PIN 원문을 포함하지 않는다.**
- 형식 오류는 서비스에 닿지 않으므로 **실패 카운터가 늘지 않는다.** 오타로 잠금이 다가오지 않는다.
- 클라이언트는 `PIN_INVALID` 가 아니라 `COMMON_400_001` 로 분기해야 한다. Swagger 의 PIN-02 설명은 이 `400` 을 "PIN 형식 오류(PIN_INVALID)"로 잘못 적고 있었고, **`58a9bd06` 에서 실제 동작(`COMMON_400_001`·`data.fieldErrors`)에 맞게 정정했다.** 같은 점검에서 `@Valid` 가 걸린 PIN-03·04 에 `400` 문서가 없고 PIN-02·03·04·05 에 `503`, PIN-05 에 `401`·`404` 가 빠져 있던 것도 §4 표에 맞춰 채웠다.

## 5. 잠금 규칙 (지수 백오프)

`UserGuardianPin` 실측 값이다.

- **상한**: 연속 실패 `5`회(`MAX_ATTEMPTS`)에 닿으면 잠근다.
- **단계별 잠금 시간**(`LOCKOUT_STEPS`): `30초 → 1분 → 5분 → 15분 → 1시간`. 마지막 값이 상한이며 그 뒤로는 더 길어지지 않는다.

| 잠금 발생 시 `lockout_level` | 적용 잠금 시간 | 잠금 후 `lockout_level` |
| --- | --- | --- |
| 0 | 30초 | 1 |
| 1 | 1분 | 2 |
| 2 | 5분 | 3 |
| 3 | 15분 | 4 |
| 4 | 1시간 | 5 |
| 5 이상 | 1시간 | 5 (고정) |

- **잠글 때 `failed_attempt_count` 는 0으로 되돌린다.** 잠금이 풀린 뒤 다시 5번의 기회를 주고, 그 기회를 또 소진하면 한 단계 더 긴 잠금이 걸린다. 따라서 잠금 직후 DB 의 `failed_attempt_count` 는 `5` 가 아니라 `0` 이다.
- **잠금 중 시도는 실패로 세지 않는다.** `423` 으로 즉시 거부하며 `failed_attempt_count`·`locked_until` 이 변하지 않는다. 세면 잠금 해제 시각이 계속 밀려 영구 잠금이 된다.
- **검증 성공 시** `failed_attempt_count`·`lockout_level` 을 함께 0으로, `locked_until` 을 `null` 로 되돌린다. 정상 사용자는 백오프를 체감하지 않는다.
- **변경(PIN-03) 성공 시에도** 같은 초기화가 일어난다.
- **변경 시 현재 PIN 이 틀리면 검증과 같은 규칙으로 실패를 센다.** 변경 경로를 무한 시도 창구로 열어 두면 검증 잠금이 우회된다. 이때 **새 PIN 해시는 저장되지 않는다.**
- `retryAfterSeconds` 는 1초 미만이 남아도 `0` 이 아니라 **`1`** 을 준다. `0` 은 클라이언트에서 "이제 시도 가능"으로 읽히는데 서버는 아직 거부한다.
- 잠금 판단은 **서버 시각으로만** 한다(`Clock.systemUTC()`). 기기 시계를 신뢰하지 않으며, 그래서 응답에 `serverTime` 을 함께 준다.
- 잠금 상태는 Redis 가 아니라 **DB**(`user_guardian_pins`)가 권위 저장소다. Redis 를 비우거나 잃어도 잠금이 살아 있다. 동시 요청은 `SELECT ... FOR UPDATE` 행 배타 락으로 직렬화한다.

## 6. 초기화 재인증 창 (PIN-05)

- PIN 분실 시 초기화 경로다. **소셜 재인증이 필수다.** 단순 로그아웃만으로 풀리면 아이가 로그아웃 버튼을 눌러 잠금을 없앨 수 있다.
- 새 토큰 타입을 만들지 않고 **`users.last_login_at` 이 재인증 창 안인지**로 판정한다("방금 소셜 로그인을 통과했다"는 사실을 재사용).
- 창 길이: **기본 5분**(`app.security.guardian-pin.reset-reauth-window-minutes`, env `GUARDIAN_PIN_RESET_WINDOW_MINUTES`).
- 판정: `last_login_at >= serverTime - 창` 이면 허용. **`last_login_at` 이 `NULL` 이면 거부**한다(`PIN_RESET_REQUIRED`) — 판단 근거가 없을 때 잠금을 푸는 쪽으로 기울면 안 된다.
- 성공 시 행을 **삭제**하고 `pinConfigured=false` 를 응답한다. 잠금 상태도 함께 사라진다.
- **PIN 이 설정돼 있지 않아도 오류가 아니다.** 재인증 창 조건만 통과하면 `200` + `pinConfigured=false` 다(`deleteById` 는 대상 행이 없으면 아무것도 하지 않는다). 재호출도 같은 결과다. 이 경로는 테스트로 고정하지 않았다.
- 클라이언트 흐름: `423` 또는 반복 실패 → "PIN 을 잊으셨나요?" → **소셜 로그인 재수행** → 5분 안에 `DELETE` → `POST` 로 재설정.

## 7. 클라이언트(FE) 경계 — 서버가 하지 않는 것

지금까지 서비스 javadoc 에만 있던 내용이다. 계약으로 옮긴다.

1. **검증 성공 상태를 서버가 들지 않는다.** "지금 이 앱이 보호자 모드로 열려 있다"는 상태는 **앱 메모리에서만** 관리한다. 짧은 수명의 해제 증표도 발급하지 않는다 — 보호자 API 권한은 이미 Access Token 으로 통제되므로 증표가 있어도 "PIN 없이 Token 으로 직접 호출"은 막지 못하고 저장·만료·검증 경로만 늘어난다.
2. **백그라운드 복귀·아동 모드 재진입·로그아웃 시 재잠금은 FE 책임이다.** 서버는 재잠금 시점을 알 수 없다. FE 가 앱 lifecycle 에서 해제 상태를 버리고 PIN 화면을 다시 띄워야 한다.
3. **"첫 아동 모드 진입 전 PIN 설정"을 서버가 강제할 수 없다.** 아동 모드 진입은 서버 API 가 아니라 앱 내 화면 전환이다. 서버는 `pinConfigured` 를 알려주고, **게이트는 클라이언트가 세운다.**

시각 처리:

- `lockedUntil`·`serverTime` 은 UTC ISO-8601 `Z` 표기다. **`Z` 없는 문자열로 가정하지 말 것** — Dart `DateTime.parse` 는 `Z` 가 없으면 로컬 시각으로 읽어 KST 기기에서 9시간 어긋난다.
- 소수 초 자리수는 값에 따라 달라진다. **고정 길이를 가정하거나 문자열을 잘라 쓰지 말고 ISO-8601 파서로 읽을 것.**
- 남은 시간은 `serverTime` 과 `lockedUntil` 의 차이로 계산하거나 `retryAfterSeconds` 를 그대로 쓴다. **기기 시계와 `lockedUntil` 을 직접 비교하지 말 것.**
- 이 표기 규약은 `S15P11B209-822`(시각 표기 통일)를 따른다. **다만 822 티켓 자체는 현재 `해야 할 일` 상태라 팀 차원에서 완결된 규약은 아니다** — 다른 endpoint 와의 정렬은 822 진행에 따라 달라질 수 있다.

## 8. DB 매핑 (V35)

`user_guardian_pins` — 신규 스키마 변경 없음. 이 계약은 V35 를 그대로 쓴다.

| 응답·동작 | 컬럼 |
| --- | --- |
| `pinConfigured` | 행 존재 여부 (`user_id` PK, `users.id` FK `ON DELETE CASCADE`) |
| PIN 비교 | `pin_hash`(pepper HMAC-SHA256 → BCrypt), `hash_algorithm`(`HMAC_SHA256+BCRYPT`) |
| `remainingAttempts` | `failed_attempt_count` (`INT NOT NULL DEFAULT 0`) |
| 백오프 단계 | `lockout_level` (`INT NOT NULL DEFAULT 0`) |
| `locked`·`lockedUntil`·`retryAfterSeconds` | `locked_until` (`DATETIME(6) NULL`) |
| 검증 성공 시각 | `last_verified_at` (`DATETIME(6) NULL`) |

- `CHECK ck_user_guardian_pins_counters`: `failed_attempt_count >= 0 AND lockout_level >= 0`.
- 시각 컬럼은 `DATETIME(6)` 이라 **마이크로초까지만** 보존된다. 서버 시계의 나노초는 저장 시 반올림된다 — `serverTime`(시계 원본)과 `lockedUntil`(DB 왕복 값)의 소수 자리수가 다를 수 있다.
- PIN 원문은 어디에도 저장하지 않는다. 4자리는 조합이 10,000개뿐이라 DB 만 유출돼도 전수 시도가 가능한데, `pepper` 키가 DB 밖(시크릿)에 있어 해시만으로는 복원할 수 없다.
- 사용자 탈퇴 시 FK CASCADE 로 PIN 이 함께 지워진다.

## 9. 배포 게이트 — 배선 완료, 값 주입은 리포로 확인 불가 (2026-08-05 갱신)

`pepper` 는 `app.security.guardian-pin.pepper` = `${GUARDIAN_PIN_PEPPER:}` 로 `backend/src/main/resources/application.yml:119` 에 정의된다. 기본값이 빈 문자열이고, 빈 문자열이면 `GuardianPinHasher.isConfigured()` 가 false 라 **PIN API 5개 전부 `503 PIN_UNAVAILABLE`** 이다(부팅·다른 API·Healthcheck 는 정상 — 설계상 의도).

**env 배선은 끝났다.** `38a30a49 feat(infra): [S15P11B209-879] 보호자 PIN pepper 주입과 시크릿 절차 정정`(병합 `942882fa`)이 두 파일을 채웠다:

- `infra/.env.example:74` — `GUARDIAN_PIN_PEPPER=CHANGE_ME_base64_32`(`openssl rand -base64 32`, 기본 빈값→503 주석 포함)
- `infra/k8s/base/backend.yaml:118` — `{ name: GUARDIAN_PIN_PEPPER, valueFrom: { secretKeyRef: { name: dodam-secrets, key: GUARDIAN_PIN_PEPPER, optional: true } } }`

> 이 문서의 이전 판(2026-08-04)은 "두 파일에 **둘 다 없다**, 인프라 담당 작업 대기 중"이라고 적었다. 그 서술은 `5abed68f` 시점 사실이었고 지금은 낡았다 — 위 커밋으로 해소됐다.

🔴 **다만 "배선됨"과 "값이 들어감"은 다르다.** `secretKeyRef` 에 `optional: true` 가 붙어 있어 **`dodam-secrets` 에 `GUARDIAN_PIN_PEPPER` 키가 없어도 pod 는 정상 기동하고, 그 경우 env 가 비어 여전히 503** 이다. 클러스터 시크릿에 실제 값이 주입됐는지는 **리포지토리로 확인할 수 없다**(`sudo sync-secrets.sh` 실행 여부는 서버에서 확인). 남은 확인 항목은 **하나**다 — 시크릿에 실제 값이 들어갔는지. 배포 서버에서 env 존재를 보거나, PIN API 를 호출해 `503` 이 아닌지로 판별한다.

⚠️ **주입 전까지 이 기능은 동작하지 않는다.** 실패 횟수 누적·5회 잠금·지수 백오프(§6)도 pepper 가 들어와야 비로소 실제로 검증된다 — `requireAvailable()` 이 해시 비교 이전에 503 으로 거부하므로 잠금 로직에 도달조차 하지 않는다.
- **키를 바꾸면 기존 PIN 은 전부 검증 실패한다**(pepper 가 해시 입력에 들어간다). 운영 투입 후에는 키를 교체할 수 없고, 교체가 필요하면 전체 PIN 초기화가 동반된다.
- 별도 설정: `GUARDIAN_PIN_HASH_STRENGTH`(기본 12), `GUARDIAN_PIN_RESET_WINDOW_MINUTES`(기본 5). 둘 다 기본값으로 동작하므로 배포 차단 요인은 아니다.

## 10. 미확정·미검증

- **Guardian role 제한 없음.** `@PreAuthorize` 등 역할 제한이 걸려 있지 않아, 인증된 사용자면 role 과 무관하게 자기 PIN 을 다룰 수 있다. 정책 미결 상태이며 이 계약에서 정하지 않았다.
- **정본 명세에 절이 없다.** `API_명세서_최종.md` 에 보호자 PIN 절을 추가하는 것은 문서 담당자 몫이다.
- **동시 요청 직렬화는 코드 근거로만 기술했다.** `SELECT ... FOR UPDATE` 문법 실행은 `UserGuardianPinRepositoryIntegrationTest` 가 확인하지만, 두 요청이 동시에 들어오는 경합 시나리오는 테스트로 재현하지 않았다.
- **`serverTime` 의 소수 초 자리수를 값 단위로 측정하지 않았다.** ISO-8601 파서로 읽으라는 규칙만 계약으로 둔다.
- **`401 PIN_MISMATCH`·`423 PIN_LOCKED` 의 HTTP 응답 본문을 테스트로 고정하지 않았다.** 이 계약의 §4 `data` 열은 `GlobalExceptionHandler.handleGuardianPinException`(오류 코드 + `GuardianPinException.getStatus()` 를 `ApiErrorResponse.of` 로 싣는다)을 코드로 읽은 결과다. 서비스 계층 테스트가 예외에 실린 상태 값을 고정하고, HTTP 경로는 `COMMON_400_001` 케이스만 MockMvc 로 검증한다. Controller 단위 테스트(`GuardianPinControllerTest`)는 현재 없다.

## 11. 검증 (테스트)

| 테스트 | 무엇을 고정하는가 |
| --- | --- |
| `GuardianPinServiceTest` | 설정·검증·변경·초기화 규칙, 백오프 단계 진행, 성공 시 초기화, pepper 미구성 시 전 경로 503 (Mock, 시계 고정) |
| `UserGuardianPinRepositoryIntegrationTest` | V35 스키마 정합, `user_id` PK 유일성, CASCADE 삭제, CHECK 제약, `for update` 문법 (실 MySQL) |
| `GuardianPinServiceIntegrationTest` | **실패가 요청(트랜잭션) 경계를 넘어 커밋되는지**, 5회 잠금 도달, 잠금 중 미가산, 변경 실패 시 `pin_hash` 불변, 성공 시 초기화 커밋, 형식 위반이 `COMMON_400_001` 로 응답되는지 (실 MySQL, 테스트 트랜잭션 없음) |
