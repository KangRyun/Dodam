-- v1.2 대화 질문 Snapshot 정규화: JSON 컬럼을 선택지·대상 객체 테이블로 전환한다.

CREATE TABLE ai_question_template_options (
    id BIGINT NOT NULL AUTO_INCREMENT,
    question_template_id BIGINT NOT NULL,
    option_key VARCHAR(80) NOT NULL,
    option_type VARCHAR(30) NOT NULL,
    option_value VARCHAR(255) NOT NULL,
    label VARCHAR(200) NOT NULL,
    emoji VARCHAR(20) NULL,
    display_order SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    CONSTRAINT uk_ai_question_template_options_template_key
        UNIQUE (question_template_id, option_key),
    CONSTRAINT uk_ai_question_template_options_template_order
        UNIQUE (question_template_id, display_order),
    CONSTRAINT fk_ai_question_template_options_template_id
        FOREIGN KEY (question_template_id) REFERENCES ai_question_templates (id)
        ON DELETE CASCADE,
    CONSTRAINT ck_ai_question_template_options_order CHECK (display_order >= 0)
);

CREATE TABLE conversation_message_options (
    id BIGINT NOT NULL AUTO_INCREMENT,
    conversation_message_id BIGINT NOT NULL,
    template_option_id BIGINT NULL,
    option_key VARCHAR(80) NOT NULL,
    option_type VARCHAR(30) NOT NULL,
    option_value VARCHAR(255) NOT NULL,
    label VARCHAR(200) NOT NULL,
    emoji VARCHAR(20) NULL,
    display_order SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    CONSTRAINT uk_conversation_message_options_message_key
        UNIQUE (conversation_message_id, option_key),
    CONSTRAINT uk_conversation_message_options_message_order
        UNIQUE (conversation_message_id, display_order),
    CONSTRAINT uk_conversation_message_options_message_id
        UNIQUE (conversation_message_id, id),
    CONSTRAINT fk_conversation_message_options_message_id
        FOREIGN KEY (conversation_message_id) REFERENCES conversation_messages (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_conversation_message_options_template_option_id
        FOREIGN KEY (template_option_id) REFERENCES ai_question_template_options (id)
        ON DELETE SET NULL,
    CONSTRAINT ck_conversation_message_options_order CHECK (display_order >= 0)
);

CREATE TABLE conversation_message_targets (
    conversation_message_id BIGINT NOT NULL,
    detected_object_id BIGINT NULL,
    object_code VARCHAR(50) NULL,
    object_name VARCHAR(100) NULL,
    bbox_x DECIMAL(8, 6) NOT NULL,
    bbox_y DECIMAL(8, 6) NOT NULL,
    bbox_width DECIMAL(8, 6) NOT NULL,
    bbox_height DECIMAL(8, 6) NOT NULL,
    PRIMARY KEY (conversation_message_id),
    CONSTRAINT fk_conversation_message_targets_message_id
        FOREIGN KEY (conversation_message_id) REFERENCES conversation_messages (id)
        ON DELETE CASCADE,
    CONSTRAINT ck_conversation_message_targets_bbox CHECK (
        bbox_x >= 0
        AND bbox_x <= 1
        AND bbox_y >= 0
        AND bbox_y <= 1
        AND bbox_width > 0
        AND bbox_width <= 1
        AND bbox_height > 0
        AND bbox_height <= 1
        AND bbox_x + bbox_width <= 1
        AND bbox_y + bbox_height <= 1
    )
);

INSERT INTO ai_question_template_options (
    question_template_id,
    option_key,
    option_type,
    option_value,
    label,
    display_order
)
SELECT
    template.id,
    option_item.option_key,
    'STATIC',
    option_item.option_key,
    option_item.label,
    option_item.ordinality - 1
FROM ai_question_templates template
JOIN JSON_TABLE(
    template.options_json,
    '$[*]' COLUMNS (
        ordinality FOR ORDINALITY,
        option_key VARCHAR(80) PATH '$.code',
        label VARCHAR(200) PATH '$.label'
    )
) option_item ON TRUE
WHERE template.options_json IS NOT NULL
  AND JSON_TYPE(template.options_json) = 'ARRAY';

INSERT INTO conversation_message_options (
    conversation_message_id,
    option_key,
    option_type,
    option_value,
    label,
    display_order
)
SELECT
    message.id,
    option_item.option_key,
    'STATIC',
    option_item.option_key,
    option_item.label,
    option_item.ordinality - 1
FROM conversation_messages message
JOIN JSON_TABLE(
    message.options_json,
    '$[*]' COLUMNS (
        ordinality FOR ORDINALITY,
        option_key VARCHAR(80) PATH '$.code',
        label VARCHAR(200) PATH '$.label'
    )
) option_item ON TRUE
WHERE message.options_json IS NOT NULL
  AND JSON_TYPE(message.options_json) = 'ARRAY';

INSERT INTO conversation_message_targets (
    conversation_message_id,
    object_code,
    object_name,
    bbox_x,
    bbox_y,
    bbox_width,
    bbox_height
)
SELECT
    message.id,
    target.object_code,
    target.object_name,
    target.bbox_x,
    target.bbox_y,
    target.bbox_width,
    target.bbox_height
FROM conversation_messages message
JOIN JSON_TABLE(
    message.target_object_json,
    '$' COLUMNS (
        object_code VARCHAR(50) PATH '$.objectCode',
        object_name VARCHAR(100) PATH '$.objectName',
        bbox_x DECIMAL(8, 6) PATH '$.boundingBox.x',
        bbox_y DECIMAL(8, 6) PATH '$.boundingBox.y',
        bbox_width DECIMAL(8, 6) PATH '$.boundingBox.width',
        bbox_height DECIMAL(8, 6) PATH '$.boundingBox.height'
    )
) target ON TRUE
WHERE message.target_object_json IS NOT NULL
  AND target.bbox_x IS NOT NULL
  AND target.bbox_y IS NOT NULL
  AND target.bbox_width IS NOT NULL
  AND target.bbox_height IS NOT NULL;

ALTER TABLE ai_question_templates
    DROP COLUMN options_json;

ALTER TABLE conversation_messages
    DROP COLUMN options_json,
    DROP COLUMN target_object_json;
