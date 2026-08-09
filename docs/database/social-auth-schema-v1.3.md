# 소셜 전용 인증 스키마 v1.3 변경 명세

## 목적

자체 이메일·비밀번호 회원가입과 로그인을 제거하고, Kakao를 포함한 Social Provider의 불변
사용자 ID로 계정을 식별한다. 이 문서의 실행 기준은 Flyway
`V6__support_social_only_authentication.sql`이며 기존 V1~V5는 수정하지 않는다.

## OAuth Provider 식별 규칙

- 앱은 이메일, 전화번호 또는 Provider 로그인 문자열을 인증 식별자로 전달하지 않는다.
- 앱은 Kakao·Naver의 `accessToken` 또는 Google의 `idToken`을 백엔드로 전달한다.
- 백엔드는 Kakao App ID, Naver 사용자 정보, Google 서명·발급자·대상·만료를 검증한 후 Provider의 불변 사용자 ID를
  `auth_accounts.provider_subject`에 문자열로 저장한다.
- 이메일은 선택 속성이다. 미동의, 미보유, 비유효 또는 미인증이면 없을 수 있다.
- 이메일이 없거나 이메일 형식이 아니어도 불변 사용자 ID가 유효하면 로그인·가입을 거부하지 않는다.
- Provider의 불변 사용자 ID가 없거나 검증할 수 없는 경우만 Provider 응답 오류로 처리한다.

| Provider | `provider_subject` 원본 | 이메일 저장 조건 |
| --- | --- | --- |
| `KAKAO` | 사용자 정보 응답의 필수 `id` | `kakao_account.email`이 유효하고 인증된 경우 |
| `GOOGLE` | 검증된 ID Token/UserInfo의 필수 `sub` | `email_verified=true`이며 이메일 형식인 경우 |
| `NAVER` | 프로필 응답 `response.id` | 사용자가 제공에 동의했고 이메일 형식인 경우 |

이 방식은 전화번호나 다른 문자열로 Provider에 로그인하는 사용자도 동일한 Provider 회원번호로
안정적으로 식별한다. 이메일 변경·철회가 계정 중복 생성이나 로그인 실패로 이어지지 않는다. 서로
다른 Provider가 같은 Subject 문자열을 사용해도 `(provider, provider_subject)` 복합 UNIQUE로
구분한다.

## 테이블 변경

### 사용자 `users`

| 논리명 | 물리명 | 타입 | NULL | 설명 |
| --- | --- | --- | --- | --- |
| 사용자 ID | `id` | `bigint` | N | 사용자 PK |
| 사용자 역할 | `role` | `varchar(20)` | Y | Social 최초 로그인 후 Onboarding 전에는 `NULL` |
| 계정 상태 | `account_status` | `varchar(20)` | N | 가입 직후 `PENDING` |
| 온보딩 완료 여부 | `is_completed` | `boolean` | N | 가입 직후 `false` |
| 삭제 일시 | `deleted_at` | `datetime(6)` | Y | 기존 이력 호환용이며 즉시 hard delete 완료 후 행은 남지 않음 |

`role`의 허용 문자열은 기존 `GUARDIAN`, `EXPERT`, `ADMIN`을 유지한다. `NULL`은 역할 미지정이지
권한 부여가 아니며, 인증 필터는 Onboarding 완료 전 보호 API 접근을 허용하지 않아야 한다.

### 인증 계정 `auth_accounts`

| 논리명 | 물리명 | 타입 | NULL | Key/제약 | 설명 |
| --- | --- | --- | --- | --- | --- |
| 인증 계정 ID | `id` | `bigint` | N | PK | 인증 계정 식별자 |
| 사용자 ID | `user_id` | `bigint` | N | FK, CASCADE | 서비스 사용자 |
| 인증 제공자 | `provider` | `varchar(20)` | N | CHECK | `KAKAO`, `GOOGLE`, `NAVER` |
| Provider 사용자 식별자 | `provider_subject` | `varchar(255)` | N | `(provider, provider_subject)` UNIQUE | Provider의 불변 사용자 ID |
| Provider 제공 이메일 | `provider_email` | `varchar(255)` | Y | UNIQUE 아님 | 유효·인증된 경우에만 저장하는 참고 속성 |
| Provider 이메일 확인 일시 | `provider_email_verified_at` | `datetime(6)` | Y | - | Provider가 이메일을 유효·인증 상태로 보장한 확인 시각 |

삭제한 컬럼과 제약:

- `local_login_email`
- `password_hash`
- `ck_auth_accounts_local_credentials`
- `uk_auth_accounts_local_login_email`
- Provider CHECK의 `LOCAL` 값
- 자체 이메일 인증 전용 `email_verifications` 테이블

Provider 이메일에는 UNIQUE를 적용하지 않는다. 이메일은 계정 식별자가 아니며 Provider가 제공하지
않거나 나중에 변경할 수 있기 때문이다.

## 즉시 회원 삭제 준비

회원 삭제 요청은 유예 상태를 만들지 않고 해당 요청에서 즉시 처리한다. `users` hard delete가
전문가 프로필의 기존 `RESTRICT` FK에 막히지 않도록
`expert_profiles.user_id -> users.id`를 `ON DELETE CASCADE`로 변경한다.

다른 사용자 참조는 기존 목적을 유지한다.

- 인증 계정, 알림 설정, 기기 Token, 보호자 관계 등 사용자 종속 데이터: `CASCADE`
- 게시글·댓글·감사·신고처럼 보존할 이력의 작성자: `SET NULL`
- Redis Access/Refresh Session: 탈퇴 Service에서 DB 삭제와 함께 즉시 폐기

아동 원본과 그림·대화·리포트의 삭제 범위는 탈퇴 API에서 명시적으로 결정해야 한다. 보호자 관계만
CASCADE하고 아동 원본을 무조건 연쇄 삭제하지 않아, 공동 보호자나 보존 정책이 있는 데이터를
우발적으로 지우지 않는다.

## Migration 안전장치

V6 적용 전에 `provider='LOCAL'` 인증 계정 또는 `email_verifications` 데이터가 하나라도 있으면
`ck_migration_v6_social_auth_guard` 위반으로 Migration이 중단된다. 운영 데이터의 이관·만료 정책을
확정하지 않은 채 비밀번호 hash나 이메일 인증 이력을 자동 삭제하지 않는다.

신규 개발 DB처럼 해당 데이터가 없을 때만 다음 변경을 적용한다.

1. `users.role` NULL 허용
2. `email_verifications` 제거
3. LOCAL 인증 컬럼·제약 제거 및 Provider 이메일 컬럼명 명확화
4. Social Provider CHECK 적용
5. 전문가 프로필 FK를 `CASCADE`로 변경

## 후속 API 이슈 반영

- S15P11B209-304: 자체 회원가입을 구현하지 않고 Kakao·Google·Naver 최초 로그인 시 사용자·인증 계정 생성 흐름으로 재정의
- S15P11B209-306, S15P11B209-375: Provider Token 검증과 서비스 JWT 발급
- S15P11B209-305: 자체 이메일 중복 확인 API가 불필요하므로 구현 대상에서 제외
- S15P11B209-308: Refresh Token은 MySQL이 아닌 Redis에서 저장·회전·폐기
- 회원 탈퇴 API: 비밀번호 확인 필드를 제거하고 인증된 사용자 요청을 즉시 hard delete
