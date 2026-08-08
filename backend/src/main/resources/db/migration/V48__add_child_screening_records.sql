-- 보호자가 입력한 표준화 선별 결과 기록 (V4 5층)
--
-- 이 서비스는 선별검사를 **실시하지도 채점하지도 않는다.** 보호자가 이미 다른 곳에서 받은
-- 결과를 옮겨 적어 두고, 리포트에서 AI 관찰과 분리해 보여 주기 위한 표다.
--
-- ⚠️ 문항·채점키·규준표·절단점은 절대 들어오지 않는다. 들어오는 순간 라이선스 위반이자
--    무면허 검사도구가 된다. 이 표에는 **결과 라벨과 그 출처**만 남는다.
--
-- ⚠️ source_verified 는 지금 항상 FALSE 다. 공식 서비스 연동이 없어 보호자 입력을 검증할
--    방법이 없기 때문이다. 그래서 화면은 이 기록을 '보호자가 입력한 기록'으로만 보여 주고
--    공식 결과(COMPLETED_OFFICIAL_RESULT)로 표시하지 않는다 — 검증되지 않은 값을 공식
--    결과처럼 보여 주는 것이 이 기능에서 가장 위험한 실패다.
--
-- payload_hash 는 등록 당시 요청 본문의 해시다. 나중에 값이 바뀌었는지 확인할 수 있게
-- 원본을 고정해 둔다.

CREATE TABLE child_screening_records (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '선별 결과 기록 ID',
    child_id BIGINT NOT NULL COMMENT '아동 ID',
    instrument_id VARCHAR(40) NOT NULL COMMENT '등록부 allow-list 안의 도구 식별자',
    instrument_version VARCHAR(60) NULL COMMENT '보호자가 적은 도구 버전',
    respondent VARCHAR(20) NOT NULL COMMENT 'GUARDIAN·TEACHER·CHILD',
    completed_at DATE NOT NULL COMMENT '검사 실시일',
    child_age_months_at_administration SMALLINT NULL COMMENT '실시 당시 아동 개월 나이',
    source_authority_type VARCHAR(30) NOT NULL COMMENT 'OFFICIAL_SERVICE·GUARDIAN_REPORTED·CLINICIAN_REPORTED',
    source_authority_name VARCHAR(150) NOT NULL COMMENT '결과를 발급한 곳',
    source_verified BOOLEAN NOT NULL DEFAULT FALSE COMMENT '출처 검증 여부. 공식 연동이 없어 현재 항상 FALSE',
    verification_method VARCHAR(150) NULL COMMENT '검증 방법이며 미검증이면 NULL',
    official_result_code VARCHAR(60) NULL COMMENT '공식 결과 코드를 그대로',
    official_result_text VARCHAR(500) NOT NULL COMMENT '공식 결과 문구를 변경 없이',
    diagnostic_status VARCHAR(30) NOT NULL DEFAULT 'SCREENING_NOT_DIAGNOSIS' COMMENT '선별은 진단이 아니라는 고정 표기',
    scored_by VARCHAR(30) NOT NULL COMMENT '채점 주체. 이 서비스는 절대 채점하지 않는다',
    ai_recalculated BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'AI 재계산 여부. 항상 FALSE',
    followup_level VARCHAR(40) NULL COMMENT 'NONE·DISCUSS_WITH_GUARDIAN·SCHEDULE_FURTHER_EVALUATION',
    followup_message VARCHAR(500) NULL COMMENT '보호자에게 보이는 후속 안내',
    consent_record_id BIGINT NOT NULL COMMENT '이 기록을 남길 때 확인한 동의 이력 ID',
    source_document_ref VARCHAR(300) NULL COMMENT '원본 문서 참조',
    payload_hash CHAR(64) NOT NULL COMMENT '등록 당시 요청 본문의 SHA-256',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '등록 일시',
    deleted_at DATETIME(6) NULL COMMENT '보호자 삭제 일시. 삭제권 행사 시각을 남긴다',
    CONSTRAINT pk_child_screening_records PRIMARY KEY (id),
    CONSTRAINT fk_child_screening_records_child_id FOREIGN KEY (child_id)
        REFERENCES children (id) ON DELETE CASCADE,
    CONSTRAINT fk_child_screening_records_consent_record_id FOREIGN KEY (consent_record_id)
        REFERENCES consent_records (id),
    CONSTRAINT ck_child_screening_records_not_scored_here CHECK (ai_recalculated = FALSE),
    INDEX idx_child_screening_records_child (child_id, deleted_at, completed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='보호자가 입력한 표준화 선별 결과';

-- 영역별 결과 라벨. **점수가 아니라 라벨만** 담는다 — 원점수·규준점수는 도구 계약과 전문가
-- 정책이 정하는 값이고, 이 서비스에는 그것을 해석할 권한이 없다.
CREATE TABLE child_screening_record_domains (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '영역 결과 ID',
    screening_record_id BIGINT NOT NULL COMMENT '선별 결과 기록 ID',
    domain_name VARCHAR(60) NOT NULL COMMENT '영역 이름을 공식 결과지 그대로',
    result_label VARCHAR(120) NOT NULL COMMENT '영역 결과 라벨을 공식 결과지 그대로',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_child_screening_record_domains PRIMARY KEY (id),
    CONSTRAINT uk_child_screening_record_domains_slot UNIQUE (screening_record_id, display_order),
    CONSTRAINT fk_child_screening_record_domains_record_id FOREIGN KEY (screening_record_id)
        REFERENCES child_screening_records (id) ON DELETE CASCADE,
    CONSTRAINT ck_child_screening_record_domains_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='선별 결과의 영역별 라벨';

-- 후속 상담을 어디로 가면 되는지. 결과 자체가 아니라 다음 걸음을 알려 주는 자리다.
CREATE TABLE child_screening_referral_options (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '후속 경로 ID',
    screening_record_id BIGINT NOT NULL COMMENT '선별 결과 기록 ID',
    referral_option VARCHAR(120) NOT NULL COMMENT '소아청소년과·발달클리닉 등',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_child_screening_referral_options PRIMARY KEY (id),
    CONSTRAINT uk_child_screening_referral_options_slot UNIQUE (screening_record_id, display_order),
    CONSTRAINT fk_child_screening_referral_options_record_id FOREIGN KEY (screening_record_id)
        REFERENCES child_screening_records (id) ON DELETE CASCADE,
    CONSTRAINT ck_child_screening_referral_options_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='선별 결과의 후속 상담 경로';

-- 임상 기록 보관 동의. 이 약관에 동의한 이력이 없으면 기록을 남길 수 없다.
-- 아동 단위 약관이며 선택 동의다 — 서비스를 쓰기 위해 의료 기록을 내놓게 하지 않는다.
INSERT INTO consent_terms
    (term_code, target_scope, is_required, version, title, content_url, content_html,
     effective_at, is_active, created_at)
VALUES
    ('CHILD_CLINICAL_RECORD', 'CHILD', FALSE, '1.0',
     '아이의 검사·평가 기록 보관 동의', NULL, NULL,
     '2026-08-08 00:00:00.000000', TRUE, '2026-08-08 00:00:00.000000');
