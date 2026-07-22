-- 기존 분석 시점과 상태 의미를 유지하면서 그림 분석 요청 API에 필요한 연결 정보와 제약을 보강한다.
-- 기존 행은 출처가 명확한 경우에만 그림 파일을 역채움하며, 추론할 수 없는 값은 NULL로 보존한다.

ALTER TABLE analyses
    ADD COLUMN drawing_asset_id BIGINT NULL COMMENT '분석 대상 그림 파일 ID'
        AFTER drawing_session_id,
    ADD COLUMN analysis_task_type VARCHAR(30) NULL COMMENT 'AI 분석 작업 유형'
        AFTER analysis_type;

UPDATE analyses AS analysis
JOIN (
    SELECT analysis_id, MIN(drawing_asset_id) AS drawing_asset_id
    FROM analysis_detected_objects
    GROUP BY analysis_id
    HAVING COUNT(DISTINCT drawing_asset_id) = 1
) AS detected_asset ON detected_asset.analysis_id = analysis.id
SET analysis.drawing_asset_id = detected_asset.drawing_asset_id
WHERE analysis.drawing_asset_id IS NULL;

ALTER TABLE analyses
    ADD CONSTRAINT fk_analyses_drawing_asset_id FOREIGN KEY (drawing_asset_id)
        REFERENCES drawing_assets (id) ON DELETE CASCADE,
    ADD CONSTRAINT ck_analyses_task_type CHECK (
        analysis_task_type IS NULL OR analysis_task_type IN ('OBJECT_DETECTION')),
    ADD INDEX idx_analyses_asset_task_status
        (drawing_asset_id, analysis_task_type, analysis_status);

ALTER TABLE analyses
    ADD COLUMN active_drawing_asset_id BIGINT
        GENERATED ALWAYS AS (
            CASE
                WHEN analysis_status IN ('PROCESSING', 'SUCCESS') THEN drawing_asset_id
                ELSE NULL
            END
        ) VIRTUAL COMMENT '진행·성공 분석 중복 방지용 생성값';

ALTER TABLE analyses
    ADD UNIQUE KEY uk_analyses_active_asset_task
        (active_drawing_asset_id, analysis_task_type);

ALTER TABLE analysis_detected_objects
    MODIFY COLUMN bbox_x DECIMAL(12,3) NULL COMMENT 'Bounding Box X 픽셀 좌표',
    MODIFY COLUMN bbox_y DECIMAL(12,3) NULL COMMENT 'Bounding Box Y 픽셀 좌표',
    MODIFY COLUMN bbox_width DECIMAL(12,3) NULL COMMENT 'Bounding Box 픽셀 너비',
    MODIFY COLUMN bbox_height DECIMAL(12,3) NULL COMMENT 'Bounding Box 픽셀 높이',
    ADD CONSTRAINT ck_analysis_detected_objects_bbox CHECK (
        (bbox_x IS NULL OR bbox_x >= 0)
        AND (bbox_y IS NULL OR bbox_y >= 0)
        AND (bbox_width IS NULL OR bbox_width > 0)
        AND (bbox_height IS NULL OR bbox_height > 0)),
    ADD CONSTRAINT ck_analysis_detected_objects_order CHECK (
        detection_order IS NULL OR detection_order >= 0);
