-- 약관 원문 HTML을 저장할 컬럼을 추가한다.
-- 약관 내용이 확정되기 전에는 NULL이며 프론트가 목데이터로 흐름을 태울 수 있도록 nullable로 둔다.
ALTER TABLE consent_terms
    ADD COLUMN content_html TEXT NULL COMMENT '약관 원문 HTML' AFTER content_url;
