-- 사용자 및 동의 도메인
CREATE TABLE users (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '사용자 ID',
    role VARCHAR(20) NOT NULL COMMENT '사용자 역할',
    nickname VARCHAR(50) NULL COMMENT '닉네임',
    account_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '계정 상태',
    profile_image_url VARCHAR(1000) NULL COMMENT '프로필 이미지 URL',
    notification_settings_json JSON NULL COMMENT '알림 설정',
    is_completed BOOLEAN NOT NULL DEFAULT FALSE COMMENT '온보딩 완료 여부',
    last_login_at DATETIME(6) NULL COMMENT '마지막 로그인 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT ck_users_role CHECK (role IN ('GUARDIAN', 'EXPERT', 'ADMIN')),
    CONSTRAINT ck_users_account_status
        CHECK (account_status IN ('PENDING', 'ACTIVE', 'SUSPENDED', 'WITHDRAWN'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자';

CREATE TABLE children (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '아동 ID',
    nickname VARCHAR(50) NOT NULL COMMENT '닉네임',
    birth_date DATE NOT NULL COMMENT '생년월일',
    profile_image_url VARCHAR(1000) NULL COMMENT '프로필 이미지 URL',
    preferred_character VARCHAR(50) NULL COMMENT '선호 캐릭터',
    question_difficulty VARCHAR(30) NOT NULL DEFAULT 'PRESCHOOL' COMMENT '질문 난이도',
    response_modes_json JSON NULL COMMENT '응답 방식',
    tutorial_status VARCHAR(20) NOT NULL DEFAULT 'NOT_STARTED' COMMENT '튜토리얼 상태',
    profile_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '프로필 상태',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    deleted_at DATETIME(6) NULL COMMENT '삭제 일시',
    CONSTRAINT pk_children PRIMARY KEY (id),
    CONSTRAINT ck_children_question_difficulty
        CHECK (question_difficulty IN ('PRESCHOOL', 'LOWER_ELEMENTARY', 'UPPER_ELEMENTARY', 'SUPPORT')),
    CONSTRAINT ck_children_tutorial_status
        CHECK (tutorial_status IN ('NOT_STARTED', 'IN_PROGRESS', 'COMPLETED', 'SKIPPED')),
    CONSTRAINT ck_children_profile_status CHECK (profile_status IN ('ACTIVE', 'DELETED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='아동';

CREATE TABLE drawing_types (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '그림 활동 유형 ID',
    code VARCHAR(50) NOT NULL COMMENT '코드',
    name VARCHAR(100) NOT NULL COMMENT '그림 활동 유형명',
    activity_category VARCHAR(20) NOT NULL COMMENT '활동 분류',
    selectable_by VARCHAR(20) NOT NULL COMMENT '선택 가능 주체',
    recommended_age_min TINYINT NULL COMMENT '권장 최소 연령',
    recommended_age_max TINYINT NULL COMMENT '권장 최대 연령',
    guide_text TEXT NULL COMMENT '안내 문구',
    is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT '활성 여부',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_drawing_types PRIMARY KEY (id),
    CONSTRAINT uk_drawing_types_code UNIQUE (code),
    CONSTRAINT ck_drawing_types_activity_category
        CHECK (activity_category IN ('ASSESSMENT', 'GENERAL')),
    CONSTRAINT ck_drawing_types_selectable_by
        CHECK (selectable_by IN ('GUARDIAN', 'CHILD', 'BOTH')),
    CONSTRAINT ck_drawing_types_age_range
        CHECK (recommended_age_min IS NULL OR recommended_age_max IS NULL
            OR recommended_age_min <= recommended_age_max)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 유형';

CREATE TABLE consent_terms (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '동의 약관 ID',
    term_code VARCHAR(50) NOT NULL COMMENT '약관 코드',
    target_scope VARCHAR(10) NOT NULL COMMENT '동의 대상 범위',
    is_required BOOLEAN NOT NULL COMMENT '필수 여부',
    version VARCHAR(30) NOT NULL COMMENT '약관 버전',
    title VARCHAR(150) NOT NULL COMMENT '약관 제목',
    content_url VARCHAR(1000) NULL COMMENT '내용 URL',
    effective_at DATETIME(6) NOT NULL COMMENT '시행 일시',
    is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT '활성 여부',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_consent_terms PRIMARY KEY (id),
    CONSTRAINT uk_consent_terms_code_version UNIQUE (term_code, version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='동의 약관';

CREATE TABLE auth_accounts (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '인증 계정 ID',
    user_id BIGINT NOT NULL COMMENT '사용자 ID',
    provider VARCHAR(20) NOT NULL COMMENT '인증 제공자',
    provider_subject VARCHAR(255) NOT NULL COMMENT '인증 제공자 사용자 식별자',
    login_email VARCHAR(255) NULL COMMENT '로그인 이메일',
    local_login_email VARCHAR(255)
        GENERATED ALWAYS AS (CASE WHEN provider = 'LOCAL' THEN login_email ELSE NULL END) STORED
        COMMENT 'Local 인증 이메일 중복 검사용 생성값',
    password_hash VARCHAR(255) NULL COMMENT '비밀번호 해시',
    email_verified_at DATETIME(6) NULL COMMENT '이메일 인증 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_auth_accounts PRIMARY KEY (id),
    CONSTRAINT uk_auth_accounts_provider_subject UNIQUE (provider, provider_subject),
    CONSTRAINT uk_auth_accounts_local_login_email UNIQUE (local_login_email),
    CONSTRAINT fk_auth_accounts_user_id FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE,
    CONSTRAINT ck_auth_accounts_provider
        CHECK (provider IN ('LOCAL', 'KAKAO', 'GOOGLE', 'NAVER')),
    CONSTRAINT ck_auth_accounts_local_credentials
        CHECK (provider <> 'LOCAL' OR (login_email IS NOT NULL AND password_hash IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='인증 계정';

CREATE TABLE refresh_tokens (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'Refresh Token ID',
    user_id BIGINT NOT NULL COMMENT '사용자 ID',
    token_hash CHAR(64) NOT NULL COMMENT 'Token Hash',
    device_id VARCHAR(255) NULL COMMENT '기기 식별자',
    expires_at DATETIME(6) NOT NULL COMMENT '만료 일시',
    revoked_at DATETIME(6) NULL COMMENT '폐기 일시',
    last_used_at DATETIME(6) NULL COMMENT '마지막 사용 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_refresh_tokens PRIMARY KEY (id),
    CONSTRAINT fk_refresh_tokens_user_id FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE,
    INDEX idx_refresh_tokens_user_id (user_id),
    INDEX idx_refresh_tokens_token_hash (token_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Refresh Token';

CREATE TABLE expert_profiles (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '전문가 프로필 ID',
    display_name VARCHAR(80) NOT NULL COMMENT '표시 이름',
    profile_image_url VARCHAR(1000) NULL COMMENT '프로필 이미지 URL',
    organization VARCHAR(150) NULL COMMENT '소속 기관',
    position_title VARCHAR(100) NULL COMMENT '직책',
    career_years SMALLINT NOT NULL DEFAULT 0 COMMENT '경력 연수',
    specialties_json JSON NULL COMMENT '전문 분야',
    introduction TEXT NULL COMMENT '소개',
    is_consultation_available BOOLEAN NOT NULL DEFAULT FALSE COMMENT '상담 가능 여부',
    verification_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '검증 상태',
    credentials_json JSON NULL COMMENT '자격 증빙 정보',
    workplace VARCHAR(255) NULL COMMENT '근무지',
    contact_phone VARCHAR(30) NULL COMMENT '연락처',
    contact_email VARCHAR(255) NULL COMMENT '연락 이메일',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    deleted_at DATETIME(6) NULL COMMENT '삭제 일시',
    users_id BIGINT NOT NULL COMMENT '사용자 ID',
    CONSTRAINT pk_expert_profiles PRIMARY KEY (id),
    CONSTRAINT uk_expert_profiles_users_id UNIQUE (users_id),
    CONSTRAINT fk_expert_profiles_users_id FOREIGN KEY (users_id) REFERENCES users (id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_expert_profiles_verification_status
        CHECK (verification_status IN ('PENDING', 'VERIFIED', 'REJECTED', 'REVIEW_REQUIRED')),
    CONSTRAINT ck_expert_profiles_career_years CHECK (career_years >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 프로필';

CREATE TABLE expert_follows (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '전문가 팔로우 ID',
    guardian_user_id BIGINT NOT NULL COMMENT '보호자 사용자 ID',
    expert_profile_id BIGINT NOT NULL COMMENT '전문가 프로필 ID',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_expert_follows PRIMARY KEY (id),
    CONSTRAINT uk_expert_follows_guardian_expert UNIQUE (guardian_user_id, expert_profile_id),
    CONSTRAINT fk_expert_follows_guardian_user_id FOREIGN KEY (guardian_user_id)
        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_expert_follows_expert_profile_id FOREIGN KEY (expert_profile_id)
        REFERENCES expert_profiles (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 팔로우';

CREATE TABLE guardian_child_relations (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '보호자-아동 관계 ID',
    guardian_user_id BIGINT NOT NULL COMMENT '보호자 사용자 ID',
    child_id BIGINT NOT NULL COMMENT '아동 ID',
    relationship_type VARCHAR(30) NOT NULL COMMENT '관계 유형',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_guardian_child_relations PRIMARY KEY (id),
    CONSTRAINT uk_guardian_child_relations_guardian_child UNIQUE (guardian_user_id, child_id),
    CONSTRAINT fk_guardian_child_relations_guardian_id FOREIGN KEY (guardian_user_id)
        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_guardian_child_relations_child_id FOREIGN KEY (child_id)
        REFERENCES children (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='보호자-아동 관계';

CREATE TABLE consent_records (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '동의 이력 ID',
    consent_term_id BIGINT NOT NULL COMMENT '동의 약관 ID',
    actor_user_id BIGINT NULL COMMENT '처리 사용자 ID',
    subject_child_id BIGINT NULL COMMENT '동의 대상 아동 ID',
    subject_reference_hash CHAR(64) NOT NULL COMMENT '동의 대상 참조 Hash',
    action VARCHAR(20) NOT NULL COMMENT '동의 또는 철회 유형',
    ip_address VARCHAR(45) NULL COMMENT 'IP 주소',
    user_agent VARCHAR(500) NULL COMMENT 'User-Agent',
    evidence_json JSON NULL COMMENT '증빙 데이터',
    recorded_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '기록 일시',
    CONSTRAINT pk_consent_records PRIMARY KEY (id),
    CONSTRAINT fk_consent_records_term_id FOREIGN KEY (consent_term_id)
        REFERENCES consent_terms (id) ON DELETE RESTRICT,
    CONSTRAINT fk_consent_records_actor_user_id FOREIGN KEY (actor_user_id)
        REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_consent_records_subject_child_id FOREIGN KEY (subject_child_id)
        REFERENCES children (id) ON DELETE SET NULL,
    CONSTRAINT ck_consent_records_action CHECK (action IN ('AGREE', 'WITHDRAW')),
    INDEX idx_consent_records_subject_hash (subject_reference_hash, recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='동의 이력';

-- 그림 활동 및 대화 도메인
CREATE TABLE drawing_sessions (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '그림 활동 세션 ID',
    child_id BIGINT NOT NULL COMMENT '아동 ID',
    drawing_type_id BIGINT NOT NULL COMMENT '그림 활동 유형 ID',
    started_by_user_id BIGINT NULL COMMENT '시작 사용자 ID',
    input_method VARCHAR(20) NOT NULL COMMENT '입력 방식',
    title VARCHAR(200) NULL COMMENT '그림 제목',
    selected_emotions_json JSON NULL COMMENT '선택 감정',
    expressed_emotion_text TEXT NULL COMMENT '표현한 감정 내용',
    session_status VARCHAR(20) NOT NULL DEFAULT 'IN_PROGRESS' COMMENT '세션 상태',
    current_stage VARCHAR(30) NOT NULL DEFAULT 'DRAWING' COMMENT '현재 단계',
    started_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '시작 일시',
    completed_at DATETIME(6) NULL COMMENT '완료 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    deleted_at DATETIME(6) NULL COMMENT '삭제 일시',
    CONSTRAINT pk_drawing_sessions PRIMARY KEY (id),
    CONSTRAINT fk_drawing_sessions_child_id FOREIGN KEY (child_id) REFERENCES children (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_drawing_sessions_drawing_type_id FOREIGN KEY (drawing_type_id)
        REFERENCES drawing_types (id) ON DELETE RESTRICT,
    CONSTRAINT fk_drawing_sessions_started_by_user_id FOREIGN KEY (started_by_user_id)
        REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT ck_drawing_sessions_input_method CHECK (input_method IN ('CANVAS', 'UPLOAD')),
    CONSTRAINT ck_drawing_sessions_session_status
        CHECK (session_status IN ('IN_PROGRESS', 'COMPLETED', 'FAILED', 'DELETED')),
    CONSTRAINT ck_drawing_sessions_current_stage
        CHECK (current_stage IN ('DRAWING', 'ANALYZING', 'CONVERSING', 'REFLECTION', 'REPORTING', 'COMPLETED')),
    INDEX idx_drawing_sessions_child_id (child_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 세션';

CREATE TABLE stroke_batches (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'Stroke 배치 ID',
    drawing_session_id BIGINT NOT NULL COMMENT '그림 활동 세션 ID',
    batch_sequence INT NOT NULL COMMENT '배치 순번',
    first_event_sequence BIGINT NOT NULL COMMENT '첫 이벤트 순번',
    last_event_sequence BIGINT NOT NULL COMMENT '마지막 이벤트 순번',
    event_count INT NOT NULL COMMENT '이벤트 수',
    payload_json JSON NOT NULL COMMENT 'Stroke 데이터',
    client_created_at DATETIME(6) NULL COMMENT '클라이언트 생성 일시',
    received_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '수신 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_stroke_batches PRIMARY KEY (id),
    CONSTRAINT uk_stroke_batches_session_sequence UNIQUE (drawing_session_id, batch_sequence),
    CONSTRAINT fk_stroke_batches_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE CASCADE,
    CONSTRAINT ck_stroke_batches_sequence_range
        CHECK (first_event_sequence <= last_event_sequence),
    CONSTRAINT ck_stroke_batches_event_count CHECK (event_count > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stroke 배치';

CREATE TABLE drawing_assets (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '그림 파일 ID',
    drawing_session_id BIGINT NOT NULL COMMENT '그림 활동 세션 ID',
    asset_type VARCHAR(20) NOT NULL COMMENT '파일 유형',
    asset_version INT NOT NULL DEFAULT 1 COMMENT '파일 버전',
    storage_key VARCHAR(1000) NOT NULL COMMENT '파일 저장 Key',
    file_url VARCHAR(1000) NULL COMMENT '파일 URL',
    mime_type VARCHAR(100) NOT NULL COMMENT 'MIME 유형',
    file_size_bytes BIGINT NOT NULL COMMENT '파일 크기(Byte)',
    width_px INT NULL COMMENT '이미지 너비(px)',
    height_px INT NULL COMMENT '이미지 높이(px)',
    checksum_sha256 CHAR(64) NOT NULL COMMENT 'SHA-256 Checksum',
    expires_at DATETIME(6) NULL COMMENT '만료 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_drawing_assets PRIMARY KEY (id),
    CONSTRAINT fk_drawing_assets_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE CASCADE,
    CONSTRAINT ck_drawing_assets_asset_type
        CHECK (asset_type IN ('DRAFT', 'INTERMEDIATE', 'FINAL', 'UPLOADED', 'THUMBNAIL', 'TIMELAPSE')),
    CONSTRAINT ck_drawing_assets_file_size CHECK (file_size_bytes >= 0),
    INDEX idx_drawing_assets_session_type (drawing_session_id, asset_type, asset_version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 파일';

CREATE TABLE ai_question_templates (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'AI 질문 Template ID',
    drawing_type_id BIGINT NULL COMMENT '그림 활동 유형 ID',
    created_by_user_id BIGINT NULL COMMENT '생성자 사용자 ID',
    updated_by_user_id BIGINT NULL COMMENT '수정자 사용자 ID',
    template_type VARCHAR(20) NOT NULL COMMENT 'Template 유형',
    age_group VARCHAR(30) NOT NULL COMMENT '연령 그룹',
    difficulty VARCHAR(30) NOT NULL COMMENT '질문 난이도',
    question_purpose VARCHAR(50) NOT NULL COMMENT '질문 목적',
    question_text TEXT NOT NULL COMMENT '질문 내용',
    risk_response_json JSON NULL COMMENT '위험 응답 처리 정보',
    is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT '활성 여부',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    options_json JSON NULL COMMENT '응답 선택지',
    CONSTRAINT pk_ai_question_templates PRIMARY KEY (id),
    CONSTRAINT fk_ai_question_templates_drawing_type_id FOREIGN KEY (drawing_type_id)
        REFERENCES drawing_types (id) ON DELETE SET NULL,
    CONSTRAINT fk_ai_question_templates_created_by_id FOREIGN KEY (created_by_user_id)
        REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_ai_question_templates_updated_by_id FOREIGN KEY (updated_by_user_id)
        REFERENCES users (id) ON DELETE SET NULL,
    INDEX idx_ai_question_templates_lookup
        (drawing_type_id, age_group, difficulty, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='AI 질문 Template';

CREATE TABLE conversation_sessions (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '대화 세션 ID',
    conversation_status VARCHAR(20) NOT NULL DEFAULT 'CONVERSING' COMMENT '대화 상태',
    difficulty_snapshot VARCHAR(30) NOT NULL COMMENT '난이도 적용값',
    max_question_count SMALLINT NOT NULL DEFAULT 10 COMMENT '최대 질문 수',
    question_count SMALLINT NOT NULL DEFAULT 0 COMMENT '현재 질문 수',
    started_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '시작 일시',
    completed_at DATETIME(6) NULL COMMENT '완료 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    drawing_session_id BIGINT NOT NULL COMMENT '그림 활동 세션 ID',
    CONSTRAINT pk_conversation_sessions PRIMARY KEY (id),
    CONSTRAINT fk_conversation_sessions_drawing_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE CASCADE,
    CONSTRAINT ck_conversation_sessions_status
        CHECK (conversation_status IN ('CONVERSING', 'COMPLETED', 'FAILED')),
    CONSTRAINT ck_conversation_sessions_question_count
        CHECK (max_question_count > 0 AND question_count >= 0 AND question_count <= max_question_count),
    INDEX idx_conversation_sessions_drawing_session_id (drawing_session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 세션';

CREATE TABLE conversation_messages (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '대화 메시지 ID',
    conversation_session_id BIGINT NOT NULL COMMENT '대화 세션 ID',
    parent_message_id BIGINT NULL COMMENT '상위 메시지 ID',
    question_template_id BIGINT NULL COMMENT '질문 Template ID',
    message_sequence INT NOT NULL COMMENT '메시지 순번',
    sender_type VARCHAR(20) NOT NULL COMMENT '발신자 유형',
    message_type VARCHAR(30) NOT NULL COMMENT '메시지 유형',
    raw_text TEXT NULL COMMENT '원문 Text',
    stt_text TEXT NULL COMMENT '음성 인식 Text',
    options_json JSON NULL COMMENT '응답 선택지',
    selected_response_json JSON NULL COMMENT '선택 응답',
    audio_storage_key VARCHAR(1000) NULL COMMENT '음성 파일 저장 Key',
    audio_url VARCHAR(1000) NULL COMMENT '음성 파일 URL',
    speech_status VARCHAR(20) NULL COMMENT '음성 처리 상태',
    target_object_json JSON NULL COMMENT '대상 객체 및 Bounding Box',
    is_skipped BOOLEAN NOT NULL DEFAULT FALSE COMMENT '건너뜀 여부',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_conversation_messages PRIMARY KEY (id),
    CONSTRAINT uk_conversation_messages_session_sequence
        UNIQUE (conversation_session_id, message_sequence),
    CONSTRAINT fk_conversation_messages_session_id FOREIGN KEY (conversation_session_id)
        REFERENCES conversation_sessions (id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_messages_parent_message_id FOREIGN KEY (parent_message_id)
        REFERENCES conversation_messages (id) ON DELETE SET NULL,
    CONSTRAINT fk_conversation_messages_template_id FOREIGN KEY (question_template_id)
        REFERENCES ai_question_templates (id) ON DELETE SET NULL,
    CONSTRAINT ck_conversation_messages_sender_type
        CHECK (sender_type IN ('AI', 'CHILD', 'GUARDIAN', 'SYSTEM')),
    CONSTRAINT ck_conversation_messages_message_type
        CHECK (message_type IN ('QUESTION', 'VOICE_ANSWER', 'OPTION_ANSWER', 'TEXT_ANSWER', 'SYSTEM_NOTICE')),
    CONSTRAINT ck_conversation_messages_speech_status
        CHECK (speech_status IS NULL OR speech_status IN ('NOT_REQUIRED', 'PENDING', 'PROCESSING', 'SUCCESS', 'FAILED')),
    INDEX idx_conversation_messages_parent_message_id (parent_message_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지';

-- 분석 및 리포트 도메인
CREATE TABLE analyses (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '분석 ID',
    drawing_session_id BIGINT NOT NULL COMMENT '그림 활동 세션 ID',
    retry_of_analysis_id BIGINT NULL COMMENT '재시도 원본 분석 ID',
    analysis_type VARCHAR(20) NOT NULL COMMENT '분석 유형',
    idempotency_key VARCHAR(100) NOT NULL COMMENT 'Idempotency Key',
    input_checksum_sha256 CHAR(64) NULL COMMENT '입력 SHA-256 Checksum',
    analysis_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '분석 상태',
    trigger_reason VARCHAR(30) NULL COMMENT '분석 실행 사유',
    model_name VARCHAR(100) NULL COMMENT 'Model 이름',
    model_version VARCHAR(100) NULL COMMENT 'Model 버전',
    confidence DECIMAL(5,4) NULL COMMENT '신뢰도',
    error_code VARCHAR(80) NULL COMMENT '오류 코드',
    error_message TEXT NULL COMMENT '오류 메시지',
    requested_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '요청 일시',
    started_at DATETIME(6) NULL COMMENT '시작 일시',
    completed_at DATETIME(6) NULL COMMENT '분석 완료 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_analyses PRIMARY KEY (id),
    CONSTRAINT uk_analyses_idempotency_key UNIQUE (idempotency_key),
    CONSTRAINT fk_analyses_drawing_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE CASCADE,
    CONSTRAINT fk_analyses_retry_of_analysis_id FOREIGN KEY (retry_of_analysis_id)
        REFERENCES analyses (id) ON DELETE SET NULL,
    CONSTRAINT ck_analyses_type CHECK (analysis_type IN ('INTERMEDIATE', 'FINAL')),
    CONSTRAINT ck_analyses_status
        CHECK (analysis_status IN ('PENDING', 'PROCESSING', 'PARTIAL_SUCCESS', 'SUCCESS', 'FAILED')),
    CONSTRAINT ck_analyses_trigger_reason
        CHECK (trigger_reason IS NULL OR trigger_reason IN
            ('PAUSE', 'INTERVAL', 'STROKE_COUNT', 'CHANGE_RATIO', 'USER_REQUEST',
             'DRAWING_COMPLETE', 'ACTIVITY_COMPLETE', 'RETRY')),
    CONSTRAINT ck_analyses_confidence
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    INDEX idx_analyses_drawing_session_id (drawing_session_id, requested_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석';

CREATE TABLE analysis_visual_features (
    visual_feature_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '시각 특징 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    canvas_coverage_ratio DECIMAL(5,4) NULL COMMENT 'Canvas 점유 비율',
    primary_color VARCHAR(20) NULL COMMENT '주요 색상',
    primary_color_ratio DECIMAL(5,4) NULL COMMENT '주요 색상 비율',
    used_color_count INT NULL COMMENT '사용 색상 수',
    average_brightness DECIMAL(6,3) NULL COMMENT '평균 명도',
    average_saturation DECIMAL(6,3) NULL COMMENT '평균 채도',
    average_line_thickness DECIMAL(8,3) NULL COMMENT '평균 선 굵기',
    line_thickness_deviation DECIMAL(8,3) NULL COMMENT '선 굵기 편차',
    edge_density DECIMAL(5,4) NULL COMMENT 'Edge 밀도',
    fill_ratio DECIMAL(5,4) NULL COMMENT '채움 비율',
    overlap_ratio DECIMAL(5,4) NULL COMMENT '겹침 비율',
    symmetry_score DECIMAL(5,4) NULL COMMENT '대칭 점수',
    center_of_mass_x DECIMAL(8,6) NULL COMMENT '무게 중심 X 좌표',
    center_of_mass_y DECIMAL(8,6) NULL COMMENT '무게 중심 Y 좌표',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_analysis_visual_features PRIMARY KEY (visual_feature_id),
    CONSTRAINT fk_analysis_visual_features_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    INDEX idx_analysis_visual_features_analysis_id (analysis_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 시각 특징';

CREATE TABLE analysis_behavior_features (
    behavior_feature_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '행동 특징 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    input_method VARCHAR(30) NULL COMMENT '입력 방식',
    drawing_duration_ms BIGINT NULL COMMENT '그림 소요 시간(ms)',
    active_drawing_duration_ms BIGINT NULL COMMENT '실제 그림 시간(ms)',
    pause_count INT NULL COMMENT '일시 정지 횟수',
    total_pause_duration_ms BIGINT NULL COMMENT '전체 일시 정지 시간(ms)',
    stroke_count INT NULL COMMENT 'Stroke 수',
    average_stroke_speed DECIMAL(10,3) NULL COMMENT '평균 Stroke 속도',
    average_stroke_length DECIMAL(10,3) NULL COMMENT '평균 Stroke 길이',
    undo_count INT NULL COMMENT '실행 취소 횟수',
    redo_count INT NULL COMMENT '다시 실행 횟수',
    erase_count INT NULL COMMENT '지우기 횟수',
    canvas_clear_count INT NULL COMMENT 'Canvas 전체 지우기 횟수',
    tool_change_count INT NULL COMMENT '도구 변경 횟수',
    color_change_count INT NULL COMMENT '색상 변경 횟수',
    average_pressure DECIMAL(8,3) NULL COMMENT '평균 압력',
    pressure_deviation DECIMAL(8,3) NULL COMMENT '압력 편차',
    save_count INT NULL COMMENT '저장 횟수',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_analysis_behavior_features PRIMARY KEY (behavior_feature_id),
    CONSTRAINT fk_analysis_behavior_features_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    CONSTRAINT ck_analysis_behavior_features_input_method
        CHECK (input_method IS NULL OR input_method IN ('CANVAS', 'UPLOAD')),
    INDEX idx_analysis_behavior_features_analysis_id (analysis_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 행동 특징';

CREATE TABLE analysis_detected_objects (
    detected_object_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '탐지 객체 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    drawing_asset_id BIGINT NOT NULL COMMENT '그림 파일 ID',
    object_code VARCHAR(50) NULL COMMENT '객체 코드',
    object_name VARCHAR(100) NULL COMMENT '객체명',
    confidence_score DECIMAL(5,4) NULL COMMENT '신뢰도 점수',
    bbox_x DECIMAL(8,6) NULL COMMENT 'Bounding Box X 좌표',
    bbox_y DECIMAL(8,6) NULL COMMENT 'Bounding Box Y 좌표',
    bbox_width DECIMAL(8,6) NULL COMMENT 'Bounding Box 너비',
    bbox_height DECIMAL(8,6) NULL COMMENT 'Bounding Box 높이',
    area_ratio DECIMAL(8,6) NULL COMMENT '면적 비율',
    detection_order INT NULL COMMENT '탐지 순서',
    model_version VARCHAR(50) NULL COMMENT 'Model 버전',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_analysis_detected_objects PRIMARY KEY (detected_object_id),
    CONSTRAINT fk_analysis_detected_objects_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    CONSTRAINT fk_analysis_detected_objects_drawing_asset_id FOREIGN KEY (drawing_asset_id)
        REFERENCES drawing_assets (id) ON DELETE CASCADE,
    CONSTRAINT ck_analysis_detected_objects_confidence
        CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
    INDEX idx_analysis_detected_objects_analysis_id (analysis_id),
    INDEX idx_analysis_detected_objects_drawing_asset_id (drawing_asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 탐지 객체';

CREATE TABLE analysis_observation_results (
    observation_result_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '관찰 결과 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    result_version INT NULL COMMENT '결과 버전',
    overall_summary TEXT NULL COMMENT '전체 요약',
    observed_emotion VARCHAR(50) NULL COMMENT '전문가 내부 검토용 관찰 감정',
    emotion_confidence DECIMAL(5,4) NULL COMMENT '전문가 내부 검토용 감정 신뢰도',
    positive_signals TEXT NULL COMMENT '긍정 신호',
    attention_points TEXT NULL COMMENT '관찰 필요 지점',
    evidence_summary TEXT NULL COMMENT '근거 요약',
    guardian_guidance TEXT NULL COMMENT '보호자 안내',
    follow_up_question TEXT NULL COMMENT '후속 질문',
    is_expert_review_required BOOLEAN NULL COMMENT '전문가 검토 필요 여부',
    review_status VARCHAR(30) NULL COMMENT '검토 상태',
    reviewed_at DATETIME(6) NULL COMMENT '검토 일시',
    disclaimer_text TEXT NULL COMMENT '주의 문구',
    generated_model_version VARCHAR(50) NULL COMMENT '생성 Model 버전',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_analysis_observation_results PRIMARY KEY (observation_result_id),
    CONSTRAINT fk_analysis_observation_results_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    CONSTRAINT ck_analysis_observation_results_emotion_confidence
        CHECK (emotion_confidence IS NULL OR (emotion_confidence >= 0 AND emotion_confidence <= 1)),
    INDEX idx_analysis_observation_results_analysis_id (analysis_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 관찰 결과';

CREATE TABLE analysis_unused_inputs (
    unused_input_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '분석 제외 입력 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    source_type VARCHAR(30) NULL COMMENT '입력 출처 유형',
    source_id BIGINT NULL COMMENT '입력 출처 ID',
    input_name VARCHAR(100) NULL COMMENT '입력 이름',
    input_sequence INT NULL COMMENT '입력 순번',
    input_value_summary TEXT NULL COMMENT '입력값 요약',
    excluded_reason_code VARCHAR(50) NULL COMMENT '제외 사유 코드',
    excluded_reason_detail TEXT NULL COMMENT '제외 사유 상세',
    validation_status VARCHAR(30) NULL COMMENT '검증 상태',
    retryable BOOLEAN NULL COMMENT '재시도 가능 여부',
    occurred_at DATETIME(6) NULL COMMENT '발생 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_analysis_unused_inputs PRIMARY KEY (unused_input_id),
    CONSTRAINT fk_analysis_unused_inputs_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    INDEX idx_analysis_unused_inputs_analysis_id (analysis_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 제외 입력';

CREATE TABLE analysis_conversation_summaries (
    conversation_summary_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '대화 분석 요약 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    conversation_session_id BIGINT NULL COMMENT '대화 세션 ID',
    summary_text TEXT NULL COMMENT '요약 내용',
    main_topic VARCHAR(100) NULL COMMENT '주요 주제',
    secondary_topic VARCHAR(100) NULL COMMENT '보조 주제',
    expressed_emotion VARCHAR(50) NULL COMMENT '표현 감정',
    emotion_source VARCHAR(30) NULL COMMENT '감정 출처',
    emotion_need VARCHAR(255) NULL COMMENT '감정 관련 필요',
    question_count INT NULL COMMENT '질문 수',
    response_count INT NULL COMMENT '응답 수',
    skipped_question_count INT NULL COMMENT '건너뛴 질문 수',
    unrecognized_speech_count INT NULL COMMENT '음성 인식 실패 수',
    representative_utterance TEXT NULL COMMENT '대표 발화',
    unanswered_topic TEXT NULL COMMENT '미응답 주제',
    summary_model_version VARCHAR(50) NULL COMMENT '요약 Model 버전',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_analysis_conversation_summaries PRIMARY KEY (conversation_summary_id),
    CONSTRAINT fk_analysis_conversation_summaries_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    CONSTRAINT fk_analysis_conversation_summaries_session_id FOREIGN KEY (conversation_session_id)
        REFERENCES conversation_sessions (id) ON DELETE SET NULL,
    INDEX idx_analysis_conversation_summaries_analysis_id (analysis_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 분석 요약';

CREATE TABLE reports (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 ID',
    drawing_session_id BIGINT NOT NULL COMMENT '그림 활동 세션 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    report_version INT NOT NULL DEFAULT 1 COMMENT '리포트 버전',
    report_status VARCHAR(20) NOT NULL DEFAULT 'GENERATING' COMMENT '리포트 상태',
    activity_summary_json JSON NULL COMMENT '활동 요약',
    observed_features_json JSON NULL COMMENT '관찰 특징',
    key_conversations_json JSON NULL COMMENT '주요 대화',
    evidence_json JSON NULL COMMENT '증빙 데이터',
    follow_up_json JSON NULL COMMENT '후속 안내',
    guardian_questions_json JSON NULL COMMENT '보호자 질문',
    is_expert_review_recommended BOOLEAN NOT NULL DEFAULT FALSE COMMENT '전문가 검토 권장 여부',
    limitations_text TEXT NOT NULL COMMENT '한계 및 주의 문구',
    pdf_storage_key VARCHAR(1000) NULL COMMENT 'PDF 저장 Key',
    pdf_url VARCHAR(1000) NULL COMMENT 'PDF URL',
    hidden_at DATETIME(6) NULL COMMENT '숨김 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '리포트 생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '리포트 수정 일시',
    CONSTRAINT pk_reports PRIMARY KEY (id),
    CONSTRAINT uk_reports_session_version UNIQUE (drawing_session_id, report_version),
    CONSTRAINT fk_reports_drawing_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE RESTRICT,
    CONSTRAINT fk_reports_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE RESTRICT,
    CONSTRAINT ck_reports_status
        CHECK (report_status IN ('GENERATING', 'COMPLETED', 'FAILED', 'HIDDEN')),
    INDEX idx_reports_drawing_session_id (drawing_session_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트';

-- 커뮤니티 및 운영 도메인
CREATE TABLE community_posts (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '게시글 ID',
    author_user_id BIGINT NULL COMMENT '작성자 사용자 ID',
    post_type VARCHAR(40) NOT NULL COMMENT '게시글 유형',
    title VARCHAR(200) NOT NULL COMMENT '게시글 제목',
    content LONGTEXT NOT NULL COMMENT '게시글 내용',
    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE COMMENT '익명 여부',
    is_visible BOOLEAN NOT NULL DEFAULT TRUE COMMENT '공개 여부',
    template_data_json JSON NULL COMMENT 'Template 데이터',
    post_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '게시글 상태',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    deleted_at DATETIME(6) NULL COMMENT '삭제 일시',
    CONSTRAINT pk_community_posts PRIMARY KEY (id),
    CONSTRAINT fk_community_posts_author_user_id FOREIGN KEY (author_user_id)
        REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT ck_community_posts_type
        CHECK (post_type IN ('GUARDIAN_STORY', 'ACTIVITY_REVIEW', 'EXPERT_COLUMN',
            'ART_RESOURCE', 'DRAWING_GUIDE', 'EXPERT_QNA', 'NOTICE')),
    CONSTRAINT ck_community_posts_status
        CHECK (post_status IN ('ACTIVE', 'HIDDEN', 'DELETED')),
    INDEX idx_community_posts_author_created_at (author_user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='커뮤니티 게시글';

CREATE TABLE comments (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '댓글 ID',
    post_id BIGINT NOT NULL COMMENT '게시글 ID',
    author_user_id BIGINT NULL COMMENT '작성자 사용자 ID',
    content TEXT NOT NULL COMMENT '댓글 내용',
    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE COMMENT '익명 여부',
    is_visible BOOLEAN NOT NULL DEFAULT TRUE COMMENT '공개 여부',
    comment_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '댓글 상태',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    deleted_at DATETIME(6) NULL COMMENT '삭제 일시',
    CONSTRAINT pk_comments PRIMARY KEY (id),
    CONSTRAINT fk_comments_post_id FOREIGN KEY (post_id) REFERENCES community_posts (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_comments_author_user_id FOREIGN KEY (author_user_id) REFERENCES users (id)
        ON DELETE SET NULL,
    CONSTRAINT ck_comments_status CHECK (comment_status IN ('ACTIVE', 'HIDDEN', 'DELETED')),
    INDEX idx_comments_author_user_id (author_user_id),
    INDEX idx_comments_post_created_at (post_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='댓글';

CREATE TABLE post_likes (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '게시글 좋아요 ID',
    post_id BIGINT NOT NULL COMMENT '게시글 ID',
    user_id BIGINT NOT NULL COMMENT '사용자 ID',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_post_likes PRIMARY KEY (id),
    CONSTRAINT uk_post_likes_post_user UNIQUE (post_id, user_id),
    CONSTRAINT fk_post_likes_post_id FOREIGN KEY (post_id) REFERENCES community_posts (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_post_likes_user_id FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='게시글 좋아요';

CREATE TABLE notifications (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '알림 ID',
    recipient_user_id BIGINT NOT NULL COMMENT '수신자 사용자 ID',
    notification_type VARCHAR(40) NOT NULL COMMENT '알림 유형',
    title VARCHAR(200) NOT NULL COMMENT '알림 제목',
    content TEXT NOT NULL COMMENT '알림 내용',
    related_post_id BIGINT NULL COMMENT '관련 게시글 ID',
    related_report_id BIGINT NULL COMMENT '관련 리포트 ID',
    related_drawing_session_id BIGINT NULL COMMENT '관련 그림 활동 세션 ID',
    data_json JSON NULL COMMENT '추가 데이터',
    delivery_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '전송 상태',
    read_at DATETIME(6) NULL COMMENT '읽은 일시',
    sent_at DATETIME(6) NULL COMMENT '전송 일시',
    failed_at DATETIME(6) NULL COMMENT '실패 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_notifications PRIMARY KEY (id),
    CONSTRAINT fk_notifications_recipient_user_id FOREIGN KEY (recipient_user_id)
        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_related_post_id FOREIGN KEY (related_post_id)
        REFERENCES community_posts (id) ON DELETE SET NULL,
    CONSTRAINT fk_notifications_related_report_id FOREIGN KEY (related_report_id)
        REFERENCES reports (id) ON DELETE SET NULL,
    CONSTRAINT fk_notifications_related_drawing_session_id FOREIGN KEY (related_drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE SET NULL,
    CONSTRAINT ck_notifications_type
        CHECK (notification_type IN ('ANALYSIS_COMPLETED', 'ANALYSIS_FAILED', 'REPORT_COMPLETED',
            'NEW_EXPERT_POST', 'COMMENT_CREATED', 'CONSENT_UPDATED', 'RETENTION_NOTICE',
            'ACTIVITY_REMINDER', 'RISK_REVIEW_GUIDE')),
    CONSTRAINT ck_notifications_delivery_status
        CHECK (delivery_status IN ('PENDING', 'SENT', 'FAILED')),
    INDEX idx_notifications_recipient_created_at (recipient_user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='알림';

CREATE TABLE audit_logs (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '감사 로그 ID',
    actor_user_id BIGINT NULL COMMENT '처리 사용자 ID',
    action_type VARCHAR(80) NOT NULL COMMENT '행위 유형',
    resource_type VARCHAR(50) NOT NULL COMMENT '대상 Resource 유형',
    resource_id BIGINT NULL COMMENT '대상 Resource ID',
    resource_snapshot_json JSON NULL COMMENT '대상 Resource Snapshot',
    ip_address VARCHAR(45) NULL COMMENT 'IP 주소',
    before_json JSON NULL COMMENT '변경 전 데이터',
    after_json JSON NULL COMMENT '변경 후 데이터',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_audit_logs PRIMARY KEY (id),
    CONSTRAINT fk_audit_logs_actor_user_id FOREIGN KEY (actor_user_id) REFERENCES users (id)
        ON DELETE SET NULL,
    INDEX idx_audit_logs_resource (resource_type, resource_id, created_at),
    INDEX idx_audit_logs_actor_user_id (actor_user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='감사 로그';
