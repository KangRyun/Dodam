-- 발달 맥락 2.0.0 — 맥락의 성격·보호자 질문·교육단계 (S15P11B209-1010 v2)
--
-- 세 가지를 더한다.
--
--   context_type       이 맥락이 무엇을 주장하는지. 화면과 로그가 "연령 규준"과 "학령 초기
--                      참고 맥락"과 "이번 활동만"을 섞지 않게 한다. 문구로만 구분하면
--                      문구를 다듬는 순간 구분이 사라진다.
--   caregiver_question 보호자가 활동에 이어 그대로 물어볼 수 있는 질문.
--   education_stage    아이가 다니는 곳. 만 6세 맥락을 나이와 **함께** 고르는 데 쓴다.
--
-- ⚠️ 도메인이 다섯에서 일곱으로 늘었다. 기존 다섯의 이름은 바꾸지 않았다 —
--    UNIQUE(report_id, domain) 로 묶여 있어 개명하면 지난 리포트의 카드가 고아가 된다.

ALTER TABLE report_diary_developmental_observations
    ADD COLUMN context_type VARCHAR(40) NOT NULL DEFAULT 'SESSION_ONLY_CONTEXT'
        COMMENT 'AGE_MILESTONE_CONTEXT·EARLY_SCHOOL_COMMUNICATION_CONTEXT·SESSION_ONLY_CONTEXT'
        AFTER status,
    ADD COLUMN caregiver_question TEXT NULL
        COMMENT '보호자가 이어서 물어볼 질문' AFTER scope_text;

ALTER TABLE report_diary_developmental_observations
    ADD CONSTRAINT ck_report_diary_developmental_observations_context_type
        CHECK (context_type IN (
            'AGE_MILESTONE_CONTEXT',
            'EARLY_SCHOOL_COMMUNICATION_CONTEXT',
            'SESSION_ONLY_CONTEXT'));

-- 도메인 목록은 컬럼 주석에만 적혀 있었다. 늘리면서 함께 고친다.
ALTER TABLE report_diary_developmental_observations
    MODIFY COLUMN domain VARCHAR(30) NOT NULL
    COMMENT 'NARRATIVE_LANGUAGE·EMOTION_EXPRESSION·SOCIAL_UNDERSTANDING·COPING_HELP_SEEKING·SELF_REFLECTION·CONVERSATION_PARTICIPATION·DRAWING_LANGUAGE_INTEGRATION';

-- 다니는 곳. **NULL 이 정상이다** — 필수로 받지 않는다.
--
-- ⚠️ 'UNKNOWN' 을 값으로 두지 않는다. 값으로 두면 "모른다고 입력한 것"과 "입력하지 않은 것"을
--    구별할 수 없고, 나중에 둘을 나눠야 할 때 되돌릴 방법이 없다. 응답 DTO 에서만 UNKNOWN 으로
--    바꿔 내보낸다.
ALTER TABLE children
    ADD COLUMN education_stage VARCHAR(20) NULL
        COMMENT '다니는 곳(PRESCHOOL·KINDERGARTEN·GRADE_1). NULL 은 미입력' AFTER question_difficulty,
    ADD CONSTRAINT ck_children_education_stage
        CHECK (education_stage IS NULL
               OR education_stage IN ('PRESCHOOL', 'KINDERGARTEN', 'GRADE_1'));
