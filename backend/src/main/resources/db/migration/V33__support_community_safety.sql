ALTER TABLE complaints
    ADD CONSTRAINT uk_complaints_reporter_post_reason
        UNIQUE (reporter_user_id, target_post_id, reason_code),
    ADD CONSTRAINT uk_complaints_reporter_comment_reason
        UNIQUE (reporter_user_id, target_comment_id, reason_code),
    ADD CONSTRAINT uk_complaints_reporter_report_reason
        UNIQUE (reporter_user_id, target_report_id, reason_code);

CREATE TABLE user_blocks (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '사용자 차단 ID',
    blocker_user_id BIGINT NOT NULL COMMENT '차단한 사용자 ID',
    blocked_user_id BIGINT NOT NULL COMMENT '차단된 사용자 ID',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '차단 일시',
    CONSTRAINT pk_user_blocks PRIMARY KEY (id),
    CONSTRAINT uk_user_blocks_blocker_blocked UNIQUE (blocker_user_id, blocked_user_id),
    CONSTRAINT fk_user_blocks_blocker_user_id FOREIGN KEY (blocker_user_id)
        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_user_blocks_blocked_user_id FOREIGN KEY (blocked_user_id)
        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT ck_user_blocks_not_self CHECK (blocker_user_id <> blocked_user_id),
    INDEX idx_user_blocks_blocked_user_id (blocked_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자 차단';
