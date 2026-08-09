ALTER TABLE conversation_sessions
    ADD COLUMN completion_reason VARCHAR(30) NULL COMMENT '대화 종료 사유' AFTER question_count,
    ADD CONSTRAINT ck_conversation_sessions_completion_reason
        CHECK (
            completion_reason IS NULL
            OR completion_reason IN (
                'QUESTION_LIMIT_REACHED',
                'CHILD_REQUEST',
                'GUARDIAN_REQUEST',
                'NO_MORE_QUESTION'
            )
        );
