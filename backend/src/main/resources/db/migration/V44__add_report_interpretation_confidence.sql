-- S15P11B209-982 경향 해석 카드가 인용한 근거의 종류로 계산한 확신 등급을 담는다.
--
-- LLM 이 매긴 점수가 아니라 AI 쪽 코드가 evidenceRefs 의 근거 종류를 세어 계산한 값이다.
-- 그래서 숫자가 아니라 등급 이름이며, VARCHAR + CHECK 로 값 목록을 고정한다(V37 방식 그대로).
--
-- NULL 을 허용한다. 두 가지 이유가 있고 둘 다 필수다.
--   1) 이미 저장된 카드에는 등급이 없다. NOT NULL 로 만들면 이 마이그레이션 자체가 실패한다.
--   2) AI 가 등급을 싣지 않았거나 알 수 없는 이름을 보냈을 때 BE 는 등급만 버리고 카드는 살린다
--      (InterpretationCandidateAdapter). 그 "등급 없음"이 DB 에도 그대로 담겨야 한다 —
--      기본값을 채우면 계산된 적 없는 카드가 화면에서 근거 없이 강등된 것처럼 보인다.

ALTER TABLE report_public_interpretations
    ADD COLUMN confidence VARCHAR(20) NULL
    COMMENT '근거 종류로 계산한 확신 등급이며 계산되지 않았으면 NULL',
    ADD CONSTRAINT ck_report_public_interpretations_confidence
        CHECK (confidence IS NULL OR confidence IN ('STRONG', 'MODERATE', 'WEAK'));
