START TRANSACTION;

INSERT INTO users (id, role, nickname, account_status, is_completed)
VALUES (-136001, 'GUARDIAN', '도담 보호자', 'ACTIVE', TRUE)
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO auth_accounts
    (id, user_id, provider, provider_subject, provider_email, provider_email_verified_at)
VALUES
    (-136001, -136001, 'KAKAO', 'mock-s15p11b209-136-guardian',
     'guardian@example.invalid', CURRENT_TIMESTAMP(6))
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO children
    (id, nickname, birth_date, question_difficulty, tutorial_status, profile_status)
VALUES
    (-136001, '도담이', '2020-01-15', 'PRESCHOOL', 'COMPLETED', 'ACTIVE')
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO guardian_child_relations
    (id, guardian_user_id, child_id, relationship_type)
VALUES (-136001, -136001, -136001, 'MOTHER')
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO drawing_types
    (id, code, name, activity_category, selectable_by,
     recommended_age_min, recommended_age_max, guide_text, is_active, display_order)
VALUES
    (-136001, 'MVP_FREE_DRAWING', '자유롭게 그리기', 'GENERAL', 'BOTH',
     3, 12, '좋아하는 것을 자유롭게 그려 보세요.', TRUE, 1)
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO drawing_sessions
    (id, child_id, drawing_type_id, started_by_user_id, input_method, title,
     session_status, current_stage, idempotency_key)
VALUES
    (-136001, -136001, -136001, -136001, 'CANVAS', '진행 중인 자유 그림',
     'IN_PROGRESS', 'DRAWING', 'mock-s15p11b209-136-session')
ON DUPLICATE KEY UPDATE id = id;

COMMIT;
