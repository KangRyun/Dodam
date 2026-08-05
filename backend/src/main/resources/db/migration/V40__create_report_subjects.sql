-- S15P11B209-960 HTP 주제(집·나무·사람)별 관찰 묶음과 리포트 참고 자료를 저장한다.
--
-- 875 §5 는 subjectReports[] 를 "리포트 상세의 스냅샷을 우선 사용(별도 재조립 금지)"으로 규정한다.
-- 지금까지 이 자리를 담을 테이블이 없어 상세 조회가 List.of() 를 하드코딩했고, AI 가 보낸
-- subjectReports 는 수신 DTO 에 자리가 없어 Jackson 이 조용히 버리고 있었다.
--
-- ⚠️ imageUrl 을 문자열로 저장하지 않는다. 그림 조회 URL 은 자산 식별자로 그때그때 발급하는 값이라
--    (DrawingAssetFileUrlFactory) 문자열을 굳혀 두면 인증 경로·호스트가 바뀔 때 죽은 링크가 남는다.
--    대신 주제별 그림 활동 세션 식별자를 담아 두고 조회 시점에 상세 화면과 같은 규칙으로 자산을 찾는다.
--
-- ⚠️ interpretation_refs 를 정수 인덱스로 저장하지 않는다. AI 가 보내는 값은 AI 응답 배열의 인덱스인데
--    서버 2단 검증에서 카드가 빠지면 보호자 응답 배열이 밀려 참조가 조용히 다른 카드를 가리킨다(875 §5-1).
--    카드 행을 FK 로 묶어 두고 응답을 낼 때 공개 카드 목록에서의 위치로 다시 계산한다.
--
-- JSON 컬럼을 쓰지 않는다(V3 에서 정규화한 규칙).

CREATE TABLE report_subjects (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '주제별 관찰 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서이며 HOUSE→TREE→PERSON 을 보존한다',
    subject_type VARCHAR(10) NULL COMMENT 'HTP 주제이며 주제가 나뉘지 않는 활동은 NULL',
    drawing_session_id BIGINT NULL COMMENT '이 주제의 그림 활동 세션이며 완성 그림 URL 을 조회 시점에 발급하는 근거다',
    CONSTRAINT pk_report_subjects PRIMARY KEY (id),
    CONSTRAINT uk_report_subjects_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_subjects_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    -- 그림 활동 세션이 지워져도 주제별 관찰 서술·문답은 남긴다. 그림만 사라지고 리포트는 읽힌다.
    CONSTRAINT fk_report_subjects_drawing_session_id FOREIGN KEY (drawing_session_id)
        REFERENCES drawing_sessions (id) ON DELETE SET NULL,
    CONSTRAINT ck_report_subjects_subject_type
        CHECK (subject_type IS NULL OR subject_type IN ('HOUSE', 'TREE', 'PERSON')),
    CONSTRAINT ck_report_subjects_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 주제별 관찰';

-- 눈으로 확인된 사실 문장이다. 해석은 담지 않는다(경향 해석은 report_public_interpretations 소관).
CREATE TABLE report_subject_observations (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '주제별 관찰 서술 ID',
    report_subject_id BIGINT NOT NULL COMMENT '주제별 관찰 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '서술 노출 순서',
    observation_text TEXT NOT NULL COMMENT '눈으로 확인된 사실 문장',
    CONSTRAINT pk_report_subject_observations PRIMARY KEY (id),
    CONSTRAINT uk_report_subject_observations_subject_order UNIQUE (report_subject_id, display_order),
    CONSTRAINT fk_report_subject_observations_subject_id FOREIGN KEY (report_subject_id)
        REFERENCES report_subjects (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_subject_observations_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='주제별 관찰 서술';

-- 그 주제에서 나눈 문답 원문이다. 아이 발화는 BE 가 자기 데이터를 그대로 쓴다 — LLM 을 통과시키지 않는다.
--
-- ⚠️ stt_needs_confirmation 은 표시 규칙이지 삭제 규칙이 아니다(875 §6-1). true 여도 문답에는 남기고
--    화면이 "음성 인식 내용을 확인해 주세요"를 함께 보여 준다. 근거·대표 발화에서만 제외한다.
CREATE TABLE report_subject_qa_pairs (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '주제별 문답 ID',
    report_subject_id BIGINT NOT NULL COMMENT '주제별 관찰 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '문답 노출 순서',
    question_text TEXT NOT NULL COMMENT 'AI 가 물은 질문 원문',
    answer_text TEXT NULL COMMENT '아이 답변 원문이며 건너뛰었으면 NULL',
    answer_state VARCHAR(20) NOT NULL COMMENT '답변 상태',
    input_type VARCHAR(20) NOT NULL COMMENT '입력 방식',
    stt_needs_confirmation TINYINT(1) NOT NULL DEFAULT 0 COMMENT '음성 인식 확인이 필요한 답변인지',
    is_representative TINYINT(1) NOT NULL DEFAULT 0 COMMENT '대표 문답인지',
    CONSTRAINT pk_report_subject_qa_pairs PRIMARY KEY (id),
    CONSTRAINT uk_report_subject_qa_pairs_subject_order UNIQUE (report_subject_id, display_order),
    CONSTRAINT fk_report_subject_qa_pairs_subject_id FOREIGN KEY (report_subject_id)
        REFERENCES report_subjects (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_subject_qa_pairs_state
        CHECK (answer_state IN ('ANSWERED', 'SKIPPED')),
    CONSTRAINT ck_report_subject_qa_pairs_input_type
        CHECK (input_type IN ('TEXT', 'VOICE')),
    -- 건너뛴 문답에 답변이 남아 있으면 화면이 "건너뛰었어요"와 답변을 동시에 보여 준다.
    CONSTRAINT ck_report_subject_qa_pairs_skipped_has_no_answer
        CHECK (answer_state <> 'SKIPPED' OR answer_text IS NULL),
    CONSTRAINT ck_report_subject_qa_pairs_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='주제별 문답';

-- 이 주제의 관찰이 근거가 된 경향 해석 카드 연결이다.
-- FK 로 묶어 "존재하지 않는 카드 참조"를 구조로 막고, 응답 인덱스는 조회 시점에 계산한다(875 §5-1).
CREATE TABLE report_subject_interpretations (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '주제별 경향 해석 참조 ID',
    report_subject_id BIGINT NOT NULL COMMENT '주제별 관찰 ID',
    interpretation_id BIGINT NOT NULL COMMENT '경향 해석 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '참조 순서',
    CONSTRAINT pk_report_subject_interpretations PRIMARY KEY (id),
    CONSTRAINT uk_report_subject_interpretations_pair UNIQUE (report_subject_id, interpretation_id),
    CONSTRAINT uk_report_subject_interpretations_order UNIQUE (report_subject_id, display_order),
    CONSTRAINT fk_report_subject_interpretations_subject_id FOREIGN KEY (report_subject_id)
        REFERENCES report_subjects (id) ON DELETE CASCADE,
    CONSTRAINT fk_report_subject_interpretations_interpretation_id FOREIGN KEY (interpretation_id)
        REFERENCES report_public_interpretations (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_subject_interpretations_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='주제별 경향 해석 참조';

-- 리포트가 근거로 참조한 전문 자료 출처다 (S15P11B209-614, 875 §9).
-- 출처 표시는 라이선스 의무(KOGL-1)라 받은 것을 버리지 않는다. AI 는 URL 을 보내지 않으므로
-- url 은 nullable 이다 — 875 §9 가 nullable 을 유지하기로 한 이유가 이 경우다.
CREATE TABLE report_references (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 참고 자료 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    source_id VARCHAR(120) NULL COMMENT '자료 출처 식별자이며 추적용이라 응답에 담지 않는다',
    title VARCHAR(300) NOT NULL COMMENT '자료 제목',
    url VARCHAR(500) NULL COMMENT '자료 링크이며 자체 저작 자료는 NULL',
    CONSTRAINT pk_report_references PRIMARY KEY (id),
    CONSTRAINT uk_report_references_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_references_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_references_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 참고 자료';
