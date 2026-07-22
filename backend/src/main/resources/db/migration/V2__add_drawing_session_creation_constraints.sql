ALTER TABLE drawing_sessions
    ADD COLUMN idempotency_key VARCHAR(100) NULL COMMENT '洹몃┝ ?몄뀡 ?앹꽦 硫깅벑??Key';

ALTER TABLE drawing_sessions
    ADD CONSTRAINT uk_drawing_sessions_idempotency_key UNIQUE (idempotency_key);

CREATE INDEX idx_drawing_sessions_active_child
    ON drawing_sessions (child_id, session_status, deleted_at);
