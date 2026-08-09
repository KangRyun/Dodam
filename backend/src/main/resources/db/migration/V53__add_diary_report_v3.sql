-- 그림일기 리포트 V3: 자료 범위, 이야기 구성, 그림 관찰, 전체 대화 스냅샷을 정규화한다.
-- 음성 URL·Storage Key는 저장하지 않는다. 조회 시 메시지 ID로 인증 Proxy URL을 조립한다.

ALTER TABLE report_diary_insights
    ADD COLUMN schema_version SMALLINT NOT NULL DEFAULT 2 COMMENT '그림일기 구조 버전' AFTER report_id,
    ADD COLUMN evidence_level VARCHAR(20) NULL COMMENT 'LIMITED·PARTIAL·RICH' AFTER schema_version,
    ADD COLUMN data_scope_summary VARCHAR(300) NULL COMMENT '자료 범위 설명' AFTER evidence_level,
    ADD COLUMN visual_observation_count SMALLINT NOT NULL DEFAULT 0 COMMENT '그림 관찰 건수' AFTER data_scope_summary,
    ADD CONSTRAINT ck_report_diary_insights_schema_version CHECK (schema_version >= 2),
    ADD CONSTRAINT ck_report_diary_insights_evidence_level
        CHECK (evidence_level IS NULL OR evidence_level IN ('LIMITED', 'PARTIAL', 'RICH')),
    ADD CONSTRAINT ck_report_diary_insights_visual_count CHECK (visual_observation_count >= 0);

CREATE TABLE report_diary_story_components (
    id BIGINT NOT NULL AUTO_INCREMENT,
    report_id BIGINT NOT NULL,
    component_type VARCHAR(30) NOT NULL COMMENT '이야기 구성 요소 종류',
    confirmation_status VARCHAR(20) NOT NULL COMMENT 'CONFIRMED·VISUAL_ONLY·SELECTED·PARTIAL·UNKNOWN',
    text TEXT NULL COMMENT '확인된 내용이며 UNKNOWN이면 null 가능',
    display_order SMALLINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_report_diary_story_component (report_id, component_type),
    CONSTRAINT fk_report_diary_story_component_report
        FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_story_component_order CHECK (display_order >= 0),
    CONSTRAINT ck_report_diary_story_component_status
        CHECK (confirmation_status IN ('CONFIRMED', 'VISUAL_ONLY', 'SELECTED', 'PARTIAL', 'UNKNOWN'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE report_diary_visual_observations (
    id BIGINT NOT NULL AUTO_INCREMENT,
    report_id BIGINT NOT NULL,
    text TEXT NOT NULL COMMENT '그림에서 직접 확인한 사실',
    confidence VARCHAR(20) NOT NULL COMMENT 'HIGH·MODERATE·LOW',
    child_confirmed TINYINT(1) NOT NULL DEFAULT 0 COMMENT '아이 발화로 확인됐는지 여부',
    display_order SMALLINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_report_diary_visual_observation_order (report_id, display_order),
    CONSTRAINT fk_report_diary_visual_observation_report
        FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_visual_observation_order CHECK (display_order >= 0),
    CONSTRAINT ck_report_diary_visual_observation_confidence
        CHECK (confidence IN ('HIGH', 'MODERATE', 'LOW'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE report_diary_transcript_entries (
    id BIGINT NOT NULL AUTO_INCREMENT,
    report_id BIGINT NOT NULL,
    question_message_id BIGINT NULL,
    answer_message_id BIGINT NULL,
    question_text TEXT NOT NULL,
    answer_text TEXT NULL,
    response_type VARCHAR(20) NOT NULL COMMENT 'VOICE·OPTION·TEXT·SKIPPED·CORRECTION',
    stt_status VARCHAR(30) NULL,
    audio_available_at_generation TINYINT(1) NOT NULL DEFAULT 0,
    audio_duration_ms INT NULL COMMENT '현재 수집하지 않으며 향후 실제 값이 있을 때만 저장',
    elicitation_type VARCHAR(30) NOT NULL,
    occurred_at DATETIME(6) NULL COMMENT '답변 메시지 시각이며 과거 데이터는 null 가능',
    display_order SMALLINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_report_diary_transcript_order (report_id, display_order),
    CONSTRAINT fk_report_diary_transcript_report
        FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_transcript_order CHECK (display_order >= 0),
    CONSTRAINT ck_report_diary_transcript_response_type
        CHECK (response_type IN ('VOICE', 'OPTION', 'TEXT', 'SKIPPED', 'CORRECTION')),
    CONSTRAINT ck_report_diary_transcript_audio_duration
        CHECK (audio_duration_ms IS NULL OR audio_duration_ms >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
