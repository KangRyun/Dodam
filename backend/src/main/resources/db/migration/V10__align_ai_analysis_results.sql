-- AI 종합 분석 §19.4 결과를 손실 없이 저장하고 객체 좌표계를 명시한다.

ALTER TABLE analysis_detected_objects
    DROP CHECK ck_analysis_detected_objects_bbox,
    ADD COLUMN coordinate_space VARCHAR(20) NOT NULL DEFAULT 'PIXEL'
        COMMENT 'Bounding Box 좌표계' AFTER area_ratio;

ALTER TABLE analysis_detected_objects
    MODIFY COLUMN bbox_x DECIMAL(12,6) NULL COMMENT 'Bounding Box X 좌표',
    MODIFY COLUMN bbox_y DECIMAL(12,6) NULL COMMENT 'Bounding Box Y 좌표',
    MODIFY COLUMN bbox_width DECIMAL(12,6) NULL COMMENT 'Bounding Box 너비',
    MODIFY COLUMN bbox_height DECIMAL(12,6) NULL COMMENT 'Bounding Box 높이',
    ADD CONSTRAINT ck_analysis_detected_objects_coordinate_space CHECK (
        coordinate_space IN ('PIXEL', 'NORMALIZED')),
    ADD CONSTRAINT ck_analysis_detected_objects_bbox_coordinate CHECK (
        (bbox_x IS NULL OR bbox_x >= 0)
        AND (bbox_y IS NULL OR bbox_y >= 0)
        AND (bbox_width IS NULL OR bbox_width > 0)
        AND (bbox_height IS NULL OR bbox_height > 0)
        AND (
            coordinate_space = 'PIXEL'
            OR (
                (bbox_x IS NULL OR bbox_x <= 1)
                AND (bbox_y IS NULL OR bbox_y <= 1)
                AND (bbox_width IS NULL OR bbox_width <= 1)
                AND (bbox_height IS NULL OR bbox_height <= 1)
                AND (bbox_x IS NULL OR bbox_width IS NULL OR bbox_x + bbox_width <= 1)
                AND (bbox_y IS NULL OR bbox_height IS NULL OR bbox_y + bbox_height <= 1)
            )
        ));

ALTER TABLE analyses
    MODIFY COLUMN active_drawing_asset_id BIGINT
        GENERATED ALWAYS AS (
            CASE
                WHEN analysis_status IN ('PROCESSING', 'SUCCESS', 'PARTIAL_SUCCESS')
                    THEN drawing_asset_id
                ELSE NULL
            END
        ) VIRTUAL COMMENT '진행·완료 분석 중복 방지용 생성값';

ALTER TABLE analysis_visual_features
    ADD COLUMN image_width_px INT NULL COMMENT '분석 이미지 너비(px)' AFTER analysis_id,
    ADD COLUMN image_height_px INT NULL COMMENT '분석 이미지 높이(px)' AFTER image_width_px,
    ADD CONSTRAINT ck_analysis_visual_features_image_size CHECK (
        (image_width_px IS NULL OR image_width_px > 0)
        AND (image_height_px IS NULL OR image_height_px > 0));

ALTER TABLE analysis_behavior_features
    ADD COLUMN pressure_available BOOLEAN NULL COMMENT '필압 데이터 사용 가능 여부'
        AFTER color_change_count,
    ADD COLUMN maximum_pressure DECIMAL(8,3) NULL COMMENT '최대 압력'
        AFTER average_pressure;

CREATE TABLE analysis_model_components (
    model_component_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '분석 Model 구성요소 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    component_type VARCHAR(30) NOT NULL COMMENT 'Model 구성요소 유형',
    model_name VARCHAR(100) NULL COMMENT 'Model 이름',
    model_version VARCHAR(100) NULL COMMENT 'Model 버전',
    knowledge_base_version VARCHAR(100) NULL COMMENT '지식 베이스 버전',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_analysis_model_components PRIMARY KEY (model_component_id),
    CONSTRAINT uk_analysis_model_components_analysis_type
        UNIQUE (analysis_id, component_type),
    CONSTRAINT fk_analysis_model_components_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    CONSTRAINT ck_analysis_model_components_type CHECK (
        component_type IN ('OBJECT_DETECTION', 'VISION', 'LANGUAGE', 'KNOWLEDGE_BASE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='분석 Model 구성요소';

CREATE TABLE analysis_warnings (
    warning_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '분석 경고 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    warning_order INT NOT NULL COMMENT '경고 순서',
    warning_code VARCHAR(100) NOT NULL COMMENT '비치명적 경고 코드',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_analysis_warnings PRIMARY KEY (warning_id),
    CONSTRAINT uk_analysis_warnings_analysis_order UNIQUE (analysis_id, warning_order),
    CONSTRAINT fk_analysis_warnings_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    CONSTRAINT ck_analysis_warnings_order CHECK (warning_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 경고';

CREATE TABLE analysis_observation_items (
    observation_item_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '관찰 초안 항목 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    item_type VARCHAR(30) NOT NULL COMMENT '관찰 또는 후속 질문 유형',
    item_order INT NOT NULL COMMENT '항목 순서',
    content TEXT NOT NULL COMMENT '관찰 또는 후속 질문 문장',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_analysis_observation_items PRIMARY KEY (observation_item_id),
    CONSTRAINT uk_analysis_observation_items_analysis_type_order
        UNIQUE (analysis_id, item_type, item_order),
    CONSTRAINT fk_analysis_observation_items_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    CONSTRAINT ck_analysis_observation_items_type
        CHECK (item_type IN ('OBSERVATION', 'FOLLOW_UP_QUESTION')),
    CONSTRAINT ck_analysis_observation_items_order CHECK (item_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='분석 관찰 초안 목록 항목';

CREATE TABLE analysis_evidence_references (
    evidence_reference_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '분석 근거 ID',
    analysis_id BIGINT NOT NULL COMMENT '분석 ID',
    reference_order INT NOT NULL COMMENT '근거 순서',
    source_id VARCHAR(100) NOT NULL COMMENT '지식 베이스 출처 ID',
    title VARCHAR(500) NOT NULL COMMENT '출처 제목',
    published_year INT NULL COMMENT '발행 연도',
    section_name VARCHAR(100) NULL COMMENT '참조 구역',
    evidence_type VARCHAR(50) NOT NULL COMMENT '근거 유형',
    applicability TEXT NULL COMMENT '적용 범위',
    limitations TEXT NULL COMMENT '적용 한계',
    knowledge_base_version VARCHAR(100) NULL COMMENT '지식 베이스 버전',
    retrieved_chunk_hash VARCHAR(100) NULL COMMENT '검색 Chunk Hash',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    CONSTRAINT pk_analysis_evidence_references PRIMARY KEY (evidence_reference_id),
    CONSTRAINT uk_analysis_evidence_references_analysis_order
        UNIQUE (analysis_id, reference_order),
    CONSTRAINT fk_analysis_evidence_references_analysis_id FOREIGN KEY (analysis_id)
        REFERENCES analyses (id) ON DELETE CASCADE,
    CONSTRAINT ck_analysis_evidence_references_order CHECK (reference_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 근거';

CREATE TABLE analysis_evidence_reference_authors (
    evidence_reference_id BIGINT NOT NULL COMMENT '분석 근거 ID',
    author_order INT NOT NULL COMMENT '저자 순서',
    author_name VARCHAR(200) NOT NULL COMMENT '저자명',
    CONSTRAINT pk_analysis_evidence_reference_authors
        PRIMARY KEY (evidence_reference_id, author_order),
    CONSTRAINT fk_analysis_evidence_reference_authors_reference_id
        FOREIGN KEY (evidence_reference_id)
        REFERENCES analysis_evidence_references (evidence_reference_id) ON DELETE CASCADE,
    CONSTRAINT ck_analysis_evidence_reference_authors_order CHECK (author_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='분석 근거 저자';
