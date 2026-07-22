-- 도담 아동 그림·대화 서비스 ERDCloud 통합 스키마 v1.2
-- Target: MySQL 8.0+
-- Encoding: UTF-8 / utf8mb4
-- Refresh Token은 Redis에서 관리하며 이 스키마에 저장하지 않는다.

SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET FOREIGN_KEY_CHECKS = 0;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `activity_template_attachments` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '미술 활동 자료 첨부 파일 ID',
  `activity_template_id` bigint NOT NULL COMMENT '미술 활동 자료 ID',
  `storage_key` varchar(1000) NOT NULL COMMENT '첨부 파일 저장 Key',
  `storage_key_hash` char(64) NOT NULL COMMENT '첨부 파일 저장 Key SHA-256 Hash',
  `file_name` varchar(255) DEFAULT NULL COMMENT '원본 파일명',
  `mime_type` varchar(100) DEFAULT NULL COMMENT 'MIME 유형',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_activity_template_attachments_key_hash` (`storage_key_hash`),
  UNIQUE KEY `uk_activity_template_attachments_order` (`activity_template_id`,`display_order`),
  CONSTRAINT `fk_activity_template_attachments_template_id` FOREIGN KEY (`activity_template_id`) REFERENCES `activity_templates` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_activity_template_attachments_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='미술 활동 자료 첨부 파일';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `activity_templates` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '미술 활동 자료 ID',
  `expert_profile_id` bigint NOT NULL COMMENT '전문가 프로필 ID',
  `title` varchar(200) NOT NULL COMMENT '자료 제목',
  `summary` text COMMENT '자료 요약',
  `content` longtext NOT NULL COMMENT '자료 내용',
  `age_group` varchar(30) NOT NULL COMMENT '권장 연령 그룹',
  `activity_type` varchar(50) NOT NULL COMMENT '활동 유형',
  `thumbnail_key` varchar(1000) DEFAULT NULL COMMENT 'Thumbnail 저장 Key',
  `is_visible` tinyint(1) NOT NULL DEFAULT '1' COMMENT '공개 여부',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `deleted_at` datetime(6) DEFAULT NULL COMMENT '삭제 일시',
  PRIMARY KEY (`id`),
  KEY `idx_activity_templates_expert_created_at` (`expert_profile_id`,`created_at`),
  KEY `idx_activity_templates_visible_created_at` (`is_visible`,`created_at`),
  CONSTRAINT `fk_activity_templates_expert_profile_id` FOREIGN KEY (`expert_profile_id`) REFERENCES `expert_profiles` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='미술 활동 자료';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ai_question_template_options` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'AI 질문 Template 선택지 ID',
  `question_template_id` bigint NOT NULL COMMENT 'AI 질문 Template ID',
  `option_key` varchar(80) NOT NULL COMMENT 'API 선택지 식별자',
  `option_type` varchar(30) NOT NULL COMMENT '선택지 유형',
  `option_value` varchar(255) NOT NULL COMMENT '선택지 값',
  `label` varchar(200) NOT NULL COMMENT '표시 문구',
  `emoji` varchar(20) DEFAULT NULL COMMENT '표시 Emoji',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_ai_question_template_options_template_key` (`question_template_id`,`option_key`),
  UNIQUE KEY `uk_ai_question_template_options_template_order` (`question_template_id`,`display_order`),
  CONSTRAINT `fk_ai_question_template_options_template_id` FOREIGN KEY (`question_template_id`) REFERENCES `ai_question_templates` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_ai_question_template_options_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='AI 질문 Template 선택지';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ai_question_template_risk_responses` (
  `question_template_id` bigint NOT NULL COMMENT 'AI 질문 Template ID',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '0' COMMENT '위험 응답 안내 활성 여부',
  `guardian_guide_template` text COMMENT '보호자 안내 Template',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`question_template_id`),
  CONSTRAINT `fk_ai_question_template_risk_responses_template_id` FOREIGN KEY (`question_template_id`) REFERENCES `ai_question_templates` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_ai_question_template_risk_responses_guide` CHECK (((`is_enabled` = false) or (`guardian_guide_template` is not null)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='AI 질문 Template 위험 응답 안내';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ai_question_templates` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'AI 질문 Template ID',
  `drawing_type_id` bigint DEFAULT NULL COMMENT '그림 활동 유형 ID',
  `created_by_user_id` bigint DEFAULT NULL COMMENT '생성자 사용자 ID',
  `updated_by_user_id` bigint DEFAULT NULL COMMENT '수정자 사용자 ID',
  `template_type` varchar(20) NOT NULL COMMENT 'Template 유형',
  `age_group` varchar(30) NOT NULL COMMENT '연령 그룹',
  `difficulty` varchar(30) NOT NULL COMMENT '질문 난이도',
  `question_purpose` varchar(50) NOT NULL COMMENT '질문 목적',
  `question_text` text NOT NULL COMMENT '질문 내용',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT '활성 여부',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  KEY `fk_ai_question_templates_created_by_id` (`created_by_user_id`),
  KEY `fk_ai_question_templates_updated_by_id` (`updated_by_user_id`),
  KEY `idx_ai_question_templates_lookup` (`drawing_type_id`,`age_group`,`difficulty`,`is_active`),
  CONSTRAINT `fk_ai_question_templates_created_by_id` FOREIGN KEY (`created_by_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_ai_question_templates_drawing_type_id` FOREIGN KEY (`drawing_type_id`) REFERENCES `drawing_types` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_ai_question_templates_updated_by_id` FOREIGN KEY (`updated_by_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='AI 질문 Template';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analyses` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '분석 ID',
  `drawing_session_id` bigint NOT NULL COMMENT '그림 활동 세션 ID',
  `retry_of_analysis_id` bigint DEFAULT NULL COMMENT '재시도 원본 분석 ID',
  `analysis_type` varchar(20) NOT NULL COMMENT '분석 유형',
  `idempotency_key` varchar(100) NOT NULL COMMENT 'Idempotency Key',
  `input_checksum_sha256` char(64) DEFAULT NULL COMMENT '입력 SHA-256 Checksum',
  `analysis_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '분석 상태',
  `trigger_reason` varchar(30) DEFAULT NULL COMMENT '분석 실행 사유',
  `model_name` varchar(100) DEFAULT NULL COMMENT 'Model 이름',
  `model_version` varchar(100) DEFAULT NULL COMMENT 'Model 버전',
  `confidence` decimal(5,4) DEFAULT NULL COMMENT '신뢰도',
  `error_code` varchar(80) DEFAULT NULL COMMENT '오류 코드',
  `error_message` text COMMENT '오류 메시지',
  `requested_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '요청 일시',
  `started_at` datetime(6) DEFAULT NULL COMMENT '시작 일시',
  `completed_at` datetime(6) DEFAULT NULL COMMENT '분석 완료 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_analyses_idempotency_key` (`idempotency_key`),
  KEY `fk_analyses_retry_of_analysis_id` (`retry_of_analysis_id`),
  KEY `idx_analyses_drawing_session_id` (`drawing_session_id`,`requested_at`),
  CONSTRAINT `fk_analyses_drawing_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_analyses_retry_of_analysis_id` FOREIGN KEY (`retry_of_analysis_id`) REFERENCES `analyses` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_analyses_confidence` CHECK (((`confidence` is null) or ((`confidence` >= 0) and (`confidence` <= 1)))),
  CONSTRAINT `ck_analyses_status` CHECK ((`analysis_status` in (_utf8mb4'PENDING',_utf8mb4'PROCESSING',_utf8mb4'PARTIAL_SUCCESS',_utf8mb4'SUCCESS',_utf8mb4'FAILED'))),
  CONSTRAINT `ck_analyses_trigger_reason` CHECK (((`trigger_reason` is null) or (`trigger_reason` in (_utf8mb4'PAUSE',_utf8mb4'INTERVAL',_utf8mb4'STROKE_COUNT',_utf8mb4'CHANGE_RATIO',_utf8mb4'USER_REQUEST',_utf8mb4'DRAWING_COMPLETE',_utf8mb4'ACTIVITY_COMPLETE',_utf8mb4'RETRY')))),
  CONSTRAINT `ck_analyses_type` CHECK ((`analysis_type` in (_utf8mb4'INTERMEDIATE',_utf8mb4'FINAL')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_behavior_features` (
  `behavior_feature_id` bigint NOT NULL AUTO_INCREMENT COMMENT '행동 특징 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `input_method` varchar(30) DEFAULT NULL COMMENT '입력 방식',
  `drawing_duration_ms` bigint DEFAULT NULL COMMENT '그림 소요 시간(ms)',
  `active_drawing_duration_ms` bigint DEFAULT NULL COMMENT '실제 그림 시간(ms)',
  `pause_count` int DEFAULT NULL COMMENT '일시 정지 횟수',
  `total_pause_duration_ms` bigint DEFAULT NULL COMMENT '전체 일시 정지 시간(ms)',
  `stroke_count` int DEFAULT NULL COMMENT 'Stroke 수',
  `average_stroke_speed` decimal(10,3) DEFAULT NULL COMMENT '평균 Stroke 속도',
  `average_stroke_length` decimal(10,3) DEFAULT NULL COMMENT '평균 Stroke 길이',
  `undo_count` int DEFAULT NULL COMMENT '실행 취소 횟수',
  `redo_count` int DEFAULT NULL COMMENT '다시 실행 횟수',
  `erase_count` int DEFAULT NULL COMMENT '지우기 횟수',
  `canvas_clear_count` int DEFAULT NULL COMMENT 'Canvas 전체 지우기 횟수',
  `tool_change_count` int DEFAULT NULL COMMENT '도구 변경 횟수',
  `color_change_count` int DEFAULT NULL COMMENT '색상 변경 횟수',
  `average_pressure` decimal(8,3) DEFAULT NULL COMMENT '평균 압력',
  `pressure_deviation` decimal(8,3) DEFAULT NULL COMMENT '압력 편차',
  `save_count` int DEFAULT NULL COMMENT '저장 횟수',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`behavior_feature_id`),
  KEY `idx_analysis_behavior_features_analysis_id` (`analysis_id`),
  CONSTRAINT `fk_analysis_behavior_features_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_behavior_features_input_method` CHECK (((`input_method` is null) or (`input_method` in (_utf8mb4'CANVAS',_utf8mb4'UPLOAD'))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 행동 특징';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_conversation_summaries` (
  `conversation_summary_id` bigint NOT NULL AUTO_INCREMENT COMMENT '대화 분석 요약 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `conversation_session_id` bigint DEFAULT NULL COMMENT '대화 세션 ID',
  `summary_text` text COMMENT '요약 내용',
  `main_topic` varchar(100) DEFAULT NULL COMMENT '주요 주제',
  `secondary_topic` varchar(100) DEFAULT NULL COMMENT '보조 주제',
  `expressed_emotion` varchar(50) DEFAULT NULL COMMENT '표현 감정',
  `emotion_source` varchar(30) DEFAULT NULL COMMENT '감정 출처',
  `emotion_need` varchar(255) DEFAULT NULL COMMENT '감정 관련 필요',
  `question_count` int DEFAULT NULL COMMENT '질문 수',
  `response_count` int DEFAULT NULL COMMENT '응답 수',
  `skipped_question_count` int DEFAULT NULL COMMENT '건너뛴 질문 수',
  `unrecognized_speech_count` int DEFAULT NULL COMMENT '음성 인식 실패 수',
  `representative_utterance` text COMMENT '대표 발화',
  `unanswered_topic` text COMMENT '미응답 주제',
  `summary_model_version` varchar(50) DEFAULT NULL COMMENT '요약 Model 버전',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`conversation_summary_id`),
  KEY `fk_analysis_conversation_summaries_session_id` (`conversation_session_id`),
  KEY `idx_analysis_conversation_summaries_analysis_id` (`analysis_id`),
  CONSTRAINT `fk_analysis_conversation_summaries_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_analysis_conversation_summaries_session_id` FOREIGN KEY (`conversation_session_id`) REFERENCES `conversation_sessions` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 분석 요약';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_detected_objects` (
  `detected_object_id` bigint NOT NULL AUTO_INCREMENT COMMENT '탐지 객체 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `drawing_asset_id` bigint NOT NULL COMMENT '그림 파일 ID',
  `object_code` varchar(50) DEFAULT NULL COMMENT '객체 코드',
  `object_name` varchar(100) DEFAULT NULL COMMENT '객체명',
  `confidence_score` decimal(5,4) DEFAULT NULL COMMENT '신뢰도 점수',
  `bbox_x` decimal(8,6) DEFAULT NULL COMMENT 'Bounding Box X 좌표',
  `bbox_y` decimal(8,6) DEFAULT NULL COMMENT 'Bounding Box Y 좌표',
  `bbox_width` decimal(8,6) DEFAULT NULL COMMENT 'Bounding Box 너비',
  `bbox_height` decimal(8,6) DEFAULT NULL COMMENT 'Bounding Box 높이',
  `area_ratio` decimal(8,6) DEFAULT NULL COMMENT '면적 비율',
  `detection_order` int DEFAULT NULL COMMENT '탐지 순서',
  `model_version` varchar(50) DEFAULT NULL COMMENT 'Model 버전',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`detected_object_id`),
  KEY `idx_analysis_detected_objects_analysis_id` (`analysis_id`),
  KEY `idx_analysis_detected_objects_drawing_asset_id` (`drawing_asset_id`),
  CONSTRAINT `fk_analysis_detected_objects_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_analysis_detected_objects_drawing_asset_id` FOREIGN KEY (`drawing_asset_id`) REFERENCES `drawing_assets` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_detected_objects_confidence` CHECK (((`confidence_score` is null) or ((`confidence_score` >= 0) and (`confidence_score` <= 1))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 탐지 객체';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_observation_results` (
  `observation_result_id` bigint NOT NULL AUTO_INCREMENT COMMENT '관찰 결과 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `result_version` int DEFAULT NULL COMMENT '결과 버전',
  `overall_summary` text COMMENT '전체 요약',
  `observed_emotion` varchar(50) DEFAULT NULL COMMENT '전문가 내부 검토용 관찰 감정',
  `emotion_confidence` decimal(5,4) DEFAULT NULL COMMENT '전문가 내부 검토용 감정 신뢰도',
  `positive_signals` text COMMENT '긍정 신호',
  `attention_points` text COMMENT '관찰 필요 지점',
  `evidence_summary` text COMMENT '근거 요약',
  `guardian_guidance` text COMMENT '보호자 안내',
  `follow_up_question` text COMMENT '후속 질문',
  `is_expert_review_required` tinyint(1) DEFAULT NULL COMMENT '전문가 검토 필요 여부',
  `review_status` varchar(30) DEFAULT NULL COMMENT '검토 상태',
  `reviewed_at` datetime(6) DEFAULT NULL COMMENT '검토 일시',
  `disclaimer_text` text COMMENT '주의 문구',
  `generated_model_version` varchar(50) DEFAULT NULL COMMENT '생성 Model 버전',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`observation_result_id`),
  KEY `idx_analysis_observation_results_analysis_id` (`analysis_id`),
  CONSTRAINT `fk_analysis_observation_results_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_observation_results_emotion_confidence` CHECK (((`emotion_confidence` is null) or ((`emotion_confidence` >= 0) and (`emotion_confidence` <= 1))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 관찰 결과';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_unused_inputs` (
  `unused_input_id` bigint NOT NULL AUTO_INCREMENT COMMENT '분석 제외 입력 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `source_type` varchar(30) DEFAULT NULL COMMENT '입력 출처 유형',
  `source_id` bigint DEFAULT NULL COMMENT '입력 출처 ID',
  `input_name` varchar(100) DEFAULT NULL COMMENT '입력 이름',
  `input_sequence` int DEFAULT NULL COMMENT '입력 순번',
  `input_value_summary` text COMMENT '입력값 요약',
  `excluded_reason_code` varchar(50) DEFAULT NULL COMMENT '제외 사유 코드',
  `excluded_reason_detail` text COMMENT '제외 사유 상세',
  `validation_status` varchar(30) DEFAULT NULL COMMENT '검증 상태',
  `retryable` tinyint(1) DEFAULT NULL COMMENT '재시도 가능 여부',
  `occurred_at` datetime(6) DEFAULT NULL COMMENT '발생 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`unused_input_id`),
  KEY `idx_analysis_unused_inputs_analysis_id` (`analysis_id`),
  CONSTRAINT `fk_analysis_unused_inputs_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 제외 입력';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_visual_features` (
  `visual_feature_id` bigint NOT NULL AUTO_INCREMENT COMMENT '시각 특징 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `canvas_coverage_ratio` decimal(5,4) DEFAULT NULL COMMENT 'Canvas 점유 비율',
  `primary_color` varchar(20) DEFAULT NULL COMMENT '주요 색상',
  `primary_color_ratio` decimal(5,4) DEFAULT NULL COMMENT '주요 색상 비율',
  `used_color_count` int DEFAULT NULL COMMENT '사용 색상 수',
  `average_brightness` decimal(6,3) DEFAULT NULL COMMENT '평균 명도',
  `average_saturation` decimal(6,3) DEFAULT NULL COMMENT '평균 채도',
  `average_line_thickness` decimal(8,3) DEFAULT NULL COMMENT '평균 선 굵기',
  `line_thickness_deviation` decimal(8,3) DEFAULT NULL COMMENT '선 굵기 편차',
  `edge_density` decimal(5,4) DEFAULT NULL COMMENT 'Edge 밀도',
  `fill_ratio` decimal(5,4) DEFAULT NULL COMMENT '채움 비율',
  `overlap_ratio` decimal(5,4) DEFAULT NULL COMMENT '겹침 비율',
  `symmetry_score` decimal(5,4) DEFAULT NULL COMMENT '대칭 점수',
  `center_of_mass_x` decimal(8,6) DEFAULT NULL COMMENT '무게 중심 X 좌표',
  `center_of_mass_y` decimal(8,6) DEFAULT NULL COMMENT '무게 중심 Y 좌표',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`visual_feature_id`),
  KEY `idx_analysis_visual_features_analysis_id` (`analysis_id`),
  CONSTRAINT `fk_analysis_visual_features_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 시각 특징';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `audit_log_changes` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '감사 로그 변경 항목 ID',
  `audit_log_id` bigint NOT NULL COMMENT '감사 로그 ID',
  `field_path` varchar(255) NOT NULL COMMENT '변경 필드 경로',
  `value_type` varchar(20) NOT NULL DEFAULT 'STRING' COMMENT '값 유형',
  `snapshot_value` text COMMENT '대상 Snapshot 값',
  `before_value` text COMMENT '변경 전 값',
  `after_value` text COMMENT '변경 후 값',
  `is_masked` tinyint(1) NOT NULL DEFAULT '0' COMMENT '민감값 마스킹 여부',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_audit_log_changes_log_field` (`audit_log_id`,`field_path`),
  CONSTRAINT `fk_audit_log_changes_audit_log_id` FOREIGN KEY (`audit_log_id`) REFERENCES `audit_logs` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_audit_log_changes_type` CHECK ((`value_type` in (_utf8mb4'STRING',_utf8mb4'NUMBER',_utf8mb4'BOOLEAN',_utf8mb4'DATE',_utf8mb4'DATETIME',_utf8mb4'NULL')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='감사 로그 변경 항목';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `audit_logs` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '감사 로그 ID',
  `actor_user_id` bigint DEFAULT NULL COMMENT '처리 사용자 ID',
  `action_type` varchar(80) NOT NULL COMMENT '행위 유형',
  `resource_type` varchar(50) NOT NULL COMMENT '대상 Resource 유형',
  `resource_id` bigint DEFAULT NULL COMMENT '대상 Resource ID',
  `ip_address` varchar(45) DEFAULT NULL COMMENT 'IP 주소',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  KEY `idx_audit_logs_resource` (`resource_type`,`resource_id`,`created_at`),
  KEY `idx_audit_logs_actor_user_id` (`actor_user_id`,`created_at`),
  CONSTRAINT `fk_audit_logs_actor_user_id` FOREIGN KEY (`actor_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='감사 로그';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `auth_accounts` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '인증 계정 ID',
  `user_id` bigint NOT NULL COMMENT '사용자 ID',
  `provider` varchar(20) NOT NULL COMMENT '인증 제공자',
  `provider_subject` varchar(255) NOT NULL COMMENT '인증 제공자 사용자 식별자',
  `login_email` varchar(255) DEFAULT NULL COMMENT '로그인 이메일',
  `local_login_email` varchar(255) GENERATED ALWAYS AS ((case when (`provider` = _utf8mb4'LOCAL') then `login_email` else NULL end)) STORED COMMENT 'Local 인증 이메일 중복 검사용 생성값',
  `password_hash` varchar(255) DEFAULT NULL COMMENT '비밀번호 해시',
  `email_verified_at` datetime(6) DEFAULT NULL COMMENT '이메일 인증 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_auth_accounts_provider_subject` (`provider`,`provider_subject`),
  UNIQUE KEY `uk_auth_accounts_local_login_email` (`local_login_email`),
  KEY `fk_auth_accounts_user_id` (`user_id`),
  CONSTRAINT `fk_auth_accounts_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_auth_accounts_local_credentials` CHECK (((`provider` <> _utf8mb4'LOCAL') or ((`login_email` is not null) and (`password_hash` is not null)))),
  CONSTRAINT `ck_auth_accounts_provider` CHECK ((`provider` in (_utf8mb4'LOCAL',_utf8mb4'KAKAO',_utf8mb4'GOOGLE',_utf8mb4'NAVER')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='인증 계정';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `child_response_modes` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '아동 응답 방식 ID',
  `child_id` bigint NOT NULL COMMENT '아동 ID',
  `response_mode` varchar(20) NOT NULL COMMENT '응답 방식',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_child_response_modes_child_mode` (`child_id`,`response_mode`),
  UNIQUE KEY `uk_child_response_modes_child_order` (`child_id`,`display_order`),
  CONSTRAINT `fk_child_response_modes_child_id` FOREIGN KEY (`child_id`) REFERENCES `children` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_child_response_modes_mode` CHECK ((`response_mode` in (_utf8mb4'VOICE',_utf8mb4'EMOJI',_utf8mb4'COLOR',_utf8mb4'PICTURE',_utf8mb4'TEXT'))),
  CONSTRAINT `ck_child_response_modes_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='아동 응답 방식';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `children` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '아동 ID',
  `nickname` varchar(50) NOT NULL COMMENT '닉네임',
  `birth_date` date NOT NULL COMMENT '생년월일',
  `profile_image_url` varchar(1000) DEFAULT NULL COMMENT '프로필 이미지 URL',
  `preferred_character` varchar(50) DEFAULT NULL COMMENT '선호 캐릭터',
  `question_difficulty` varchar(30) NOT NULL DEFAULT 'PRESCHOOL' COMMENT '질문 난이도',
  `tutorial_status` varchar(20) NOT NULL DEFAULT 'NOT_STARTED' COMMENT '튜토리얼 상태',
  `profile_status` varchar(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '프로필 상태',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `deleted_at` datetime(6) DEFAULT NULL COMMENT '삭제 일시',
  PRIMARY KEY (`id`),
  CONSTRAINT `ck_children_profile_status` CHECK ((`profile_status` in (_utf8mb4'ACTIVE',_utf8mb4'DELETED'))),
  CONSTRAINT `ck_children_question_difficulty` CHECK ((`question_difficulty` in (_utf8mb4'PRESCHOOL',_utf8mb4'LOWER_ELEMENTARY',_utf8mb4'UPPER_ELEMENTARY',_utf8mb4'SUPPORT'))),
  CONSTRAINT `ck_children_tutorial_status` CHECK ((`tutorial_status` in (_utf8mb4'NOT_STARTED',_utf8mb4'IN_PROGRESS',_utf8mb4'COMPLETED',_utf8mb4'SKIPPED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='아동';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `comments` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '댓글 ID',
  `post_id` bigint NOT NULL COMMENT '게시글 ID',
  `author_user_id` bigint DEFAULT NULL COMMENT '작성자 사용자 ID',
  `content` text NOT NULL COMMENT '댓글 내용',
  `is_anonymous` tinyint(1) NOT NULL DEFAULT '0' COMMENT '익명 여부',
  `is_visible` tinyint(1) NOT NULL DEFAULT '1' COMMENT '공개 여부',
  `comment_status` varchar(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '댓글 상태',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `deleted_at` datetime(6) DEFAULT NULL COMMENT '삭제 일시',
  PRIMARY KEY (`id`),
  KEY `idx_comments_author_user_id` (`author_user_id`),
  KEY `idx_comments_post_created_at` (`post_id`,`created_at`),
  CONSTRAINT `fk_comments_author_user_id` FOREIGN KEY (`author_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_comments_post_id` FOREIGN KEY (`post_id`) REFERENCES `community_posts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_comments_status` CHECK ((`comment_status` in (_utf8mb4'ACTIVE',_utf8mb4'HIDDEN',_utf8mb4'DELETED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='댓글';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `community_post_template_fields` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '커뮤니티 Template 항목 ID',
  `community_post_id` bigint NOT NULL COMMENT '게시글 ID',
  `field_code` varchar(80) NOT NULL COMMENT 'Template 항목 코드',
  `value_type` varchar(20) NOT NULL DEFAULT 'STRING' COMMENT '값 유형',
  `value_text` text NOT NULL COMMENT 'Template 항목 값',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_community_post_template_fields_post_code` (`community_post_id`,`field_code`),
  UNIQUE KEY `uk_community_post_template_fields_post_order` (`community_post_id`,`display_order`),
  CONSTRAINT `fk_community_post_template_fields_post_id` FOREIGN KEY (`community_post_id`) REFERENCES `community_posts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_community_post_template_fields_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_community_post_template_fields_type` CHECK ((`value_type` in (_utf8mb4'STRING',_utf8mb4'NUMBER',_utf8mb4'BOOLEAN',_utf8mb4'DATE')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='커뮤니티 게시글 Template 항목';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `community_posts` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '게시글 ID',
  `author_user_id` bigint DEFAULT NULL COMMENT '작성자 사용자 ID',
  `post_type` varchar(40) NOT NULL COMMENT '게시글 유형',
  `title` varchar(200) NOT NULL COMMENT '게시글 제목',
  `content` longtext NOT NULL COMMENT '게시글 내용',
  `is_anonymous` tinyint(1) NOT NULL DEFAULT '0' COMMENT '익명 여부',
  `is_visible` tinyint(1) NOT NULL DEFAULT '1' COMMENT '공개 여부',
  `post_status` varchar(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '게시글 상태',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `deleted_at` datetime(6) DEFAULT NULL COMMENT '삭제 일시',
  PRIMARY KEY (`id`),
  KEY `idx_community_posts_author_created_at` (`author_user_id`,`created_at`),
  CONSTRAINT `fk_community_posts_author_user_id` FOREIGN KEY (`author_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_community_posts_status` CHECK ((`post_status` in (_utf8mb4'ACTIVE',_utf8mb4'HIDDEN',_utf8mb4'DELETED'))),
  CONSTRAINT `ck_community_posts_type` CHECK ((`post_type` in (_utf8mb4'GUARDIAN_STORY',_utf8mb4'ACTIVITY_REVIEW',_utf8mb4'EXPERT_COLUMN',_utf8mb4'ART_RESOURCE',_utf8mb4'DRAWING_GUIDE',_utf8mb4'EXPERT_QNA',_utf8mb4'NOTICE')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='커뮤니티 게시글';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `complaint_actions` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '신고 처리 이력 ID',
  `complaint_id` bigint NOT NULL COMMENT '신고 ID',
  `actor_user_id` bigint DEFAULT NULL COMMENT '처리 관리자 사용자 ID',
  `action_type` varchar(30) NOT NULL COMMENT '처리 유형',
  `previous_status` varchar(20) NOT NULL COMMENT '처리 전 상태',
  `next_status` varchar(20) NOT NULL COMMENT '처리 후 상태',
  `resolution_note` text COMMENT '처리 메모',
  `notify_reporter` tinyint(1) NOT NULL DEFAULT '0' COMMENT '신고자 알림 여부',
  `notify_target_author` tinyint(1) NOT NULL DEFAULT '0' COMMENT '대상 작성자 알림 여부',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  KEY `fk_complaint_actions_actor_user_id` (`actor_user_id`),
  KEY `idx_complaint_actions_complaint_created_at` (`complaint_id`,`created_at`),
  CONSTRAINT `fk_complaint_actions_actor_user_id` FOREIGN KEY (`actor_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_complaint_actions_complaint_id` FOREIGN KEY (`complaint_id`) REFERENCES `complaints` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_complaint_actions_type` CHECK ((`action_type` in (_utf8mb4'NO_ACTION',_utf8mb4'HIDE_CONTENT',_utf8mb4'DELETE_CONTENT',_utf8mb4'WARN_USER',_utf8mb4'SUSPEND_USER',_utf8mb4'HIDE_REPORT',_utf8mb4'REQUEST_REANALYSIS')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='신고 처리 이력';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `complaints` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '신고 ID',
  `reporter_user_id` bigint DEFAULT NULL COMMENT '신고자 사용자 ID',
  `target_type` varchar(20) NOT NULL COMMENT '신고 대상 유형',
  `target_report_id` bigint DEFAULT NULL COMMENT '대상 리포트 ID',
  `target_post_id` bigint DEFAULT NULL COMMENT '대상 게시글 ID',
  `target_comment_id` bigint DEFAULT NULL COMMENT '대상 댓글 ID',
  `reason_code` varchar(50) NOT NULL COMMENT '신고 사유 코드',
  `detail_text` text COMMENT '신고 상세',
  `complaint_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '신고 처리 상태',
  `assigned_admin_user_id` bigint DEFAULT NULL COMMENT '담당 관리자 사용자 ID',
  `resolved_at` datetime(6) DEFAULT NULL COMMENT '처리 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  KEY `fk_complaints_target_report_id` (`target_report_id`),
  KEY `fk_complaints_target_post_id` (`target_post_id`),
  KEY `fk_complaints_target_comment_id` (`target_comment_id`),
  KEY `fk_complaints_assigned_admin_user_id` (`assigned_admin_user_id`),
  KEY `idx_complaints_status_created_at` (`complaint_status`,`created_at`),
  KEY `idx_complaints_reporter_created_at` (`reporter_user_id`,`created_at`),
  CONSTRAINT `fk_complaints_assigned_admin_user_id` FOREIGN KEY (`assigned_admin_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_complaints_reporter_user_id` FOREIGN KEY (`reporter_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_complaints_target_comment_id` FOREIGN KEY (`target_comment_id`) REFERENCES `comments` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_complaints_target_post_id` FOREIGN KEY (`target_post_id`) REFERENCES `community_posts` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_complaints_target_report_id` FOREIGN KEY (`target_report_id`) REFERENCES `reports` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_complaints_status` CHECK ((`complaint_status` in (_utf8mb4'PENDING',_utf8mb4'REVIEWING',_utf8mb4'RESOLVED',_utf8mb4'REJECTED'))),
  CONSTRAINT `ck_complaints_target` CHECK ((((`target_type` = _utf8mb4'REPORT') and (`target_report_id` is not null) and (`target_post_id` is null) and (`target_comment_id` is null)) or ((`target_type` = _utf8mb4'POST') and (`target_report_id` is null) and (`target_post_id` is not null) and (`target_comment_id` is null)) or ((`target_type` = _utf8mb4'COMMENT') and (`target_report_id` is null) and (`target_post_id` is null) and (`target_comment_id` is not null))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='신고';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `consent_record_evidences` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '동의 증빙 항목 ID',
  `consent_record_id` bigint NOT NULL COMMENT '동의 이력 ID',
  `evidence_key` varchar(80) NOT NULL COMMENT '증빙 항목 코드',
  `value_type` varchar(20) NOT NULL DEFAULT 'STRING' COMMENT '값 유형',
  `value_text` text NOT NULL COMMENT '증빙 값',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_consent_record_evidences_record_key` (`consent_record_id`,`evidence_key`),
  CONSTRAINT `fk_consent_record_evidences_record_id` FOREIGN KEY (`consent_record_id`) REFERENCES `consent_records` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_consent_record_evidences_type` CHECK ((`value_type` in (_utf8mb4'STRING',_utf8mb4'NUMBER',_utf8mb4'BOOLEAN',_utf8mb4'DATETIME')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='동의 증빙 항목';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `consent_records` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '동의 이력 ID',
  `consent_term_id` bigint NOT NULL COMMENT '동의 약관 ID',
  `actor_user_id` bigint DEFAULT NULL COMMENT '처리 사용자 ID',
  `subject_child_id` bigint DEFAULT NULL COMMENT '동의 대상 아동 ID',
  `subject_reference_hash` char(64) NOT NULL COMMENT '동의 대상 참조 Hash',
  `action` varchar(20) NOT NULL COMMENT '동의 또는 철회 유형',
  `ip_address` varchar(45) DEFAULT NULL COMMENT 'IP 주소',
  `user_agent` varchar(500) DEFAULT NULL COMMENT 'User-Agent',
  `recorded_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '기록 일시',
  PRIMARY KEY (`id`),
  KEY `fk_consent_records_term_id` (`consent_term_id`),
  KEY `fk_consent_records_actor_user_id` (`actor_user_id`),
  KEY `fk_consent_records_subject_child_id` (`subject_child_id`),
  KEY `idx_consent_records_subject_hash` (`subject_reference_hash`,`recorded_at`),
  CONSTRAINT `fk_consent_records_actor_user_id` FOREIGN KEY (`actor_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_consent_records_subject_child_id` FOREIGN KEY (`subject_child_id`) REFERENCES `children` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_consent_records_term_id` FOREIGN KEY (`consent_term_id`) REFERENCES `consent_terms` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_consent_records_action` CHECK ((`action` in (_utf8mb4'AGREE',_utf8mb4'WITHDRAW')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='동의 이력';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `consent_terms` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '동의 약관 ID',
  `term_code` varchar(50) NOT NULL COMMENT '약관 코드',
  `target_scope` varchar(10) NOT NULL COMMENT '동의 대상 범위',
  `is_required` tinyint(1) NOT NULL COMMENT '필수 여부',
  `version` varchar(30) NOT NULL COMMENT '약관 버전',
  `title` varchar(150) NOT NULL COMMENT '약관 제목',
  `content_url` varchar(1000) DEFAULT NULL COMMENT '내용 URL',
  `effective_at` datetime(6) NOT NULL COMMENT '시행 일시',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT '활성 여부',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_consent_terms_code_version` (`term_code`,`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='동의 약관';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `conversation_message_audio_variants` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '대화 음성 변형 ID',
  `conversation_message_id` bigint NOT NULL COMMENT '대화 메시지 ID',
  `voice_code` varchar(50) NOT NULL COMMENT '음성 코드',
  `speech_speed` decimal(4,2) NOT NULL DEFAULT '1.00' COMMENT '재생 속도',
  `storage_key` varchar(1000) NOT NULL COMMENT '음성 파일 저장 Key',
  `checksum_sha256` char(64) NOT NULL COMMENT '음성 파일 SHA-256 Checksum',
  `mime_type` varchar(100) NOT NULL COMMENT 'MIME 유형',
  `file_size_bytes` bigint NOT NULL COMMENT '파일 크기(Byte)',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_conversation_audio_variant` (`conversation_message_id`,`voice_code`,`speech_speed`),
  CONSTRAINT `fk_conversation_audio_variant_message_id` FOREIGN KEY (`conversation_message_id`) REFERENCES `conversation_messages` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_conversation_audio_variant_size` CHECK ((`file_size_bytes` > 0)),
  CONSTRAINT `ck_conversation_audio_variant_speed` CHECK ((`speech_speed` between 0.80 and 1.20))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 음성 변형';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `conversation_message_options` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '대화 메시지 선택지 ID',
  `conversation_message_id` bigint NOT NULL COMMENT '질문 메시지 ID',
  `template_option_id` bigint DEFAULT NULL COMMENT '원본 Template 선택지 ID',
  `option_key` varchar(80) NOT NULL COMMENT 'API 선택지 식별자 Snapshot',
  `option_type` varchar(30) NOT NULL COMMENT '선택지 유형 Snapshot',
  `option_value` varchar(255) NOT NULL COMMENT '선택지 값 Snapshot',
  `label` varchar(200) NOT NULL COMMENT '표시 문구 Snapshot',
  `emoji` varchar(20) DEFAULT NULL COMMENT '표시 Emoji Snapshot',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_conversation_message_options_message_key` (`conversation_message_id`,`option_key`),
  UNIQUE KEY `uk_conversation_message_options_message_order` (`conversation_message_id`,`display_order`),
  UNIQUE KEY `uk_conversation_message_options_message_id` (`conversation_message_id`,`id`),
  KEY `fk_conversation_message_options_template_option_id` (`template_option_id`),
  CONSTRAINT `fk_conversation_message_options_message_id` FOREIGN KEY (`conversation_message_id`) REFERENCES `conversation_messages` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_conversation_message_options_template_option_id` FOREIGN KEY (`template_option_id`) REFERENCES `ai_question_template_options` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_conversation_message_options_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 선택지 Snapshot';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `conversation_message_selected_options` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '대화 선택 응답 ID',
  `answer_message_id` bigint NOT NULL COMMENT '답변 메시지 ID',
  `question_message_id` bigint NOT NULL COMMENT '질문 메시지 ID',
  `message_option_id` bigint NOT NULL COMMENT '질문 메시지 선택지 ID',
  `label_snapshot` varchar(200) NOT NULL COMMENT '선택 당시 표시 문구',
  `selection_order` smallint NOT NULL DEFAULT '0' COMMENT '선택 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_conversation_message_selected_options_answer_option` (`answer_message_id`,`message_option_id`),
  UNIQUE KEY `uk_conversation_message_selected_options_answer_order` (`answer_message_id`,`selection_order`),
  KEY `fk_conversation_message_selected_options_answer_question` (`answer_message_id`,`question_message_id`),
  KEY `fk_conversation_message_selected_options_question_option` (`question_message_id`,`message_option_id`),
  CONSTRAINT `fk_conversation_message_selected_options_answer_question` FOREIGN KEY (`answer_message_id`, `question_message_id`) REFERENCES `conversation_messages` (`id`, `parent_message_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_conversation_message_selected_options_question_option` FOREIGN KEY (`question_message_id`, `message_option_id`) REFERENCES `conversation_message_options` (`conversation_message_id`, `id`) ON DELETE CASCADE,
  CONSTRAINT `ck_conversation_message_selected_options_order` CHECK ((`selection_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 선택 응답';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `conversation_message_targets` (
  `conversation_message_id` bigint NOT NULL COMMENT '질문 메시지 ID',
  `detected_object_id` bigint DEFAULT NULL COMMENT '분석 탐지 객체 ID',
  `object_code` varchar(50) DEFAULT NULL COMMENT '객체 코드 Snapshot',
  `object_name` varchar(100) DEFAULT NULL COMMENT '객체명 Snapshot',
  `bbox_x` decimal(8,6) NOT NULL COMMENT 'Bounding Box X 좌표',
  `bbox_y` decimal(8,6) NOT NULL COMMENT 'Bounding Box Y 좌표',
  `bbox_width` decimal(8,6) NOT NULL COMMENT 'Bounding Box 너비',
  `bbox_height` decimal(8,6) NOT NULL COMMENT 'Bounding Box 높이',
  PRIMARY KEY (`conversation_message_id`),
  KEY `fk_conversation_message_targets_detected_object_id` (`detected_object_id`),
  CONSTRAINT `fk_conversation_message_targets_detected_object_id` FOREIGN KEY (`detected_object_id`) REFERENCES `analysis_detected_objects` (`detected_object_id`) ON DELETE SET NULL,
  CONSTRAINT `fk_conversation_message_targets_message_id` FOREIGN KEY (`conversation_message_id`) REFERENCES `conversation_messages` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_conversation_message_targets_bbox` CHECK (((`bbox_x` >= 0) and (`bbox_x` <= 1) and (`bbox_y` >= 0) and (`bbox_y` <= 1) and (`bbox_width` > 0) and (`bbox_width` <= 1) and (`bbox_height` > 0) and (`bbox_height` <= 1) and ((`bbox_x` + `bbox_width`) <= 1) and ((`bbox_y` + `bbox_height`) <= 1)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 대상 객체';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `conversation_messages` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '대화 메시지 ID',
  `conversation_session_id` bigint NOT NULL COMMENT '대화 세션 ID',
  `parent_message_id` bigint DEFAULT NULL COMMENT '상위 메시지 ID',
  `question_template_id` bigint DEFAULT NULL COMMENT '질문 Template ID',
  `message_sequence` int NOT NULL COMMENT '메시지 순번',
  `sender_type` varchar(20) NOT NULL COMMENT '발신자 유형',
  `message_type` varchar(30) NOT NULL COMMENT '메시지 유형',
  `raw_text` text COMMENT '원문 Text',
  `stt_text` text COMMENT '음성 인식 Text',
  `audio_storage_key` varchar(1000) DEFAULT NULL COMMENT '음성 파일 저장 Key',
  `audio_url` varchar(1000) DEFAULT NULL COMMENT '음성 파일 URL',
  `audio_checksum_sha256` char(64) DEFAULT NULL COMMENT '음성 파일 SHA-256 Checksum',
  `speech_status` varchar(20) DEFAULT NULL COMMENT '음성 처리 상태',
  `stt_confidence` decimal(5,4) DEFAULT NULL COMMENT 'STT 신뢰도',
  `needs_guardian_confirmation` tinyint(1) NOT NULL DEFAULT '0' COMMENT '보호자 확인 필요 여부',
  `is_skipped` tinyint(1) NOT NULL DEFAULT '0' COMMENT '건너뜀 여부',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_conversation_messages_session_sequence` (`conversation_session_id`,`message_sequence`),
  UNIQUE KEY `uk_conversation_messages_id_parent` (`id`,`parent_message_id`),
  KEY `fk_conversation_messages_template_id` (`question_template_id`),
  KEY `idx_conversation_messages_parent_message_id` (`parent_message_id`),
  CONSTRAINT `fk_conversation_messages_parent_message_id` FOREIGN KEY (`parent_message_id`) REFERENCES `conversation_messages` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_conversation_messages_session_id` FOREIGN KEY (`conversation_session_id`) REFERENCES `conversation_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_conversation_messages_template_id` FOREIGN KEY (`question_template_id`) REFERENCES `ai_question_templates` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_conversation_messages_message_type` CHECK ((`message_type` in (_utf8mb4'QUESTION',_utf8mb4'VOICE_ANSWER',_utf8mb4'OPTION_ANSWER',_utf8mb4'TEXT_ANSWER',_utf8mb4'SYSTEM_NOTICE'))),
  CONSTRAINT `ck_conversation_messages_sender_type` CHECK ((`sender_type` in (_utf8mb4'AI',_utf8mb4'CHILD',_utf8mb4'GUARDIAN',_utf8mb4'SYSTEM'))),
  CONSTRAINT `ck_conversation_messages_speech_status` CHECK (((`speech_status` is null) or (`speech_status` in (_utf8mb4'NOT_REQUIRED',_utf8mb4'PENDING',_utf8mb4'PROCESSING',_utf8mb4'SUCCESS',_utf8mb4'FAILED')))),
  CONSTRAINT `ck_conversation_messages_stt_confidence` CHECK (((`stt_confidence` is null) or ((`stt_confidence` >= 0) and (`stt_confidence` <= 1))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `conversation_sessions` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '대화 세션 ID',
  `conversation_status` varchar(20) NOT NULL DEFAULT 'CONVERSING' COMMENT '대화 상태',
  `difficulty_snapshot` varchar(30) NOT NULL COMMENT '난이도 적용값',
  `max_question_count` smallint NOT NULL DEFAULT '10' COMMENT '최대 질문 수',
  `question_count` smallint NOT NULL DEFAULT '0' COMMENT '현재 질문 수',
  `started_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '시작 일시',
  `completed_at` datetime(6) DEFAULT NULL COMMENT '완료 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `drawing_session_id` bigint NOT NULL COMMENT '그림 활동 세션 ID',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_conversation_sessions_drawing_session_id` (`drawing_session_id`),
  KEY `idx_conversation_sessions_drawing_session_id` (`drawing_session_id`),
  CONSTRAINT `fk_conversation_sessions_drawing_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_conversation_sessions_question_count` CHECK (((`max_question_count` > 0) and (`question_count` >= 0) and (`question_count` <= `max_question_count`))),
  CONSTRAINT `ck_conversation_sessions_status` CHECK ((`conversation_status` in (_utf8mb4'CONVERSING',_utf8mb4'COMPLETED',_utf8mb4'FAILED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 세션';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `data_export_jobs` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '데이터 내보내기 작업 ID',
  `user_id` bigint NOT NULL COMMENT '사용자 ID',
  `export_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '내보내기 상태',
  `storage_key` varchar(1000) DEFAULT NULL COMMENT '내보내기 파일 저장 Key',
  `expires_at` datetime(6) DEFAULT NULL COMMENT '다운로드 만료 일시',
  `completed_at` datetime(6) DEFAULT NULL COMMENT '완료 일시',
  `error_code` varchar(80) DEFAULT NULL COMMENT '오류 코드',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  KEY `idx_data_export_jobs_user_created_at` (`user_id`,`created_at`),
  KEY `idx_data_export_jobs_status_created_at` (`export_status`,`created_at`),
  CONSTRAINT `fk_data_export_jobs_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_data_export_jobs_status` CHECK ((`export_status` in (_utf8mb4'PENDING',_utf8mb4'PROCESSING',_utf8mb4'COMPLETED',_utf8mb4'FAILED',_utf8mb4'EXPIRED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='데이터 내보내기 작업';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `drawing_assets` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '그림 파일 ID',
  `drawing_session_id` bigint NOT NULL COMMENT '그림 활동 세션 ID',
  `asset_type` varchar(20) NOT NULL COMMENT '파일 유형',
  `asset_version` int NOT NULL DEFAULT '1' COMMENT '파일 버전',
  `storage_key` varchar(1000) NOT NULL COMMENT '파일 저장 Key',
  `file_url` varchar(1000) DEFAULT NULL COMMENT '파일 URL',
  `mime_type` varchar(100) NOT NULL COMMENT 'MIME 유형',
  `file_size_bytes` bigint NOT NULL COMMENT '파일 크기(Byte)',
  `width_px` int DEFAULT NULL COMMENT '이미지 너비(px)',
  `height_px` int DEFAULT NULL COMMENT '이미지 높이(px)',
  `checksum_sha256` char(64) NOT NULL COMMENT 'SHA-256 Checksum',
  `last_event_sequence` bigint DEFAULT NULL COMMENT '자산에 반영된 마지막 Stroke 이벤트 순번',
  `object_code` varchar(50) DEFAULT NULL COMMENT '다중 객체 업로드 식별 코드',
  `expires_at` datetime(6) DEFAULT NULL COMMENT '만료 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  KEY `idx_drawing_assets_session_type` (`drawing_session_id`,`asset_type`,`asset_version`),
  CONSTRAINT `fk_drawing_assets_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_drawing_assets_asset_type` CHECK ((`asset_type` in (_utf8mb4'DRAFT',_utf8mb4'INTERMEDIATE',_utf8mb4'FINAL',_utf8mb4'UPLOADED',_utf8mb4'THUMBNAIL',_utf8mb4'TIMELAPSE'))),
  CONSTRAINT `ck_drawing_assets_file_size` CHECK ((`file_size_bytes` >= 0)),
  CONSTRAINT `ck_drawing_assets_last_event_sequence` CHECK (((`last_event_sequence` is null) or (`last_event_sequence` >= 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 파일';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `drawing_session_emotions` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '그림 활동 선택 감정 ID',
  `drawing_session_id` bigint NOT NULL COMMENT '그림 활동 세션 ID',
  `emotion_code` varchar(20) NOT NULL COMMENT '감정 코드',
  `selection_order` smallint NOT NULL DEFAULT '0' COMMENT '선택 순서',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_drawing_session_emotions_session_emotion` (`drawing_session_id`,`emotion_code`),
  UNIQUE KEY `uk_drawing_session_emotions_session_order` (`drawing_session_id`,`selection_order`),
  CONSTRAINT `fk_drawing_session_emotions_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_drawing_session_emotions_code` CHECK ((`emotion_code` in (_utf8mb4'HAPPY',_utf8mb4'SAD',_utf8mb4'ANGRY',_utf8mb4'SCARED',_utf8mb4'CALM',_utf8mb4'UNKNOWN'))),
  CONSTRAINT `ck_drawing_session_emotions_order` CHECK ((`selection_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 선택 감정';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `drawing_sessions` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '그림 활동 세션 ID',
  `child_id` bigint NOT NULL COMMENT '아동 ID',
  `drawing_type_id` bigint NOT NULL COMMENT '그림 활동 유형 ID',
  `started_by_user_id` bigint DEFAULT NULL COMMENT '시작 사용자 ID',
  `input_method` varchar(20) NOT NULL COMMENT '입력 방식',
  `title` varchar(200) DEFAULT NULL COMMENT '그림 제목',
  `expressed_emotion_text` text COMMENT '표현한 감정 내용',
  `session_status` varchar(20) NOT NULL DEFAULT 'IN_PROGRESS' COMMENT '세션 상태',
  `current_stage` varchar(30) NOT NULL DEFAULT 'DRAWING' COMMENT '현재 단계',
  `started_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '시작 일시',
  `completed_at` datetime(6) DEFAULT NULL COMMENT '완료 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `deleted_at` datetime(6) DEFAULT NULL COMMENT '삭제 일시',
  `idempotency_key` varchar(100) DEFAULT NULL COMMENT '그림 활동 세션 생성 요청 멱등성 Key',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_drawing_sessions_idempotency_key` (`idempotency_key`),
  KEY `fk_drawing_sessions_drawing_type_id` (`drawing_type_id`),
  KEY `fk_drawing_sessions_started_by_user_id` (`started_by_user_id`),
  KEY `idx_drawing_sessions_child_id` (`child_id`,`created_at`),
  KEY `idx_drawing_sessions_active_child` (`child_id`,`session_status`,`deleted_at`),
  CONSTRAINT `fk_drawing_sessions_child_id` FOREIGN KEY (`child_id`) REFERENCES `children` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_drawing_sessions_drawing_type_id` FOREIGN KEY (`drawing_type_id`) REFERENCES `drawing_types` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_drawing_sessions_started_by_user_id` FOREIGN KEY (`started_by_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_drawing_sessions_current_stage` CHECK ((`current_stage` in (_utf8mb4'DRAWING',_utf8mb4'ANALYZING',_utf8mb4'CONVERSING',_utf8mb4'REFLECTION',_utf8mb4'REPORTING',_utf8mb4'COMPLETED'))),
  CONSTRAINT `ck_drawing_sessions_input_method` CHECK ((`input_method` in (_utf8mb4'CANVAS',_utf8mb4'UPLOAD'))),
  CONSTRAINT `ck_drawing_sessions_session_status` CHECK ((`session_status` in (_utf8mb4'IN_PROGRESS',_utf8mb4'COMPLETED',_utf8mb4'FAILED',_utf8mb4'DELETED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 세션';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `drawing_types` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '그림 활동 유형 ID',
  `code` varchar(50) NOT NULL COMMENT '코드',
  `name` varchar(100) NOT NULL COMMENT '그림 활동 유형명',
  `activity_category` varchar(20) NOT NULL COMMENT '활동 분류',
  `selectable_by` varchar(20) NOT NULL COMMENT '선택 가능 주체',
  `recommended_age_min` tinyint DEFAULT NULL COMMENT '권장 최소 연령',
  `recommended_age_max` tinyint DEFAULT NULL COMMENT '권장 최대 연령',
  `guide_text` text COMMENT '안내 문구',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT '활성 여부',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_drawing_types_code` (`code`),
  CONSTRAINT `ck_drawing_types_activity_category` CHECK ((`activity_category` in (_utf8mb4'ASSESSMENT',_utf8mb4'GENERAL'))),
  CONSTRAINT `ck_drawing_types_age_range` CHECK (((`recommended_age_min` is null) or (`recommended_age_max` is null) or (`recommended_age_min` <= `recommended_age_max`))),
  CONSTRAINT `ck_drawing_types_selectable_by` CHECK ((`selectable_by` in (_utf8mb4'GUARDIAN',_utf8mb4'CHILD',_utf8mb4'BOTH')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 유형';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `email_verifications` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '이메일 인증 ID',
  `auth_account_id` bigint NOT NULL COMMENT '인증 계정 ID',
  `verification_code_hash` char(64) NOT NULL COMMENT '인증 코드 Hash',
  `expires_at` datetime(6) NOT NULL COMMENT '만료 일시',
  `verified_at` datetime(6) DEFAULT NULL COMMENT '인증 완료 일시',
  `attempt_count` smallint NOT NULL DEFAULT '0' COMMENT '인증 시도 횟수',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  KEY `idx_email_verifications_account_expires_at` (`auth_account_id`,`expires_at`),
  CONSTRAINT `fk_email_verifications_auth_account_id` FOREIGN KEY (`auth_account_id`) REFERENCES `auth_accounts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_email_verifications_attempt_count` CHECK ((`attempt_count` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='이메일 인증';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `expert_credential_files` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '전문가 자격 증빙 파일 ID',
  `expert_credential_id` bigint NOT NULL COMMENT '전문가 자격 ID',
  `storage_key` varchar(1000) NOT NULL COMMENT '증빙 파일 저장 Key',
  `storage_key_hash` char(64) NOT NULL COMMENT '증빙 파일 저장 Key SHA-256 Hash',
  `file_name` varchar(255) DEFAULT NULL COMMENT '원본 파일명',
  `mime_type` varchar(100) DEFAULT NULL COMMENT 'MIME 유형',
  `file_size_bytes` bigint DEFAULT NULL COMMENT '파일 크기(Byte)',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_expert_credential_files_key_hash` (`storage_key_hash`),
  UNIQUE KEY `uk_expert_credential_files_order` (`expert_credential_id`,`display_order`),
  CONSTRAINT `fk_expert_credential_files_credential_id` FOREIGN KEY (`expert_credential_id`) REFERENCES `expert_credentials` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_expert_credential_files_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_expert_credential_files_size` CHECK (((`file_size_bytes` is null) or (`file_size_bytes` > 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 자격 증빙 파일';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `expert_credentials` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '전문가 자격 ID',
  `expert_profile_id` bigint NOT NULL COMMENT '전문가 프로필 ID',
  `license_name` varchar(150) NOT NULL COMMENT '자격명',
  `issuer` varchar(150) NOT NULL COMMENT '발급 기관',
  `credential_number` varchar(100) DEFAULT NULL COMMENT '자격 번호',
  `acquired_on` date DEFAULT NULL COMMENT '취득일',
  `expires_on` date DEFAULT NULL COMMENT '만료일',
  `verification_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '검증 상태',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  KEY `idx_expert_credentials_profile_status` (`expert_profile_id`,`verification_status`),
  CONSTRAINT `fk_expert_credentials_profile_id` FOREIGN KEY (`expert_profile_id`) REFERENCES `expert_profiles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_expert_credentials_dates` CHECK (((`expires_on` is null) or (`acquired_on` is null) or (`expires_on` >= `acquired_on`))),
  CONSTRAINT `ck_expert_credentials_status` CHECK ((`verification_status` in (_utf8mb4'PENDING',_utf8mb4'VERIFIED',_utf8mb4'REJECTED',_utf8mb4'REVIEW_REQUIRED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 자격';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `expert_follows` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '전문가 팔로우 ID',
  `guardian_user_id` bigint NOT NULL COMMENT '보호자 사용자 ID',
  `expert_profile_id` bigint NOT NULL COMMENT '전문가 프로필 ID',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_expert_follows_guardian_expert` (`guardian_user_id`,`expert_profile_id`),
  KEY `fk_expert_follows_expert_profile_id` (`expert_profile_id`),
  CONSTRAINT `fk_expert_follows_expert_profile_id` FOREIGN KEY (`expert_profile_id`) REFERENCES `expert_profiles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_expert_follows_guardian_user_id` FOREIGN KEY (`guardian_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 팔로우';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `expert_profile_specialties` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '전문가 전문 분야 ID',
  `expert_profile_id` bigint NOT NULL COMMENT '전문가 프로필 ID',
  `specialty_code` varchar(50) NOT NULL COMMENT '전문 분야 코드',
  `specialty_name` varchar(100) NOT NULL COMMENT '전문 분야명 Snapshot',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_expert_profile_specialties_profile_code` (`expert_profile_id`,`specialty_code`),
  CONSTRAINT `fk_expert_profile_specialties_profile_id` FOREIGN KEY (`expert_profile_id`) REFERENCES `expert_profiles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_expert_profile_specialties_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 전문 분야';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `expert_profiles` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '전문가 프로필 ID',
  `display_name` varchar(80) NOT NULL COMMENT '표시 이름',
  `profile_image_url` varchar(1000) DEFAULT NULL COMMENT '프로필 이미지 URL',
  `organization` varchar(150) DEFAULT NULL COMMENT '소속 기관',
  `position_title` varchar(100) DEFAULT NULL COMMENT '직책',
  `career_years` smallint NOT NULL DEFAULT '0' COMMENT '경력 연수',
  `introduction` text COMMENT '소개',
  `is_consultation_available` tinyint(1) NOT NULL DEFAULT '0' COMMENT '상담 가능 여부',
  `verification_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '검증 상태',
  `workplace` varchar(255) DEFAULT NULL COMMENT '근무지',
  `contact_phone` varchar(30) DEFAULT NULL COMMENT '연락처',
  `contact_email` varchar(255) DEFAULT NULL COMMENT '연락 이메일',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `deleted_at` datetime(6) DEFAULT NULL COMMENT '삭제 일시',
  `user_id` bigint NOT NULL COMMENT '사용자 ID',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_expert_profiles_user_id` (`user_id`),
  CONSTRAINT `fk_expert_profiles_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_expert_profiles_career_years` CHECK ((`career_years` >= 0)),
  CONSTRAINT `ck_expert_profiles_verification_status` CHECK ((`verification_status` in (_utf8mb4'PENDING',_utf8mb4'VERIFIED',_utf8mb4'REJECTED',_utf8mb4'REVIEW_REQUIRED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 프로필';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `guardian_child_relations` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '보호자-아동 관계 ID',
  `guardian_user_id` bigint NOT NULL COMMENT '보호자 사용자 ID',
  `child_id` bigint NOT NULL COMMENT '아동 ID',
  `relationship_type` varchar(30) NOT NULL COMMENT '관계 유형',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_guardian_child_relations_guardian_child` (`guardian_user_id`,`child_id`),
  KEY `fk_guardian_child_relations_child_id` (`child_id`),
  CONSTRAINT `fk_guardian_child_relations_child_id` FOREIGN KEY (`child_id`) REFERENCES `children` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_guardian_child_relations_guardian_id` FOREIGN KEY (`guardian_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='보호자-아동 관계';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `notification_attributes` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '알림 부가 속성 ID',
  `notification_id` bigint NOT NULL COMMENT '알림 ID',
  `attribute_key` varchar(80) NOT NULL COMMENT '부가 속성 코드',
  `value_type` varchar(20) NOT NULL DEFAULT 'STRING' COMMENT '값 유형',
  `value_text` varchar(1000) NOT NULL COMMENT '부가 속성 값',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_notification_attributes_notification_key` (`notification_id`,`attribute_key`),
  CONSTRAINT `fk_notification_attributes_notification_id` FOREIGN KEY (`notification_id`) REFERENCES `notifications` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_notification_attributes_type` CHECK ((`value_type` in (_utf8mb4'STRING',_utf8mb4'NUMBER',_utf8mb4'BOOLEAN',_utf8mb4'DATETIME')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='알림 부가 속성';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `notification_device_tokens` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'Push 기기 Token ID',
  `user_id` bigint NOT NULL COMMENT '사용자 ID',
  `token_ciphertext` varchar(1500) NOT NULL COMMENT '암호화된 Push Provider 기기 Token',
  `token_hash` char(64) NOT NULL COMMENT '기기 Token SHA-256 Hash',
  `platform` varchar(20) NOT NULL COMMENT '기기 Platform',
  `push_provider` varchar(20) NOT NULL COMMENT 'Push Provider',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT '활성 여부',
  `last_used_at` datetime(6) DEFAULT NULL COMMENT '마지막 사용 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_notification_device_tokens_hash` (`token_hash`),
  KEY `idx_notification_device_tokens_user_active` (`user_id`,`is_active`),
  CONSTRAINT `fk_notification_device_tokens_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_notification_device_tokens_platform` CHECK ((`platform` in (_utf8mb4'ANDROID',_utf8mb4'IOS',_utf8mb4'WEB'))),
  CONSTRAINT `ck_notification_device_tokens_provider` CHECK ((`push_provider` in (_utf8mb4'FCM',_utf8mb4'APNS')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Push 기기 Token';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `notifications` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '알림 ID',
  `recipient_user_id` bigint NOT NULL COMMENT '수신자 사용자 ID',
  `notification_type` varchar(40) NOT NULL COMMENT '알림 유형',
  `title` varchar(200) NOT NULL COMMENT '알림 제목',
  `content` text NOT NULL COMMENT '알림 내용',
  `related_post_id` bigint DEFAULT NULL COMMENT '관련 게시글 ID',
  `related_report_id` bigint DEFAULT NULL COMMENT '관련 리포트 ID',
  `related_drawing_session_id` bigint DEFAULT NULL COMMENT '관련 그림 활동 세션 ID',
  `delivery_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '전송 상태',
  `read_at` datetime(6) DEFAULT NULL COMMENT '읽은 일시',
  `sent_at` datetime(6) DEFAULT NULL COMMENT '전송 일시',
  `failed_at` datetime(6) DEFAULT NULL COMMENT '실패 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  KEY `fk_notifications_related_post_id` (`related_post_id`),
  KEY `fk_notifications_related_report_id` (`related_report_id`),
  KEY `fk_notifications_related_drawing_session_id` (`related_drawing_session_id`),
  KEY `idx_notifications_recipient_created_at` (`recipient_user_id`,`created_at`),
  CONSTRAINT `fk_notifications_recipient_user_id` FOREIGN KEY (`recipient_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_notifications_related_drawing_session_id` FOREIGN KEY (`related_drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_notifications_related_post_id` FOREIGN KEY (`related_post_id`) REFERENCES `community_posts` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_notifications_related_report_id` FOREIGN KEY (`related_report_id`) REFERENCES `reports` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_notifications_delivery_status` CHECK ((`delivery_status` in (_utf8mb4'PENDING',_utf8mb4'SENT',_utf8mb4'FAILED'))),
  CONSTRAINT `ck_notifications_type` CHECK ((`notification_type` in (_utf8mb4'ANALYSIS_COMPLETED',_utf8mb4'ANALYSIS_FAILED',_utf8mb4'REPORT_COMPLETED',_utf8mb4'NEW_EXPERT_POST',_utf8mb4'COMMENT_CREATED',_utf8mb4'CONSENT_UPDATED',_utf8mb4'RETENTION_NOTICE',_utf8mb4'ACTIVITY_REMINDER',_utf8mb4'RISK_REVIEW_GUIDE')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='알림';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `post_likes` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '게시글 좋아요 ID',
  `post_id` bigint NOT NULL COMMENT '게시글 ID',
  `user_id` bigint NOT NULL COMMENT '사용자 ID',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_post_likes_post_user` (`post_id`,`user_id`),
  KEY `fk_post_likes_user_id` (`user_id`),
  CONSTRAINT `fk_post_likes_post_id` FOREIGN KEY (`post_id`) REFERENCES `community_posts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_post_likes_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='게시글 좋아요';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_activity_notes` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 활동 주의사항 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `note_text` text NOT NULL COMMENT '객관적 활동 주의사항',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_activity_notes_report_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_activity_notes_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_activity_notes_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 활동 주의사항';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_activity_summaries` (
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `drawing_duration_ms` bigint DEFAULT NULL COMMENT '그림 활동 시간(ms)',
  `pause_count` int DEFAULT NULL COMMENT '일시 정지 횟수',
  `erase_count` int DEFAULT NULL COMMENT '지우기 횟수',
  `pressure_available` tinyint(1) NOT NULL DEFAULT '0' COMMENT '필압 데이터 존재 여부',
  `conversation_question_count` int DEFAULT NULL COMMENT '대화 질문 수',
  `conversation_answered_count` int DEFAULT NULL COMMENT '대화 응답 수',
  `conversation_skipped_count` int DEFAULT NULL COMMENT '건너뛴 질문 수',
  `conversation_summary` text COMMENT '보호자용 대화 요약',
  PRIMARY KEY (`report_id`),
  CONSTRAINT `fk_report_activity_summaries_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_activity_summaries_counts` CHECK ((((`drawing_duration_ms` is null) or (`drawing_duration_ms` >= 0)) and ((`pause_count` is null) or (`pause_count` >= 0)) and ((`erase_count` is null) or (`erase_count` >= 0)) and ((`conversation_question_count` is null) or (`conversation_question_count` >= 0)) and ((`conversation_answered_count` is null) or (`conversation_answered_count` >= 0)) and ((`conversation_skipped_count` is null) or (`conversation_skipped_count` >= 0))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 활동 요약';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_evidence_authors` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 근거 저자 ID',
  `evidence_reference_id` bigint NOT NULL COMMENT '리포트 근거 문헌 ID',
  `author_name` varchar(200) NOT NULL COMMENT '저자명',
  `author_order` smallint NOT NULL DEFAULT '0' COMMENT '저자 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_evidence_authors_evidence_order` (`evidence_reference_id`,`author_order`),
  CONSTRAINT `fk_report_evidence_authors_evidence_id` FOREIGN KEY (`evidence_reference_id`) REFERENCES `report_evidence_references` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_evidence_authors_order` CHECK ((`author_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 근거 저자';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_evidence_references` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 근거 문헌 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `source_id` varchar(100) NOT NULL COMMENT '지식베이스 출처 ID',
  `title` varchar(500) NOT NULL COMMENT '문헌 제목',
  `published_year` smallint DEFAULT NULL COMMENT '발행 연도',
  `section` varchar(100) DEFAULT NULL COMMENT '참조 구간',
  `evidence_type` varchar(50) NOT NULL COMMENT '근거 유형',
  `applicability` text NOT NULL COMMENT '적용 가능 범위',
  `limitations` text NOT NULL COMMENT '적용 한계',
  `knowledge_base_version` varchar(100) NOT NULL COMMENT '지식베이스 버전',
  `retrieved_chunk_hash` char(64) NOT NULL COMMENT '검색 문단 SHA-256 Hash',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_evidence_references_report_source` (`report_id`,`source_id`,`retrieved_chunk_hash`),
  UNIQUE KEY `uk_report_evidence_references_report_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_evidence_references_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_evidence_references_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_report_evidence_references_year` CHECK (((`published_year` is null) or (`published_year` between 1000 and 9999)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 근거 문헌';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_follow_up_guides` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 후속 안내 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `guidance` text NOT NULL COMMENT '보호자 안내 문장',
  `detail_text` text COMMENT '상세 설명',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_follow_up_guides_report_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_follow_up_guides_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_follow_up_guides_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 후속 안내';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_guardian_questions` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 보호자 질문 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `question_text` text NOT NULL COMMENT '보호자 질문 문장',
  `question_purpose` varchar(50) DEFAULT NULL COMMENT '질문 목적',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_guardian_questions_report_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_guardian_questions_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_guardian_questions_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 보호자 질문';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_key_conversations` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 주요 대화 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `question_message_id` bigint DEFAULT NULL COMMENT '질문 메시지 ID',
  `answer_message_id` bigint DEFAULT NULL COMMENT '답변 메시지 ID',
  `question_text` text NOT NULL COMMENT '질문 Snapshot',
  `answer_text` text COMMENT '답변 Snapshot',
  `answer_type` varchar(30) DEFAULT NULL COMMENT '답변 유형 Snapshot',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_key_conversations_report_order` (`report_id`,`display_order`),
  KEY `fk_report_key_conversations_question_id` (`question_message_id`),
  KEY `fk_report_key_conversations_answer_id` (`answer_message_id`),
  CONSTRAINT `fk_report_key_conversations_answer_id` FOREIGN KEY (`answer_message_id`) REFERENCES `conversation_messages` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_report_key_conversations_question_id` FOREIGN KEY (`question_message_id`) REFERENCES `conversation_messages` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_report_key_conversations_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_key_conversations_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 주요 대화';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_observed_features` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 관찰 특징 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `feature_code` varchar(80) DEFAULT NULL COMMENT '관찰 특징 코드',
  `title` varchar(200) DEFAULT NULL COMMENT '관찰 제목',
  `description` text NOT NULL COMMENT '관찰 내용',
  `evidence_summary` text COMMENT '관찰 근거 요약',
  `visibility_scope` varchar(20) NOT NULL DEFAULT 'EXPERT_ONLY' COMMENT '노출 범위',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_observed_features_report_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_observed_features_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_observed_features_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_report_observed_features_scope` CHECK ((`visibility_scope` in (_utf8mb4'EXPERT_ONLY',_utf8mb4'REVIEWED_GUARDIAN')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 관찰 특징';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `reports` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 ID',
  `drawing_session_id` bigint NOT NULL COMMENT '그림 활동 세션 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `report_version` int NOT NULL DEFAULT '1' COMMENT '리포트 버전',
  `report_status` varchar(20) NOT NULL DEFAULT 'GENERATING' COMMENT '리포트 상태',
  `is_expert_review_recommended` tinyint(1) NOT NULL DEFAULT '0' COMMENT '전문가 검토 권장 여부',
  `limitations_text` text NOT NULL COMMENT '한계 및 주의 문구',
  `pdf_storage_key` varchar(1000) DEFAULT NULL COMMENT 'PDF 저장 Key',
  `pdf_url` varchar(1000) DEFAULT NULL COMMENT 'PDF URL',
  `pdf_status` varchar(20) NOT NULL DEFAULT 'NONE' COMMENT 'PDF 생성 상태',
  `hidden_at` datetime(6) DEFAULT NULL COMMENT '숨김 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '리포트 생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '리포트 수정 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_reports_session_version` (`drawing_session_id`,`report_version`),
  KEY `fk_reports_analysis_id` (`analysis_id`),
  KEY `idx_reports_drawing_session_id` (`drawing_session_id`,`created_at`),
  CONSTRAINT `fk_reports_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_reports_drawing_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_reports_pdf_status` CHECK ((`pdf_status` in (_utf8mb4'NONE',_utf8mb4'GENERATING',_utf8mb4'READY',_utf8mb4'FAILED'))),
  CONSTRAINT `ck_reports_status` CHECK ((`report_status` in (_utf8mb4'GENERATING',_utf8mb4'COMPLETED',_utf8mb4'FAILED',_utf8mb4'HIDDEN')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `storage_deletion_jobs` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'Storage 삭제 작업 ID',
  `storage_key` varchar(1000) NOT NULL COMMENT '삭제 대상 Storage Key',
  `resource_type` varchar(50) NOT NULL COMMENT '연결 Resource 유형',
  `resource_id` bigint DEFAULT NULL COMMENT '연결 Resource ID',
  `deletion_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '삭제 상태',
  `retry_count` smallint NOT NULL DEFAULT '0' COMMENT '재시도 횟수',
  `error_code` varchar(80) DEFAULT NULL COMMENT '마지막 오류 코드',
  `requested_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '삭제 요청 일시',
  `last_attempted_at` datetime(6) DEFAULT NULL COMMENT '마지막 시도 일시',
  `completed_at` datetime(6) DEFAULT NULL COMMENT '삭제 완료 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  KEY `idx_storage_deletion_jobs_status_requested_at` (`deletion_status`,`requested_at`),
  KEY `idx_storage_deletion_jobs_resource` (`resource_type`,`resource_id`),
  CONSTRAINT `ck_storage_deletion_jobs_retry_count` CHECK ((`retry_count` >= 0)),
  CONSTRAINT `ck_storage_deletion_jobs_status` CHECK ((`deletion_status` in (_utf8mb4'PENDING',_utf8mb4'PROCESSING',_utf8mb4'COMPLETED',_utf8mb4'FAILED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Storage 삭제 작업';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `stroke_batches` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'Stroke 배치 ID',
  `drawing_session_id` bigint NOT NULL COMMENT '그림 활동 세션 ID',
  `batch_sequence` int NOT NULL COMMENT '배치 순번',
  `first_event_sequence` bigint NOT NULL COMMENT '첫 이벤트 순번',
  `last_event_sequence` bigint NOT NULL COMMENT '마지막 이벤트 순번',
  `event_count` int NOT NULL COMMENT '이벤트 수',
  `payload_checksum_sha256` char(64) NOT NULL COMMENT '배치 Payload SHA-256 Checksum',
  `undo_count_delta` int NOT NULL DEFAULT '0' COMMENT '실행 취소 증가량',
  `redo_count_delta` int NOT NULL DEFAULT '0' COMMENT '다시 실행 증가량',
  `erase_count_delta` int NOT NULL DEFAULT '0' COMMENT '지우기 증가량',
  `pause_duration_ms_delta` bigint NOT NULL DEFAULT '0' COMMENT '일시 정지 시간 증가량(ms)',
  `client_created_at` datetime(6) DEFAULT NULL COMMENT '클라이언트 생성 일시',
  `received_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '수신 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_stroke_batches_session_sequence` (`drawing_session_id`,`batch_sequence`),
  CONSTRAINT `fk_stroke_batches_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_stroke_batches_event_count` CHECK ((`event_count` > 0)),
  CONSTRAINT `ck_stroke_batches_metric_deltas` CHECK (((`undo_count_delta` >= 0) and (`redo_count_delta` >= 0) and (`erase_count_delta` >= 0) and (`pause_duration_ms_delta` >= 0))),
  CONSTRAINT `ck_stroke_batches_sequence_range` CHECK ((`first_event_sequence` <= `last_event_sequence`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stroke 배치';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `stroke_event_points` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'Stroke 좌표 ID',
  `stroke_event_id` bigint NOT NULL COMMENT 'Stroke 이벤트 ID',
  `point_sequence` int NOT NULL COMMENT '이벤트 내부 좌표 순번',
  `x` decimal(8,6) NOT NULL COMMENT '정규화 X 좌표',
  `y` decimal(8,6) NOT NULL COMMENT '정규화 Y 좌표',
  `elapsed_ms` bigint NOT NULL COMMENT '이벤트 시작 후 경과 시간(ms)',
  `pressure` decimal(6,5) DEFAULT NULL COMMENT '좌표별 필압',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_stroke_event_points_event_sequence` (`stroke_event_id`,`point_sequence`),
  CONSTRAINT `fk_stroke_event_points_event_id` FOREIGN KEY (`stroke_event_id`) REFERENCES `stroke_events` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_stroke_event_points_coordinates` CHECK (((`x` >= 0) and (`x` <= 1) and (`y` >= 0) and (`y` <= 1))),
  CONSTRAINT `ck_stroke_event_points_elapsed` CHECK ((`elapsed_ms` >= 0)),
  CONSTRAINT `ck_stroke_event_points_pressure` CHECK (((`pressure` is null) or ((`pressure` >= 0) and (`pressure` <= 1)))),
  CONSTRAINT `ck_stroke_event_points_sequence` CHECK ((`point_sequence` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stroke 이벤트 좌표';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `stroke_events` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'Stroke 이벤트 ID',
  `stroke_batch_id` bigint NOT NULL COMMENT 'Stroke 배치 ID',
  `event_sequence` bigint NOT NULL COMMENT '전체 이벤트 순번',
  `event_type` varchar(30) NOT NULL COMMENT '이벤트 유형',
  `tool` varchar(30) DEFAULT NULL COMMENT '그리기 도구',
  `color` char(9) DEFAULT NULL COMMENT '색상 코드',
  `width` decimal(8,3) DEFAULT NULL COMMENT '선 굵기',
  `pressure` decimal(6,5) DEFAULT NULL COMMENT '이벤트 대표 필압',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_stroke_events_batch_sequence` (`stroke_batch_id`,`event_sequence`),
  CONSTRAINT `fk_stroke_events_batch_id` FOREIGN KEY (`stroke_batch_id`) REFERENCES `stroke_batches` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_stroke_events_pressure` CHECK (((`pressure` is null) or ((`pressure` >= 0) and (`pressure` <= 1)))),
  CONSTRAINT `ck_stroke_events_sequence` CHECK ((`event_sequence` >= 0)),
  CONSTRAINT `ck_stroke_events_width` CHECK (((`width` is null) or (`width` > 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stroke 이벤트';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_notification_settings` (
  `user_id` bigint NOT NULL COMMENT '사용자 ID',
  `analysis_completed` tinyint(1) NOT NULL DEFAULT '1' COMMENT '분석 완료 알림 수신 여부',
  `community` tinyint(1) NOT NULL DEFAULT '1' COMMENT '커뮤니티 알림 수신 여부',
  `service_notice` tinyint(1) NOT NULL DEFAULT '1' COMMENT '서비스 공지 수신 여부',
  `marketing` tinyint(1) NOT NULL DEFAULT '0' COMMENT '마케팅 알림 수신 여부',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_user_notification_settings_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자 알림 설정';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '사용자 ID',
  `role` varchar(20) NOT NULL COMMENT '사용자 역할',
  `nickname` varchar(50) DEFAULT NULL COMMENT '닉네임',
  `account_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '계정 상태',
  `profile_image_url` varchar(1000) DEFAULT NULL COMMENT '프로필 이미지 URL',
  `is_completed` tinyint(1) NOT NULL DEFAULT '0' COMMENT '온보딩 완료 여부',
  `last_login_at` datetime(6) DEFAULT NULL COMMENT '마지막 로그인 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `deleted_at` datetime(6) DEFAULT NULL COMMENT '삭제 일시',
  PRIMARY KEY (`id`),
  CONSTRAINT `ck_users_account_status` CHECK ((`account_status` in (_utf8mb4'PENDING',_utf8mb4'ACTIVE',_utf8mb4'SUSPENDED',_utf8mb4'DELETED'))),
  CONSTRAINT `ck_users_role` CHECK ((`role` in (_utf8mb4'GUARDIAN',_utf8mb4'EXPERT',_utf8mb4'ADMIN')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자';
/*!40101 SET character_set_client = @saved_cs_client */;
SET FOREIGN_KEY_CHECKS = 1;
