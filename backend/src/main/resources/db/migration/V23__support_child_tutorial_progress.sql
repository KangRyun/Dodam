ALTER TABLE children
    ADD COLUMN tutorial_last_step VARCHAR(50) NULL COMMENT 'Tutorial 마지막 진행 단계'
        AFTER tutorial_status,
    ADD COLUMN tutorial_completed_at DATETIME(6) NULL COMMENT 'Tutorial 완료 또는 건너뛰기 일시'
        AFTER tutorial_last_step;
