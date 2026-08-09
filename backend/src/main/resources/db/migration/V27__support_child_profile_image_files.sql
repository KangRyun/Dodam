CREATE TABLE child_profile_image_files (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '아동 프로필 이미지 내부 ID',
    file_id CHAR(36) NOT NULL COMMENT 'API 공개 파일 UUID',
    uploaded_by_user_id BIGINT NOT NULL COMMENT '업로드 사용자 ID',
    storage_key VARCHAR(1000) NOT NULL COMMENT '이미지 Storage Key',
    content_type VARCHAR(100) NOT NULL COMMENT '검증된 MIME Type',
    file_size_bytes BIGINT NOT NULL COMMENT '파일 크기(Byte)',
    width_px INT NOT NULL COMMENT '이미지 너비(px)',
    height_px INT NOT NULL COMMENT '이미지 높이(px)',
    checksum_sha256 CHAR(64) NOT NULL COMMENT '이미지 Byte SHA-256',
    status VARCHAR(20) NOT NULL DEFAULT 'TEMP' COMMENT 'TEMP 또는 ATTACHED',
    child_id BIGINT NULL COMMENT '연결된 아동 ID',
    expires_at DATETIME(6) NOT NULL COMMENT 'TEMP 파일 만료 시각',
    attached_at DATETIME(6) NULL COMMENT '아동 연결 시각',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '업로드 시각',
    CONSTRAINT pk_child_profile_image_files PRIMARY KEY (id),
    CONSTRAINT uk_child_profile_image_files_file_id UNIQUE (file_id),
    CONSTRAINT uk_child_profile_image_files_child_id UNIQUE (child_id),
    CONSTRAINT fk_child_profile_image_files_user_id
        FOREIGN KEY (uploaded_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_child_profile_image_files_child_id
        FOREIGN KEY (child_id) REFERENCES children (id) ON DELETE SET NULL,
    CONSTRAINT ck_child_profile_image_files_status
        CHECK (status IN ('TEMP', 'ATTACHED')),
    CONSTRAINT ck_child_profile_image_files_size
        CHECK (file_size_bytes > 0 AND file_size_bytes <= 5242880),
    CONSTRAINT ck_child_profile_image_files_dimensions
        CHECK (width_px > 0 AND height_px > 0),
    INDEX idx_child_profile_image_files_owner_status
        (uploaded_by_user_id, status, expires_at),
    INDEX idx_child_profile_image_files_expiry (status, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='아동 프로필 이미지 파일';
