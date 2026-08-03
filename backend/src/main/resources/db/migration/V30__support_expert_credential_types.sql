ALTER TABLE expert_credentials
    ADD COLUMN credential_type VARCHAR(50) NOT NULL DEFAULT 'OTHER' COMMENT '자격 분류 코드'
        AFTER expert_profile_id;

ALTER TABLE expert_credentials
    ALTER COLUMN credential_type DROP DEFAULT;
