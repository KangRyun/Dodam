-- 자체 이메일·비밀번호 인증을 제거하고 Social Provider의 불변 사용자 ID를 인증 기준으로 사용한다.
-- 기존 LOCAL 계정이 있으면 자격 증명 유실을 막기 위해 운영 이관 정책이 적용될 때까지 즉시 실패한다.

CREATE TEMPORARY TABLE migration_v6_social_auth_guard (
    violation TINYINT NOT NULL,
    CONSTRAINT ck_migration_v6_social_auth_guard CHECK (violation = 0)
);

INSERT INTO migration_v6_social_auth_guard (violation)
SELECT 1
WHERE EXISTS (SELECT 1 FROM auth_accounts WHERE provider = 'LOCAL')
   OR EXISTS (SELECT 1 FROM email_verifications);

DROP TEMPORARY TABLE migration_v6_social_auth_guard;

ALTER TABLE users
    MODIFY COLUMN role VARCHAR(20) NULL COMMENT '사용자 역할, Onboarding 전에는 NULL';

DROP TABLE email_verifications;

ALTER TABLE auth_accounts
    DROP INDEX uk_auth_accounts_local_login_email,
    DROP CHECK ck_auth_accounts_local_credentials,
    DROP CHECK ck_auth_accounts_provider,
    DROP COLUMN local_login_email,
    DROP COLUMN password_hash,
    RENAME COLUMN login_email TO provider_email,
    RENAME COLUMN email_verified_at TO provider_email_verified_at,
    ADD CONSTRAINT ck_auth_accounts_provider
        CHECK (provider IN ('KAKAO', 'GOOGLE', 'NAVER'));

ALTER TABLE expert_profiles
    DROP FOREIGN KEY fk_expert_profiles_user_id;

ALTER TABLE expert_profiles
    ADD CONSTRAINT fk_expert_profiles_user_id FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE CASCADE;
