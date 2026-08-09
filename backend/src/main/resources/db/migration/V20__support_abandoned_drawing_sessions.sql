ALTER TABLE drawing_sessions
    DROP CHECK ck_drawing_sessions_session_status;

ALTER TABLE drawing_sessions
    ADD CONSTRAINT ck_drawing_sessions_session_status
        CHECK (session_status IN ('IN_PROGRESS', 'COMPLETED', 'FAILED', 'ABANDONED', 'DELETED'));
