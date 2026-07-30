-- S15P11B209-736 — 시각 저장 규약을 KST 로 통일한다
--
-- 배경
--   같은 스키마 안에서 created_at 의 기준이 둘로 갈려 있었다.
--     · 엔티티가 매핑한 컬럼  → 앱이 쓴다 → JDBC serverTimezone=Asia/Seoul 가 변환 → KST
--     · DEFAULT CURRENT_TIMESTAMP → MySQL 이 채운다 → 서버 TZ(UTC) → UTC
--   같은 행 안에서도 갈렸다. drawing_sessions 의 started_at 은 KST, created_at 은 UTC 였다.
--
--   무해해 보였지만 "왜 무해한지 아무도 모르는" 상태였다. 가드레일 9절의 보관 기간
--   자동 삭제가 created_at 기준으로 돌면 테이블마다 9시간씩 다른 시점에 만료된다.
--
-- 이 마이그레이션이 하는 일
--   DB 가 채워 온 50개 컬럼(35개 테이블)을 +9시간 시프트해 KST 로 맞춘다.
--   앱이 써 온 26개 컬럼은 이미 KST 라 **건드리지 않는다.**
--
-- ⚠️ 반드시 JDBC 변경과 같은 배포에 묶여야 한다
--   application-local.yml 에 sessionVariables=time_zone='+09:00' 을 함께 넣었다.
--   그래야 이 시점 이후 DEFAULT CURRENT_TIMESTAMP 도 KST 로 쓰인다.
--   따로 배포하면 한 테이블 안에 두 규약이 섞이고, 그 뒤로는 **데이터만으로 판별할 수 없다.**
--
-- ⚠️ CONVERT_TZ 를 쓰지 않은 이유
--   CONVERT_TZ(col,'UTC','Asia/Seoul') 가 의미상 정확하지만, mysql.time_zone 테이블이
--   없는 환경에서는 **NULL 을 반환한다.** 그 경우 시각이 통째로 NULL 이 된다.
--   한국은 1988년 이후 서머타임이 없어 고정 +9시간과 결과가 같으므로, 조용히 데이터를
--   지울 위험이 없는 쪽을 택한다.
--
-- ⚠️ ON UPDATE CURRENT_TIMESTAMP 주의
--   대상 테이블의 ON UPDATE 컬럼 17개는 전부 아래 SET 절에 **명시적으로** 들어간다.
--   명시하지 않으면 다른 컬럼을 UPDATE 하는 순간 현재시각으로 덮어써져 값이 사라진다.
--
-- 되돌리기: 같은 컬럼에 -9시간. 되돌릴 지점 b209-2026-07-30-1347.sql.gz.enc

UPDATE `activity_template_attachments` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `activity_templates` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `ai_question_template_risk_responses` SET
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `ai_question_templates` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `analysis_behavior_features` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `analysis_evidence_references` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `analysis_model_components` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `analysis_observation_items` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `analysis_unused_inputs` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `analysis_visual_features` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `analysis_warnings` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `audit_log_changes` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `audit_logs` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `child_response_modes` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `children` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `comments` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `complaint_actions` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `complaints` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `consent_record_evidences` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `conversation_message_audio_variants` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `conversation_sessions` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `data_export_jobs` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `drawing_session_emotions` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `drawing_sessions` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `drawing_types` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `expert_credential_files` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `expert_credentials` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `expert_follows` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `expert_profile_specialties` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `expert_profiles` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `guardian_child_relations` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `post_likes` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR;
UPDATE `storage_deletion_jobs` SET
    `created_at` = `created_at` + INTERVAL 9 HOUR,
    `requested_at` = `requested_at` + INTERVAL 9 HOUR,
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `user_data_retention_settings` SET
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
UPDATE `user_notification_settings` SET
    `updated_at` = `updated_at` + INTERVAL 9 HOUR;
