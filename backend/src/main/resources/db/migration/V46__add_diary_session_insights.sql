-- 그림일기 3층 인사이트 — 주장의 세기와 다른 설명
--
-- V45 의 관찰 카드는 종류가 하나였다. "아이가 이렇게 말했다"와 "이렇게 볼 수도 있다"가 같은
-- 무게로 읽히면 보호자는 후자를 결론으로 받아들인다. 카드마다 주장의 세기를 적고, 가설에는
-- 다른 설명을 함께 저장한다.
--
--   CONFIRMED_EXPRESSION  아이가 자기 말로 한 답에서 확인된 것 (추측 없음)
--   SESSION_HYPOTHESIS    이번 회차 한정 가설 (다른 설명이 있어야 성립)
--   EXPLORE_NEXT          뜻을 정하지 않고 다음에 확인할 단서
--
-- NULL 허용: V45 로 만든 기존 행에는 이 값이 없다. 읽는 쪽이 기본값으로 다룬다.

ALTER TABLE report_diary_session_observations
    ADD COLUMN insight_type VARCHAR(30) NOT NULL DEFAULT 'CONFIRMED_EXPRESSION'
        COMMENT '주장의 세기 — CONFIRMED_EXPRESSION·SESSION_HYPOTHESIS·EXPLORE_NEXT',
    ADD COLUMN domain VARCHAR(30) NOT NULL DEFAULT 'STORY'
        COMMENT 'STORY·EMOTION·RELATIONSHIP·SELF_EXPRESSION·COPING·ACTIVITY_STYLE',
    ADD COLUMN hypothesis TEXT NULL
        COMMENT '이번 회차 한정 가설이며 확인된 표현·단서에는 NULL',
    ADD COLUMN clarification_question TEXT NULL
        COMMENT '다음에 확인할 질문이며 EXPLORE_NEXT 에는 필수';

-- 다른 가능한 설명. **가설의 필수 짝**이라 별도 표로 둔다 — 이 행이 없으면 서버가 가설 카드를
-- 만들지 않는다. 하나의 해석만 남으면 그것이 결론으로 읽히기 때문이다.
CREATE TABLE report_diary_insight_alternatives (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '다른 설명 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    observation_order SMALLINT NOT NULL COMMENT '소유 관찰 카드의 display_order',
    text TEXT NOT NULL COMMENT '다르게 볼 수 있는 설명 한 문장',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '카드 안에서의 순서',
    CONSTRAINT pk_report_diary_insight_alternatives PRIMARY KEY (id),
    CONSTRAINT uk_report_diary_insight_alternatives_slot
        UNIQUE (report_id, observation_order, display_order),
    CONSTRAINT fk_report_diary_insight_alternatives_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_insight_alternatives_order
        CHECK (display_order >= 0 AND observation_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 인사이트의 다른 가능한 설명';

-- 이번 활동에서 확인하지 못한 것.
--
-- 근거가 없어 카드를 비우면 보호자에게는 '문제가 없었다'로 읽힌다. 무엇을 알 수 없었는지
-- 이름을 붙여 돌려주기 위한 자리다. 문구까지 서버가 정한다 — 모델에게 맡기면 '모르는 것'조차
-- 지어낸다.
CREATE TABLE report_diary_unknown_items (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '확인하지 못한 것 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    code VARCHAR(40) NOT NULL COMMENT 'NO_VOICE_ANSWER·SKIPPED_QUESTIONS 등 서버가 정한 코드',
    text TEXT NOT NULL COMMENT '보호자에게 보이는 문구',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    CONSTRAINT pk_report_diary_unknown_items PRIMARY KEY (id),
    CONSTRAINT uk_report_diary_unknown_items_slot UNIQUE (report_id, code),
    CONSTRAINT fk_report_diary_unknown_items_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_unknown_items_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기에서 확인하지 못한 것';
