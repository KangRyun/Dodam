# 온보딩 연락 이메일 정규화 설계

## 배경

`S15P11B209-531`은 온보딩 이메일 저장과 중복 검증을 요구한다. 그러나 현재 서비스는 자체 로그인을 제공하지 않으며 OAuth 계정은 `(provider, provider_subject)`로 식별한다. `V8__add_user_onboarding_email.sql`도 `users.email`을 사용자 연락 이메일로 정의하고 의도적으로 `UNIQUE` 제약을 두지 않는다.

따라서 과거 자체 로그인 기준의 이메일 중복 거부를 온보딩에 적용하지 않는다. 같은 연락 이메일을 사용하는 서로 다른 OAuth 계정은 별도 사용자로 유지한다.

## 결정

- `PUT /api/v1/users/me/onboarding`의 `email`은 필수다.
- 요청 이메일은 앞뒤 공백을 제거하고 `Locale.ROOT` 기준 소문자로 변환한다.
- 정규화 이후 기존 `@NotBlank`, `@Email`, 최대 255자 검증을 적용한다.
- 정규화된 이메일을 `users.email`에 저장하고 응답에도 같은 값을 반환한다.
- `users.email` 중복은 허용한다.
- OAuth 계정 자동 병합이나 이메일 기반 사용자 조회를 추가하지 않는다.
- 이미 온보딩을 완료한 사용자의 재요청은 기존 멱등 계약대로 현재 정보를 반환한다.

## 변경 범위

- `OnboardingRequest`: 생성 시 연락 이메일 정규화
- `UserOnboardingServiceTest`: 정규화된 이메일 저장·응답 검증
- `UserRepository` 통합 테스트: 동일 이메일을 가진 서로 다른 사용자의 저장 허용 검증
- `API_명세서_최종.md`: USER-02 이메일 필드와 중복 허용 정책 명시

## 오류 처리

- 공백 제거 후 빈 문자열: Bean Validation `400`
- 이메일 형식 오류: Bean Validation `400`
- 최대 길이 초과: Bean Validation `400`
- 이메일 중복: 오류가 아니며 정상 저장

## 검증

- 정규화 회귀 테스트
- 동일 연락 이메일 저장 통합 테스트
- `spotlessCheck`
- 전체 Backend 테스트
- Javadoc 생성
