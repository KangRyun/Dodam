-- 그림일기 연령 발달 맥락 (4층)
--
-- 그림일기에서 관찰된 표현을 연령에 맞게 설명하되 **한 번의 활동을 발달검사처럼 채점하지
-- 않는다.** 저장 구조가 그 원칙을 강제한다 — 연령 맥락·이번 활동 관찰·범위 문구가 한 행에
-- 함께 있고, 어느 하나만 떼어 보여 줄 수 없다.
--
--   age_context  검수된 공개 자료에서 온 연령 맥락 한 줄
--   observation  이번 활동에서 확인된 표현
--   scope_text   "전체 발달 수준을 평가한 결과가 아니에요" — 항상 함께 나간다
--   status       OBSERVED_THIS_SESSION · PARTIALLY_OBSERVED · NOT_ASSESSED
--
-- ⚠️ NOT_ASSESSED 는 "확인하지 않았다"이지 "못한다"가 아니다. 아이의 무응답·건너뜀·짧은 답을
--    발달 지연으로 읽지 않도록 화면과 문구가 함께 지킨다.
--
-- 근거 참조는 새 표를 만들지 않고 report_diary_evidence_refs 에 owner_type =
-- 'DEVELOPMENTAL_OBSERVATION' 으로 함께 담는다.

CREATE TABLE report_diary_developmental_observations (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '발달 맥락 관찰 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    domain VARCHAR(30) NOT NULL COMMENT 'NARRATIVE_LANGUAGE·EMOTION_EXPRESSION·SOCIAL_UNDERSTANDING·COPING_HELP_SEEKING·SELF_REFLECTION',
    status VARCHAR(30) NOT NULL COMMENT 'OBSERVED_THIS_SESSION·PARTIALLY_OBSERVED·NOT_ASSESSED',
    age_context TEXT NOT NULL COMMENT '검수 출처에서 온 연령 맥락 한 줄',
    observation TEXT NOT NULL COMMENT '이번 활동에서 확인된 표현',
    scope_text VARCHAR(200) NOT NULL COMMENT '범위 고지, 화면에 항상 함께 나간다',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_diary_developmental_observations PRIMARY KEY (id),
    CONSTRAINT uk_report_diary_developmental_observations_slot UNIQUE (report_id, domain),
    CONSTRAINT fk_report_diary_developmental_observations_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_developmental_observations_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 연령 발달 맥락 관찰';

-- 검수 출처 식별자. **한 관찰에 출처가 없는 것은 정상이다** — AI 서버는 규준 문장(출처 있음)과
-- '이번 활동에서만 살펴본다'는 문장(규준을 주장하지 않아 출처 없음) 두 가지를 보낸다. 출처 없는
-- 규준 문장이 나가지 않는다는 보장은 등록부가 하고, 화면은 출처가 있을 때만 밝힌다.
CREATE TABLE report_diary_development_sources (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '출처 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    domain VARCHAR(30) NOT NULL COMMENT '소유 관찰의 도메인',
    source_id VARCHAR(60) NOT NULL COMMENT '검수 출처 식별자(CDC_5Y_MILESTONES 등)',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '관찰 안에서의 순서',
    CONSTRAINT pk_report_diary_development_sources PRIMARY KEY (id),
    CONSTRAINT uk_report_diary_development_sources_slot UNIQUE (report_id, domain, source_id),
    CONSTRAINT fk_report_diary_development_sources_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_development_sources_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 발달 맥락의 검수 출처';

-- owner_type 에 종류가 하나 늘었다. 값 목록이 컬럼 주석에만 적혀 있어 함께 고쳐 둔다.
ALTER TABLE report_diary_evidence_refs
    MODIFY COLUMN owner_type VARCHAR(30) NOT NULL
    COMMENT 'STORY_SNAPSHOT·NARRATIVE_STEP·SESSION_OBSERVATION·CAREGIVER_QUESTION·DEVELOPMENTAL_OBSERVATION';
