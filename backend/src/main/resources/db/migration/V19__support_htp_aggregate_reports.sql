ALTER TABLE htp_assessments
    ADD COLUMN completion_idempotency_key VARCHAR(100) NULL
        COMMENT 'HTP 종합 완료 요청 멱등 키' AFTER idempotency_key,
    ADD COLUMN report_analysis_id BIGINT NULL
        COMMENT '현재 HTP 리포트 생성 분석 ID' AFTER completion_idempotency_key,
    ADD COLUMN report_id BIGINT NULL
        COMMENT '현재 HTP 단일 리포트 ID' AFTER report_analysis_id,
    ADD CONSTRAINT uk_htp_assessments_completion_key UNIQUE (completion_idempotency_key),
    ADD CONSTRAINT fk_htp_assessments_report_analysis_id FOREIGN KEY (report_analysis_id)
        REFERENCES analyses (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_htp_assessments_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE RESTRICT;

ALTER TABLE htp_assessments
    DROP CHECK ck_htp_assessments_status,
    ADD CONSTRAINT ck_htp_assessments_status
        CHECK (status IN ('IN_PROGRESS', 'ANALYZING', 'COMPLETED', 'FAILED', 'ABANDONED', 'EXPIRED'));
