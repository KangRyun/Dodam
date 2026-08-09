-- 그림일기 리포트 V2 구조화 결과
--
-- 그림일기 한 회차를 '주요 심리 경향'으로 만들지 않기 위해, 경향 카드 대신 이번 활동에서 실제로
-- 확인된 것만 구조화해 담는다. AI 가 근거 식별자와 대조해 살아남은 것만 보내며, 살아남은 것이
-- 하나도 없으면 아예 보내지 않는다 — 그때는 report_diary_insights 행 자체가 없다.
--
-- ⚠️ JSON 컬럼을 쓰지 않는다. V3 이 JSON 컬럼을 전부 정규화했고 DatabaseMigrationIntegrationTest 가
--    JSON 타입 컬럼 0개를 강제한다. 리포트 도메인의 다른 자식 테이블과 같은 모양으로 맞춘다.
--
-- ai_raw_report(V43) 와 겹치지 않는다. 저쪽은 "무엇이 버려졌나"를 나중에 확인하기 위한 원문
-- 보관이고, 여기는 화면이 실제로 읽는 제품 데이터다. 진단용 보관에서 제품 데이터를 꺼내 쓰면
-- 보관을 끄는 순간 화면이 함께 죽는다.

CREATE TABLE report_diary_insights (
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    headline VARCHAR(200) NULL COMMENT '핵심 이야기 제목',
    summary TEXT NULL COMMENT '사건·행동·상대 반응을 이은 요약',
    reality_status VARCHAR(20) NOT NULL DEFAULT 'UNKNOWN' COMMENT '실제/상상 구분, 아이가 말한 경우에만 UNKNOWN 이 아니다',
    time_scope VARCHAR(20) NOT NULL DEFAULT 'UNKNOWN' COMMENT '사건 시점, 활동 날짜는 근거가 아니다',
    main_event VARCHAR(300) NULL COMMENT '중심 사건, 분명하지 않으면 NULL',
    listening_tip TEXT NULL COMMENT '이번 이야기를 들을 때의 태도 한 문장',
    confirmed_voice_count SMALLINT NOT NULL DEFAULT 0 COMMENT '음성으로 확정된 답변 수',
    option_answer_count SMALLINT NOT NULL DEFAULT 0 COMMENT '선택지에서 고른 답변 수',
    skipped_count SMALLINT NOT NULL DEFAULT 0 COMMENT '건너뛴 질문 수',
    stt_confirmation_count SMALLINT NOT NULL DEFAULT 0 COMMENT '음성 인식 확인이 필요한 답변 수',
    evidence_count SMALLINT NOT NULL DEFAULT 0 COMMENT '사용된 근거 수',
    vision_summary_available TINYINT(1) NOT NULL DEFAULT 0 COMMENT '그림 관찰 서술 존재 여부',
    CONSTRAINT pk_report_diary_insights PRIMARY KEY (report_id),
    CONSTRAINT fk_report_diary_insights_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 핵심 이야기와 데이터 구성';

CREATE TABLE report_diary_narrative_steps (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '이야기 흐름 단계 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    step_type VARCHAR(30) NOT NULL COMMENT 'EVENT·CHILD_ACTION·OTHER_RESPONSE·EMOTION·WISH·OUTCOME',
    text TEXT NOT NULL COMMENT '그 단계에서 확인된 내용',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '시간 흐름 순서',
    CONSTRAINT pk_report_diary_narrative_steps PRIMARY KEY (id),
    CONSTRAINT uk_report_diary_narrative_steps_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_diary_narrative_steps_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_narrative_steps_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 이야기 흐름';

CREATE TABLE report_diary_child_voices (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '아이 발화 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    text TEXT NOT NULL COMMENT '아이가 한 말 그대로',
    elicitation_type VARCHAR(30) NOT NULL COMMENT '그 말을 끌어낸 질문 방식, 고른 답을 자발 표현으로 읽지 않기 위한 구분',
    answer_type VARCHAR(30) NULL COMMENT '답변 입력 방식',
    source_ref_kind VARCHAR(40) NULL COMMENT '근거 종류',
    source_ref_id VARCHAR(64) NULL COMMENT 'BE 가 발급한 근거 식별자',
    stt_needs_confirmation TINYINT(1) NOT NULL DEFAULT 0 COMMENT '음성 인식 확인 필요 여부',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_diary_child_voices PRIMARY KEY (id),
    CONSTRAINT uk_report_diary_child_voices_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_diary_child_voices_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_child_voices_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 아이가 직접 들려준 말';

CREATE TABLE report_diary_session_observations (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '이번 활동 관찰 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    observation_code VARCHAR(60) NOT NULL COMMENT '관찰 코드',
    title VARCHAR(200) NOT NULL COMMENT '보호자에게 보이는 제목',
    description TEXT NOT NULL COMMENT '근거에 묶인 이번 활동 한정 설명',
    scope_text VARCHAR(200) NOT NULL COMMENT '범위를 알리는 문구',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_diary_session_observations PRIMARY KEY (id),
    CONSTRAINT uk_report_diary_session_observations_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_diary_session_observations_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_session_observations_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 이번 활동에서 확인된 표현';

CREATE TABLE report_diary_caregiver_questions (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '보호자 질문 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    question TEXT NOT NULL COMMENT '보호자가 그대로 물어볼 질문',
    purpose VARCHAR(300) NULL COMMENT '이 질문으로 더 들어볼 내용',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_diary_caregiver_questions PRIMARY KEY (id),
    CONSTRAINT uk_report_diary_caregiver_questions_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_diary_caregiver_questions_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_caregiver_questions_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 보호자가 이어 갈 질문';

-- 근거 참조는 항목 종류가 달라도 모양이 같아 한 테이블에 모은다. owner_type 으로 가른다 —
-- 종류마다 테이블을 만들면 같은 두 컬럼짜리 표가 넷이 된다.
CREATE TABLE report_diary_evidence_refs (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '근거 참조 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    owner_type VARCHAR(30) NOT NULL COMMENT 'STORY_SNAPSHOT·NARRATIVE_STEP·SESSION_OBSERVATION·CAREGIVER_QUESTION',
    owner_order SMALLINT NOT NULL DEFAULT 0 COMMENT '소유 항목의 display_order, 1:1 인 STORY_SNAPSHOT 은 0',
    ref_kind VARCHAR(40) NOT NULL COMMENT '근거 종류',
    ref_id VARCHAR(64) NOT NULL COMMENT 'BE 가 발급한 근거 식별자',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '항목 안에서의 순서',
    CONSTRAINT pk_report_diary_evidence_refs PRIMARY KEY (id),
    CONSTRAINT uk_report_diary_evidence_refs_slot UNIQUE (report_id, owner_type, owner_order, display_order),
    CONSTRAINT fk_report_diary_evidence_refs_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_evidence_refs_order CHECK (display_order >= 0 AND owner_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 구조화 항목의 근거 참조';
