-- S15P11B209-900 보호자 리포트의 비진단 경향 해석과 그 근거를 저장한다.
--
-- 기존 report_observed_features 를 재사용하지 않는다. 그 경로는
-- ObservationReportPersistenceService.resolveVisibility() 가 expertReviewed 가 아닌 모든 항목을
-- EXPERT_ONLY 로 강등하고, expertReviewed 는 전이 코드가 없어 항상 false 이므로 경향 해석을 실으면
-- 전부 숨겨진다(계약 report-detail-guardian-contract.md §4-2 결정 1). 노출 여부는 구조적 공개
-- 게이트 결과를 이 테이블에 직접 담아 판단한다.
--
-- JSON 컬럼을 쓰지 않는다(V3 에서 정규화한 규칙). 파생 근거의 원본 목록도 별도 테이블로 정규화한다.

CREATE TABLE report_public_interpretations (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '경향 해석 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서이며 응답의 interpretationRefs 가 이 순서를 가리킨다',
    category VARCHAR(20) NOT NULL COMMENT '관찰 관점 라벨',
    title VARCHAR(200) NOT NULL COMMENT '카드 제목',
    tendency_text TEXT NOT NULL COMMENT '가능성 어조의 경향 문장',
    scope_text TEXT NULL COMMENT '해석 범위 안내이며 비면 미공개',
    home_observation_guide TEXT NULL COMMENT '가정에서 살펴볼 점이며 비면 미공개',
    disclosure_state VARCHAR(20) NOT NULL DEFAULT 'WITHHELD' COMMENT '공개 판정 결과',
    withheld_reason_code VARCHAR(40) NULL COMMENT '미공개·강등 사유 코드',
    CONSTRAINT pk_report_public_interpretations PRIMARY KEY (id),
    CONSTRAINT uk_report_public_interpretations_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_public_interpretations_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_public_interpretations_category
        CHECK (category IN ('RELATIONSHIP', 'EMOTION', 'SELF_EXPRESSION', 'ACTIVITY_STYLE', 'ADAPTATION')),
    -- PUBLISHED = 두 단 모두 통과, WITHHELD = 구조 게이트 실패(제외),
    -- EXPERT_ONLY = 표현 안전 필터 실패로 강등(내용 보존). 두 실패를 구분해 담는다(계약 §4-3).
    CONSTRAINT ck_report_public_interpretations_state
        CHECK (disclosure_state IN ('PUBLISHED', 'WITHHELD', 'EXPERT_ONLY')),
    CONSTRAINT ck_report_public_interpretations_withheld_reason
        CHECK (disclosure_state = 'PUBLISHED' OR withheld_reason_code IS NOT NULL),
    CONSTRAINT ck_report_public_interpretations_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 경향 해석';

CREATE TABLE report_evidence_items (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 근거 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    evidence_number INT NOT NULL COMMENT '리포트 안에서 유일한 근거 번호이며 응답의 evidenceId 로 나간다',
    source_type VARCHAR(20) NOT NULL COMMENT '근거 종류',
    text TEXT NOT NULL COMMENT '근거 문장',
    source_ref_kind VARCHAR(20) NULL COMMENT '원본 근거의 종류이며 파생 근거면 NULL',
    source_ref_id VARCHAR(64) NULL COMMENT 'BE 가 발급한 원본 식별자이며 파생 근거면 NULL',
    stt_needs_confirmation TINYINT(1) NOT NULL DEFAULT 0 COMMENT '음성 인식 확인이 필요한 발화에서 온 근거인지',
    CONSTRAINT pk_report_evidence_items PRIMARY KEY (id),
    CONSTRAINT uk_report_evidence_items_report_number UNIQUE (report_id, evidence_number),
    CONSTRAINT fk_report_evidence_items_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_evidence_items_source_type
        CHECK (source_type IN ('VISION', 'CHILD_ANSWER', 'SELECTED_EMOTION', 'STATED_EMOTION',
                               'ACTIVITY_METRIC', 'REPEATED_SUBJECT', 'LONGITUDINAL')),
    CONSTRAINT ck_report_evidence_items_source_ref_kind
        CHECK (source_ref_kind IS NULL OR source_ref_kind IN ('QA_ANSWER', 'DETECTED_OBJECT',
               'VLM_OBSERVATION', 'EMOTION_SELECTION', 'ACTIVITY_METRIC', 'PRIOR_ACTIVITY')),
    -- 원본 참조는 종류와 식별자가 함께 있어야 한다. 한쪽만 있으면 해석할 수 없는 참조가 된다.
    CONSTRAINT ck_report_evidence_items_source_ref_pair
        CHECK ((source_ref_kind IS NULL AND source_ref_id IS NULL)
               OR (source_ref_kind IS NOT NULL AND source_ref_id IS NOT NULL)),
    CONSTRAINT ck_report_evidence_items_number CHECK (evidence_number > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 근거';

-- 파생 근거(REPEATED_SUBJECT·LONGITUDINAL)가 어떤 원본에서 왔는지 담는다.
-- 원본 근거는 이 테이블에 행을 갖지 않는다. "source_ref 와 derivedFrom 중 정확히 하나"라는
-- 배타 규칙에서 행 존재 여부는 DB CHECK 로 표현할 수 없어 도메인 팩토리와 통합 테스트로 강제한다.
CREATE TABLE report_evidence_derivations (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '파생 근거 원본 참조 ID',
    evidence_item_id BIGINT NOT NULL COMMENT '파생 근거 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '원본 참조 순서',
    source_ref_kind VARCHAR(20) NOT NULL COMMENT '원본 근거의 종류',
    source_ref_id VARCHAR(64) NOT NULL COMMENT 'BE 가 발급한 원본 식별자',
    CONSTRAINT pk_report_evidence_derivations PRIMARY KEY (id),
    CONSTRAINT uk_report_evidence_derivations_item_order UNIQUE (evidence_item_id, display_order),
    CONSTRAINT fk_report_evidence_derivations_item_id FOREIGN KEY (evidence_item_id)
        REFERENCES report_evidence_items (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_evidence_derivations_kind
        CHECK (source_ref_kind IN ('QA_ANSWER', 'DETECTED_OBJECT', 'VLM_OBSERVATION',
                                   'EMOTION_SELECTION', 'ACTIVITY_METRIC', 'PRIOR_ACTIVITY')),
    CONSTRAINT ck_report_evidence_derivations_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='파생 근거의 원본 참조';

-- 카드가 참조하는 근거를 FK 로 묶어 "존재하지 않는 evidenceId 참조"를 구조로 막는다.
CREATE TABLE report_interpretation_evidences (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '경향 해석 근거 참조 ID',
    interpretation_id BIGINT NOT NULL COMMENT '경향 해석 ID',
    evidence_item_id BIGINT NOT NULL COMMENT '리포트 근거 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '근거 노출 순서',
    CONSTRAINT pk_report_interpretation_evidences PRIMARY KEY (id),
    CONSTRAINT uk_report_interpretation_evidences_pair UNIQUE (interpretation_id, evidence_item_id),
    CONSTRAINT uk_report_interpretation_evidences_order UNIQUE (interpretation_id, display_order),
    CONSTRAINT fk_report_interpretation_evidences_interpretation_id FOREIGN KEY (interpretation_id)
        REFERENCES report_public_interpretations (id) ON DELETE CASCADE,
    CONSTRAINT fk_report_interpretation_evidences_evidence_item_id FOREIGN KEY (evidence_item_id)
        REFERENCES report_evidence_items (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_interpretation_evidences_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='경향 해석과 근거의 연결';

CREATE TABLE report_parent_guides (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '보호자 가이드 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    guide_type VARCHAR(30) NOT NULL COMMENT '가이드 유형',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '유형 안에서의 노출 순서',
    guidance TEXT NOT NULL COMMENT '화면에 그대로 나가는 완결 문장',
    CONSTRAINT pk_report_parent_guides PRIMARY KEY (id),
    CONSTRAINT uk_report_parent_guides_report_type_order UNIQUE (report_id, guide_type, display_order),
    CONSTRAINT fk_report_parent_guides_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_parent_guides_type
        CHECK (guide_type IN ('DRAWING_CONVERSATION', 'DAILY_PARENTING',
                              'HOME_OBSERVATION', 'PROFESSIONAL_SUPPORT')),
    CONSTRAINT ck_report_parent_guides_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 보호자 가이드';
