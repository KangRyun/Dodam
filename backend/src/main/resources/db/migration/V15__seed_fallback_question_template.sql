-- AI 질문 생성이 실패했을 때 사용할 폴백 질문 Template을 시드한다.
--
-- 왜 필요한가: ConversationQuestionService는 AI 호출 실패 시 활성 FALLBACK Template을 저장해
-- 대화를 이어가도록 설계되어 있으나, 이 데이터가 어떤 migration·시드에도 없어서
-- 폴백 자체가 CONVERSATION_503_001(FALLBACK_QUESTION_NOT_FOUND)로 실패했다.
-- 즉 AI 장애를 흡수하려고 만든 장치가 장애 순간 함께 죽는 상태였다(2026-07-27 로컬 실측).
-- 명세 12.7도 폴백 질문을 ai_question_templates(templateType=FALLBACK)에서 조회한다고 정하고 있다.
--
-- 선택지 행이 함께 필요한 이유: 외부 응답 방식 EMOJI는 내부 ResponseMode.OPTION으로 매핑되며,
-- OPTION이 허용되면 서비스가 Template 선택지를 조회해 비어 있으면 같은 503으로 실패한다.
-- Template만 넣으면 증상이 그대로 남으므로 ai_question_template_options까지 함께 시드한다.
--
-- age_group·difficulty를 CUSTOM으로 두는 이유: 이 행은 특정 연령·난이도용 질문이 아니라
-- 모든 세션이 공유하는 단일 폴백이다. 현재 조회는 templateType과 is_active만 보므로
-- 연령·난이도별 행을 넣으면 첫 행 외에는 도달하지 않는 죽은 데이터가 된다.
-- CUSTOM은 ERD 문서가 정의한 값이며 새 어휘를 만들지 않는다.
--
-- 질문·선택지 문구는 그림 내용에 의존하지 않는다. 폴백은 AI 분석 결과가 없을 때 쓰이므로
-- 특정 사물을 가리키는 질문은 성립하지 않는다. 대신 활동 감정을 묻는 형태로 두어
-- 음성·선택 두 응답 방식 모두에서 답할 수 있게 한다.
--
-- 재실행 안전: 이 테이블에는 자연 키 UNIQUE가 없어 INSERT IGNORE로 중복을 막을 수 없다.
-- NOT EXISTS 조건으로 활성 FALLBACK이 이미 있으면 넣지 않는다.

INSERT INTO ai_question_templates (
    template_type,
    age_group,
    difficulty,
    question_purpose,
    question_text,
    is_active
)
SELECT
    'FALLBACK',
    'CUSTOM',
    'CUSTOM',
    'DRAWING_CONTEXT',
    '그림을 그리는 동안 기분이 어땠어?',
    TRUE
FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM ai_question_templates existing
    WHERE existing.template_type = 'FALLBACK' AND existing.is_active = TRUE
);

INSERT INTO ai_question_template_options (
    question_template_id,
    option_key,
    option_type,
    option_value,
    label,
    emoji,
    display_order
)
SELECT
    template.id,
    seed.option_key,
    'EMOTION',
    seed.option_key,
    seed.label,
    seed.emoji,
    seed.display_order
FROM (
    SELECT id FROM ai_question_templates
    WHERE template_type = 'FALLBACK' AND is_active = TRUE
    ORDER BY id ASC
    LIMIT 1
) template
JOIN (
    SELECT 'HAPPY' AS option_key, '기분이 좋았어요' AS label, '😊' AS emoji, 1 AS display_order
    UNION ALL SELECT 'FUN', '재미있었어요', '😄', 2
    UNION ALL SELECT 'NOT_SURE', '잘 모르겠어요', '🤔', 3
) seed
WHERE NOT EXISTS (
    SELECT 1 FROM ai_question_template_options existing
    WHERE existing.question_template_id = template.id
);
