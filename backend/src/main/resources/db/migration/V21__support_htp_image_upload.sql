ALTER TABLE drawing_assets
    ADD COLUMN upload_idempotency_key VARCHAR(100) NULL
        COMMENT 'HTP 원본 이미지 업로드 멱등 키',
    ADD COLUMN upload_fingerprint CHAR(64) NULL
        COMMENT '정규화된 업로드 요청 SHA-256',
    ADD COLUMN upload_rotation_degrees INT NULL
        COMMENT '클라이언트가 적용한 회전 각도',
    ADD COLUMN upload_crop_applied BOOLEAN NULL
        COMMENT '클라이언트 자르기 적용 여부';

ALTER TABLE drawing_assets
    ADD UNIQUE KEY uk_drawing_assets_upload_idempotency_key (upload_idempotency_key);

ALTER TABLE drawing_assets
    ADD COLUMN uploaded_drawing_session_id BIGINT
        GENERATED ALWAYS AS (
            CASE WHEN asset_type = 'UPLOADED' THEN drawing_session_id ELSE NULL END
        ) VIRTUAL COMMENT '세션별 업로드 원본 유일성 검사용 생성값';

ALTER TABLE drawing_assets
    ADD UNIQUE KEY uk_drawing_assets_uploaded_session (uploaded_drawing_session_id);
