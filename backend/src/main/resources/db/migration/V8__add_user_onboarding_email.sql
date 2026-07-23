-- Onboarding에서 확정하는 사용자 연락 이메일 컬럼을 추가한다.
-- Provider가 이메일을 제공하지 않는 경우(예: Kakao) Onboarding에서 직접 수집한다.
-- 계정 식별자는 auth_accounts.provider_subject이므로 email에는 UNIQUE 제약을 두지 않는다.
ALTER TABLE users
    ADD COLUMN email VARCHAR(255) NULL COMMENT '사용자 연락 이메일, Onboarding에서 확정' AFTER nickname;
