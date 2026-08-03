-- S15P11B209-815: 그림 심리 상담 리포트 재현성 태그가 VARCHAR(50)을 넘겨 저장이 실패하던 문제를 푼다.
-- AI가 보내는 model_version은 "pipeline=<파이프라인>;prompt=<프롬프트 조합>" 형식이고, 리포트 프롬프트가
-- report_common + report_htp/report_diary로 갈리면서 43자에서 76~78자로 늘었다.
-- 프롬프트 항목 하나가 25~28자를 더하므로, 지금 조합에 항목 6개를 더 붙여도 견디도록 255자로 넓힌다.
-- (같은 Schema의 analysis_conversation_summaries.emotion_need와 같은 폭이며 Index 대상이 아니다.)

ALTER TABLE analyses
    MODIFY COLUMN model_version VARCHAR(255) NULL COMMENT 'Model 버전';

ALTER TABLE analysis_observation_results
    MODIFY COLUMN generated_model_version VARCHAR(255) NULL COMMENT '생성 Model 버전';

ALTER TABLE analysis_conversation_summaries
    MODIFY COLUMN summary_model_version VARCHAR(255) NULL COMMENT '요약 Model 버전';
