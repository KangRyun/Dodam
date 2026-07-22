ALTER TABLE drawing_assets
    ADD COLUMN captured_at DATETIME(6) NULL COMMENT '클라이언트 캡처 일시' AFTER object_code;

UPDATE drawing_assets
SET captured_at = created_at
WHERE captured_at IS NULL;

ALTER TABLE drawing_assets
    MODIFY COLUMN captured_at DATETIME(6) NOT NULL COMMENT '클라이언트 캡처 일시',
    ALGORITHM=INPLACE,
    LOCK=NONE;

ALTER TABLE drawing_assets
    ADD UNIQUE KEY uk_drawing_assets_session_type_version
        (drawing_session_id, asset_type, asset_version);

ALTER TABLE drawing_assets
    ADD COLUMN final_drawing_session_id BIGINT
        GENERATED ALWAYS AS (
            CASE WHEN asset_type = 'FINAL' THEN drawing_session_id ELSE NULL END
        ) VIRTUAL COMMENT '세션별 최종 그림 유일성 검사용 생성값',
    ALGORITHM=INSTANT;

ALTER TABLE drawing_assets
    ADD UNIQUE KEY uk_drawing_assets_final_session (final_drawing_session_id);
