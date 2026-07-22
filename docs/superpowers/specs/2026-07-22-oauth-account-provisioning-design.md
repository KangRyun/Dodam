# S15P11B209-304 OAuth 계정 Provisioning 설계

## 목적

자체 이메일·비밀번호 회원가입을 제거한 정책에 따라 Kakao·Google·Naver에서 검증된 사용자를
서비스 사용자와 인증 계정으로 최초 등록한다. 공개 OAuth endpoint와 authorization code 검증,
JWT 발급은 S15P11B209-306에서 구현한다.

## 보안 경계

304번은 공개 `POST /auth/signup`을 만들지 않는다. 클라이언트가 Provider ID나 이메일을 직접
전달하면 다른 사용자를 사칭할 수 있기 때문이다. 306번의 Provider Adapter가 code 교환과 응답
검증을 완료한 뒤에만 `VerifiedOAuthIdentity`를 생성해 Provisioning Service에 전달한다.

Provider별 불변 Subject는 다음과 같다.

- Kakao: 사용자 정보의 `id`
- Google: 검증된 ID Token 또는 UserInfo의 `sub`
- Naver: 프로필 응답의 `response.id`

이메일은 계정 식별에 사용하지 않는다. Adapter가 Provider별 신뢰 조건과 이메일 형식을 확인한
경우만 선택값으로 전달하고, 없으면 `null`을 사용한다.

## 처리 흐름

1. `(provider, providerSubject)`로 기존 인증 계정을 조회한다.
2. 기존 계정이면 사용자 ID와 현재 온보딩 필요 여부를 반환하며 새 행을 만들지 않는다.
3. 신규 계정이면 `users`를 `role=null`, `PENDING`, `is_completed=false`로 생성한다.
4. 같은 트랜잭션에서 `auth_accounts`를 생성한다.
5. 동시 최초 로그인으로 UNIQUE 충돌이 발생하면 `ACCOUNT_LINK_CONFLICT`를 반환하고 전체 저장을
   Rollback한다. 클라이언트는 새 로그인 요청으로 안전하게 재시도할 수 있다.

결과는 `userId`, `provider`, `newUser`, `needsOnboarding`만 제공한다. Token과 Provider Access
Token, 이메일은 반환하지 않는다.

## 제외 범위

- OAuth HTTP Client와 Secret 설정
- authorization code, ID Token, state, nonce 검증
- Access/Refresh Token 발급
- 공개 Controller endpoint와 OpenAPI
- 역할 선택과 동의 내역 저장
- 자체 회원가입·로그인·이메일 중복 확인

## 검증

- Kakao·Google·Naver 신규 계정 생성
- 이메일이 없는 Provider 사용자 허용
- 기존 Subject의 멱등 반환
- Provider가 다르면 같은 Subject 문자열 허용
- 같은 Provider/Subject 동시 생성 충돌 변환
- 사용자와 인증 계정의 트랜잭션 원자성
