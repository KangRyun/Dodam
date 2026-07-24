-- 리포트 생성 실패 시 내부 진단용 실패 분류 코드와 실패 시각을 리포트 자체에 보존한다.

ALTER TABLE reports
    ADD COLUMN failure_reason VARCHAR(100) NULL
        COMMENT '리포트 생성 실패 분류 코드' AFTER limitations_text,
    ADD COLUMN failed_at DATETIME(6) NULL
        COMMENT '리포트 생성 실패 일시' AFTER failure_reason;
