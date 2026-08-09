CREATE TABLE expert_verification_reviews (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '전문가 검토 이력 ID',
    expert_profile_id BIGINT NOT NULL COMMENT '검토 대상 전문가 프로필 ID',
    reviewer_user_id BIGINT NOT NULL COMMENT '검토 관리자 사용자 ID',
    decision_status VARCHAR(20) NOT NULL COMMENT '최종 승인·반려 상태',
    rejection_reason VARCHAR(1000) NULL COMMENT '전문가에게 공개할 반려 사유',
    internal_note VARCHAR(2000) NULL COMMENT '관리자 내부 검토 메모',
    reviewed_at DATETIME(6) NOT NULL COMMENT '검토 완료 일시',
    CONSTRAINT pk_expert_verification_reviews PRIMARY KEY (id),
    CONSTRAINT fk_expert_verification_reviews_profile_id
        FOREIGN KEY (expert_profile_id) REFERENCES expert_profiles (id) ON DELETE CASCADE,
    CONSTRAINT fk_expert_verification_reviews_reviewer_id
        FOREIGN KEY (reviewer_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT ck_expert_verification_reviews_status
        CHECK (decision_status IN ('VERIFIED', 'REJECTED')),
    CONSTRAINT ck_expert_verification_reviews_reason
        CHECK ((decision_status = 'VERIFIED' AND rejection_reason IS NULL)
            OR (decision_status = 'REJECTED' AND rejection_reason IS NOT NULL)),
    INDEX idx_expert_verification_reviews_profile_reviewed
        (expert_profile_id, reviewed_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='전문가 자격 검토 이력';

CREATE TABLE expert_verification_review_credentials (
    review_id BIGINT NOT NULL COMMENT '전문가 검토 이력 ID',
    expert_credential_id BIGINT NOT NULL COMMENT '승인한 전문가 자격 ID',
    CONSTRAINT pk_expert_verification_review_credentials
        PRIMARY KEY (review_id, expert_credential_id),
    CONSTRAINT fk_expert_verification_review_credentials_review_id
        FOREIGN KEY (review_id) REFERENCES expert_verification_reviews (id) ON DELETE CASCADE,
    CONSTRAINT fk_expert_verification_review_credentials_credential_id
        FOREIGN KEY (expert_credential_id) REFERENCES expert_credentials (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='전문가 검토 승인 자격';

ALTER TABLE notifications
    DROP CHECK ck_notifications_type,
    ADD CONSTRAINT ck_notifications_type
        CHECK (notification_type IN ('ANALYSIS_COMPLETED', 'ANALYSIS_FAILED',
            'REPORT_COMPLETED', 'NEW_EXPERT_POST', 'COMMENT_CREATED', 'CONSENT_UPDATED',
            'RETENTION_NOTICE', 'ACTIVITY_REMINDER', 'RISK_REVIEW_GUIDE',
            'EXPERT_VERIFICATION_RESULT'));
