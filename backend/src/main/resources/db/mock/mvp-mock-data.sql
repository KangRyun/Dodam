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

-- 음성 답변(288·289) 로컬 확인용 약관 마스터.
--   VoiceAnswerAuthorizationRepository는 활성 VOICE_PROCESSING(CHILD) 약관의 최신 이력이
--   AGREE여야 업로드를 허용한다. 약관 마스터가 없으면 로컬에서 음성 경로가 항상
--   403 VOICE_CONSENT_REQUIRED로 막혀 흐름을 확인할 수 없다(2026-07-27 실측).
--   운영 약관 문구·버전은 이 파일의 소관이 아니며, 여기 값은 local 개발 전용이다.
--
--   동의 이력(consent_records)은 넣지 않는다. 동의는 보호자 행위이므로 로컬에서도
--   POST /api/v1/consents 로 받는 것이 실제 경로와 같다.
--   id를 지정하지 않는 이유: CreateConsentRequest.termId가 @Positive라서 이 파일의 다른
--   행처럼 음수 id를 쓰면 동의 API로 참조할 수 없다. 자연 키(term_code, version) UNIQUE에
--   맡겨 양수 자동 id를 받고 재실행 시 중복도 막는다.
INSERT INTO consent_terms
    (term_code, target_scope, is_required, version, title, effective_at, is_active)
VALUES
    ('VOICE_PROCESSING', 'CHILD', TRUE, 'mock-v1', '음성 처리 동의(로컬 개발용)',
     '2026-01-01 00:00:00.000000', TRUE)
ON DUPLICATE KEY UPDATE title = VALUES(title);

COMMIT;
