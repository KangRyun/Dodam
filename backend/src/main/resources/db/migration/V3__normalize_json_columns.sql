-- JSON 컬럼을 관계형 하위 테이블로 정규화하고 Refresh Token 저장소를 Redis로 이전한다.
-- 초기 개발 단계의 Migration으로, 기존 JSON 데이터가 있으면 데이터 유실 방지를 위해 즉시 실패한다.

CREATE TEMPORARY TABLE migration_v3_state_guard (
    violation TINYINT NOT NULL,
    CONSTRAINT ck_migration_v3_state_guard CHECK (violation = 0)
);

INSERT INTO migration_v3_state_guard (violation)
SELECT 1
WHERE EXISTS (SELECT 1 FROM refresh_tokens)
   OR EXISTS (SELECT 1 FROM users WHERE notification_settings_json IS NOT NULL AND JSON_LENGTH(notification_settings_json) > 0)
   OR EXISTS (SELECT 1 FROM children WHERE response_modes_json IS NOT NULL AND JSON_LENGTH(response_modes_json) > 0)
   OR EXISTS (SELECT 1 FROM expert_profiles WHERE specialties_json IS NOT NULL AND JSON_LENGTH(specialties_json) > 0)
   OR EXISTS (SELECT 1 FROM expert_profiles WHERE credentials_json IS NOT NULL AND JSON_LENGTH(credentials_json) > 0)
   OR EXISTS (SELECT 1 FROM stroke_batches WHERE payload_json IS NOT NULL AND JSON_LENGTH(payload_json) > 0)
   OR EXISTS (SELECT 1 FROM consent_records WHERE evidence_json IS NOT NULL AND JSON_LENGTH(evidence_json) > 0)
   OR EXISTS (SELECT 1 FROM audit_logs WHERE resource_snapshot_json IS NOT NULL AND JSON_LENGTH(resource_snapshot_json) > 0)
   OR EXISTS (SELECT 1 FROM audit_logs WHERE before_json IS NOT NULL AND JSON_LENGTH(before_json) > 0)
   OR EXISTS (SELECT 1 FROM audit_logs WHERE after_json IS NOT NULL AND JSON_LENGTH(after_json) > 0)
   OR EXISTS (SELECT 1 FROM notifications WHERE data_json IS NOT NULL AND JSON_LENGTH(data_json) > 0)
   OR EXISTS (SELECT 1 FROM ai_question_templates WHERE risk_response_json IS NOT NULL AND JSON_LENGTH(risk_response_json) > 0)
   OR EXISTS (SELECT 1 FROM ai_question_templates WHERE options_json IS NOT NULL AND JSON_LENGTH(options_json) > 0)
   OR EXISTS (SELECT 1 FROM conversation_messages WHERE options_json IS NOT NULL AND JSON_LENGTH(options_json) > 0)
   OR EXISTS (SELECT 1 FROM conversation_messages WHERE selected_response_json IS NOT NULL AND JSON_LENGTH(selected_response_json) > 0)
   OR EXISTS (SELECT 1 FROM conversation_messages WHERE target_object_json IS NOT NULL AND JSON_LENGTH(target_object_json) > 0)
   OR EXISTS (SELECT 1 FROM drawing_sessions WHERE selected_emotions_json IS NOT NULL AND JSON_LENGTH(selected_emotions_json) > 0)
   OR EXISTS (SELECT 1 FROM reports WHERE activity_summary_json IS NOT NULL AND JSON_LENGTH(activity_summary_json) > 0)
   OR EXISTS (SELECT 1 FROM reports WHERE observed_features_json IS NOT NULL AND JSON_LENGTH(observed_features_json) > 0)
   OR EXISTS (SELECT 1 FROM reports WHERE key_conversations_json IS NOT NULL AND JSON_LENGTH(key_conversations_json) > 0)
   OR EXISTS (SELECT 1 FROM reports WHERE evidence_json IS NOT NULL AND JSON_LENGTH(evidence_json) > 0)
   OR EXISTS (SELECT 1 FROM reports WHERE follow_up_json IS NOT NULL AND JSON_LENGTH(follow_up_json) > 0)
   OR EXISTS (SELECT 1 FROM reports WHERE guardian_questions_json IS NOT NULL AND JSON_LENGTH(guardian_questions_json) > 0)
   OR EXISTS (SELECT 1 FROM community_posts WHERE template_data_json IS NOT NULL AND JSON_LENGTH(template_data_json) > 0);

DROP TEMPORARY TABLE migration_v3_state_guard;

ALTER TABLE users
    DROP CHECK ck_users_account_status,
    ADD COLUMN deleted_at DATETIME(6) NULL COMMENT '삭제 일시' AFTER updated_at;

UPDATE users
SET account_status = 'DELETED',
    deleted_at = COALESCE(deleted_at, updated_at)
WHERE account_status = 'WITHDRAWN';

ALTER TABLE users
    ADD CONSTRAINT ck_users_account_status
        CHECK (account_status IN ('PENDING', 'ACTIVE', 'SUSPENDED', 'DELETED'));

ALTER TABLE expert_profiles
    DROP FOREIGN KEY fk_expert_profiles_users_id,
    DROP INDEX uk_expert_profiles_users_id,
    RENAME COLUMN users_id TO user_id,
    ADD CONSTRAINT uk_expert_profiles_user_id UNIQUE (user_id),
    ADD CONSTRAINT fk_expert_profiles_user_id FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE stroke_batches
    ADD COLUMN payload_checksum_sha256 CHAR(64) NOT NULL COMMENT '배치 Payload SHA-256 Checksum' AFTER event_count,
    ADD COLUMN undo_count_delta INT NOT NULL DEFAULT 0 COMMENT '실행 취소 증가량' AFTER payload_checksum_sha256,
    ADD COLUMN redo_count_delta INT NOT NULL DEFAULT 0 COMMENT '다시 실행 증가량' AFTER undo_count_delta,
    ADD COLUMN erase_count_delta INT NOT NULL DEFAULT 0 COMMENT '지우기 증가량' AFTER redo_count_delta,
    ADD COLUMN pause_duration_ms_delta BIGINT NOT NULL DEFAULT 0 COMMENT '일시 정지 시간 증가량(ms)' AFTER erase_count_delta,
    ADD CONSTRAINT ck_stroke_batches_metric_deltas CHECK (
        undo_count_delta >= 0 AND redo_count_delta >= 0
        AND erase_count_delta >= 0 AND pause_duration_ms_delta >= 0);

ALTER TABLE drawing_assets
    ADD COLUMN last_event_sequence BIGINT NULL COMMENT '자산에 반영된 마지막 Stroke 이벤트 순번' AFTER checksum_sha256,
    ADD COLUMN object_code VARCHAR(50) NULL COMMENT '다중 객체 업로드 식별 코드' AFTER last_event_sequence,
    ADD CONSTRAINT ck_drawing_assets_last_event_sequence
        CHECK (last_event_sequence IS NULL OR last_event_sequence >= 0);

ALTER TABLE drawing_sessions
    MODIFY COLUMN idempotency_key VARCHAR(100) NULL COMMENT '그림 활동 세션 생성 요청 멱등성 Key';

ALTER TABLE conversation_sessions
    ADD CONSTRAINT uk_conversation_sessions_drawing_session_id UNIQUE (drawing_session_id);

ALTER TABLE conversation_messages
    ADD COLUMN audio_checksum_sha256 CHAR(64) NULL COMMENT '음성 파일 SHA-256 Checksum' AFTER audio_url,
    ADD COLUMN stt_confidence DECIMAL(5,4) NULL COMMENT 'STT 신뢰도' AFTER speech_status,
    ADD COLUMN needs_guardian_confirmation BOOLEAN NOT NULL DEFAULT FALSE COMMENT '보호자 확인 필요 여부' AFTER stt_confidence,
    ADD CONSTRAINT ck_conversation_messages_stt_confidence
        CHECK (stt_confidence IS NULL OR (stt_confidence >= 0 AND stt_confidence <= 1)),
    ADD CONSTRAINT uk_conversation_messages_id_parent UNIQUE (id, parent_message_id);

ALTER TABLE reports
    ADD COLUMN pdf_status VARCHAR(20) NOT NULL DEFAULT 'NONE' COMMENT 'PDF 생성 상태' AFTER pdf_url,
    ADD CONSTRAINT ck_reports_pdf_status
        CHECK (pdf_status IN ('NONE', 'GENERATING', 'READY', 'FAILED'));

CREATE TABLE user_notification_settings (
    user_id BIGINT NOT NULL COMMENT '사용자 ID',
    analysis_completed BOOLEAN NOT NULL DEFAULT TRUE COMMENT '분석 완료 알림 수신 여부',
    community BOOLEAN NOT NULL DEFAULT TRUE COMMENT '커뮤니티 알림 수신 여부',
    service_notice BOOLEAN NOT NULL DEFAULT TRUE COMMENT '서비스 공지 수신 여부',
    marketing BOOLEAN NOT NULL DEFAULT FALSE COMMENT '마케팅 알림 수신 여부',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_user_notification_settings PRIMARY KEY (user_id),
    CONSTRAINT fk_user_notification_settings_user_id FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자 알림 설정';

CREATE TABLE child_response_modes (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '아동 응답 방식 ID',
    child_id BIGINT NOT NULL COMMENT '아동 ID',
    response_mode VARCHAR(20) NOT NULL COMMENT '응답 방식',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_child_response_modes PRIMARY KEY (id),
    CONSTRAINT uk_child_response_modes_child_mode UNIQUE (child_id, response_mode),
    CONSTRAINT uk_child_response_modes_child_order UNIQUE (child_id, display_order),
    CONSTRAINT fk_child_response_modes_child_id FOREIGN KEY (child_id)
        REFERENCES children (id) ON DELETE CASCADE,
    CONSTRAINT ck_child_response_modes_mode
        CHECK (response_mode IN ('VOICE', 'EMOJI', 'COLOR', 'PICTURE', 'TEXT')),
    CONSTRAINT ck_child_response_modes_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='아동 응답 방식';

CREATE TABLE expert_profile_specialties (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '전문가 전문 분야 ID',
    expert_profile_id BIGINT NOT NULL COMMENT '전문가 프로필 ID',
    specialty_code VARCHAR(50) NOT NULL COMMENT '전문 분야 코드',
    specialty_name VARCHAR(100) NOT NULL COMMENT '전문 분야명 Snapshot',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_expert_profile_specialties PRIMARY KEY (id),
    CONSTRAINT uk_expert_profile_specialties_profile_code UNIQUE (expert_profile_id, specialty_code),
    CONSTRAINT fk_expert_profile_specialties_profile_id FOREIGN KEY (expert_profile_id)
        REFERENCES expert_profiles (id) ON DELETE CASCADE,
    CONSTRAINT ck_expert_profile_specialties_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 전문 분야';

CREATE TABLE expert_credentials (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '전문가 자격 ID',
    expert_profile_id BIGINT NOT NULL COMMENT '전문가 프로필 ID',
    license_name VARCHAR(150) NOT NULL COMMENT '자격명',
    issuer VARCHAR(150) NOT NULL COMMENT '발급 기관',
    credential_number VARCHAR(100) NULL COMMENT '자격 번호',
    acquired_on DATE NULL COMMENT '취득일',
    expires_on DATE NULL COMMENT '만료일',
    verification_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '검증 상태',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_expert_credentials PRIMARY KEY (id),
    CONSTRAINT fk_expert_credentials_profile_id FOREIGN KEY (expert_profile_id)
        REFERENCES expert_profiles (id) ON DELETE CASCADE,
    CONSTRAINT ck_expert_credentials_status
        CHECK (verification_status IN ('PENDING', 'VERIFIED', 'REJECTED', 'REVIEW_REQUIRED')),
    CONSTRAINT ck_expert_credentials_dates
        CHECK (expires_on IS NULL OR acquired_on IS NULL OR expires_on >= acquired_on),
    INDEX idx_expert_credentials_profile_status (expert_profile_id, verification_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 자격';

CREATE TABLE expert_credential_files (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '전문가 자격 증빙 파일 ID',
    expert_credential_id BIGINT NOT NULL COMMENT '전문가 자격 ID',
    storage_key VARCHAR(1000) NOT NULL COMMENT '증빙 파일 저장 Key',
    storage_key_hash CHAR(64) NOT NULL COMMENT '증빙 파일 저장 Key SHA-256 Hash',
    file_name VARCHAR(255) NULL COMMENT '원본 파일명',
    mime_type VARCHAR(100) NULL COMMENT 'MIME 유형',
    file_size_bytes BIGINT NULL COMMENT '파일 크기(Byte)',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_expert_credential_files PRIMARY KEY (id),
    CONSTRAINT uk_expert_credential_files_key_hash UNIQUE (storage_key_hash),
    CONSTRAINT uk_expert_credential_files_order UNIQUE (expert_credential_id, display_order),
    CONSTRAINT fk_expert_credential_files_credential_id FOREIGN KEY (expert_credential_id)
        REFERENCES expert_credentials (id) ON DELETE CASCADE,
    CONSTRAINT ck_expert_credential_files_size
        CHECK (file_size_bytes IS NULL OR file_size_bytes > 0),
    CONSTRAINT ck_expert_credential_files_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 자격 증빙 파일';

CREATE TABLE stroke_events (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'Stroke 이벤트 ID',
    stroke_batch_id BIGINT NOT NULL COMMENT 'Stroke 배치 ID',
    event_sequence BIGINT NOT NULL COMMENT '전체 이벤트 순번',
    event_type VARCHAR(30) NOT NULL COMMENT '이벤트 유형',
    tool VARCHAR(30) NULL COMMENT '그리기 도구',
    color CHAR(9) NULL COMMENT '색상 코드',
    width DECIMAL(8,3) NULL COMMENT '선 굵기',
    pressure DECIMAL(6,5) NULL COMMENT '이벤트 대표 필압',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_stroke_events PRIMARY KEY (id),
    CONSTRAINT uk_stroke_events_batch_sequence UNIQUE (stroke_batch_id, event_sequence),
    CONSTRAINT fk_stroke_events_batch_id FOREIGN KEY (stroke_batch_id)
        REFERENCES stroke_batches (id) ON DELETE CASCADE,
    CONSTRAINT ck_stroke_events_sequence CHECK (event_sequence >= 0),
    CONSTRAINT ck_stroke_events_width CHECK (width IS NULL OR width > 0),
    CONSTRAINT ck_stroke_events_pressure
        CHECK (pressure IS NULL OR (pressure >= 0 AND pressure <= 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stroke 이벤트';

CREATE TABLE stroke_event_points (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'Stroke 좌표 ID',
    stroke_event_id BIGINT NOT NULL COMMENT 'Stroke 이벤트 ID',
    point_sequence INT NOT NULL COMMENT '이벤트 내부 좌표 순번',
    x DECIMAL(8,6) NOT NULL COMMENT '정규화 X 좌표',
    y DECIMAL(8,6) NOT NULL COMMENT '정규화 Y 좌표',
    elapsed_ms BIGINT NOT NULL COMMENT '이벤트 시작 후 경과 시간(ms)',
    pressure DECIMAL(6,5) NULL COMMENT '좌표별 필압',
    CONSTRAINT pk_stroke_event_points PRIMARY KEY (id),
    CONSTRAINT uk_stroke_event_points_event_sequence UNIQUE (stroke_event_id, point_sequence),
    CONSTRAINT fk_stroke_event_points_event_id FOREIGN KEY (stroke_event_id)
        REFERENCES stroke_events (id) ON DELETE CASCADE,
    CONSTRAINT ck_stroke_event_points_sequence CHECK (point_sequence >= 0),
    CONSTRAINT ck_stroke_event_points_coordinates CHECK (x >= 0 AND x <= 1 AND y >= 0 AND y <= 1),
    CONSTRAINT ck_stroke_event_points_elapsed CHECK (elapsed_ms >= 0),
    CONSTRAINT ck_stroke_event_points_pressure
        CHECK (pressure IS NULL OR (pressure >= 0 AND pressure <= 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stroke 이벤트 좌표';

CREATE TABLE consent_record_evidences (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '동의 증빙 항목 ID',
    consent_record_id BIGINT NOT NULL COMMENT '동의 이력 ID',
    evidence_key VARCHAR(80) NOT NULL COMMENT '증빙 항목 코드',
    value_type VARCHAR(20) NOT NULL DEFAULT 'STRING' COMMENT '값 유형',
    value_text TEXT NOT NULL COMMENT '증빙 값',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_consent_record_evidences PRIMARY KEY (id),
    CONSTRAINT uk_consent_record_evidences_record_key UNIQUE (consent_record_id, evidence_key),
    CONSTRAINT fk_consent_record_evidences_record_id FOREIGN KEY (consent_record_id)
        REFERENCES consent_records (id) ON DELETE CASCADE,
    CONSTRAINT ck_consent_record_evidences_type
        CHECK (value_type IN ('STRING', 'NUMBER', 'BOOLEAN', 'DATETIME'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='동의 증빙 항목';

CREATE TABLE audit_log_changes (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '감사 로그 변경 항목 ID',
    audit_log_id BIGINT NOT NULL COMMENT '감사 로그 ID',
    field_path VARCHAR(255) NOT NULL COMMENT '변경 필드 경로',
    value_type VARCHAR(20) NOT NULL DEFAULT 'STRING' COMMENT '값 유형',
    snapshot_value TEXT NULL COMMENT '대상 Snapshot 값',
    before_value TEXT NULL COMMENT '변경 전 값',
    after_value TEXT NULL COMMENT '변경 후 값',
    is_masked BOOLEAN NOT NULL DEFAULT FALSE COMMENT '민감값 마스킹 여부',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_audit_log_changes PRIMARY KEY (id),
    CONSTRAINT uk_audit_log_changes_log_field UNIQUE (audit_log_id, field_path),
    CONSTRAINT fk_audit_log_changes_audit_log_id FOREIGN KEY (audit_log_id)
        REFERENCES audit_logs (id) ON DELETE CASCADE,
    CONSTRAINT ck_audit_log_changes_type
        CHECK (value_type IN ('STRING', 'NUMBER', 'BOOLEAN', 'DATE', 'DATETIME', 'NULL'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='감사 로그 변경 항목';

CREATE TABLE notification_attributes (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '알림 부가 속성 ID',
    notification_id BIGINT NOT NULL COMMENT '알림 ID',
    attribute_key VARCHAR(80) NOT NULL COMMENT '부가 속성 코드',
    value_type VARCHAR(20) NOT NULL DEFAULT 'STRING' COMMENT '값 유형',
    value_text VARCHAR(1000) NOT NULL COMMENT '부가 속성 값',
    CONSTRAINT pk_notification_attributes PRIMARY KEY (id),
    CONSTRAINT uk_notification_attributes_notification_key UNIQUE (notification_id, attribute_key),
    CONSTRAINT fk_notification_attributes_notification_id FOREIGN KEY (notification_id)
        REFERENCES notifications (id) ON DELETE CASCADE,
    CONSTRAINT ck_notification_attributes_type
        CHECK (value_type IN ('STRING', 'NUMBER', 'BOOLEAN', 'DATETIME'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='알림 부가 속성';

CREATE TABLE ai_question_template_risk_responses (
    question_template_id BIGINT NOT NULL COMMENT 'AI 질문 Template ID',
    is_enabled BOOLEAN NOT NULL DEFAULT FALSE COMMENT '위험 응답 안내 활성 여부',
    guardian_guide_template TEXT NULL COMMENT '보호자 안내 Template',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_ai_question_template_risk_responses PRIMARY KEY (question_template_id),
    CONSTRAINT fk_ai_question_template_risk_responses_template_id FOREIGN KEY (question_template_id)
        REFERENCES ai_question_templates (id) ON DELETE CASCADE,
    CONSTRAINT ck_ai_question_template_risk_responses_guide
        CHECK (is_enabled = FALSE OR guardian_guide_template IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='AI 질문 Template 위험 응답 안내';

CREATE TABLE ai_question_template_options (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'AI 질문 Template 선택지 ID',
    question_template_id BIGINT NOT NULL COMMENT 'AI 질문 Template ID',
    option_key VARCHAR(80) NOT NULL COMMENT 'API 선택지 식별자',
    option_type VARCHAR(30) NOT NULL COMMENT '선택지 유형',
    option_value VARCHAR(255) NOT NULL COMMENT '선택지 값',
    label VARCHAR(200) NOT NULL COMMENT '표시 문구',
    emoji VARCHAR(20) NULL COMMENT '표시 Emoji',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_ai_question_template_options PRIMARY KEY (id),
    CONSTRAINT uk_ai_question_template_options_template_key UNIQUE (question_template_id, option_key),
    CONSTRAINT uk_ai_question_template_options_template_order UNIQUE (question_template_id, display_order),
    CONSTRAINT fk_ai_question_template_options_template_id FOREIGN KEY (question_template_id)
        REFERENCES ai_question_templates (id) ON DELETE CASCADE,
    CONSTRAINT ck_ai_question_template_options_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='AI 질문 Template 선택지';

CREATE TABLE conversation_message_options (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '대화 메시지 선택지 ID',
    conversation_message_id BIGINT NOT NULL COMMENT '질문 메시지 ID',
    template_option_id BIGINT NULL COMMENT '원본 Template 선택지 ID',
    option_key VARCHAR(80) NOT NULL COMMENT 'API 선택지 식별자 Snapshot',
    option_type VARCHAR(30) NOT NULL COMMENT '선택지 유형 Snapshot',
    option_value VARCHAR(255) NOT NULL COMMENT '선택지 값 Snapshot',
    label VARCHAR(200) NOT NULL COMMENT '표시 문구 Snapshot',
    emoji VARCHAR(20) NULL COMMENT '표시 Emoji Snapshot',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_conversation_message_options PRIMARY KEY (id),
    CONSTRAINT uk_conversation_message_options_message_key UNIQUE (conversation_message_id, option_key),
    CONSTRAINT uk_conversation_message_options_message_order UNIQUE (conversation_message_id, display_order),
    CONSTRAINT uk_conversation_message_options_message_id UNIQUE (conversation_message_id, id),
    CONSTRAINT fk_conversation_message_options_message_id FOREIGN KEY (conversation_message_id)
        REFERENCES conversation_messages (id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_message_options_template_option_id FOREIGN KEY (template_option_id)
        REFERENCES ai_question_template_options (id) ON DELETE SET NULL,
    CONSTRAINT ck_conversation_message_options_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 선택지 Snapshot';

CREATE TABLE conversation_message_selected_options (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '대화 선택 응답 ID',
    answer_message_id BIGINT NOT NULL COMMENT '답변 메시지 ID',
    question_message_id BIGINT NOT NULL COMMENT '질문 메시지 ID',
    message_option_id BIGINT NOT NULL COMMENT '질문 메시지 선택지 ID',
    label_snapshot VARCHAR(200) NOT NULL COMMENT '선택 당시 표시 문구',
    selection_order SMALLINT NOT NULL DEFAULT 0 COMMENT '선택 순서',
    CONSTRAINT pk_conversation_message_selected_options PRIMARY KEY (id),
    CONSTRAINT uk_conversation_message_selected_options_answer_option UNIQUE (answer_message_id, message_option_id),
    CONSTRAINT uk_conversation_message_selected_options_answer_order UNIQUE (answer_message_id, selection_order),
    CONSTRAINT fk_conversation_message_selected_options_answer_question
        FOREIGN KEY (answer_message_id, question_message_id)
        REFERENCES conversation_messages (id, parent_message_id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_message_selected_options_question_option
        FOREIGN KEY (question_message_id, message_option_id)
        REFERENCES conversation_message_options (conversation_message_id, id) ON DELETE CASCADE,
    CONSTRAINT ck_conversation_message_selected_options_order CHECK (selection_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 선택 응답';

CREATE TABLE conversation_message_targets (
    conversation_message_id BIGINT NOT NULL COMMENT '질문 메시지 ID',
    detected_object_id BIGINT NULL COMMENT '분석 탐지 객체 ID',
    object_code VARCHAR(50) NULL COMMENT '객체 코드 Snapshot',
    object_name VARCHAR(100) NULL COMMENT '객체명 Snapshot',
    bbox_x DECIMAL(8,6) NOT NULL COMMENT 'Bounding Box X 좌표',
    bbox_y DECIMAL(8,6) NOT NULL COMMENT 'Bounding Box Y 좌표',
    bbox_width DECIMAL(8,6) NOT NULL COMMENT 'Bounding Box 너비',
    bbox_height DECIMAL(8,6) NOT NULL COMMENT 'Bounding Box 높이',
    CONSTRAINT pk_conversation_message_targets PRIMARY KEY (conversation_message_id),
    CONSTRAINT fk_conversation_message_targets_message_id FOREIGN KEY (conversation_message_id)
        REFERENCES conversation_messages (id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_message_targets_detected_object_id FOREIGN KEY (detected_object_id)
        REFERENCES analysis_detected_objects (detected_object_id) ON DELETE SET NULL,
    CONSTRAINT ck_conversation_message_targets_bbox CHECK (
        bbox_x >= 0 AND bbox_x <= 1 AND bbox_y >= 0 AND bbox_y <= 1
        AND bbox_width > 0 AND bbox_width <= 1 AND bbox_height > 0 AND bbox_height <= 1
        AND bbox_x + bbox_width <= 1 AND bbox_y + bbox_height <= 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 대상 객체';

CREATE TABLE drawing_session_emotions (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '그림 활동 선택 감정 ID',
    drawing_session_id BIGINT NOT NULL COMMENT '그림 활동 세션 ID',
    emotion_code VARCHAR(20) NOT NULL COMMENT '감정 코드',
    selection_order SMALLINT NOT NULL DEFAULT 0 COMMENT '선택 순서',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_drawing_session_emotions PRIMARY KEY (id),
    CONSTRAINT uk_drawing_session_emotions_session_emotion UNIQUE (drawing_session_id, emotion_code),
    CONSTRAINT uk_drawing_session_emotions_session_order UNIQUE (drawing_session_id, selection_order),
    CONSTRAINT fk_drawing_session_emotions_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE CASCADE,
    CONSTRAINT ck_drawing_session_emotions_code
        CHECK (emotion_code IN ('HAPPY', 'SAD', 'ANGRY', 'SCARED', 'CALM', 'UNKNOWN')),
    CONSTRAINT ck_drawing_session_emotions_order CHECK (selection_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 선택 감정';

CREATE TABLE report_activity_summaries (
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    drawing_duration_ms BIGINT NULL COMMENT '그림 활동 시간(ms)',
    pause_count INT NULL COMMENT '일시 정지 횟수',
    erase_count INT NULL COMMENT '지우기 횟수',
    pressure_available BOOLEAN NOT NULL DEFAULT FALSE COMMENT '필압 데이터 존재 여부',
    conversation_question_count INT NULL COMMENT '대화 질문 수',
    conversation_answered_count INT NULL COMMENT '대화 응답 수',
    conversation_skipped_count INT NULL COMMENT '건너뛴 질문 수',
    conversation_summary TEXT NULL COMMENT '보호자용 대화 요약',
    CONSTRAINT pk_report_activity_summaries PRIMARY KEY (report_id),
    CONSTRAINT fk_report_activity_summaries_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_activity_summaries_counts CHECK (
        (drawing_duration_ms IS NULL OR drawing_duration_ms >= 0)
        AND (pause_count IS NULL OR pause_count >= 0)
        AND (erase_count IS NULL OR erase_count >= 0)
        AND (conversation_question_count IS NULL OR conversation_question_count >= 0)
        AND (conversation_answered_count IS NULL OR conversation_answered_count >= 0)
        AND (conversation_skipped_count IS NULL OR conversation_skipped_count >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 활동 요약';

CREATE TABLE report_activity_notes (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 활동 주의사항 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    note_text TEXT NOT NULL COMMENT '객관적 활동 주의사항',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_activity_notes PRIMARY KEY (id),
    CONSTRAINT uk_report_activity_notes_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_activity_notes_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_activity_notes_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 활동 주의사항';

CREATE TABLE report_observed_features (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 관찰 특징 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    feature_code VARCHAR(80) NULL COMMENT '관찰 특징 코드',
    title VARCHAR(200) NULL COMMENT '관찰 제목',
    description TEXT NOT NULL COMMENT '관찰 내용',
    evidence_summary TEXT NULL COMMENT '관찰 근거 요약',
    visibility_scope VARCHAR(20) NOT NULL DEFAULT 'EXPERT_ONLY' COMMENT '노출 범위',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_observed_features PRIMARY KEY (id),
    CONSTRAINT uk_report_observed_features_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_observed_features_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_observed_features_scope
        CHECK (visibility_scope IN ('EXPERT_ONLY', 'REVIEWED_GUARDIAN')),
    CONSTRAINT ck_report_observed_features_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 관찰 특징';

CREATE TABLE report_key_conversations (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 주요 대화 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    question_message_id BIGINT NULL COMMENT '질문 메시지 ID',
    answer_message_id BIGINT NULL COMMENT '답변 메시지 ID',
    question_text TEXT NOT NULL COMMENT '질문 Snapshot',
    answer_text TEXT NULL COMMENT '답변 Snapshot',
    answer_type VARCHAR(30) NULL COMMENT '답변 유형 Snapshot',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_key_conversations PRIMARY KEY (id),
    CONSTRAINT uk_report_key_conversations_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_key_conversations_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT fk_report_key_conversations_question_id FOREIGN KEY (question_message_id)
        REFERENCES conversation_messages (id) ON DELETE SET NULL,
    CONSTRAINT fk_report_key_conversations_answer_id FOREIGN KEY (answer_message_id)
        REFERENCES conversation_messages (id) ON DELETE SET NULL,
    CONSTRAINT ck_report_key_conversations_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 주요 대화';

CREATE TABLE report_evidence_references (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 근거 문헌 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    source_id VARCHAR(100) NOT NULL COMMENT '지식베이스 출처 ID',
    title VARCHAR(500) NOT NULL COMMENT '문헌 제목',
    published_year SMALLINT NULL COMMENT '발행 연도',
    section VARCHAR(100) NULL COMMENT '참조 구간',
    evidence_type VARCHAR(50) NOT NULL COMMENT '근거 유형',
    applicability TEXT NOT NULL COMMENT '적용 가능 범위',
    limitations TEXT NOT NULL COMMENT '적용 한계',
    knowledge_base_version VARCHAR(100) NOT NULL COMMENT '지식베이스 버전',
    retrieved_chunk_hash CHAR(64) NOT NULL COMMENT '검색 문단 SHA-256 Hash',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_evidence_references PRIMARY KEY (id),
    CONSTRAINT uk_report_evidence_references_report_source UNIQUE (report_id, source_id, retrieved_chunk_hash),
    CONSTRAINT uk_report_evidence_references_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_evidence_references_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_evidence_references_year
        CHECK (published_year IS NULL OR published_year BETWEEN 1000 AND 9999),
    CONSTRAINT ck_report_evidence_references_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 근거 문헌';

CREATE TABLE report_evidence_authors (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 근거 저자 ID',
    evidence_reference_id BIGINT NOT NULL COMMENT '리포트 근거 문헌 ID',
    author_name VARCHAR(200) NOT NULL COMMENT '저자명',
    author_order SMALLINT NOT NULL DEFAULT 0 COMMENT '저자 순서',
    CONSTRAINT pk_report_evidence_authors PRIMARY KEY (id),
    CONSTRAINT uk_report_evidence_authors_evidence_order UNIQUE (evidence_reference_id, author_order),
    CONSTRAINT fk_report_evidence_authors_evidence_id FOREIGN KEY (evidence_reference_id)
        REFERENCES report_evidence_references (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_evidence_authors_order CHECK (author_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 근거 저자';

CREATE TABLE report_follow_up_guides (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 후속 안내 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    guidance TEXT NOT NULL COMMENT '보호자 안내 문장',
    detail_text TEXT NULL COMMENT '상세 설명',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_follow_up_guides PRIMARY KEY (id),
    CONSTRAINT uk_report_follow_up_guides_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_follow_up_guides_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_follow_up_guides_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 후속 안내';

CREATE TABLE report_guardian_questions (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 보호자 질문 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    question_text TEXT NOT NULL COMMENT '보호자 질문 문장',
    question_purpose VARCHAR(50) NULL COMMENT '질문 목적',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_guardian_questions PRIMARY KEY (id),
    CONSTRAINT uk_report_guardian_questions_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_guardian_questions_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_guardian_questions_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 보호자 질문';

CREATE TABLE community_post_template_fields (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '커뮤니티 Template 항목 ID',
    community_post_id BIGINT NOT NULL COMMENT '게시글 ID',
    field_code VARCHAR(80) NOT NULL COMMENT 'Template 항목 코드',
    value_type VARCHAR(20) NOT NULL DEFAULT 'STRING' COMMENT '값 유형',
    value_text TEXT NOT NULL COMMENT 'Template 항목 값',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_community_post_template_fields PRIMARY KEY (id),
    CONSTRAINT uk_community_post_template_fields_post_code UNIQUE (community_post_id, field_code),
    CONSTRAINT uk_community_post_template_fields_post_order UNIQUE (community_post_id, display_order),
    CONSTRAINT fk_community_post_template_fields_post_id FOREIGN KEY (community_post_id)
        REFERENCES community_posts (id) ON DELETE CASCADE,
    CONSTRAINT ck_community_post_template_fields_type
        CHECK (value_type IN ('STRING', 'NUMBER', 'BOOLEAN', 'DATE')),
    CONSTRAINT ck_community_post_template_fields_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='커뮤니티 게시글 Template 항목';

CREATE TABLE email_verifications (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '이메일 인증 ID',
    auth_account_id BIGINT NOT NULL COMMENT '인증 계정 ID',
    verification_code_hash CHAR(64) NOT NULL COMMENT '인증 코드 Hash',
    expires_at DATETIME(6) NOT NULL COMMENT '만료 일시',
    verified_at DATETIME(6) NULL COMMENT '인증 완료 일시',
    attempt_count SMALLINT NOT NULL DEFAULT 0 COMMENT '인증 시도 횟수',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_email_verifications PRIMARY KEY (id),
    CONSTRAINT fk_email_verifications_auth_account_id FOREIGN KEY (auth_account_id)
        REFERENCES auth_accounts (id) ON DELETE CASCADE,
    CONSTRAINT ck_email_verifications_attempt_count CHECK (attempt_count >= 0),
    INDEX idx_email_verifications_account_expires_at (auth_account_id, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='이메일 인증';

CREATE TABLE data_export_jobs (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '데이터 내보내기 작업 ID',
    user_id BIGINT NOT NULL COMMENT '사용자 ID',
    export_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '내보내기 상태',
    storage_key VARCHAR(1000) NULL COMMENT '내보내기 파일 저장 Key',
    expires_at DATETIME(6) NULL COMMENT '다운로드 만료 일시',
    completed_at DATETIME(6) NULL COMMENT '완료 일시',
    error_code VARCHAR(80) NULL COMMENT '오류 코드',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_data_export_jobs PRIMARY KEY (id),
    CONSTRAINT fk_data_export_jobs_user_id FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT ck_data_export_jobs_status
        CHECK (export_status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'EXPIRED')),
    INDEX idx_data_export_jobs_user_created_at (user_id, created_at),
    INDEX idx_data_export_jobs_status_created_at (export_status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='데이터 내보내기 작업';

CREATE TABLE conversation_message_audio_variants (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '대화 음성 변형 ID',
    conversation_message_id BIGINT NOT NULL COMMENT '대화 메시지 ID',
    voice_code VARCHAR(50) NOT NULL COMMENT '음성 코드',
    speech_speed DECIMAL(4,2) NOT NULL DEFAULT 1.00 COMMENT '재생 속도',
    storage_key VARCHAR(1000) NOT NULL COMMENT '음성 파일 저장 Key',
    checksum_sha256 CHAR(64) NOT NULL COMMENT '음성 파일 SHA-256 Checksum',
    mime_type VARCHAR(100) NOT NULL COMMENT 'MIME 유형',
    file_size_bytes BIGINT NOT NULL COMMENT '파일 크기(Byte)',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_conversation_message_audio_variants PRIMARY KEY (id),
    CONSTRAINT uk_conversation_audio_variant UNIQUE (conversation_message_id, voice_code, speech_speed),
    CONSTRAINT fk_conversation_audio_variant_message_id FOREIGN KEY (conversation_message_id)
        REFERENCES conversation_messages (id) ON DELETE CASCADE,
    CONSTRAINT ck_conversation_audio_variant_speed CHECK (speech_speed BETWEEN 0.80 AND 1.20),
    CONSTRAINT ck_conversation_audio_variant_size CHECK (file_size_bytes > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 음성 변형';

CREATE TABLE complaints (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '신고 ID',
    reporter_user_id BIGINT NULL COMMENT '신고자 사용자 ID',
    target_type VARCHAR(20) NOT NULL COMMENT '신고 대상 유형',
    target_report_id BIGINT NULL COMMENT '대상 리포트 ID',
    target_post_id BIGINT NULL COMMENT '대상 게시글 ID',
    target_comment_id BIGINT NULL COMMENT '대상 댓글 ID',
    reason_code VARCHAR(50) NOT NULL COMMENT '신고 사유 코드',
    detail_text TEXT NULL COMMENT '신고 상세',
    complaint_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '신고 처리 상태',
    assigned_admin_user_id BIGINT NULL COMMENT '담당 관리자 사용자 ID',
    resolved_at DATETIME(6) NULL COMMENT '처리 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_complaints PRIMARY KEY (id),
    CONSTRAINT fk_complaints_reporter_user_id FOREIGN KEY (reporter_user_id)
        REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_complaints_target_report_id FOREIGN KEY (target_report_id)
        REFERENCES reports (id) ON DELETE RESTRICT,
    CONSTRAINT fk_complaints_target_post_id FOREIGN KEY (target_post_id)
        REFERENCES community_posts (id) ON DELETE RESTRICT,
    CONSTRAINT fk_complaints_target_comment_id FOREIGN KEY (target_comment_id)
        REFERENCES comments (id) ON DELETE RESTRICT,
    CONSTRAINT fk_complaints_assigned_admin_user_id FOREIGN KEY (assigned_admin_user_id)
        REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT ck_complaints_target CHECK (
        (target_type = 'REPORT' AND target_report_id IS NOT NULL AND target_post_id IS NULL AND target_comment_id IS NULL)
        OR (target_type = 'POST' AND target_report_id IS NULL AND target_post_id IS NOT NULL AND target_comment_id IS NULL)
        OR (target_type = 'COMMENT' AND target_report_id IS NULL AND target_post_id IS NULL AND target_comment_id IS NOT NULL)),
    CONSTRAINT ck_complaints_status
        CHECK (complaint_status IN ('PENDING', 'REVIEWING', 'RESOLVED', 'REJECTED')),
    INDEX idx_complaints_status_created_at (complaint_status, created_at),
    INDEX idx_complaints_reporter_created_at (reporter_user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='신고';

CREATE TABLE complaint_actions (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '신고 처리 이력 ID',
    complaint_id BIGINT NOT NULL COMMENT '신고 ID',
    actor_user_id BIGINT NULL COMMENT '처리 관리자 사용자 ID',
    action_type VARCHAR(30) NOT NULL COMMENT '처리 유형',
    previous_status VARCHAR(20) NOT NULL COMMENT '처리 전 상태',
    next_status VARCHAR(20) NOT NULL COMMENT '처리 후 상태',
    resolution_note TEXT NULL COMMENT '처리 메모',
    notify_reporter BOOLEAN NOT NULL DEFAULT FALSE COMMENT '신고자 알림 여부',
    notify_target_author BOOLEAN NOT NULL DEFAULT FALSE COMMENT '대상 작성자 알림 여부',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_complaint_actions PRIMARY KEY (id),
    CONSTRAINT fk_complaint_actions_complaint_id FOREIGN KEY (complaint_id)
        REFERENCES complaints (id) ON DELETE CASCADE,
    CONSTRAINT fk_complaint_actions_actor_user_id FOREIGN KEY (actor_user_id)
        REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT ck_complaint_actions_type CHECK (action_type IN (
        'NO_ACTION', 'HIDE_CONTENT', 'DELETE_CONTENT', 'WARN_USER',
        'SUSPEND_USER', 'HIDE_REPORT', 'REQUEST_REANALYSIS')),
    INDEX idx_complaint_actions_complaint_created_at (complaint_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='신고 처리 이력';

CREATE TABLE notification_device_tokens (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'Push 기기 Token ID',
    user_id BIGINT NOT NULL COMMENT '사용자 ID',
    token_ciphertext VARCHAR(1500) NOT NULL COMMENT '암호화된 Push Provider 기기 Token',
    token_hash CHAR(64) NOT NULL COMMENT '기기 Token SHA-256 Hash',
    platform VARCHAR(20) NOT NULL COMMENT '기기 Platform',
    push_provider VARCHAR(20) NOT NULL COMMENT 'Push Provider',
    is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT '활성 여부',
    last_used_at DATETIME(6) NULL COMMENT '마지막 사용 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_notification_device_tokens PRIMARY KEY (id),
    CONSTRAINT uk_notification_device_tokens_hash UNIQUE (token_hash),
    CONSTRAINT fk_notification_device_tokens_user_id FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT ck_notification_device_tokens_platform CHECK (platform IN ('ANDROID', 'IOS', 'WEB')),
    CONSTRAINT ck_notification_device_tokens_provider CHECK (push_provider IN ('FCM', 'APNS')),
    INDEX idx_notification_device_tokens_user_active (user_id, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Push 기기 Token';

CREATE TABLE activity_templates (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '미술 활동 자료 ID',
    expert_profile_id BIGINT NOT NULL COMMENT '전문가 프로필 ID',
    title VARCHAR(200) NOT NULL COMMENT '자료 제목',
    summary TEXT NULL COMMENT '자료 요약',
    content LONGTEXT NOT NULL COMMENT '자료 내용',
    age_group VARCHAR(30) NOT NULL COMMENT '권장 연령 그룹',
    activity_type VARCHAR(50) NOT NULL COMMENT '활동 유형',
    thumbnail_key VARCHAR(1000) NULL COMMENT 'Thumbnail 저장 Key',
    is_visible BOOLEAN NOT NULL DEFAULT TRUE COMMENT '공개 여부',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    deleted_at DATETIME(6) NULL COMMENT '삭제 일시',
    CONSTRAINT pk_activity_templates PRIMARY KEY (id),
    CONSTRAINT fk_activity_templates_expert_profile_id FOREIGN KEY (expert_profile_id)
        REFERENCES expert_profiles (id) ON DELETE RESTRICT,
    INDEX idx_activity_templates_expert_created_at (expert_profile_id, created_at),
    INDEX idx_activity_templates_visible_created_at (is_visible, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='미술 활동 자료';

CREATE TABLE activity_template_attachments (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '미술 활동 자료 첨부 파일 ID',
    activity_template_id BIGINT NOT NULL COMMENT '미술 활동 자료 ID',
    storage_key VARCHAR(1000) NOT NULL COMMENT '첨부 파일 저장 Key',
    storage_key_hash CHAR(64) NOT NULL COMMENT '첨부 파일 저장 Key SHA-256 Hash',
    file_name VARCHAR(255) NULL COMMENT '원본 파일명',
    mime_type VARCHAR(100) NULL COMMENT 'MIME 유형',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_activity_template_attachments PRIMARY KEY (id),
    CONSTRAINT uk_activity_template_attachments_key_hash UNIQUE (storage_key_hash),
    CONSTRAINT uk_activity_template_attachments_order UNIQUE (activity_template_id, display_order),
    CONSTRAINT fk_activity_template_attachments_template_id FOREIGN KEY (activity_template_id)
        REFERENCES activity_templates (id) ON DELETE CASCADE,
    CONSTRAINT ck_activity_template_attachments_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='미술 활동 자료 첨부 파일';

CREATE TABLE storage_deletion_jobs (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'Storage 삭제 작업 ID',
    storage_key VARCHAR(1000) NOT NULL COMMENT '삭제 대상 Storage Key',
    resource_type VARCHAR(50) NOT NULL COMMENT '연결 Resource 유형',
    resource_id BIGINT NULL COMMENT '연결 Resource ID',
    deletion_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '삭제 상태',
    retry_count SMALLINT NOT NULL DEFAULT 0 COMMENT '재시도 횟수',
    error_code VARCHAR(80) NULL COMMENT '마지막 오류 코드',
    requested_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '삭제 요청 일시',
    last_attempted_at DATETIME(6) NULL COMMENT '마지막 시도 일시',
    completed_at DATETIME(6) NULL COMMENT '삭제 완료 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_storage_deletion_jobs PRIMARY KEY (id),
    CONSTRAINT ck_storage_deletion_jobs_status
        CHECK (deletion_status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED')),
    CONSTRAINT ck_storage_deletion_jobs_retry_count CHECK (retry_count >= 0),
    INDEX idx_storage_deletion_jobs_status_requested_at (deletion_status, requested_at),
    INDEX idx_storage_deletion_jobs_resource (resource_type, resource_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Storage 삭제 작업';

ALTER TABLE users DROP COLUMN notification_settings_json;
ALTER TABLE children DROP COLUMN response_modes_json;
ALTER TABLE expert_profiles DROP COLUMN specialties_json, DROP COLUMN credentials_json;
ALTER TABLE stroke_batches DROP COLUMN payload_json;
ALTER TABLE consent_records DROP COLUMN evidence_json;
ALTER TABLE audit_logs DROP COLUMN resource_snapshot_json, DROP COLUMN before_json, DROP COLUMN after_json;
ALTER TABLE notifications DROP COLUMN data_json;
ALTER TABLE ai_question_templates DROP COLUMN risk_response_json, DROP COLUMN options_json;
ALTER TABLE conversation_messages
    DROP COLUMN options_json,
    DROP COLUMN selected_response_json,
    DROP COLUMN target_object_json;
ALTER TABLE drawing_sessions DROP COLUMN selected_emotions_json;
ALTER TABLE reports
    DROP COLUMN activity_summary_json,
    DROP COLUMN observed_features_json,
    DROP COLUMN key_conversations_json,
    DROP COLUMN evidence_json,
    DROP COLUMN follow_up_json,
    DROP COLUMN guardian_questions_json;
ALTER TABLE community_posts DROP COLUMN template_data_json;

DROP TABLE refresh_tokens;
