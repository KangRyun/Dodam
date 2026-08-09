-- "오늘 마음 나누기" 정서적 교감 — 보호자 질문에 교감 유형·공감 반응 안내를 더한다.
--
-- 그림일기 V2 의 "이어서 물어보면 좋아요"를 정서적 교감 전용 섹션으로 재설계하면서, 질문 하나에
-- 다음 셋을 함께 담는다.
--
--   connection_type      이 질문이 여는 교감의 종류. AI 는 감정 4종만 태그하고, 서버가 화이트리스트로
--                        검증한다. 빈 상태 폴백으로 GENERAL_CONNECTION 이 함께 온다.
--   response_guide       아이 답에 부모가 어떻게 마음으로 반응할지(반영적 경청). **서버가
--                        connection_type 으로 정적 매핑**한다 — LLM 이 만들지 않는다. 공감 문구를
--                        모델에게 맡기면 발달 규준 주장·지시형 훈육으로 새기 쉬워서다.
--   co_regulation_action 함께 해보기 한 줄이며 없을 수 있다.
--
-- ⚠️ connection_type 은 NOT NULL DEFAULT 'GENERAL_CONNECTION' 이다. 지난 리포트의 질문 행에는
--    유형이 없으므로 기본값으로 채워 CHECK 를 통과시킨다. 폴백 유형이 기본값이라 의미도 맞다.

ALTER TABLE report_diary_caregiver_questions
    ADD COLUMN connection_type VARCHAR(30) NOT NULL DEFAULT 'GENERAL_CONNECTION'
        COMMENT 'FEELING_SHARING·COMFORT_SEEKING·SHARED_JOY·PERSPECTIVE_TAKING·GENERAL_CONNECTION'
        AFTER purpose,
    ADD COLUMN response_guide TEXT NULL
        COMMENT '아이 답에 부모가 마음으로 반응하는 법. 서버가 유형으로 정적 매핑' AFTER connection_type,
    ADD COLUMN co_regulation_action TEXT NULL
        COMMENT '함께 해보기 한 줄이며 없을 수 있음' AFTER response_guide;

ALTER TABLE report_diary_caregiver_questions
    ADD CONSTRAINT ck_report_diary_caregiver_questions_connection_type
        CHECK (connection_type IN (
            'FEELING_SHARING',
            'COMFORT_SEEKING',
            'SHARED_JOY',
            'PERSPECTIVE_TAKING',
            'GENERAL_CONNECTION'));
