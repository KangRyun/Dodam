-- S15P11B209-912 보호자 리포트 '그린 것' 줄의 값을 VLM 관찰 서술 기반으로 저장한다.
--
-- 종전에는 YOLO 탐지 라벨(analysis_detected_objects.object_name)을 조회 시점에 그대로 나열했다.
-- 탐지 임계값은 0.20 으로 '박스를 남길지'의 기준일 뿐인데 그 라벨이 보호자에게 확정 사실로 나갔고,
-- AI 리포트 프롬프트는 같은 탐지에 0.50 필터를 걸어 써서 두 경로의 기준이 어긋나 있었다.
-- VLM 서술은 실제 이미지를 보고 쓰며 "목록에 있어도 이미지에서 안 보이면 쓰지 마"가 강제되므로
-- 서술에 남은 대상이 라벨보다 정확하다(S15P11B209-911 에서 AI 가 서술 원문과 대조해 걸러 보낸다).
--
-- 활동 기록 계열(report_activity_summaries)은 리포트당 단일 행이라 여기에 얹을 수 없다.
-- '그린 것'은 주제와 순서를 갖는 N 건이고, 하나의 컬럼에 이어 붙이면 V3 에서 정규화로 없앤 형태가
-- 된다. 순서는 계약이다 — 화면과 PDF 가 이 순서로 이어 붙여 문장을 만든다.

-- 행이 없는 최신 빈 결과와, 이 필드가 없던 과거 리포트를 구분한다. 이 표식이 없을 때만
-- 0.50 이상 YOLO 폴백을 사용한다.
ALTER TABLE reports
    ADD COLUMN has_drawn_items BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'AI drawnItems 필드 저장 여부';

CREATE TABLE report_drawn_items (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '리포트 그린 것 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서이며 주제 순서(집→나무→사람)를 보존한다',
    drawing_subject VARCHAR(10) NULL COMMENT 'HTP 주제이며 그림일기는 NULL',
    name VARCHAR(100) NOT NULL COMMENT '보호자 화면에 그대로 나가는 한국어 표현',
    CONSTRAINT pk_report_drawn_items PRIMARY KEY (id),
    CONSTRAINT uk_report_drawn_items_report_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_drawn_items_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_drawn_items_subject
        CHECK (drawing_subject IS NULL OR drawing_subject IN ('HOUSE', 'TREE', 'PERSON')),
    CONSTRAINT ck_report_drawn_items_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 그린 것';
