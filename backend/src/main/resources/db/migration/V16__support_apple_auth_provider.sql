-- Sign in with Apple의 불변 사용자 식별자를 기존 Social 인증 계정 구조에 저장할 수 있게 한다.

ALTER TABLE auth_accounts
    DROP CHECK ck_auth_accounts_provider,
    ADD CONSTRAINT ck_auth_accounts_provider
        CHECK (provider IN ('KAKAO', 'GOOGLE', 'NAVER', 'APPLE'));
