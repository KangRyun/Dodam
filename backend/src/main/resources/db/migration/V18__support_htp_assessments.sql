INSERT INTO drawing_types (
    code,
    name,
    activity_category,
    selectable_by,
    recommended_age_min,
    recommended_age_max,
    guide_text,
    is_active,
    display_order
) VALUES (
    'HTP',
    '집·나무·사람 그림',
    'ASSESSMENT',
    'GUARDIAN',
    4,
    12,
    '집, 나무, 사람을 순서대로 그리며 마음을 표현해 보세요.',
    TRUE,
    20
) AS new
ON DUPLICATE KEY UPDATE
    name = new.name,
    activity_category = new.activity_category,
    selectable_by = new.selectable_by,
    recommended_age_min = new.recommended_age_min,
    recommended_age_max = new.recommended_age_max,
    guide_text = new.guide_text,
    is_active = new.is_active,
    display_order = new.display_order;

UPDATE drawing_types
SET is_active = FALSE
WHERE code IN ('FREE_DRAWING', 'EMOTION_COLORING', 'WEATHER_MIND');

UPDATE drawing_types
SET is_active = TRUE, display_order = 10
WHERE code = 'ART_DIARY';

CREATE TABLE htp_assessments (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'HTP 활동 묶음 ID',
    child_id BIGINT NOT NULL COMMENT '아동 ID',
    drawing_type_id BIGINT NOT NULL COMMENT 'HTP 그림 활동 유형 ID',
    status VARCHAR(20) NOT NULL COMMENT 'HTP 활동 상태',
    current_step_order TINYINT NOT NULL COMMENT '현재 그림 단계 순서',
    expires_at DATETIME(6) NOT NULL COMMENT '재개 만료 일시',
    created_at DATETIME(6) NOT NULL COMMENT '생성 일시',
    completed_at DATETIME(6) NULL COMMENT '완료·포기 일시',
    idempotency_key VARCHAR(100) NOT NULL COMMENT 'HTP 시작 요청 멱등 키',
    active_child_id BIGINT GENERATED ALWAYS AS (
        CASE WHEN status IN ('IN_PROGRESS', 'ANALYZING') THEN child_id ELSE NULL END
    ) STORED COMMENT '아동별 진행 중 HTP 유일성 보장용',
    CONSTRAINT pk_htp_assessments PRIMARY KEY (id),
    CONSTRAINT fk_htp_assessments_child_id FOREIGN KEY (child_id)
        REFERENCES children (id) ON DELETE RESTRICT,
    CONSTRAINT fk_htp_assessments_drawing_type_id FOREIGN KEY (drawing_type_id)
        REFERENCES drawing_types (id) ON DELETE RESTRICT,
    CONSTRAINT uk_htp_assessments_idempotency_key UNIQUE (idempotency_key),
    CONSTRAINT uk_htp_assessments_active_child UNIQUE (active_child_id),
    CONSTRAINT ck_htp_assessments_status
        CHECK (status IN ('IN_PROGRESS', 'ANALYZING', 'COMPLETED', 'ABANDONED', 'EXPIRED')),
    CONSTRAINT ck_htp_assessments_current_step_order
        CHECK (current_step_order BETWEEN 1 AND 3),
    INDEX idx_htp_assessments_child_created_at (child_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='HTP 활동 묶음';

CREATE TABLE htp_assessment_steps (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'HTP 그림 단계 ID',
    htp_assessment_id BIGINT NOT NULL COMMENT 'HTP 활동 묶음 ID',
    step_order TINYINT NOT NULL COMMENT '그림 단계 순서',
    drawing_subject VARCHAR(20) NOT NULL COMMENT '그림 주제',
    drawing_session_id BIGINT NOT NULL COMMENT '단계별 그림 활동 세션 ID',
    subject_detected BOOLEAN NULL COMMENT '주제 전체 객체 탐지 여부',
    retry_count TINYINT NOT NULL DEFAULT 0 COMMENT '추가 그리기 요청 횟수',
    transition_idempotency_key VARCHAR(100) NOT NULL COMMENT '단계 생성 요청 멱등 키',
    completion_idempotency_key VARCHAR(100) NULL COMMENT '단계 완료 요청 멱등 키',
    created_at DATETIME(6) NOT NULL COMMENT '단계 생성 일시',
    CONSTRAINT pk_htp_assessment_steps PRIMARY KEY (id),
    CONSTRAINT fk_htp_assessment_steps_assessment_id FOREIGN KEY (htp_assessment_id)
        REFERENCES htp_assessments (id) ON DELETE CASCADE,
    CONSTRAINT fk_htp_assessment_steps_drawing_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE RESTRICT,
    CONSTRAINT uk_htp_assessment_steps_order UNIQUE (htp_assessment_id, step_order),
    CONSTRAINT uk_htp_assessment_steps_subject UNIQUE (htp_assessment_id, drawing_subject),
    CONSTRAINT uk_htp_assessment_steps_session UNIQUE (drawing_session_id),
    CONSTRAINT uk_htp_assessment_steps_transition_key UNIQUE (transition_idempotency_key),
    CONSTRAINT ck_htp_assessment_steps_order CHECK (step_order BETWEEN 1 AND 3),
    CONSTRAINT ck_htp_assessment_steps_subject
        CHECK (drawing_subject IN ('HOUSE', 'TREE', 'PERSON')),
    CONSTRAINT ck_htp_assessment_steps_retry_count CHECK (retry_count BETWEEN 0 AND 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='HTP 그림 단계';
