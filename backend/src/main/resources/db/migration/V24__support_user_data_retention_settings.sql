CREATE TABLE user_data_retention_settings (
    user_id BIGINT NOT NULL COMMENT '사용자 ID',
    retention_days INT NOT NULL DEFAULT 180 COMMENT '데이터 보관 기간(일). 정책 확정 전 잠정값',
    notice_days_before INT NOT NULL DEFAULT 30 COMMENT '보관 만료 사전 안내 시점(일). 정책 확정 전 잠정값',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_user_data_retention_settings PRIMARY KEY (user_id),
    CONSTRAINT fk_user_data_retention_settings_user_id FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT ck_user_data_retention_settings_retention_days CHECK (retention_days > 0),
    CONSTRAINT ck_user_data_retention_settings_notice_days CHECK (notice_days_before >= 0),
    CONSTRAINT ck_user_data_retention_settings_notice_before_expiry
        CHECK (notice_days_before < retention_days)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자 데이터 보관 설정';
