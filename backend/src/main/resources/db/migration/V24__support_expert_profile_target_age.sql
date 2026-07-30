-- EXPERT-01 요청·응답의 상담 대상 연령을 프로필에 보존한다.
ALTER TABLE expert_profiles
    ADD COLUMN target_age_min SMALLINT NULL COMMENT '상담 대상 최소 연령' AFTER career_years,
    ADD COLUMN target_age_max SMALLINT NULL COMMENT '상담 대상 최대 연령' AFTER target_age_min,
    ADD CONSTRAINT ck_expert_profiles_target_age CHECK (
        (target_age_min IS NULL AND target_age_max IS NULL)
        OR (
            target_age_min BETWEEN 0 AND 19
            AND target_age_max BETWEEN 0 AND 19
            AND target_age_min <= target_age_max
        )
    );
