-- ============================================================================
--  도담(dodam) DB 덤프 — 스키마 전체 + 코드성 마스터 데이터
--  DB: b209 (MySQL 8.4.10 LTS, utf8mb4 / utf8mb4_0900_ai_ci, InnoDB)
--
--  ⚠️ 아동 민감정보(그림·음성·대화·리포트·회원)는 포함하지 않는다 (가드레일 9절).
--     - 전 테이블의 CREATE(구조)는 그대로 담는다.
--     - 데이터는 아래 '마스터/코드' 테이블에 한해서만 담는다:
--         drawing_types, consent_terms,
--         ai_question_templates, ai_question_template_options, ai_question_template_risk_responses,
--         activity_templates, activity_template_attachments,
--         community_post_template_fields, child_screening_referral_options,
--         flyway_schema_history (스키마 상태 — Flyway validate 정합용)
--
--  복원(빈 MySQL 기준):
--     CREATE DATABASE b209 CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
--     mysql -uroot -p b209 < dodam-schema-and-master.sql
--   이후 backend 기동 시 Flyway 가 validate 로 정합성만 확인한다(신규 DDL 없음).
-- ============================================================================

-- MySQL dump 10.13  Distrib 8.4.10, for Linux (x86_64)
--
-- Host: localhost    Database: b209
-- ------------------------------------------------------
-- Server version	8.4.10

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `activity_template_attachments`
--

DROP TABLE IF EXISTS `activity_template_attachments`;
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

--
-- Table structure for table `activity_templates`
--

DROP TABLE IF EXISTS `activity_templates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `activity_templates` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '미술 활동 자료 ID',
  `expert_profile_id` bigint DEFAULT NULL COMMENT '전문가 프로필 ID (NULL = 작성자 탈퇴)',
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
  CONSTRAINT `fk_activity_templates_expert_profile_id` FOREIGN KEY (`expert_profile_id`) REFERENCES `expert_profiles` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='미술 활동 자료';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ai_question_template_options`
--

DROP TABLE IF EXISTS `ai_question_template_options`;
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
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='AI 질문 Template 선택지';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ai_question_template_risk_responses`
--

DROP TABLE IF EXISTS `ai_question_template_risk_responses`;
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

--
-- Table structure for table `ai_question_templates`
--

DROP TABLE IF EXISTS `ai_question_templates`;
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
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='AI 질문 Template';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analyses`
--

DROP TABLE IF EXISTS `analyses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analyses` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '분석 ID',
  `drawing_session_id` bigint NOT NULL COMMENT '그림 활동 세션 ID',
  `drawing_asset_id` bigint DEFAULT NULL COMMENT '분석 대상 그림 파일 ID',
  `retry_of_analysis_id` bigint DEFAULT NULL COMMENT '재시도 원본 분석 ID',
  `analysis_type` varchar(20) NOT NULL COMMENT '분석 유형',
  `analysis_task_type` varchar(30) DEFAULT NULL COMMENT 'AI 분석 작업 유형',
  `idempotency_key` varchar(100) NOT NULL COMMENT 'Idempotency Key',
  `input_checksum_sha256` char(64) DEFAULT NULL COMMENT '입력 SHA-256 Checksum',
  `analysis_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '분석 상태',
  `trigger_reason` varchar(30) DEFAULT NULL COMMENT '분석 실행 사유',
  `model_name` varchar(100) DEFAULT NULL COMMENT 'Model 이름',
  `model_version` varchar(255) DEFAULT NULL COMMENT 'Model 버전',
  `confidence` decimal(5,4) DEFAULT NULL COMMENT '신뢰도',
  `error_code` varchar(80) DEFAULT NULL COMMENT '오류 코드',
  `error_message` text COMMENT '오류 메시지',
  `requested_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '요청 일시',
  `started_at` datetime(6) DEFAULT NULL COMMENT '시작 일시',
  `completed_at` datetime(6) DEFAULT NULL COMMENT '분석 완료 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `active_drawing_asset_id` bigint GENERATED ALWAYS AS ((case when (`analysis_status` in (_utf8mb4'PROCESSING',_utf8mb4'SUCCESS',_utf8mb4'PARTIAL_SUCCESS')) then `drawing_asset_id` else NULL end)) VIRTUAL COMMENT '진행·완료 분석 중복 방지용 생성값',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_analyses_idempotency_key` (`idempotency_key`),
  UNIQUE KEY `uk_analyses_active_asset_task` (`active_drawing_asset_id`,`analysis_task_type`),
  KEY `fk_analyses_retry_of_analysis_id` (`retry_of_analysis_id`),
  KEY `idx_analyses_drawing_session_id` (`drawing_session_id`,`requested_at`),
  KEY `idx_analyses_asset_task_status` (`drawing_asset_id`,`analysis_task_type`,`analysis_status`),
  CONSTRAINT `fk_analyses_drawing_asset_id` FOREIGN KEY (`drawing_asset_id`) REFERENCES `drawing_assets` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_analyses_drawing_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_analyses_retry_of_analysis_id` FOREIGN KEY (`retry_of_analysis_id`) REFERENCES `analyses` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_analyses_confidence` CHECK (((`confidence` is null) or ((`confidence` >= 0) and (`confidence` <= 1)))),
  CONSTRAINT `ck_analyses_status` CHECK ((`analysis_status` in (_utf8mb4'PENDING',_utf8mb4'PROCESSING',_utf8mb4'PARTIAL_SUCCESS',_utf8mb4'SUCCESS',_utf8mb4'FAILED'))),
  CONSTRAINT `ck_analyses_task_type` CHECK (((`analysis_task_type` is null) or (`analysis_task_type` in (_utf8mb4'OBJECT_DETECTION',_utf8mb4'ACTIVITY_REPORT')))),
  CONSTRAINT `ck_analyses_trigger_reason` CHECK (((`trigger_reason` is null) or (`trigger_reason` in (_utf8mb4'PAUSE',_utf8mb4'INTERVAL',_utf8mb4'STROKE_COUNT',_utf8mb4'CHANGE_RATIO',_utf8mb4'USER_REQUEST',_utf8mb4'DRAWING_COMPLETE',_utf8mb4'ACTIVITY_COMPLETE',_utf8mb4'RETRY')))),
  CONSTRAINT `ck_analyses_type` CHECK ((`analysis_type` in (_utf8mb4'INTERMEDIATE',_utf8mb4'FINAL')))
) ENGINE=InnoDB AUTO_INCREMENT=1084 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_behavior_features`
--

DROP TABLE IF EXISTS `analysis_behavior_features`;
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
  `pressure_available` tinyint(1) DEFAULT NULL COMMENT '필압 데이터 사용 가능 여부',
  `average_pressure` decimal(8,3) DEFAULT NULL COMMENT '평균 압력',
  `maximum_pressure` decimal(8,3) DEFAULT NULL COMMENT '최대 압력',
  `pressure_deviation` decimal(8,3) DEFAULT NULL COMMENT '압력 편차',
  `save_count` int DEFAULT NULL COMMENT '저장 횟수',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`behavior_feature_id`),
  KEY `idx_analysis_behavior_features_analysis_id` (`analysis_id`),
  CONSTRAINT `fk_analysis_behavior_features_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_behavior_features_input_method` CHECK (((`input_method` is null) or (`input_method` in (_utf8mb4'CANVAS',_utf8mb4'UPLOAD'))))
) ENGINE=InnoDB AUTO_INCREMENT=233 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 행동 특징';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_conversation_summaries`
--

DROP TABLE IF EXISTS `analysis_conversation_summaries`;
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
  `summary_model_version` varchar(255) DEFAULT NULL COMMENT '요약 Model 버전',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`conversation_summary_id`),
  KEY `fk_analysis_conversation_summaries_session_id` (`conversation_session_id`),
  KEY `idx_analysis_conversation_summaries_analysis_id` (`analysis_id`),
  CONSTRAINT `fk_analysis_conversation_summaries_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_analysis_conversation_summaries_session_id` FOREIGN KEY (`conversation_session_id`) REFERENCES `conversation_sessions` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=153 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 분석 요약';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_detected_objects`
--

DROP TABLE IF EXISTS `analysis_detected_objects`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_detected_objects` (
  `detected_object_id` bigint NOT NULL AUTO_INCREMENT COMMENT '탐지 객체 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `drawing_asset_id` bigint NOT NULL COMMENT '그림 파일 ID',
  `object_code` varchar(50) DEFAULT NULL COMMENT '객체 코드',
  `object_name` varchar(100) DEFAULT NULL COMMENT '객체명',
  `confidence_score` decimal(5,4) DEFAULT NULL COMMENT '신뢰도 점수',
  `bbox_x` decimal(12,6) DEFAULT NULL COMMENT 'Bounding Box X 좌표',
  `bbox_y` decimal(12,6) DEFAULT NULL COMMENT 'Bounding Box Y 좌표',
  `bbox_width` decimal(12,6) DEFAULT NULL COMMENT 'Bounding Box 너비',
  `bbox_height` decimal(12,6) DEFAULT NULL COMMENT 'Bounding Box 높이',
  `area_ratio` decimal(8,6) DEFAULT NULL COMMENT '면적 비율',
  `coordinate_space` varchar(20) NOT NULL DEFAULT 'PIXEL' COMMENT 'Bounding Box 좌표계',
  `detection_order` int DEFAULT NULL COMMENT '탐지 순서',
  `model_version` varchar(50) DEFAULT NULL COMMENT 'Model 버전',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`detected_object_id`),
  KEY `idx_analysis_detected_objects_analysis_id` (`analysis_id`),
  KEY `idx_analysis_detected_objects_drawing_asset_id` (`drawing_asset_id`),
  CONSTRAINT `fk_analysis_detected_objects_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_analysis_detected_objects_drawing_asset_id` FOREIGN KEY (`drawing_asset_id`) REFERENCES `drawing_assets` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_detected_objects_bbox_coordinate` CHECK ((((`bbox_x` is null) or (`bbox_x` >= 0)) and ((`bbox_y` is null) or (`bbox_y` >= 0)) and ((`bbox_width` is null) or (`bbox_width` > 0)) and ((`bbox_height` is null) or (`bbox_height` > 0)) and ((`coordinate_space` = _utf8mb4'PIXEL') or (((`bbox_x` is null) or (`bbox_x` <= 1)) and ((`bbox_y` is null) or (`bbox_y` <= 1)) and ((`bbox_width` is null) or (`bbox_width` <= 1)) and ((`bbox_height` is null) or (`bbox_height` <= 1)) and ((`bbox_x` is null) or (`bbox_width` is null) or ((`bbox_x` + `bbox_width`) <= 1)) and ((`bbox_y` is null) or (`bbox_height` is null) or ((`bbox_y` + `bbox_height`) <= 1)))))),
  CONSTRAINT `ck_analysis_detected_objects_confidence` CHECK (((`confidence_score` is null) or ((`confidence_score` >= 0) and (`confidence_score` <= 1)))),
  CONSTRAINT `ck_analysis_detected_objects_coordinate_space` CHECK ((`coordinate_space` in (_utf8mb4'PIXEL',_utf8mb4'NORMALIZED'))),
  CONSTRAINT `ck_analysis_detected_objects_order` CHECK (((`detection_order` is null) or (`detection_order` >= 0)))
) ENGINE=InnoDB AUTO_INCREMENT=2196 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 탐지 객체';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_evidence_reference_authors`
--

DROP TABLE IF EXISTS `analysis_evidence_reference_authors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_evidence_reference_authors` (
  `evidence_reference_id` bigint NOT NULL COMMENT '분석 근거 ID',
  `author_order` int NOT NULL COMMENT '저자 순서',
  `author_name` varchar(200) NOT NULL COMMENT '저자명',
  PRIMARY KEY (`evidence_reference_id`,`author_order`),
  CONSTRAINT `fk_analysis_evidence_reference_authors_reference_id` FOREIGN KEY (`evidence_reference_id`) REFERENCES `analysis_evidence_references` (`evidence_reference_id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_evidence_reference_authors_order` CHECK ((`author_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 근거 저자';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_evidence_references`
--

DROP TABLE IF EXISTS `analysis_evidence_references`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_evidence_references` (
  `evidence_reference_id` bigint NOT NULL AUTO_INCREMENT COMMENT '분석 근거 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `reference_order` int NOT NULL COMMENT '근거 순서',
  `source_id` varchar(100) NOT NULL COMMENT '지식 베이스 출처 ID',
  `title` varchar(500) NOT NULL COMMENT '출처 제목',
  `published_year` int DEFAULT NULL COMMENT '발행 연도',
  `section_name` varchar(100) DEFAULT NULL COMMENT '참조 구역',
  `evidence_type` varchar(50) NOT NULL COMMENT '근거 유형',
  `applicability` text COMMENT '적용 범위',
  `limitations` text COMMENT '적용 한계',
  `knowledge_base_version` varchar(100) DEFAULT NULL COMMENT '지식 베이스 버전',
  `retrieved_chunk_hash` varchar(100) DEFAULT NULL COMMENT '검색 Chunk Hash',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`evidence_reference_id`),
  UNIQUE KEY `uk_analysis_evidence_references_analysis_order` (`analysis_id`,`reference_order`),
  CONSTRAINT `fk_analysis_evidence_references_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_evidence_references_order` CHECK ((`reference_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 근거';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_model_components`
--

DROP TABLE IF EXISTS `analysis_model_components`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_model_components` (
  `model_component_id` bigint NOT NULL AUTO_INCREMENT COMMENT '분석 Model 구성요소 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `component_type` varchar(30) NOT NULL COMMENT 'Model 구성요소 유형',
  `model_name` varchar(100) DEFAULT NULL COMMENT 'Model 이름',
  `model_version` varchar(100) DEFAULT NULL COMMENT 'Model 버전',
  `knowledge_base_version` varchar(100) DEFAULT NULL COMMENT '지식 베이스 버전',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`model_component_id`),
  UNIQUE KEY `uk_analysis_model_components_analysis_type` (`analysis_id`,`component_type`),
  CONSTRAINT `fk_analysis_model_components_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_model_components_type` CHECK ((`component_type` in (_utf8mb4'OBJECT_DETECTION',_utf8mb4'VISION',_utf8mb4'LANGUAGE',_utf8mb4'KNOWLEDGE_BASE')))
) ENGINE=InnoDB AUTO_INCREMENT=1793 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 Model 구성요소';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_observation_items`
--

DROP TABLE IF EXISTS `analysis_observation_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_observation_items` (
  `observation_item_id` bigint NOT NULL AUTO_INCREMENT COMMENT '관찰 초안 항목 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `item_type` varchar(30) NOT NULL COMMENT '관찰 또는 후속 질문 유형',
  `item_order` int NOT NULL COMMENT '항목 순서',
  `content` text NOT NULL COMMENT '관찰 또는 후속 질문 문장',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`observation_item_id`),
  UNIQUE KEY `uk_analysis_observation_items_analysis_type_order` (`analysis_id`,`item_type`,`item_order`),
  CONSTRAINT `fk_analysis_observation_items_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_observation_items_order` CHECK ((`item_order` >= 0)),
  CONSTRAINT `ck_analysis_observation_items_type` CHECK ((`item_type` in (_utf8mb4'OBSERVATION',_utf8mb4'FOLLOW_UP_QUESTION')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 관찰 초안 목록 항목';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_observation_results`
--

DROP TABLE IF EXISTS `analysis_observation_results`;
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
  `generated_model_version` varchar(255) DEFAULT NULL COMMENT '생성 Model 버전',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`observation_result_id`),
  KEY `idx_analysis_observation_results_analysis_id` (`analysis_id`),
  CONSTRAINT `fk_analysis_observation_results_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_observation_results_emotion_confidence` CHECK (((`emotion_confidence` is null) or ((`emotion_confidence` >= 0) and (`emotion_confidence` <= 1))))
) ENGINE=InnoDB AUTO_INCREMENT=800 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 관찰 결과';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_unused_inputs`
--

DROP TABLE IF EXISTS `analysis_unused_inputs`;
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
) ENGINE=InnoDB AUTO_INCREMENT=2660 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 제외 입력';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_visual_features`
--

DROP TABLE IF EXISTS `analysis_visual_features`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_visual_features` (
  `visual_feature_id` bigint NOT NULL AUTO_INCREMENT COMMENT '시각 특징 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `image_width_px` int DEFAULT NULL COMMENT '분석 이미지 너비(px)',
  `image_height_px` int DEFAULT NULL COMMENT '분석 이미지 높이(px)',
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
  CONSTRAINT `fk_analysis_visual_features_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_visual_features_image_size` CHECK ((((`image_width_px` is null) or (`image_width_px` > 0)) and ((`image_height_px` is null) or (`image_height_px` > 0))))
) ENGINE=InnoDB AUTO_INCREMENT=648 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 시각 특징';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `analysis_warnings`
--

DROP TABLE IF EXISTS `analysis_warnings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analysis_warnings` (
  `warning_id` bigint NOT NULL AUTO_INCREMENT COMMENT '분석 경고 ID',
  `analysis_id` bigint NOT NULL COMMENT '분석 ID',
  `warning_order` int NOT NULL COMMENT '경고 순서',
  `warning_code` varchar(100) NOT NULL COMMENT '비치명적 경고 코드',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`warning_id`),
  UNIQUE KEY `uk_analysis_warnings_analysis_order` (`analysis_id`,`warning_order`),
  CONSTRAINT `fk_analysis_warnings_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_analysis_warnings_order` CHECK ((`warning_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=1156 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='분석 경고';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `audit_log_changes`
--

DROP TABLE IF EXISTS `audit_log_changes`;
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

--
-- Table structure for table `audit_logs`
--

DROP TABLE IF EXISTS `audit_logs`;
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

--
-- Table structure for table `auth_accounts`
--

DROP TABLE IF EXISTS `auth_accounts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `auth_accounts` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '인증 계정 ID',
  `user_id` bigint NOT NULL COMMENT '사용자 ID',
  `provider` varchar(20) NOT NULL COMMENT '인증 제공자',
  `provider_subject` varchar(255) NOT NULL COMMENT '인증 제공자 사용자 식별자',
  `provider_email` varchar(255) DEFAULT NULL COMMENT '로그인 이메일',
  `provider_email_verified_at` datetime(6) DEFAULT NULL COMMENT '이메일 인증 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_auth_accounts_provider_subject` (`provider`,`provider_subject`),
  KEY `fk_auth_accounts_user_id` (`user_id`),
  CONSTRAINT `fk_auth_accounts_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_auth_accounts_provider` CHECK ((`provider` in (_utf8mb4'KAKAO',_utf8mb4'GOOGLE',_utf8mb4'NAVER',_utf8mb4'APPLE')))
) ENGINE=InnoDB AUTO_INCREMENT=36 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='인증 계정';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `child_profile_image_files`
--

DROP TABLE IF EXISTS `child_profile_image_files`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `child_profile_image_files` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '아동 프로필 이미지 내부 ID',
  `file_id` char(36) NOT NULL COMMENT 'API 공개 파일 UUID',
  `uploaded_by_user_id` bigint NOT NULL COMMENT '업로드 사용자 ID',
  `storage_key` varchar(1000) NOT NULL COMMENT '이미지 Storage Key',
  `content_type` varchar(100) NOT NULL COMMENT '검증된 MIME Type',
  `file_size_bytes` bigint NOT NULL COMMENT '파일 크기(Byte)',
  `width_px` int NOT NULL COMMENT '이미지 너비(px)',
  `height_px` int NOT NULL COMMENT '이미지 높이(px)',
  `checksum_sha256` char(64) NOT NULL COMMENT '이미지 Byte SHA-256',
  `status` varchar(20) NOT NULL DEFAULT 'TEMP' COMMENT 'TEMP 또는 ATTACHED',
  `child_id` bigint DEFAULT NULL COMMENT '연결된 아동 ID',
  `expires_at` datetime(6) NOT NULL COMMENT 'TEMP 파일 만료 시각',
  `attached_at` datetime(6) DEFAULT NULL COMMENT '아동 연결 시각',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '업로드 시각',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_child_profile_image_files_file_id` (`file_id`),
  UNIQUE KEY `uk_child_profile_image_files_child_id` (`child_id`),
  KEY `idx_child_profile_image_files_owner_status` (`uploaded_by_user_id`,`status`,`expires_at`),
  KEY `idx_child_profile_image_files_expiry` (`status`,`expires_at`),
  CONSTRAINT `fk_child_profile_image_files_child_id` FOREIGN KEY (`child_id`) REFERENCES `children` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_child_profile_image_files_user_id` FOREIGN KEY (`uploaded_by_user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_child_profile_image_files_dimensions` CHECK (((`width_px` > 0) and (`height_px` > 0))),
  CONSTRAINT `ck_child_profile_image_files_size` CHECK (((`file_size_bytes` > 0) and (`file_size_bytes` <= 5242880))),
  CONSTRAINT `ck_child_profile_image_files_status` CHECK ((`status` in (_utf8mb4'TEMP',_utf8mb4'ATTACHED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='아동 프로필 이미지 파일';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `child_response_modes`
--

DROP TABLE IF EXISTS `child_response_modes`;
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
) ENGINE=InnoDB AUTO_INCREMENT=158 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='아동 응답 방식';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `child_screening_record_domains`
--

DROP TABLE IF EXISTS `child_screening_record_domains`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `child_screening_record_domains` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '영역 결과 ID',
  `screening_record_id` bigint NOT NULL COMMENT '선별 결과 기록 ID',
  `domain_name` varchar(60) NOT NULL COMMENT '영역 이름을 공식 결과지 그대로',
  `result_label` varchar(120) NOT NULL COMMENT '영역 결과 라벨을 공식 결과지 그대로',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_child_screening_record_domains_slot` (`screening_record_id`,`display_order`),
  CONSTRAINT `fk_child_screening_record_domains_record_id` FOREIGN KEY (`screening_record_id`) REFERENCES `child_screening_records` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_child_screening_record_domains_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='선별 결과의 영역별 라벨';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `child_screening_records`
--

DROP TABLE IF EXISTS `child_screening_records`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `child_screening_records` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '선별 결과 기록 ID',
  `child_id` bigint NOT NULL COMMENT '아동 ID',
  `instrument_id` varchar(40) NOT NULL COMMENT '등록부 allow-list 안의 도구 식별자',
  `instrument_version` varchar(60) DEFAULT NULL COMMENT '보호자가 적은 도구 버전',
  `respondent` varchar(20) NOT NULL COMMENT 'GUARDIAN·TEACHER·CHILD',
  `completed_at` date NOT NULL COMMENT '검사 실시일',
  `child_age_months_at_administration` smallint DEFAULT NULL COMMENT '실시 당시 아동 개월 나이',
  `source_authority_type` varchar(30) NOT NULL COMMENT 'OFFICIAL_SERVICE·GUARDIAN_REPORTED·CLINICIAN_REPORTED',
  `source_authority_name` varchar(150) NOT NULL COMMENT '결과를 발급한 곳',
  `source_verified` tinyint(1) NOT NULL DEFAULT '0' COMMENT '출처 검증 여부. 공식 연동이 없어 현재 항상 FALSE',
  `verification_method` varchar(150) DEFAULT NULL COMMENT '검증 방법이며 미검증이면 NULL',
  `official_result_code` varchar(60) DEFAULT NULL COMMENT '공식 결과 코드를 그대로',
  `official_result_text` varchar(500) NOT NULL COMMENT '공식 결과 문구를 변경 없이',
  `diagnostic_status` varchar(30) NOT NULL DEFAULT 'SCREENING_NOT_DIAGNOSIS' COMMENT '선별은 진단이 아니라는 고정 표기',
  `scored_by` varchar(30) NOT NULL COMMENT '채점 주체. 이 서비스는 절대 채점하지 않는다',
  `ai_recalculated` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'AI 재계산 여부. 항상 FALSE',
  `followup_level` varchar(40) DEFAULT NULL COMMENT 'NONE·DISCUSS_WITH_GUARDIAN·SCHEDULE_FURTHER_EVALUATION',
  `followup_message` varchar(500) DEFAULT NULL COMMENT '보호자에게 보이는 후속 안내',
  `consent_record_id` bigint NOT NULL COMMENT '이 기록을 남길 때 확인한 동의 이력 ID',
  `source_document_ref` varchar(300) DEFAULT NULL COMMENT '원본 문서 참조',
  `payload_hash` char(64) NOT NULL COMMENT '등록 당시 요청 본문의 SHA-256',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '등록 일시',
  `deleted_at` datetime(6) DEFAULT NULL COMMENT '보호자 삭제 일시. 삭제권 행사 시각을 남긴다',
  PRIMARY KEY (`id`),
  KEY `fk_child_screening_records_consent_record_id` (`consent_record_id`),
  KEY `idx_child_screening_records_child` (`child_id`,`deleted_at`,`completed_at`),
  CONSTRAINT `fk_child_screening_records_child_id` FOREIGN KEY (`child_id`) REFERENCES `children` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_child_screening_records_consent_record_id` FOREIGN KEY (`consent_record_id`) REFERENCES `consent_records` (`id`),
  CONSTRAINT `ck_child_screening_records_not_scored_here` CHECK ((`ai_recalculated` = false))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='보호자가 입력한 표준화 선별 결과';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `child_screening_referral_options`
--

DROP TABLE IF EXISTS `child_screening_referral_options`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `child_screening_referral_options` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '후속 경로 ID',
  `screening_record_id` bigint NOT NULL COMMENT '선별 결과 기록 ID',
  `referral_option` varchar(120) NOT NULL COMMENT '소아청소년과·발달클리닉 등',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_child_screening_referral_options_slot` (`screening_record_id`,`display_order`),
  CONSTRAINT `fk_child_screening_referral_options_record_id` FOREIGN KEY (`screening_record_id`) REFERENCES `child_screening_records` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_child_screening_referral_options_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='선별 결과의 후속 상담 경로';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `children`
--

DROP TABLE IF EXISTS `children`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `children` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '아동 ID',
  `nickname` varchar(50) NOT NULL COMMENT '닉네임',
  `birth_date` date NOT NULL COMMENT '생년월일',
  `profile_image_url` varchar(1000) DEFAULT NULL COMMENT '프로필 이미지 URL',
  `preferred_character` varchar(50) DEFAULT NULL COMMENT '선호 캐릭터',
  `question_difficulty` varchar(30) NOT NULL DEFAULT 'PRESCHOOL' COMMENT '질문 난이도',
  `education_stage` varchar(20) DEFAULT NULL COMMENT '다니는 곳(PRESCHOOL·KINDERGARTEN·GRADE_1). NULL 은 미입력',
  `tutorial_status` varchar(20) NOT NULL DEFAULT 'NOT_STARTED' COMMENT '튜토리얼 상태',
  `tutorial_last_step` varchar(50) DEFAULT NULL COMMENT 'Tutorial 마지막 진행 단계',
  `tutorial_completed_at` datetime(6) DEFAULT NULL COMMENT 'Tutorial 완료 또는 건너뛰기 일시',
  `profile_status` varchar(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '프로필 상태',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `deleted_at` datetime(6) DEFAULT NULL COMMENT '삭제 일시',
  PRIMARY KEY (`id`),
  CONSTRAINT `ck_children_education_stage` CHECK (((`education_stage` is null) or (`education_stage` in (_utf8mb4'PRESCHOOL',_utf8mb4'KINDERGARTEN',_utf8mb4'GRADE_1')))),
  CONSTRAINT `ck_children_preferred_character` CHECK (((`preferred_character` is null) or (`preferred_character` in (_utf8mb4'BASE',_utf8mb4'PRINCESS',_utf8mb4'DINO',_utf8mb4'OCTOPUS',_utf8mb4'EXPLORER',_utf8mb4'RIBBON',_utf8mb4'PRINCE')))),
  CONSTRAINT `ck_children_profile_status` CHECK ((`profile_status` in (_utf8mb4'ACTIVE',_utf8mb4'DELETED'))),
  CONSTRAINT `ck_children_question_difficulty` CHECK ((`question_difficulty` in (_utf8mb4'PRESCHOOL',_utf8mb4'LOWER_ELEMENTARY',_utf8mb4'UPPER_ELEMENTARY',_utf8mb4'SUPPORT'))),
  CONSTRAINT `ck_children_tutorial_status` CHECK ((`tutorial_status` in (_utf8mb4'NOT_STARTED',_utf8mb4'IN_PROGRESS',_utf8mb4'COMPLETED',_utf8mb4'SKIPPED')))
) ENGINE=InnoDB AUTO_INCREMENT=217 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='아동';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `comments`
--

DROP TABLE IF EXISTS `comments`;
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

--
-- Table structure for table `community_attachment_files`
--

DROP TABLE IF EXISTS `community_attachment_files`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `community_attachment_files` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '커뮤니티 첨부 파일 내부 ID',
  `file_id` char(36) NOT NULL COMMENT 'API 공개 파일 UUID',
  `uploaded_by_user_id` bigint NOT NULL COMMENT '업로드 사용자 ID',
  `storage_key` varchar(1000) NOT NULL COMMENT '이미지 Storage Key',
  `content_type` varchar(100) NOT NULL COMMENT '검증된 MIME Type',
  `file_size_bytes` bigint NOT NULL COMMENT '파일 크기(Byte)',
  `width_px` int NOT NULL COMMENT '이미지 너비(px)',
  `height_px` int NOT NULL COMMENT '이미지 높이(px)',
  `checksum_sha256` char(64) NOT NULL COMMENT '이미지 Byte SHA-256',
  `status` varchar(20) NOT NULL DEFAULT 'TEMP' COMMENT 'TEMP 또는 ATTACHED',
  `post_id` bigint DEFAULT NULL COMMENT '연결된 커뮤니티 게시글 ID',
  `display_order` int DEFAULT NULL COMMENT '게시글 내 노출 순서',
  `expires_at` datetime(6) NOT NULL COMMENT 'TEMP 파일 만료 시각',
  `attached_at` datetime(6) DEFAULT NULL COMMENT '게시글 연결 시각',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '업로드 시각',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_community_attachment_files_file_id` (`file_id`),
  KEY `idx_community_attachment_files_owner_status` (`uploaded_by_user_id`,`status`,`expires_at`),
  KEY `idx_community_attachment_files_post_order` (`post_id`,`display_order`),
  KEY `idx_community_attachment_files_expiry` (`status`,`expires_at`),
  CONSTRAINT `fk_community_attachment_files_post_id` FOREIGN KEY (`post_id`) REFERENCES `community_posts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_community_attachment_files_user_id` FOREIGN KEY (`uploaded_by_user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_community_attachment_files_dimensions` CHECK (((`width_px` > 0) and (`height_px` > 0))),
  CONSTRAINT `ck_community_attachment_files_order` CHECK (((`display_order` is null) or ((`display_order` >= 0) and (`display_order` < 5)))),
  CONSTRAINT `ck_community_attachment_files_size` CHECK (((`file_size_bytes` > 0) and (`file_size_bytes` <= 5242880))),
  CONSTRAINT `ck_community_attachment_files_status` CHECK ((`status` in (_utf8mb4'TEMP',_utf8mb4'ATTACHED'))),
  CONSTRAINT `ck_community_attachment_files_status_fields` CHECK ((((`status` = _utf8mb4'TEMP') and (`post_id` is null) and (`display_order` is null) and (`attached_at` is null)) or ((`status` = _utf8mb4'ATTACHED') and (`post_id` is not null) and (`display_order` is not null) and (`attached_at` is not null))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='커뮤니티 게시글 첨부 이미지 파일';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `community_post_template_fields`
--

DROP TABLE IF EXISTS `community_post_template_fields`;
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

--
-- Table structure for table `community_posts`
--

DROP TABLE IF EXISTS `community_posts`;
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
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='커뮤니티 게시글';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `complaint_actions`
--

DROP TABLE IF EXISTS `complaint_actions`;
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

--
-- Table structure for table `complaints`
--

DROP TABLE IF EXISTS `complaints`;
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
  UNIQUE KEY `uk_complaints_reporter_post_reason` (`reporter_user_id`,`target_post_id`,`reason_code`),
  UNIQUE KEY `uk_complaints_reporter_comment_reason` (`reporter_user_id`,`target_comment_id`,`reason_code`),
  UNIQUE KEY `uk_complaints_reporter_report_reason` (`reporter_user_id`,`target_report_id`,`reason_code`),
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

--
-- Table structure for table `consent_record_evidences`
--

DROP TABLE IF EXISTS `consent_record_evidences`;
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

--
-- Table structure for table `consent_records`
--

DROP TABLE IF EXISTS `consent_records`;
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
) ENGINE=InnoDB AUTO_INCREMENT=594 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='동의 이력';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `consent_terms`
--

DROP TABLE IF EXISTS `consent_terms`;
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
  `content_html` text COMMENT '약관 원문 HTML',
  `effective_at` datetime(6) NOT NULL COMMENT '시행 일시',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT '활성 여부',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_consent_terms_code_version` (`term_code`,`version`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='동의 약관';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `conversation_message_audio_variants`
--

DROP TABLE IF EXISTS `conversation_message_audio_variants`;
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

--
-- Table structure for table `conversation_message_options`
--

DROP TABLE IF EXISTS `conversation_message_options`;
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
) ENGINE=InnoDB AUTO_INCREMENT=5654 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 선택지 Snapshot';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `conversation_message_selected_options`
--

DROP TABLE IF EXISTS `conversation_message_selected_options`;
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
) ENGINE=InnoDB AUTO_INCREMENT=185 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지 선택 응답';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `conversation_message_targets`
--

DROP TABLE IF EXISTS `conversation_message_targets`;
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

--
-- Table structure for table `conversation_messages`
--

DROP TABLE IF EXISTS `conversation_messages`;
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
  `tts_voice` varchar(50) DEFAULT NULL COMMENT 'AI 질문 TTS 생성 음성 코드',
  `tts_speed` decimal(3,2) DEFAULT NULL COMMENT 'AI 질문 TTS 생성 재생 속도',
  `stt_confidence` decimal(5,4) DEFAULT NULL COMMENT 'STT 신뢰도',
  `needs_guardian_confirmation` tinyint(1) NOT NULL DEFAULT '0' COMMENT '보호자 확인 필요 여부',
  `is_skipped` tinyint(1) NOT NULL DEFAULT '0' COMMENT '건너뜀 여부',
  `superseded_at` datetime(6) DEFAULT NULL COMMENT '뒤에 온 명시적 답에 자리를 내준 시각. NULL 이면 살아 있는 답',
  `superseded_by_message_id` bigint DEFAULT NULL COMMENT '자리를 대신한 답 메시지 ID',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `tts_tone_profile` varchar(50) DEFAULT NULL COMMENT '질문 TTS 캐시를 구분하는 서버 고정 캐릭터·상황 말투 프로필',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_conversation_messages_session_sequence` (`conversation_session_id`,`message_sequence`),
  UNIQUE KEY `uk_conversation_messages_id_parent` (`id`,`parent_message_id`),
  KEY `fk_conversation_messages_template_id` (`question_template_id`),
  KEY `idx_conversation_messages_parent_message_id` (`parent_message_id`),
  KEY `idx_conversation_messages_live_answer` (`parent_message_id`,`superseded_at`),
  CONSTRAINT `fk_conversation_messages_parent_message_id` FOREIGN KEY (`parent_message_id`) REFERENCES `conversation_messages` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_conversation_messages_session_id` FOREIGN KEY (`conversation_session_id`) REFERENCES `conversation_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_conversation_messages_template_id` FOREIGN KEY (`question_template_id`) REFERENCES `ai_question_templates` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_conversation_messages_message_type` CHECK ((`message_type` in (_utf8mb4'QUESTION',_utf8mb4'VOICE_ANSWER',_utf8mb4'OPTION_ANSWER',_utf8mb4'TEXT_ANSWER',_utf8mb4'SYSTEM_NOTICE'))),
  CONSTRAINT `ck_conversation_messages_sender_type` CHECK ((`sender_type` in (_utf8mb4'AI',_utf8mb4'CHILD',_utf8mb4'GUARDIAN',_utf8mb4'SYSTEM'))),
  CONSTRAINT `ck_conversation_messages_speech_status` CHECK (((`speech_status` is null) or (`speech_status` in (_utf8mb4'NOT_REQUIRED',_utf8mb4'PENDING',_utf8mb4'PROCESSING',_utf8mb4'SUCCESS',_utf8mb4'FAILED')))),
  CONSTRAINT `ck_conversation_messages_stt_confidence` CHECK (((`stt_confidence` is null) or ((`stt_confidence` >= 0) and (`stt_confidence` <= 1)))),
  CONSTRAINT `ck_conversation_messages_supersede_pair` CHECK ((((`superseded_at` is null) and (`superseded_by_message_id` is null)) or ((`superseded_at` is not null) and (`superseded_by_message_id` is not null)))),
  CONSTRAINT `ck_conversation_messages_tts_tone_profile` CHECK (((`tts_tone_profile` is null) or (`tts_tone_profile` in (_utf8mb4'CHARACTER_DEFAULT_V1',_utf8mb4'CHARACTER_CELEBRATING_V1',_utf8mb4'CHARACTER_ENCOURAGING_V1'))))
) ENGINE=InnoDB AUTO_INCREMENT=2178 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 메시지';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `conversation_sessions`
--

DROP TABLE IF EXISTS `conversation_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `conversation_sessions` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '대화 세션 ID',
  `conversation_status` varchar(20) NOT NULL DEFAULT 'CONVERSING' COMMENT '대화 상태',
  `difficulty_snapshot` varchar(30) NOT NULL COMMENT '난이도 적용값',
  `max_question_count` smallint NOT NULL DEFAULT '10' COMMENT '최대 질문 수',
  `question_count` smallint NOT NULL DEFAULT '0' COMMENT '현재 질문 수',
  `completion_reason` varchar(30) DEFAULT NULL COMMENT '대화 종료 사유',
  `started_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '시작 일시',
  `completed_at` datetime(6) DEFAULT NULL COMMENT '완료 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  `drawing_session_id` bigint NOT NULL COMMENT '그림 활동 세션 ID',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_conversation_sessions_drawing_session_id` (`drawing_session_id`),
  KEY `idx_conversation_sessions_drawing_session_id` (`drawing_session_id`),
  CONSTRAINT `fk_conversation_sessions_drawing_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_conversation_sessions_completion_reason` CHECK (((`completion_reason` is null) or (`completion_reason` in (_utf8mb4'QUESTION_LIMIT_REACHED',_utf8mb4'CHILD_REQUEST',_utf8mb4'GUARDIAN_REQUEST',_utf8mb4'NO_MORE_QUESTION')))),
  CONSTRAINT `ck_conversation_sessions_question_count` CHECK (((`max_question_count` > 0) and (`question_count` >= 0) and (`question_count` <= `max_question_count`))),
  CONSTRAINT `ck_conversation_sessions_status` CHECK ((`conversation_status` in (_utf8mb4'CONVERSING',_utf8mb4'COMPLETED',_utf8mb4'FAILED')))
) ENGINE=InnoDB AUTO_INCREMENT=506 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='대화 세션';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `data_export_jobs`
--

DROP TABLE IF EXISTS `data_export_jobs`;
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

--
-- Table structure for table `drawing_assets`
--

DROP TABLE IF EXISTS `drawing_assets`;
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
  `captured_at` datetime(6) NOT NULL COMMENT '클라이언트 캡처 일시',
  `expires_at` datetime(6) DEFAULT NULL COMMENT '만료 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `final_drawing_session_id` bigint GENERATED ALWAYS AS ((case when (`asset_type` = _utf8mb4'FINAL') then `drawing_session_id` else NULL end)) VIRTUAL COMMENT '세션별 최종 그림 유일성 검사용 생성값',
  `upload_idempotency_key` varchar(100) DEFAULT NULL COMMENT 'HTP 원본 이미지 업로드 멱등 키',
  `upload_fingerprint` char(64) DEFAULT NULL COMMENT '정규화된 업로드 요청 SHA-256',
  `upload_rotation_degrees` int DEFAULT NULL COMMENT '클라이언트가 적용한 회전 각도',
  `upload_crop_applied` tinyint(1) DEFAULT NULL COMMENT '클라이언트 자르기 적용 여부',
  `uploaded_drawing_session_id` bigint GENERATED ALWAYS AS ((case when (`asset_type` = _utf8mb4'UPLOADED') then `drawing_session_id` else NULL end)) VIRTUAL COMMENT '세션별 업로드 원본 유일성 검사용 생성값',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_drawing_assets_session_type_version` (`drawing_session_id`,`asset_type`,`asset_version`),
  UNIQUE KEY `uk_drawing_assets_upload_idempotency_key` (`upload_idempotency_key`),
  UNIQUE KEY `uk_drawing_assets_final_session` (`final_drawing_session_id`),
  UNIQUE KEY `uk_drawing_assets_uploaded_session` (`uploaded_drawing_session_id`),
  KEY `idx_drawing_assets_session_type` (`drawing_session_id`,`asset_type`,`asset_version`),
  CONSTRAINT `fk_drawing_assets_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_drawing_assets_asset_type` CHECK ((`asset_type` in (_utf8mb4'DRAFT',_utf8mb4'INTERMEDIATE',_utf8mb4'FINAL',_utf8mb4'UPLOADED',_utf8mb4'THUMBNAIL',_utf8mb4'TIMELAPSE'))),
  CONSTRAINT `ck_drawing_assets_file_size` CHECK ((`file_size_bytes` >= 0)),
  CONSTRAINT `ck_drawing_assets_last_event_sequence` CHECK (((`last_event_sequence` is null) or (`last_event_sequence` >= 0)))
) ENGINE=InnoDB AUTO_INCREMENT=4229 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 파일';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `drawing_session_emotions`
--

DROP TABLE IF EXISTS `drawing_session_emotions`;
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
) ENGINE=InnoDB AUTO_INCREMENT=188 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 선택 감정';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `drawing_sessions`
--

DROP TABLE IF EXISTS `drawing_sessions`;
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
  CONSTRAINT `ck_drawing_sessions_session_status` CHECK ((`session_status` in (_utf8mb4'IN_PROGRESS',_utf8mb4'COMPLETED',_utf8mb4'FAILED',_utf8mb4'ABANDONED',_utf8mb4'DELETED')))
) ENGINE=InnoDB AUTO_INCREMENT=3705 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 세션';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `drawing_types`
--

DROP TABLE IF EXISTS `drawing_types`;
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
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림 활동 유형';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `expert_credential_files`
--

DROP TABLE IF EXISTS `expert_credential_files`;
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

--
-- Table structure for table `expert_credentials`
--

DROP TABLE IF EXISTS `expert_credentials`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `expert_credentials` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '전문가 자격 ID',
  `expert_profile_id` bigint NOT NULL COMMENT '전문가 프로필 ID',
  `credential_type` varchar(50) NOT NULL COMMENT '자격 분류 코드',
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

--
-- Table structure for table `expert_follows`
--

DROP TABLE IF EXISTS `expert_follows`;
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

--
-- Table structure for table `expert_profile_specialties`
--

DROP TABLE IF EXISTS `expert_profile_specialties`;
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

--
-- Table structure for table `expert_profiles`
--

DROP TABLE IF EXISTS `expert_profiles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `expert_profiles` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '전문가 프로필 ID',
  `display_name` varchar(80) NOT NULL COMMENT '표시 이름',
  `profile_image_url` varchar(1000) DEFAULT NULL COMMENT '프로필 이미지 URL',
  `organization` varchar(150) DEFAULT NULL COMMENT '소속 기관',
  `position_title` varchar(100) DEFAULT NULL COMMENT '직책',
  `career_years` smallint NOT NULL DEFAULT '0' COMMENT '경력 연수',
  `target_age_min` smallint DEFAULT NULL COMMENT '상담 대상 최소 연령',
  `target_age_max` smallint DEFAULT NULL COMMENT '상담 대상 최대 연령',
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
  CONSTRAINT `fk_expert_profiles_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_expert_profiles_career_years` CHECK ((`career_years` >= 0)),
  CONSTRAINT `ck_expert_profiles_target_age` CHECK ((((`target_age_min` is null) and (`target_age_max` is null)) or ((`target_age_min` between 0 and 19) and (`target_age_max` between 0 and 19) and (`target_age_min` <= `target_age_max`)))),
  CONSTRAINT `ck_expert_profiles_verification_status` CHECK ((`verification_status` in (_utf8mb4'PENDING',_utf8mb4'VERIFIED',_utf8mb4'REJECTED',_utf8mb4'REVIEW_REQUIRED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 프로필';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `expert_verification_review_credentials`
--

DROP TABLE IF EXISTS `expert_verification_review_credentials`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `expert_verification_review_credentials` (
  `review_id` bigint NOT NULL COMMENT '전문가 검토 이력 ID',
  `expert_credential_id` bigint NOT NULL COMMENT '승인한 전문가 자격 ID',
  PRIMARY KEY (`review_id`,`expert_credential_id`),
  KEY `fk_expert_verification_review_credentials_credential_id` (`expert_credential_id`),
  CONSTRAINT `fk_expert_verification_review_credentials_credential_id` FOREIGN KEY (`expert_credential_id`) REFERENCES `expert_credentials` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_expert_verification_review_credentials_review_id` FOREIGN KEY (`review_id`) REFERENCES `expert_verification_reviews` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 검토 승인 자격';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `expert_verification_reviews`
--

DROP TABLE IF EXISTS `expert_verification_reviews`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `expert_verification_reviews` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '전문가 검토 이력 ID',
  `expert_profile_id` bigint NOT NULL COMMENT '검토 대상 전문가 프로필 ID',
  `reviewer_user_id` bigint NOT NULL COMMENT '검토 관리자 사용자 ID',
  `decision_status` varchar(20) NOT NULL COMMENT '최종 승인·반려 상태',
  `rejection_reason` varchar(1000) DEFAULT NULL COMMENT '전문가에게 공개할 반려 사유',
  `internal_note` varchar(2000) DEFAULT NULL COMMENT '관리자 내부 검토 메모',
  `reviewed_at` datetime(6) NOT NULL COMMENT '검토 완료 일시',
  PRIMARY KEY (`id`),
  KEY `fk_expert_verification_reviews_reviewer_id` (`reviewer_user_id`),
  KEY `idx_expert_verification_reviews_profile_reviewed` (`expert_profile_id`,`reviewed_at` DESC),
  CONSTRAINT `fk_expert_verification_reviews_profile_id` FOREIGN KEY (`expert_profile_id`) REFERENCES `expert_profiles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_expert_verification_reviews_reviewer_id` FOREIGN KEY (`reviewer_user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_expert_verification_reviews_reason` CHECK ((((`decision_status` = _utf8mb4'VERIFIED') and (`rejection_reason` is null)) or ((`decision_status` = _utf8mb4'REJECTED') and (`rejection_reason` is not null)))),
  CONSTRAINT `ck_expert_verification_reviews_status` CHECK ((`decision_status` in (_utf8mb4'VERIFIED',_utf8mb4'REJECTED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='전문가 자격 검토 이력';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `flyway_schema_history`
--

DROP TABLE IF EXISTS `flyway_schema_history`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `flyway_schema_history` (
  `installed_rank` int NOT NULL,
  `version` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `description` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `type` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `script` varchar(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `checksum` int DEFAULT NULL,
  `installed_by` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `installed_on` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `execution_time` int NOT NULL,
  `success` tinyint(1) NOT NULL,
  PRIMARY KEY (`installed_rank`),
  KEY `flyway_schema_history_s_idx` (`success`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `guardian_child_relations`
--

DROP TABLE IF EXISTS `guardian_child_relations`;
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
) ENGINE=InnoDB AUTO_INCREMENT=216 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='보호자-아동 관계';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `htp_assessment_steps`
--

DROP TABLE IF EXISTS `htp_assessment_steps`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `htp_assessment_steps` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'HTP 그림 단계 ID',
  `htp_assessment_id` bigint NOT NULL COMMENT 'HTP 활동 묶음 ID',
  `step_order` tinyint NOT NULL COMMENT '그림 단계 순서',
  `drawing_subject` varchar(20) NOT NULL COMMENT '그림 주제',
  `drawing_session_id` bigint NOT NULL COMMENT '단계별 그림 활동 세션 ID',
  `subject_detected` tinyint(1) DEFAULT NULL COMMENT '주제 전체 객체 탐지 여부',
  `retry_count` tinyint NOT NULL DEFAULT '0' COMMENT '추가 그리기 요청 횟수',
  `transition_idempotency_key` varchar(100) NOT NULL COMMENT '단계 생성 요청 멱등 키',
  `completion_idempotency_key` varchar(100) DEFAULT NULL COMMENT '단계 완료 요청 멱등 키',
  `created_at` datetime(6) NOT NULL COMMENT '단계 생성 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_htp_assessment_steps_order` (`htp_assessment_id`,`step_order`),
  UNIQUE KEY `uk_htp_assessment_steps_subject` (`htp_assessment_id`,`drawing_subject`),
  UNIQUE KEY `uk_htp_assessment_steps_session` (`drawing_session_id`),
  UNIQUE KEY `uk_htp_assessment_steps_transition_key` (`transition_idempotency_key`),
  CONSTRAINT `fk_htp_assessment_steps_assessment_id` FOREIGN KEY (`htp_assessment_id`) REFERENCES `htp_assessments` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_htp_assessment_steps_drawing_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_htp_assessment_steps_order` CHECK ((`step_order` between 1 and 3)),
  CONSTRAINT `ck_htp_assessment_steps_retry_count` CHECK ((`retry_count` between 0 and 1)),
  CONSTRAINT `ck_htp_assessment_steps_subject` CHECK ((`drawing_subject` in (_utf8mb4'HOUSE',_utf8mb4'TREE',_utf8mb4'PERSON')))
) ENGINE=InnoDB AUTO_INCREMENT=298 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='HTP 그림 단계';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `htp_assessments`
--

DROP TABLE IF EXISTS `htp_assessments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `htp_assessments` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'HTP 활동 묶음 ID',
  `child_id` bigint NOT NULL COMMENT '아동 ID',
  `drawing_type_id` bigint NOT NULL COMMENT 'HTP 그림 활동 유형 ID',
  `status` varchar(20) NOT NULL COMMENT 'HTP 활동 상태',
  `current_step_order` tinyint NOT NULL COMMENT '현재 그림 단계 순서',
  `expires_at` datetime(6) NOT NULL COMMENT '재개 만료 일시',
  `created_at` datetime(6) NOT NULL COMMENT '생성 일시',
  `completed_at` datetime(6) DEFAULT NULL COMMENT '완료·포기 일시',
  `idempotency_key` varchar(100) NOT NULL COMMENT 'HTP 시작 요청 멱등 키',
  `completion_idempotency_key` varchar(100) DEFAULT NULL COMMENT 'HTP 종합 완료 요청 멱등 키',
  `report_analysis_id` bigint DEFAULT NULL COMMENT '현재 HTP 리포트 생성 분석 ID',
  `report_id` bigint DEFAULT NULL COMMENT '현재 HTP 단일 리포트 ID',
  `active_child_id` bigint GENERATED ALWAYS AS ((case when (`status` in (_utf8mb4'IN_PROGRESS',_utf8mb4'ANALYZING')) then `child_id` else NULL end)) STORED COMMENT '아동별 진행 중 HTP 유일성 보장용',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_htp_assessments_idempotency_key` (`idempotency_key`),
  UNIQUE KEY `uk_htp_assessments_active_child` (`active_child_id`),
  UNIQUE KEY `uk_htp_assessments_completion_key` (`completion_idempotency_key`),
  KEY `fk_htp_assessments_drawing_type_id` (`drawing_type_id`),
  KEY `idx_htp_assessments_child_created_at` (`child_id`,`created_at`),
  KEY `fk_htp_assessments_report_analysis_id` (`report_analysis_id`),
  KEY `fk_htp_assessments_report_id` (`report_id`),
  CONSTRAINT `fk_htp_assessments_child_id` FOREIGN KEY (`child_id`) REFERENCES `children` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_htp_assessments_drawing_type_id` FOREIGN KEY (`drawing_type_id`) REFERENCES `drawing_types` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_htp_assessments_report_analysis_id` FOREIGN KEY (`report_analysis_id`) REFERENCES `analyses` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_htp_assessments_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_htp_assessments_current_step_order` CHECK ((`current_step_order` between 1 and 3)),
  CONSTRAINT `ck_htp_assessments_status` CHECK ((`status` in (_utf8mb4'IN_PROGRESS',_utf8mb4'ANALYZING',_utf8mb4'COMPLETED',_utf8mb4'FAILED',_utf8mb4'ABANDONED',_utf8mb4'EXPIRED')))
) ENGINE=InnoDB AUTO_INCREMENT=151 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='HTP 활동 묶음';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `notification_attributes`
--

DROP TABLE IF EXISTS `notification_attributes`;
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

--
-- Table structure for table `notification_device_tokens`
--

DROP TABLE IF EXISTS `notification_device_tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `notification_device_tokens` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'Push 기기 Token ID',
  `user_id` bigint NOT NULL COMMENT '사용자 ID',
  `device_id` varchar(100) NOT NULL COMMENT '클라이언트 설치 식별자',
  `token_ciphertext` varchar(1500) NOT NULL COMMENT '암호화된 Push Provider 기기 Token',
  `token_hash` char(64) NOT NULL COMMENT '기기 Token SHA-256 Hash',
  `platform` varchar(20) NOT NULL COMMENT '기기 Platform',
  `push_provider` varchar(20) NOT NULL COMMENT 'Push Provider',
  `app_version` varchar(20) DEFAULT NULL COMMENT '등록 시점 앱 버전',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT '활성 여부',
  `last_used_at` datetime(6) DEFAULT NULL COMMENT '마지막 사용 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_notification_device_tokens_hash` (`token_hash`),
  UNIQUE KEY `uk_notification_device_tokens_user_device` (`user_id`,`device_id`),
  KEY `idx_notification_device_tokens_user_active` (`user_id`,`is_active`),
  CONSTRAINT `fk_notification_device_tokens_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_notification_device_tokens_platform` CHECK ((`platform` in (_utf8mb4'ANDROID',_utf8mb4'IOS',_utf8mb4'WEB'))),
  CONSTRAINT `ck_notification_device_tokens_provider` CHECK ((`push_provider` in (_utf8mb4'FCM',_utf8mb4'APNS')))
) ENGINE=InnoDB AUTO_INCREMENT=57 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Push 기기 Token';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `notifications`
--

DROP TABLE IF EXISTS `notifications`;
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
  CONSTRAINT `ck_notifications_type` CHECK ((`notification_type` in (_utf8mb4'ANALYSIS_COMPLETED',_utf8mb4'ANALYSIS_FAILED',_utf8mb4'REPORT_COMPLETED',_utf8mb4'NEW_EXPERT_POST',_utf8mb4'COMMENT_CREATED',_utf8mb4'CONSENT_UPDATED',_utf8mb4'RETENTION_NOTICE',_utf8mb4'ACTIVITY_REMINDER',_utf8mb4'RISK_REVIEW_GUIDE',_utf8mb4'EXPERT_VERIFICATION_RESULT')))
) ENGINE=InnoDB AUTO_INCREMENT=135 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='알림';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `post_likes`
--

DROP TABLE IF EXISTS `post_likes`;
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
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='게시글 좋아요';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_activity_notes`
--

DROP TABLE IF EXISTS `report_activity_notes`;
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
) ENGINE=InnoDB AUTO_INCREMENT=284 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 활동 주의사항';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_activity_summaries`
--

DROP TABLE IF EXISTS `report_activity_summaries`;
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

--
-- Table structure for table `report_crisis_alert_resources`
--

DROP TABLE IF EXISTS `report_crisis_alert_resources`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_crisis_alert_resources` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '위기 안내 자원 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  `resource_name` varchar(100) NOT NULL COMMENT '자원 이름',
  `contact` varchar(100) NOT NULL COMMENT '연락처',
  `note` varchar(300) NOT NULL DEFAULT '' COMMENT '보충 설명',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_crisis_alert_resources_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_crisis_alert_resources_report_id` FOREIGN KEY (`report_id`) REFERENCES `report_crisis_alerts` (`report_id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_crisis_alert_resources_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='위기 안내 상담·신고 자원';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_crisis_alert_steps`
--

DROP TABLE IF EXISTS `report_crisis_alert_steps`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_crisis_alert_steps` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '위기 안내 행동 단계 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  `step_text` text NOT NULL COMMENT '보호자가 취할 행동',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_crisis_alert_steps_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_crisis_alert_steps_report_id` FOREIGN KEY (`report_id`) REFERENCES `report_crisis_alerts` (`report_id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_crisis_alert_steps_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='위기 안내 행동 단계';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_crisis_alerts`
--

DROP TABLE IF EXISTS `report_crisis_alerts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_crisis_alerts` (
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `reason_code` varchar(30) NOT NULL COMMENT '위기 사유 코드',
  `severity` varchar(10) NOT NULL COMMENT '심각도',
  `title` varchar(200) NOT NULL COMMENT '안내 제목',
  `message` text NOT NULL COMMENT '안내 본문',
  PRIMARY KEY (`report_id`),
  CONSTRAINT `fk_report_crisis_alerts_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_crisis_alerts_reason` CHECK ((`reason_code` in (_utf8mb4'SELF_HARM_RISK',_utf8mb4'CRISIS_INTENT'))),
  CONSTRAINT `ck_report_crisis_alerts_severity` CHECK ((`severity` in (_utf8mb4'HIGH',_utf8mb4'ELEVATED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 위기 대응 안내';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_caregiver_questions`
--

DROP TABLE IF EXISTS `report_diary_caregiver_questions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_caregiver_questions` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '보호자 질문 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `question` text NOT NULL COMMENT '보호자가 그대로 물어볼 질문',
  `purpose` varchar(300) DEFAULT NULL COMMENT '이 질문으로 더 들어볼 내용',
  `connection_type` varchar(30) NOT NULL DEFAULT 'GENERAL_CONNECTION' COMMENT 'FEELING_SHARING·COMFORT_SEEKING·SHARED_JOY·PERSPECTIVE_TAKING·GENERAL_CONNECTION',
  `response_guide` text COMMENT '아이 답에 부모가 마음으로 반응하는 법. 서버가 유형으로 정적 매핑',
  `co_regulation_action` text COMMENT '함께 해보기 한 줄이며 없을 수 있음',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_caregiver_questions_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_diary_caregiver_questions_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_caregiver_questions_connection_type` CHECK ((`connection_type` in (_utf8mb4'FEELING_SHARING',_utf8mb4'COMFORT_SEEKING',_utf8mb4'SHARED_JOY',_utf8mb4'PERSPECTIVE_TAKING',_utf8mb4'GENERAL_CONNECTION'))),
  CONSTRAINT `ck_report_diary_caregiver_questions_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 보호자가 이어 갈 질문';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_child_voices`
--

DROP TABLE IF EXISTS `report_diary_child_voices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_child_voices` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '아이 발화 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `text` text NOT NULL COMMENT '아이가 한 말 그대로',
  `elicitation_type` varchar(30) NOT NULL COMMENT '그 말을 끌어낸 질문 방식, 고른 답을 자발 표현으로 읽지 않기 위한 구분',
  `answer_type` varchar(30) DEFAULT NULL COMMENT '답변 입력 방식',
  `source_ref_kind` varchar(40) DEFAULT NULL COMMENT '근거 종류',
  `source_ref_id` varchar(64) DEFAULT NULL COMMENT 'BE 가 발급한 근거 식별자',
  `stt_needs_confirmation` tinyint(1) NOT NULL DEFAULT '0' COMMENT '음성 인식 확인 필요 여부',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_child_voices_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_diary_child_voices_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_child_voices_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 아이가 직접 들려준 말';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_development_sources`
--

DROP TABLE IF EXISTS `report_diary_development_sources`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_development_sources` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '출처 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `domain` varchar(30) NOT NULL COMMENT '소유 관찰의 도메인',
  `source_id` varchar(60) NOT NULL COMMENT '검수 출처 식별자(CDC_5Y_MILESTONES 등)',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '관찰 안에서의 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_development_sources_slot` (`report_id`,`domain`,`source_id`),
  CONSTRAINT `fk_report_diary_development_sources_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_development_sources_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=29 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 발달 맥락의 검수 출처';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_developmental_observations`
--

DROP TABLE IF EXISTS `report_diary_developmental_observations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_developmental_observations` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '발달 맥락 관찰 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `domain` varchar(30) NOT NULL COMMENT 'NARRATIVE_LANGUAGE·EMOTION_EXPRESSION·SOCIAL_UNDERSTANDING·COPING_HELP_SEEKING·SELF_REFLECTION·CONVERSATION_PARTICIPATION·DRAWING_LANGUAGE_INTEGRATION',
  `status` varchar(30) NOT NULL COMMENT 'OBSERVED_THIS_SESSION·PARTIALLY_OBSERVED·NOT_ASSESSED',
  `context_type` varchar(40) NOT NULL DEFAULT 'SESSION_ONLY_CONTEXT' COMMENT 'AGE_MILESTONE_CONTEXT·EARLY_SCHOOL_COMMUNICATION_CONTEXT·SESSION_ONLY_CONTEXT',
  `age_context` text NOT NULL COMMENT '검수 출처에서 온 연령 맥락 한 줄',
  `observation` text NOT NULL COMMENT '이번 활동에서 확인된 표현',
  `scope_text` varchar(200) NOT NULL COMMENT '범위 고지, 화면에 항상 함께 나간다',
  `caregiver_question` text COMMENT '보호자가 이어서 물어볼 질문',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_developmental_observations_slot` (`report_id`,`domain`),
  CONSTRAINT `fk_report_diary_developmental_observations_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_developmental_observations_context_type` CHECK ((`context_type` in (_utf8mb4'AGE_MILESTONE_CONTEXT',_utf8mb4'EARLY_SCHOOL_COMMUNICATION_CONTEXT',_utf8mb4'SESSION_ONLY_CONTEXT'))),
  CONSTRAINT `ck_report_diary_developmental_observations_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=46 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 연령 발달 맥락 관찰';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_evidence_refs`
--

DROP TABLE IF EXISTS `report_diary_evidence_refs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_evidence_refs` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '근거 참조 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `owner_type` varchar(30) NOT NULL COMMENT 'STORY_SNAPSHOT·NARRATIVE_STEP·SESSION_OBSERVATION·CAREGIVER_QUESTION·DEVELOPMENTAL_OBSERVATION',
  `owner_order` smallint NOT NULL DEFAULT '0' COMMENT '소유 항목의 display_order, 1:1 인 STORY_SNAPSHOT 은 0',
  `ref_kind` varchar(40) NOT NULL COMMENT '근거 종류',
  `ref_id` varchar(64) NOT NULL COMMENT 'BE 가 발급한 근거 식별자',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '항목 안에서의 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_evidence_refs_slot` (`report_id`,`owner_type`,`owner_order`,`display_order`),
  CONSTRAINT `fk_report_diary_evidence_refs_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_evidence_refs_order` CHECK (((`display_order` >= 0) and (`owner_order` >= 0)))
) ENGINE=InnoDB AUTO_INCREMENT=122 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 구조화 항목의 근거 참조';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_insight_alternatives`
--

DROP TABLE IF EXISTS `report_diary_insight_alternatives`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_insight_alternatives` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '다른 설명 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `observation_order` smallint NOT NULL COMMENT '소유 관찰 카드의 display_order',
  `text` text NOT NULL COMMENT '다르게 볼 수 있는 설명 한 문장',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '카드 안에서의 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_insight_alternatives_slot` (`report_id`,`observation_order`,`display_order`),
  CONSTRAINT `fk_report_diary_insight_alternatives_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_insight_alternatives_order` CHECK (((`display_order` >= 0) and (`observation_order` >= 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 인사이트의 다른 가능한 설명';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_insights`
--

DROP TABLE IF EXISTS `report_diary_insights`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_insights` (
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `schema_version` smallint NOT NULL DEFAULT '2' COMMENT '그림일기 구조 버전',
  `evidence_level` varchar(20) DEFAULT NULL COMMENT 'LIMITED·PARTIAL·RICH',
  `data_scope_summary` varchar(300) DEFAULT NULL COMMENT '자료 범위 설명',
  `visual_observation_count` smallint NOT NULL DEFAULT '0' COMMENT '그림 관찰 건수',
  `headline` varchar(200) DEFAULT NULL COMMENT '핵심 이야기 제목',
  `summary` text COMMENT '사건·행동·상대 반응을 이은 요약',
  `reality_status` varchar(20) NOT NULL DEFAULT 'UNKNOWN' COMMENT '실제/상상 구분, 아이가 말한 경우에만 UNKNOWN 이 아니다',
  `time_scope` varchar(20) NOT NULL DEFAULT 'UNKNOWN' COMMENT '사건 시점, 활동 날짜는 근거가 아니다',
  `main_event` varchar(300) DEFAULT NULL COMMENT '중심 사건, 분명하지 않으면 NULL',
  `listening_tip` text COMMENT '이번 이야기를 들을 때의 태도 한 문장',
  `confirmed_voice_count` smallint NOT NULL DEFAULT '0' COMMENT '음성으로 확정된 답변 수',
  `option_answer_count` smallint NOT NULL DEFAULT '0' COMMENT '선택지에서 고른 답변 수',
  `skipped_count` smallint NOT NULL DEFAULT '0' COMMENT '건너뛴 질문 수',
  `stt_confirmation_count` smallint NOT NULL DEFAULT '0' COMMENT '음성 인식 확인이 필요한 답변 수',
  `evidence_count` smallint NOT NULL DEFAULT '0' COMMENT '사용된 근거 수',
  `vision_summary_available` tinyint(1) NOT NULL DEFAULT '0' COMMENT '그림 관찰 서술 존재 여부',
  PRIMARY KEY (`report_id`),
  CONSTRAINT `fk_report_diary_insights_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_insights_evidence_level` CHECK (((`evidence_level` is null) or (`evidence_level` in (_utf8mb4'LIMITED',_utf8mb4'PARTIAL',_utf8mb4'RICH')))),
  CONSTRAINT `ck_report_diary_insights_schema_version` CHECK ((`schema_version` >= 2)),
  CONSTRAINT `ck_report_diary_insights_visual_count` CHECK ((`visual_observation_count` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 핵심 이야기와 데이터 구성';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_narrative_steps`
--

DROP TABLE IF EXISTS `report_diary_narrative_steps`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_narrative_steps` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '이야기 흐름 단계 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `step_type` varchar(30) NOT NULL COMMENT 'EVENT·CHILD_ACTION·OTHER_RESPONSE·EMOTION·WISH·OUTCOME',
  `text` text NOT NULL COMMENT '그 단계에서 확인된 내용',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '시간 흐름 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_narrative_steps_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_diary_narrative_steps_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_narrative_steps_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=24 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 이야기 흐름';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_session_observations`
--

DROP TABLE IF EXISTS `report_diary_session_observations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_session_observations` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '이번 활동 관찰 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `observation_code` varchar(60) NOT NULL COMMENT '관찰 코드',
  `title` varchar(200) NOT NULL COMMENT '보호자에게 보이는 제목',
  `description` text NOT NULL COMMENT '근거에 묶인 이번 활동 한정 설명',
  `scope_text` varchar(200) NOT NULL COMMENT '범위를 알리는 문구',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  `insight_type` varchar(30) NOT NULL DEFAULT 'CONFIRMED_EXPRESSION' COMMENT '주장의 세기 — CONFIRMED_EXPRESSION·SESSION_HYPOTHESIS·EXPLORE_NEXT',
  `domain` varchar(30) NOT NULL DEFAULT 'STORY' COMMENT 'STORY·EMOTION·RELATIONSHIP·SELF_EXPRESSION·COPING·ACTIVITY_STYLE',
  `hypothesis` text COMMENT '이번 회차 한정 가설이며 확인된 표현·단서에는 NULL',
  `clarification_question` text COMMENT '다음에 확인할 질문이며 EXPLORE_NEXT 에는 필수',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_session_observations_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_diary_session_observations_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_session_observations_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기 V2 이번 활동에서 확인된 표현';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_story_components`
--

DROP TABLE IF EXISTS `report_diary_story_components`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_story_components` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `report_id` bigint NOT NULL,
  `component_type` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '이야기 구성 요소 종류',
  `confirmation_status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'CONFIRMED·VISUAL_ONLY·SELECTED·PARTIAL·UNKNOWN',
  `text` text COLLATE utf8mb4_unicode_ci COMMENT '확인된 내용이며 UNKNOWN이면 null 가능',
  `display_order` smallint NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_story_component` (`report_id`,`component_type`),
  CONSTRAINT `fk_report_diary_story_component_report` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_story_component_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_report_diary_story_component_status` CHECK ((`confirmation_status` in (_utf8mb4'CONFIRMED',_utf8mb4'VISUAL_ONLY',_utf8mb4'SELECTED',_utf8mb4'PARTIAL',_utf8mb4'UNKNOWN')))
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_transcript_entries`
--

DROP TABLE IF EXISTS `report_diary_transcript_entries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_transcript_entries` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `report_id` bigint NOT NULL,
  `question_message_id` bigint DEFAULT NULL,
  `answer_message_id` bigint DEFAULT NULL,
  `question_text` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `answer_text` text COLLATE utf8mb4_unicode_ci,
  `response_type` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'VOICE·OPTION·TEXT·SKIPPED·CORRECTION',
  `stt_status` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `audio_available_at_generation` tinyint(1) NOT NULL DEFAULT '0',
  `audio_duration_ms` int DEFAULT NULL COMMENT '현재 수집하지 않으며 향후 실제 값이 있을 때만 저장',
  `elicitation_type` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL,
  `occurred_at` datetime(6) DEFAULT NULL COMMENT '답변 메시지 시각이며 과거 데이터는 null 가능',
  `display_order` smallint NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_transcript_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_diary_transcript_report` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_transcript_audio_duration` CHECK (((`audio_duration_ms` is null) or (`audio_duration_ms` >= 0))),
  CONSTRAINT `ck_report_diary_transcript_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_report_diary_transcript_response_type` CHECK ((`response_type` in (_utf8mb4'VOICE',_utf8mb4'OPTION',_utf8mb4'TEXT',_utf8mb4'SKIPPED',_utf8mb4'CORRECTION')))
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_unknown_items`
--

DROP TABLE IF EXISTS `report_diary_unknown_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_unknown_items` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '확인하지 못한 것 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `code` varchar(40) NOT NULL COMMENT 'NO_VOICE_ANSWER·SKIPPED_QUESTIONS 등 서버가 정한 코드',
  `text` text NOT NULL COMMENT '보호자에게 보이는 문구',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_unknown_items_slot` (`report_id`,`code`),
  CONSTRAINT `fk_report_diary_unknown_items_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_unknown_items_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='그림일기에서 확인하지 못한 것';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_diary_visual_observations`
--

DROP TABLE IF EXISTS `report_diary_visual_observations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_diary_visual_observations` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `report_id` bigint NOT NULL,
  `text` text COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '그림에서 직접 확인한 사실',
  `confidence` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'HIGH·MODERATE·LOW',
  `child_confirmed` tinyint(1) NOT NULL DEFAULT '0' COMMENT '아이 발화로 확인됐는지 여부',
  `display_order` smallint NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_diary_visual_observation_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_diary_visual_observation_report` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_diary_visual_observation_confidence` CHECK ((`confidence` in (_utf8mb4'HIGH',_utf8mb4'MODERATE',_utf8mb4'LOW'))),
  CONSTRAINT `ck_report_diary_visual_observation_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_drawn_items`
--

DROP TABLE IF EXISTS `report_drawn_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_drawn_items` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 그린 것 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서이며 주제 순서(집→나무→사람)를 보존한다',
  `drawing_subject` varchar(10) DEFAULT NULL COMMENT 'HTP 주제이며 그림일기는 NULL',
  `name` varchar(100) NOT NULL COMMENT '보호자 화면에 그대로 나가는 한국어 표현',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_drawn_items_report_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_drawn_items_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_drawn_items_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_report_drawn_items_subject` CHECK (((`drawing_subject` is null) or (`drawing_subject` in (_utf8mb4'HOUSE',_utf8mb4'TREE',_utf8mb4'PERSON'))))
) ENGINE=InnoDB AUTO_INCREMENT=220 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 그린 것';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_evidence_authors`
--

DROP TABLE IF EXISTS `report_evidence_authors`;
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

--
-- Table structure for table `report_evidence_derivations`
--

DROP TABLE IF EXISTS `report_evidence_derivations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_evidence_derivations` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '파생 근거 원본 참조 ID',
  `evidence_item_id` bigint NOT NULL COMMENT '파생 근거 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '원본 참조 순서',
  `source_ref_kind` varchar(20) NOT NULL COMMENT '원본 근거의 종류',
  `source_ref_id` varchar(64) NOT NULL COMMENT 'BE 가 발급한 원본 식별자',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_evidence_derivations_item_order` (`evidence_item_id`,`display_order`),
  CONSTRAINT `fk_report_evidence_derivations_item_id` FOREIGN KEY (`evidence_item_id`) REFERENCES `report_evidence_items` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_evidence_derivations_kind` CHECK ((`source_ref_kind` in (_utf8mb4'QA_ANSWER',_utf8mb4'DETECTED_OBJECT',_utf8mb4'VLM_OBSERVATION',_utf8mb4'EMOTION_SELECTION',_utf8mb4'ACTIVITY_METRIC',_utf8mb4'PRIOR_ACTIVITY'))),
  CONSTRAINT `ck_report_evidence_derivations_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='파생 근거의 원본 참조';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_evidence_items`
--

DROP TABLE IF EXISTS `report_evidence_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_evidence_items` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 근거 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `evidence_number` int NOT NULL COMMENT '리포트 안에서 유일한 근거 번호이며 응답의 evidenceId 로 나간다',
  `source_type` varchar(20) NOT NULL COMMENT '근거 종류',
  `text` text NOT NULL COMMENT '근거 문장',
  `source_ref_kind` varchar(20) DEFAULT NULL COMMENT '원본 근거의 종류이며 파생 근거면 NULL',
  `source_ref_id` varchar(64) DEFAULT NULL COMMENT 'BE 가 발급한 원본 식별자이며 파생 근거면 NULL',
  `stt_needs_confirmation` tinyint(1) NOT NULL DEFAULT '0' COMMENT '음성 인식 확인이 필요한 발화에서 온 근거인지',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_evidence_items_report_number` (`report_id`,`evidence_number`),
  CONSTRAINT `fk_report_evidence_items_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_evidence_items_number` CHECK ((`evidence_number` > 0)),
  CONSTRAINT `ck_report_evidence_items_source_ref_kind` CHECK (((`source_ref_kind` is null) or (`source_ref_kind` in (_utf8mb4'QA_ANSWER',_utf8mb4'DETECTED_OBJECT',_utf8mb4'VLM_OBSERVATION',_utf8mb4'EMOTION_SELECTION',_utf8mb4'ACTIVITY_METRIC',_utf8mb4'PRIOR_ACTIVITY')))),
  CONSTRAINT `ck_report_evidence_items_source_ref_pair` CHECK ((((`source_ref_kind` is null) and (`source_ref_id` is null)) or ((`source_ref_kind` is not null) and (`source_ref_id` is not null)))),
  CONSTRAINT `ck_report_evidence_items_source_type` CHECK ((`source_type` in (_utf8mb4'VISION',_utf8mb4'CHILD_ANSWER',_utf8mb4'SELECTED_EMOTION',_utf8mb4'STATED_EMOTION',_utf8mb4'ACTIVITY_METRIC',_utf8mb4'REPEATED_SUBJECT',_utf8mb4'LONGITUDINAL')))
) ENGINE=InnoDB AUTO_INCREMENT=37 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 근거';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_evidence_references`
--

DROP TABLE IF EXISTS `report_evidence_references`;
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

--
-- Table structure for table `report_follow_up_guides`
--

DROP TABLE IF EXISTS `report_follow_up_guides`;
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
) ENGINE=InnoDB AUTO_INCREMENT=217 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 후속 안내';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_generation_retries`
--

DROP TABLE IF EXISTS `report_generation_retries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_generation_retries` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '재시도 작업 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `analysis_id` bigint NOT NULL COMMENT '최종 분석 ID',
  `attempt_count` smallint NOT NULL DEFAULT '0' COMMENT '지금까지 시도한 횟수',
  `next_attempt_at` datetime(6) NOT NULL COMMENT '다음 시도 예정 시각',
  `last_failure_stage` varchar(40) DEFAULT NULL COMMENT '마지막 실패 단계(AI 호출·응답 검증·저장)',
  `last_failure_code` varchar(100) DEFAULT NULL COMMENT '마지막 실패 분류 코드',
  `correlation_id` char(36) DEFAULT NULL COMMENT '요청을 로그와 잇는 식별자',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '등록 일시',
  `resolved_at` datetime(6) DEFAULT NULL COMMENT '성공하거나 포기한 시각',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_generation_retries_report` (`report_id`),
  KEY `idx_report_generation_retries_due` (`resolved_at`,`next_attempt_at`),
  CONSTRAINT `fk_report_generation_retries_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_generation_retries_attempts` CHECK ((`attempt_count` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 생성 재시도 대기열';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_guardian_questions`
--

DROP TABLE IF EXISTS `report_guardian_questions`;
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
) ENGINE=InnoDB AUTO_INCREMENT=170 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 보호자 질문';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_interpretation_evidences`
--

DROP TABLE IF EXISTS `report_interpretation_evidences`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_interpretation_evidences` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '경향 해석 근거 참조 ID',
  `interpretation_id` bigint NOT NULL COMMENT '경향 해석 ID',
  `evidence_item_id` bigint NOT NULL COMMENT '리포트 근거 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '근거 노출 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_interpretation_evidences_pair` (`interpretation_id`,`evidence_item_id`),
  UNIQUE KEY `uk_report_interpretation_evidences_order` (`interpretation_id`,`display_order`),
  KEY `fk_report_interpretation_evidences_evidence_item_id` (`evidence_item_id`),
  CONSTRAINT `fk_report_interpretation_evidences_evidence_item_id` FOREIGN KEY (`evidence_item_id`) REFERENCES `report_evidence_items` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_report_interpretation_evidences_interpretation_id` FOREIGN KEY (`interpretation_id`) REFERENCES `report_public_interpretations` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_interpretation_evidences_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=38 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='경향 해석과 근거의 연결';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_key_conversations`
--

DROP TABLE IF EXISTS `report_key_conversations`;
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
) ENGINE=InnoDB AUTO_INCREMENT=317 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 주요 대화';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_observed_features`
--

DROP TABLE IF EXISTS `report_observed_features`;
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
) ENGINE=InnoDB AUTO_INCREMENT=205 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 관찰 특징';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_parent_guides`
--

DROP TABLE IF EXISTS `report_parent_guides`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_parent_guides` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '보호자 가이드 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `guide_type` varchar(30) NOT NULL COMMENT '가이드 유형',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '유형 안에서의 노출 순서',
  `guidance` text NOT NULL COMMENT '화면에 그대로 나가는 완결 문장',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_parent_guides_report_type_order` (`report_id`,`guide_type`,`display_order`),
  CONSTRAINT `fk_report_parent_guides_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_parent_guides_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_report_parent_guides_type` CHECK ((`guide_type` in (_utf8mb4'DRAWING_CONVERSATION',_utf8mb4'DAILY_PARENTING',_utf8mb4'HOME_OBSERVATION',_utf8mb4'PROFESSIONAL_SUPPORT')))
) ENGINE=InnoDB AUTO_INCREMENT=111 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 보호자 가이드';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_public_interpretations`
--

DROP TABLE IF EXISTS `report_public_interpretations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_public_interpretations` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '경향 해석 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서이며 응답의 interpretationRefs 가 이 순서를 가리킨다',
  `category` varchar(20) NOT NULL COMMENT '관찰 관점 라벨',
  `title` varchar(200) NOT NULL COMMENT '카드 제목',
  `tendency_text` text NOT NULL COMMENT '가능성 어조의 경향 문장',
  `scope_text` text COMMENT '해석 범위 안내이며 비면 미공개',
  `home_observation_guide` text COMMENT '가정에서 살펴볼 점이며 비면 미공개',
  `disclosure_state` varchar(20) NOT NULL DEFAULT 'WITHHELD' COMMENT '공개 판정 결과',
  `withheld_reason_code` varchar(40) DEFAULT NULL COMMENT '미공개·강등 사유 코드',
  `confidence` varchar(20) DEFAULT NULL COMMENT '근거 종류로 계산한 확신 등급이며 계산되지 않았으면 NULL',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_public_interpretations_report_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_public_interpretations_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_public_interpretations_category` CHECK ((`category` in (_utf8mb4'RELATIONSHIP',_utf8mb4'EMOTION',_utf8mb4'SELF_EXPRESSION',_utf8mb4'ACTIVITY_STYLE',_utf8mb4'ADAPTATION'))),
  CONSTRAINT `ck_report_public_interpretations_confidence` CHECK (((`confidence` is null) or (`confidence` in (_utf8mb4'STRONG',_utf8mb4'MODERATE',_utf8mb4'WEAK')))),
  CONSTRAINT `ck_report_public_interpretations_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_report_public_interpretations_state` CHECK ((`disclosure_state` in (_utf8mb4'PUBLISHED',_utf8mb4'WITHHELD',_utf8mb4'EXPERT_ONLY'))),
  CONSTRAINT `ck_report_public_interpretations_withheld_reason` CHECK (((`disclosure_state` = _utf8mb4'PUBLISHED') or (`withheld_reason_code` is not null)))
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 경향 해석';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_references`
--

DROP TABLE IF EXISTS `report_references`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_references` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '리포트 참고 자료 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서',
  `source_id` varchar(120) DEFAULT NULL COMMENT '자료 출처 식별자이며 추적용이라 응답에 담지 않는다',
  `title` varchar(300) NOT NULL COMMENT '자료 제목',
  `url` varchar(500) DEFAULT NULL COMMENT '자료 링크이며 자체 저작 자료는 NULL',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_references_report_order` (`report_id`,`display_order`),
  CONSTRAINT `fk_report_references_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_references_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 참고 자료';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_subject_interpretations`
--

DROP TABLE IF EXISTS `report_subject_interpretations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_subject_interpretations` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '주제별 경향 해석 참조 ID',
  `report_subject_id` bigint NOT NULL COMMENT '주제별 관찰 ID',
  `interpretation_id` bigint NOT NULL COMMENT '경향 해석 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '참조 순서',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_subject_interpretations_pair` (`report_subject_id`,`interpretation_id`),
  UNIQUE KEY `uk_report_subject_interpretations_order` (`report_subject_id`,`display_order`),
  KEY `fk_report_subject_interpretations_interpretation_id` (`interpretation_id`),
  CONSTRAINT `fk_report_subject_interpretations_interpretation_id` FOREIGN KEY (`interpretation_id`) REFERENCES `report_public_interpretations` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_report_subject_interpretations_subject_id` FOREIGN KEY (`report_subject_id`) REFERENCES `report_subjects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_subject_interpretations_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=23 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='주제별 경향 해석 참조';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_subject_observations`
--

DROP TABLE IF EXISTS `report_subject_observations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_subject_observations` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '주제별 관찰 서술 ID',
  `report_subject_id` bigint NOT NULL COMMENT '주제별 관찰 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '서술 노출 순서',
  `observation_text` text NOT NULL COMMENT '눈으로 확인된 사실 문장',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_subject_observations_subject_order` (`report_subject_id`,`display_order`),
  CONSTRAINT `fk_report_subject_observations_subject_id` FOREIGN KEY (`report_subject_id`) REFERENCES `report_subjects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_subject_observations_order` CHECK ((`display_order` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=198 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='주제별 관찰 서술';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_subject_qa_pairs`
--

DROP TABLE IF EXISTS `report_subject_qa_pairs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_subject_qa_pairs` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '주제별 문답 ID',
  `report_subject_id` bigint NOT NULL COMMENT '주제별 관찰 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '문답 노출 순서',
  `question_text` text NOT NULL COMMENT 'AI 가 물은 질문 원문',
  `answer_text` text COMMENT '아이 답변 원문이며 건너뛰었으면 NULL',
  `answer_state` varchar(20) NOT NULL COMMENT '답변 상태',
  `input_type` varchar(20) NOT NULL COMMENT '입력 방식',
  `stt_needs_confirmation` tinyint(1) NOT NULL DEFAULT '0' COMMENT '음성 인식 확인이 필요한 답변인지',
  `is_representative` tinyint(1) NOT NULL DEFAULT '0' COMMENT '대표 문답인지',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_subject_qa_pairs_subject_order` (`report_subject_id`,`display_order`),
  CONSTRAINT `fk_report_subject_qa_pairs_subject_id` FOREIGN KEY (`report_subject_id`) REFERENCES `report_subjects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_subject_qa_pairs_input_type` CHECK ((`input_type` in (_utf8mb4'TEXT',_utf8mb4'VOICE'))),
  CONSTRAINT `ck_report_subject_qa_pairs_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_report_subject_qa_pairs_skipped_has_no_answer` CHECK (((`answer_state` <> _utf8mb4'SKIPPED') or (`answer_text` is null))),
  CONSTRAINT `ck_report_subject_qa_pairs_state` CHECK ((`answer_state` in (_utf8mb4'ANSWERED',_utf8mb4'SKIPPED')))
) ENGINE=InnoDB AUTO_INCREMENT=246 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='주제별 문답';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `report_subjects`
--

DROP TABLE IF EXISTS `report_subjects`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `report_subjects` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '주제별 관찰 ID',
  `report_id` bigint NOT NULL COMMENT '리포트 ID',
  `display_order` smallint NOT NULL DEFAULT '0' COMMENT '노출 순서이며 HOUSE→TREE→PERSON 을 보존한다',
  `subject_type` varchar(10) DEFAULT NULL COMMENT 'HTP 주제이며 주제가 나뉘지 않는 활동은 NULL',
  `drawing_session_id` bigint DEFAULT NULL COMMENT '이 주제의 그림 활동 세션이며 완성 그림 URL 을 조회 시점에 발급하는 근거다',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_report_subjects_report_order` (`report_id`,`display_order`),
  KEY `fk_report_subjects_drawing_session_id` (`drawing_session_id`),
  CONSTRAINT `fk_report_subjects_drawing_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_report_subjects_report_id` FOREIGN KEY (`report_id`) REFERENCES `reports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_report_subjects_order` CHECK ((`display_order` >= 0)),
  CONSTRAINT `ck_report_subjects_subject_type` CHECK (((`subject_type` is null) or (`subject_type` in (_utf8mb4'HOUSE',_utf8mb4'TREE',_utf8mb4'PERSON'))))
) ENGINE=InnoDB AUTO_INCREMENT=88 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 주제별 관찰';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `reports`
--

DROP TABLE IF EXISTS `reports`;
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
  `failure_reason` varchar(100) DEFAULT NULL COMMENT '리포트 생성 실패 분류 코드',
  `failed_at` datetime(6) DEFAULT NULL COMMENT '리포트 생성 실패 일시',
  `pdf_storage_key` varchar(1000) DEFAULT NULL COMMENT 'PDF 저장 Key',
  `pdf_url` varchar(1000) DEFAULT NULL COMMENT 'PDF URL',
  `pdf_status` varchar(20) NOT NULL DEFAULT 'NONE' COMMENT 'PDF 생성 상태',
  `hidden_at` datetime(6) DEFAULT NULL COMMENT '숨김 일시',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '리포트 생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '리포트 수정 일시',
  `has_drawn_items` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'AI drawnItems 필드 저장 여부',
  `ai_raw_report` longtext COMMENT 'AI 관찰 생성 응답 원문 (S15P11B209-980)',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_reports_session_version` (`drawing_session_id`,`report_version`),
  KEY `fk_reports_analysis_id` (`analysis_id`),
  KEY `idx_reports_drawing_session_id` (`drawing_session_id`,`created_at`),
  CONSTRAINT `fk_reports_analysis_id` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_reports_drawing_session_id` FOREIGN KEY (`drawing_session_id`) REFERENCES `drawing_sessions` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `ck_reports_pdf_status` CHECK ((`pdf_status` in (_utf8mb4'NONE',_utf8mb4'GENERATING',_utf8mb4'READY',_utf8mb4'FAILED'))),
  CONSTRAINT `ck_reports_status` CHECK ((`report_status` in (_utf8mb4'GENERATING',_utf8mb4'COMPLETED',_utf8mb4'FAILED',_utf8mb4'HIDDEN',_utf8mb4'FAILED_RETRYABLE',_utf8mb4'FAILED_FINAL')))
) ENGINE=InnoDB AUTO_INCREMENT=213 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `storage_deletion_jobs`
--

DROP TABLE IF EXISTS `storage_deletion_jobs`;
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
) ENGINE=InnoDB AUTO_INCREMENT=4946 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Storage 삭제 작업';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `stroke_batches`
--

DROP TABLE IF EXISTS `stroke_batches`;
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
) ENGINE=InnoDB AUTO_INCREMENT=588 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stroke 배치';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `stroke_event_points`
--

DROP TABLE IF EXISTS `stroke_event_points`;
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
) ENGINE=InnoDB AUTO_INCREMENT=59426 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stroke 이벤트 좌표';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `stroke_events`
--

DROP TABLE IF EXISTS `stroke_events`;
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
) ENGINE=InnoDB AUTO_INCREMENT=851 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stroke 이벤트';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_blocks`
--

DROP TABLE IF EXISTS `user_blocks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_blocks` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '사용자 차단 ID',
  `blocker_user_id` bigint NOT NULL COMMENT '차단한 사용자 ID',
  `blocked_user_id` bigint NOT NULL COMMENT '차단된 사용자 ID',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '차단 일시',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_blocks_blocker_blocked` (`blocker_user_id`,`blocked_user_id`),
  KEY `idx_user_blocks_blocked_user_id` (`blocked_user_id`),
  CONSTRAINT `fk_user_blocks_blocked_user_id` FOREIGN KEY (`blocked_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_user_blocks_blocker_user_id` FOREIGN KEY (`blocker_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_user_blocks_not_self` CHECK ((`blocker_user_id` <> `blocked_user_id`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자 차단';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_data_retention_settings`
--

DROP TABLE IF EXISTS `user_data_retention_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_data_retention_settings` (
  `user_id` bigint NOT NULL COMMENT '사용자 ID',
  `retention_days` int NOT NULL DEFAULT '180' COMMENT '데이터 보관 기간(일). 정책 확정 전 잠정값',
  `notice_days_before` int NOT NULL DEFAULT '30' COMMENT '보관 만료 사전 안내 시점(일). 정책 확정 전 잠정값',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_user_data_retention_settings_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_user_data_retention_settings_notice_before_expiry` CHECK ((`notice_days_before` < `retention_days`)),
  CONSTRAINT `ck_user_data_retention_settings_notice_days` CHECK ((`notice_days_before` >= 0)),
  CONSTRAINT `ck_user_data_retention_settings_retention_days` CHECK ((`retention_days` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자 데이터 보관 설정';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_guardian_pins`
--

DROP TABLE IF EXISTS `user_guardian_pins`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_guardian_pins` (
  `user_id` bigint NOT NULL COMMENT '보호자 사용자 ID',
  `pin_hash` varchar(255) NOT NULL COMMENT 'pepper 적용 후 BCrypt 해시. 원문 저장 금지',
  `hash_algorithm` varchar(30) NOT NULL COMMENT '해시 알고리즘 식별자',
  `failed_attempt_count` int NOT NULL DEFAULT '0' COMMENT '연속 검증 실패 횟수',
  `lockout_level` int NOT NULL DEFAULT '0' COMMENT '지수 백오프 단계이며 성공 시 0으로 초기화',
  `locked_until` datetime(6) DEFAULT NULL COMMENT '잠금 해제 시각(UTC)이며 잠금 중이 아니면 NULL',
  `last_verified_at` datetime(6) DEFAULT NULL COMMENT '마지막 검증 성공 시각(UTC)',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_user_guardian_pins_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_user_guardian_pins_counters` CHECK (((`failed_attempt_count` >= 0) and (`lockout_level` >= 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='보호자 PIN';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_notification_settings`
--

DROP TABLE IF EXISTS `user_notification_settings`;
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

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '사용자 ID',
  `role` varchar(20) DEFAULT NULL COMMENT '사용자 역할, Onboarding 전에는 NULL',
  `nickname` varchar(50) DEFAULT NULL COMMENT '닉네임',
  `email` varchar(255) DEFAULT NULL COMMENT '사용자 연락 이메일, Onboarding에서 확정',
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
) ENGINE=InnoDB AUTO_INCREMENT=38 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping routines for database 'b209'
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-08-10  0:12:14

-- ==================== 마스터/코드 데이터 ====================
-- MySQL dump 10.13  Distrib 8.4.10, for Linux (x86_64)
--
-- Host: localhost    Database: b209
-- ------------------------------------------------------
-- Server version	8.4.10

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Dumping data for table `drawing_types`
--

/*!40000 ALTER TABLE `drawing_types` DISABLE KEYS */;
INSERT INTO `drawing_types` (`id`, `code`, `name`, `activity_category`, `selectable_by`, `recommended_age_min`, `recommended_age_max`, `guide_text`, `is_active`, `display_order`, `created_at`, `updated_at`) VALUES (1,'ART_DIARY','그림 일기','GENERAL','BOTH',4,12,'오늘 있었던 일이나 기억에 남는 순간을 그림으로 표현해 보세요.',1,10,'2026-07-24 21:16:35.206450','2026-07-24 21:16:35.206450'),(2,'FREE_DRAWING','자유 그리기','GENERAL','BOTH',4,12,'그리고 싶은 것을 자유롭게 그려 보세요.',0,20,'2026-07-24 21:16:35.206450','2026-07-28 14:33:49.762737'),(3,'EMOTION_COLORING','마음 색칠하기','GENERAL','BOTH',4,12,'지금 마음과 어울리는 색을 골라 자유롭게 표현해 보세요.',0,30,'2026-07-24 21:16:35.206450','2026-07-28 14:33:49.762737'),(4,'WEATHER_MIND','마음 날씨 그리기','GENERAL','BOTH',4,12,'지금 마음을 날씨로 떠올려 그림으로 표현해 보세요.',0,40,'2026-07-24 21:16:35.206450','2026-07-28 14:33:49.762737'),(5,'HTP','집·나무·사람 그림','ASSESSMENT','GUARDIAN',4,12,'집, 나무, 사람을 순서대로 그리며 마음을 표현해 보세요.',1,20,'2026-07-28 14:33:49.757961','2026-07-28 14:33:49.757961');
/*!40000 ALTER TABLE `drawing_types` ENABLE KEYS */;

--
-- Dumping data for table `consent_terms`
--

/*!40000 ALTER TABLE `consent_terms` DISABLE KEYS */;
INSERT INTO `consent_terms` (`id`, `term_code`, `target_scope`, `is_required`, `version`, `title`, `content_url`, `content_html`, `effective_at`, `is_active`, `created_at`) VALUES (1,'SERVICE_TOS','USER',1,'v1','서비스 이용약관',NULL,'\n<p><strong>제1조 (목적)</strong></p>\n<p>이 약관은 도담(이하 서비스)이 제공하는 아동 미술 활동 관찰 서비스의 이용 조건과 절차, 서비스 운영자와 이용자의 권리·의무·책임 사항을 정하는 것을 목적으로 합니다.</p>\n<p><strong>제2조 (용어의 정의)</strong></p>\n<p>1. 보호자: 아동의 법정대리인으로서 서비스에 가입한 회원을 말합니다.<br>2. 아동: 보호자가 서비스에 등록하여 그림 활동을 이용하는 아이를 말합니다.<br>3. 전문가: 상담사·치료사로서 자격 정보를 등록한 회원을 말합니다.<br>4. 활동: 아동이 그림을 그리거나 그린 그림을 올리고, AI 캐릭터와 대화를 나누는 일련의 과정을 말합니다.<br>5. 관찰 리포트: 활동 내용을 바탕으로 생성하여 보호자에게 제공하는 참고 자료를 말합니다.</p>\n<p><strong>제3조 (서비스의 성격)</strong></p>\n<p>서비스가 제공하는 분석 결과와 관찰 리포트는 의학적 진단, 심리 검사 결과, 치료 행위가 아닙니다. 아이의 표현을 보호자가 이해하고 아이와 대화를 나누는 데 참고할 자료입니다.</p>\n<p>1. 서비스는 진단명을 부여하거나 발달 점수를 매기지 않습니다.<br>2. AI가 생성한 결과는 부정확하거나 불완전할 수 있습니다.<br>3. 아이의 상태가 걱정된다면 반드시 전문가와 상담하시기 바랍니다.<br>4. 서비스는 응급 상황에 대응하지 않습니다. 긴급한 도움이 필요하면 즉시 전문 기관에 연락해 주세요.</p>\n<p><strong>제4조 (회원가입과 아동 등록)</strong></p>\n<p>1. 보호자는 카카오·구글·네이버·애플 계정을 이용한 소셜 로그인으로 가입합니다. 서비스는 별도의 비밀번호를 만들거나 보관하지 않습니다.<br>2. 아동 등록은 아동의 법정대리인인 보호자만 할 수 있습니다.<br>3. 보호자는 아동의 개인정보 수집·이용에 대하여 법정대리인의 지위에서 동의합니다.<br>4. 한 아동에 여러 보호자가 연결될 수 있으며, 각 보호자는 자신과 연결된 아동에 대해서만 활동 기록과 리포트를 볼 수 있습니다.<br>5. 타인의 정보를 도용하거나 사실과 다른 정보를 등록할 수 없습니다.</p>\n<p><strong>제5조 (서비스의 내용)</strong></p>\n<p>서비스는 현재 다음 기능을 무료로 제공합니다.</p>\n<p>1. 앱 안 캔버스로 그림 그리기 또는 종이에 그린 그림을 촬영·업로드하기<br>2. AI 캐릭터와의 대화. 아이는 선택형 답변 또는 음성 답변으로 응답할 수 있습니다.<br>3. 집·나무·사람을 순서대로 그리는 활동<br>4. 활동을 마칠 때 그날의 감정 고르기<br>5. 그림과 활동 과정을 정리한 관찰 리포트 제공 및 내려받기<br>6. 활동 기록과 월별 감정 흐름 열람<br>7. 커뮤니티. 보호자 이야기, 전문가 칼럼, 그림 자료 등을 읽고 쓸 수 있습니다.<br>8. 전문가 정보 열람<br>9. 분석 완료, 서비스 공지 등 알림 수신</p>\n<p>보호자가 지정한 전문가에게 아동의 관찰 리포트를 공유하는 기능은 현재 제공되지 않으며 준비 중입니다. 제공을 시작하기 전에 별도로 안내드립니다.</p>\n<p><strong>제6조 (이용자의 의무)</strong></p>\n<p>1. 아동이 활동하는 동안에는 보호자의 관심과 주의가 필요합니다.<br>2. 타인의 권리를 침해하거나 법령을 위반하는 내용을 올릴 수 없습니다.<br>3. 아동에게 유해한 내용을 게시하거나 전송할 수 없습니다.<br>4. 서비스를 부정한 방법으로 이용하거나 자동화된 수단으로 접근할 수 없습니다.<br>5. 계정을 타인에게 양도·대여하거나 공유할 수 없습니다.</p>\n<p><strong>제7조 (아동 데이터의 보호)</strong></p>\n<p>1. 아동의 그림·음성·대화 내용은 커뮤니티 등 공개 영역에 노출되지 않습니다.<br>2. 아동의 그림과 음성 파일은 요청할 때마다 로그인 정보와 보호자·아동 관계를 확인한 뒤에만 제공되며, 누구나 열 수 있는 공개 주소로 제공하지 않습니다.<br>3. 아동 화면에는 분석 결과, 위험 신호, 오류 상세 등 아이가 알 필요가 없는 정보를 표시하지 않습니다. 주의가 필요한 신호는 보호자에게만 안내합니다.<br>4. 보호자는 아동 데이터에 관한 선택 동의를 언제든 철회할 수 있습니다.<br>5. 개인정보의 구체적인 처리 내용은 각 개인정보 관련 동의 항목과 개인정보 처리방침을 따릅니다.</p>\n<p><strong>제8조 (게시물)</strong></p>\n<p>1. 커뮤니티 게시물의 저작권은 작성자에게 있습니다.<br>2. 서비스는 운영에 필요한 범위에서 게시물을 노출·보관할 수 있습니다.<br>3. 타인의 권리를 침해하거나 아동에게 유해한 게시물은 사전 통지 없이 삭제될 수 있습니다.<br>4. 회원 탈퇴 후에도 이미 작성한 게시물은 삭제되지 않을 수 있으며, 이 경우 작성자 정보는 알아볼 수 없게 처리합니다.</p>\n<p><strong>제9조 (서비스의 변경과 중단)</strong></p>\n<p>1. 서비스 내용은 개선을 위해 변경될 수 있으며, 중요한 변경은 사전에 알립니다.<br>2. 설비 점검, 통신 장애, 천재지변 등으로 서비스 제공이 일시 중단될 수 있습니다.<br>3. 서비스는 외부 AI 모델을 이용하므로, 해당 모델의 장애나 정책 변경으로 일부 기능이 제한될 수 있습니다.</p>\n<p><strong>제10조 (책임의 한계)</strong></p>\n<p>1. 서비스는 진단·치료를 제공하지 않으며, 분석 결과를 바탕으로 한 판단과 그에 따른 조치의 책임은 이용자에게 있습니다.<br>2. 천재지변, 통신 장애 등 서비스 운영자의 통제를 벗어난 사유로 발생한 손해에 대해서는 책임을 지지 않습니다.<br>3. 이용자의 귀책사유로 발생한 손해에 대해서는 책임을 지지 않습니다.<br>4. 무료로 제공되는 서비스의 이용과 관련하여 발생한 손해에 대해서는 관련 법령이 정한 범위에서 책임을 집니다.</p>\n<p><strong>제11조 (이용 제한과 계약의 해지)</strong></p>\n<p>1. 이 약관을 위반한 경우 서비스 이용이 제한될 수 있습니다.<br>2. 이용자는 언제든지 앱의 설정 화면에서 회원 탈퇴를 할 수 있습니다.<br>3. 탈퇴하면 계정은 즉시 이용할 수 없게 되고 모든 기기의 로그인이 해제되며, 연결된 소셜 계정 정보는 삭제됩니다.<br>4. 다른 보호자가 연결되어 있지 않은 아동의 정보는 탈퇴와 함께 삭제 대상이 되고, 그리는 과정에서 기록된 획 데이터는 즉시 삭제됩니다. 다른 보호자가 함께 돌보는 아동은 그 보호자와의 연결이 유지되며, 탈퇴한 보호자와의 연결만 해제됩니다.<br>5. 같은 소셜 계정으로 다시 가입하면 새로운 계정이 만들어지며, 이전 계정의 활동 기록은 복구되지 않습니다.<br>6. 법령상 보존 의무가 있는 정보와 동의 증빙은 해당 기간 동안 별도로 보관합니다.</p>\n<p><strong>제12조 (약관의 변경)</strong></p>\n<p>1. 약관이 변경되면 시행일 7일 전까지, 이용자에게 불리한 변경은 시행일 30일 전까지 서비스 내 공지와 알림으로 알립니다.<br>2. 동의의 의미나 처리 범위가 바뀌는 변경은 다시 동의를 받습니다.</p>\n<p><strong>제13조 (문의와 분쟁 해결)</strong></p>\n<p>1. 서비스 이용에 관한 문의는 앱의 문의 기능을 통해 접수할 수 있습니다.<br>2. 분쟁은 상호 협의로 해결하며, 협의가 이루어지지 않으면 관련 법령이 정한 절차를 따릅니다.</p>\n<p><strong>부칙</strong></p>\n<p>사업자 정보, 고객센터 연락처, 이 약관의 시행일은 확정되는 대로 이 약관과 서비스 내 공지에 반영합니다.</p>\n','2020-01-01 00:00:00.000000',1,'2026-07-27 08:04:04.512237'),(2,'CHILD_PERSONAL_INFO','CHILD',0,'v1','아동 개인정보 수집·이용',NULL,'\n<p><strong>법정대리인 동의 안내</strong></p>\n<p>도담은 만 14세 미만 아동의 정보를 다룹니다. 아동의 개인정보는 법정대리인인 보호자의 동의를 받아 수집·이용하며, 보호자는 언제든지 동의를 철회할 수 있습니다. 아래 내용을 확인하신 뒤 동의 여부를 선택해 주세요.</p>\n<p><strong>1. 수집하는 항목</strong></p>\n<p>가. 아동 프로필<br>- 별명(실명을 입력하지 않으셔도 됩니다)<br>- 생년월일<br>- 프로필 이미지(등록한 경우)<br>- 아이가 고른 캐릭터<br>- 질문 난이도 설정<br>- 튜토리얼 진행 상태</p>\n<p>나. 보호자와의 관계<br>- 아동을 등록한 보호자 계정과의 연결 정보</p>\n<p>다. 활동 과정에서 생기는 정보<br>- 활동 시작·종료 시각, 활동 종류, 그림 입력 방식<br>- 활동을 마칠 때 고른 감정<br>- 그림·대화·음성에 관한 정보는 각각 별도의 동의 항목에서 안내합니다.</p>\n<p><strong>2. 이용 목적</strong></p>\n<p>1. 아동 프로필 관리와 보호자·아동 관계 확인<br>2. 나이에 맞는 질문 난이도와 활동 구성 제공<br>3. 아이가 고른 캐릭터로 대화 화면 구성<br>4. 활동 기록과 관찰 리포트를 아동별로 정리하여 보호자에게 제공<br>5. 서비스 오류 대응과 안정적인 운영</p>\n<p><strong>3. 보유 및 이용 기간</strong></p>\n<p>1. 동의를 철회하거나 아동을 삭제하거나 회원에서 탈퇴할 때까지 보유합니다.<br>2. 위 사유가 발생하면 해당 목적의 처리를 중단하고 삭제 대상으로 등록합니다.<br>3. 저장소에 보관된 파일이 실제로 지워지는 시점은 현재 보장해 드릴 수 없습니다. 삭제 집행 절차를 갖추는 대로 안내드립니다.<br>4. 항목별 구체적인 보유 기간은 아직 확정되지 않았습니다. 임의의 기간을 정해 두지 않았으며, 확정되면 별도로 고지하고 이 약관에 반영합니다.<br>5. 동의 사실을 남긴 기록은 분쟁에 대응하기 위해 위 기간과 별도로 보관합니다.</p>\n<p><strong>4. 제3자 제공과 처리위탁</strong></p>\n<p>1. 서비스는 아동의 개인정보를 판매하거나 광고 목적으로 제공하지 않습니다.<br>2. 아동의 별명과 프로필 이미지는 외부로 전송되지 않습니다.<br>3. 다만 생년월일에서 계산한 나이는 아이 수준에 맞는 질문을 만들기 위해 외부 AI 모델 처리 과정에 전달됩니다. 이때 아동의 별명이나 계정 식별 정보는 함께 보내지 않습니다. 외부 전송의 자세한 내용은 그림 데이터 분석 활용, 음성 데이터 처리 동의 항목에서 안내합니다.<br>4. 데이터베이스와 파일 저장소는 서비스가 직접 운영하며 외부 사업자에게 위탁하지 않습니다.</p>\n<p><strong>5. 동의를 거부할 권리와 그에 따른 불이익</strong></p>\n<p>보호자는 이 동의를 거부할 수 있습니다. 다만 아동 프로필 정보가 없으면 아동을 등록할 수 없고, 그림 활동과 관찰 리포트를 포함한 서비스의 주요 기능을 이용하실 수 없습니다.</p>\n<p><strong>6. 동의 철회 방법</strong></p>\n<p>1. 앱의 설정 화면에서 동의 관리로 들어가 아이를 선택하고 항목별로 철회하거나 다시 동의할 수 있습니다.<br>2. 아동을 삭제하거나 회원에서 탈퇴하는 방법으로도 철회할 수 있습니다.<br>3. 철회하시면 해당 목적의 처리를 중단합니다. 이미 수집된 정보의 삭제는 위 3항의 절차를 따릅니다.</p>\n','2020-01-01 00:00:00.000000',1,'2026-07-27 08:04:04.512237'),(3,'DRAWING_ANALYSIS','CHILD',0,'v1','그림 데이터 분석 활용',NULL,'\n<p><strong>법정대리인 동의 안내</strong></p>\n<p>아이가 그린 그림과 그리는 과정을 분석하여 보호자에게 관찰 자료를 제공하기 위한 동의입니다. 법정대리인인 보호자가 동의 여부를 선택합니다.</p>\n<p><strong>1. 수집하는 항목</strong></p>\n<p>가. 그림<br>- 앱 캔버스로 그린 그림 이미지<br>- 종이에 그린 그림을 촬영하여 올린 이미지<br>- 이미지의 크기·형식·용량 등 파일 정보</p>\n<p>나. 그리는 과정<br>- 획의 좌표와 그려진 시각<br>- 사용한 도구와 색상, 선의 굵기<br>- 기기가 지원하는 경우 필압<br>- 되돌리기·다시하기·지우기·전체 지우기 횟수, 멈춘 시간</p>\n<p>다. 활동 정보<br>- 활동 종류와 진행 단계, 시작·종료 시각<br>- 아이가 활동을 마칠 때 고른 감정과 직접 적은 감정 표현<br>- 대화에서 아이가 고른 선택형 답변</p>\n<p>라. 분석 결과<br>- 그림에서 찾은 사물의 종류와 위치<br>- 색 사용, 화면을 채운 정도, 선의 특성 등 시각 지표<br>- 그리는 데 걸린 시간, 획 수, 멈춤 횟수 등 행동 지표<br>- 위 정보를 정리한 관찰 리포트</p>\n<p><strong>2. 이용 목적</strong></p>\n<p>1. 그림에 나타난 사물과 표현 특성을 찾아 정리<br>2. 그리는 과정에서 나타난 행동 특성을 지표로 정리<br>3. 아이의 그림에 맞춘 대화 질문 생성<br>4. 위 내용을 종합한 관찰 리포트를 보호자에게 제공<br>5. 분석 품질 확인과 오류 대응</p>\n<p>분석 결과는 의학적 진단이나 심리 검사 결과가 아니라 보호자가 아이를 이해하는 데 참고할 관찰 자료입니다.</p>\n<p><strong>3. 보유 및 이용 기간</strong></p>\n<p>1. 동의를 철회하거나 아동을 삭제하거나 회원에서 탈퇴할 때까지 보유합니다.<br>2. 그리는 과정에서 기록된 획 데이터는 일정 보관 기간이 지나면 자동으로 삭제되도록 설정되어 있으며, 아동 삭제나 회원 탈퇴 시에는 즉시 삭제됩니다.<br>3. 그림 이미지 파일과 리포트 문서가 저장소에서 실제로 지워지는 시점은 현재 보장해 드릴 수 없습니다. 삭제 집행 절차를 갖추는 대로 안내드립니다.<br>4. 항목별 구체적인 보유 기간은 아직 확정되지 않았으며, 확정되면 별도로 고지합니다.</p>\n<p><strong>4. 제3자 제공과 처리위탁</strong></p>\n<p>1. 그림에서 사물을 찾는 처리는 서비스가 직접 운영하는 서버에서 자체 모델로 수행하며, 이 과정에서 그림이 외부로 나가지 않습니다.<br>2. 그림에 대한 설명 생성과 대화 질문 생성에는 외부 AI 모델을 이용합니다. 이 과정에서 다음 정보가 외부로 전송됩니다.<br>- 전송받는 곳: SSAFY가 운영하는 게이트웨이를 거쳐 연결되는 OpenAI 호환 모델 서비스<br>- 전송 항목: 그림 이미지, 대화 내용 텍스트, 생년월일에서 계산한 나이<br>- 이용 목적: 그림 설명 생성, 아이에게 건넬 질문 생성<br>- 전송하지 않는 항목: 아동의 별명, 보호자 정보, 계정 식별 정보<br>3. 전송된 데이터가 모델 제공자 측에서 어떻게 보관되고 재사용되는지는 아직 확인 중입니다. 확인되는 대로 이 약관과 개인정보 처리방침에 반영합니다.<br>4. 그림 파일이 저장되는 저장소는 서비스가 직접 운영하며 외부 사업자에게 위탁하지 않습니다.<br>5. 아동의 그림과 분석 결과는 커뮤니티 등 공개 영역에 노출되지 않습니다.</p>\n<p><strong>5. 동의를 거부할 권리와 그에 따른 불이익</strong></p>\n<p>보호자는 이 동의를 거부할 수 있습니다. 다만 그림 분석과 관찰 리포트는 이 동의를 근거로 제공되므로, 거부하시면 분석 결과와 리포트를 받아보실 수 없습니다.</p>\n<p><strong>6. 동의 철회 방법</strong></p>\n<p>1. 앱의 설정 화면에서 동의 관리로 들어가 아이를 선택하고 이 항목을 철회할 수 있습니다.<br>2. 아동을 삭제하거나 회원에서 탈퇴하는 방법으로도 철회할 수 있습니다.<br>3. 철회하시면 이후의 분석을 중단합니다. 이미 수집된 그림과 분석 결과의 삭제는 위 3항의 절차를 따릅니다.</p>\n','2020-01-01 00:00:00.000000',1,'2026-07-27 08:04:04.512237'),(4,'VOICE_PROCESSING','CHILD',0,'v1','음성 데이터 처리',NULL,'\n<p><strong>법정대리인 동의 안내</strong></p>\n<p>아이가 마이크로 답한 음성을 글자로 옮겨 대화를 이어가기 위한 동의입니다. 목소리는 그 자체로 개인을 알아볼 수 있는 정보가 될 수 있어 별도 항목으로 동의를 받습니다.</p>\n<p><strong>1. 수집하는 항목</strong></p>\n<p>1. 아이가 답한 음성 녹음 파일<br>2. 음성을 글자로 옮긴 텍스트<br>3. 음성 인식의 신뢰도와 처리 상태<br>4. 보호자 확인이 필요한지 여부<br>5. 캐릭터가 읽어 주는 음성을 만들 때 생기는 음성 파일과 그 설정(목소리 종류, 말하기 속도)</p>\n<p><strong>2. 이용 목적</strong></p>\n<p>1. 아이의 음성 답변을 글자로 변환하여 대화를 이어가기<br>2. 변환된 답변을 활동 기록과 관찰 리포트에 반영<br>3. 인식이 잘 되지 않은 경우 보호자에게 확인 요청<br>4. 캐릭터가 질문을 소리로 읽어 주기<br>5. 음성 인식 오류 대응</p>\n<p><strong>3. 보유 및 이용 기간</strong></p>\n<p>1. 동의를 철회하거나 아동을 삭제하거나 회원에서 탈퇴할 때까지 보유합니다.<br>2. 음성 녹음 원본은 인식 결과를 확인하고 활동 기록을 복원하기 위해 보관합니다.<br>3. 캐릭터 음성처럼 다시 만들어 낼 수 있는 파일은 일정 기간이 지나면 자동으로 정리됩니다.<br>4. 음성 파일이 저장소에서 실제로 지워지는 시점은 현재 보장해 드릴 수 없습니다. 삭제 집행 절차를 갖추는 대로 안내드립니다.<br>5. 구체적인 보유 기간은 아직 확정되지 않았으며, 확정되면 별도로 고지합니다.</p>\n<p><strong>4. 제3자 제공과 처리위탁</strong></p>\n<p>1. 음성을 글자로 옮기는 처리와 캐릭터 음성을 만드는 처리는 외부 AI 모델을 이용합니다. 이 과정에서 다음 정보가 외부로 전송됩니다.<br>- 전송받는 곳: SSAFY가 운영하는 게이트웨이를 거쳐 연결되는 OpenAI 호환 모델 서비스<br>- 전송 항목: 아이의 음성 녹음 파일, 대화 내용 텍스트<br>- 이용 목적: 음성 인식, 음성 합성<br>- 전송하지 않는 항목: 아동의 별명, 보호자 정보, 계정 식별 정보<br>2. 전송된 음성이 모델 제공자 측에서 어떻게 보관되고 재사용되는지는 아직 확인 중입니다. 확인되는 대로 이 약관과 개인정보 처리방침에 반영합니다.<br>3. 음성 파일이 저장되는 저장소는 서비스가 직접 운영하며 외부 사업자에게 위탁하지 않습니다.<br>4. 아동의 음성은 커뮤니티 등 공개 영역에 노출되지 않습니다.<br>5. 음성 녹음 원본은 AI 모델을 학습시키는 목적으로 사용하지 않습니다.</p>\n<p><strong>5. 동의를 거부할 권리와 그에 따른 불이익</strong></p>\n<p>보호자는 이 동의를 거부할 수 있습니다. 거부하시면 아이는 음성으로 답할 수 없고, 대신 화면에 제시되는 선택형 답변으로 대화를 이어갈 수 있습니다. 그림 활동과 관찰 리포트는 그대로 이용하실 수 있습니다.</p>\n<p><strong>6. 동의 철회 방법</strong></p>\n<p>1. 앱의 설정 화면에서 동의 관리로 들어가 아이를 선택하고 이 항목을 철회할 수 있습니다.<br>2. 철회하면 그 즉시 음성 답변 기능이 중지되고, 이후 대화는 선택형 답변으로만 진행됩니다.<br>3. 이미 수집된 음성과 변환 텍스트의 삭제는 위 3항의 절차를 따릅니다.</p>\n','2020-01-01 00:00:00.000000',1,'2026-07-27 08:04:04.512237'),(5,'EXPERT_SHARING','CHILD',0,'v1','전문가 리포트 공유',NULL,'\n<p><strong>법정대리인 동의 안내</strong></p>\n<p>보호자가 지정한 전문가에게 아이의 관찰 리포트를 보여 주기 위한 동의입니다. 법정대리인인 보호자가 동의 여부를 선택합니다.</p>\n<p><strong>1. 현재 제공 상태를 먼저 알려드립니다</strong></p>\n<p>전문가에게 아동의 리포트를 공유하는 기능은 현재 제공되지 않습니다. 지금 이 항목에 동의하시더라도 전문가에게 전달되는 아동의 자료는 없습니다. 이 동의는 향후 기능을 제공할 때를 대비해 미리 받아 두는 것이며, 실제 공유를 시작하기 전에 공유 대상과 범위를 다시 안내하고 확인을 받겠습니다.</p>\n<p><strong>2. 공유하려는 항목</strong></p>\n<p>1. 활동으로 생성된 관찰 리포트<br>2. 리포트의 근거가 된 그림 이미지와 활동 기록<br>3. 대화 내용의 요약<br>4. 아동의 별명, 나이 등 리포트를 이해하는 데 필요한 최소한의 프로필 정보</p>\n<p><strong>3. 공유받는 사람과 목적</strong></p>\n<p>1. 공유 대상: 보호자가 직접 지정한, 자격 정보를 등록한 전문가<br>2. 목적: 아이의 표현에 대한 전문가의 의견을 듣고 상담에 활용하기 위함<br>3. 보호자가 지정하지 않은 전문가에게는 어떤 자료도 제공하지 않습니다.<br>4. 전문가가 아닌 다른 이용자나 커뮤니티에는 공개되지 않습니다.</p>\n<p><strong>4. 보유 및 이용 기간</strong></p>\n<p>1. 동의를 철회하거나 아동을 삭제하거나 회원에서 탈퇴할 때까지 보유합니다.<br>2. 공유 기능이 제공되기 시작하면 공유 이력과 열람 기록의 보관 기준을 함께 안내합니다.<br>3. 구체적인 보유 기간은 아직 확정되지 않았으며, 확정되면 별도로 고지합니다.</p>\n<p><strong>5. 동의를 거부할 권리와 그에 따른 불이익</strong></p>\n<p>보호자는 이 동의를 거부할 수 있으며, 거부하셔도 서비스 이용에 아무런 불이익이 없습니다. 그림 활동, 대화, 관찰 리포트를 그대로 이용하실 수 있습니다.</p>\n<p><strong>6. 동의 철회 방법</strong></p>\n<p>1. 앱의 설정 화면에서 동의 관리로 들어가 아이를 선택하고 이 항목을 철회할 수 있습니다.<br>2. 철회하면 이후 전문가에게 자료를 공유하지 않습니다.</p>\n','2020-01-01 00:00:00.000000',1,'2026-07-27 08:04:04.512237'),(6,'AI_TRAINING','CHILD',0,'v1','AI 학습 데이터 활용',NULL,'\n<p><strong>법정대리인 동의 안내</strong></p>\n<p>아이의 활동 데이터를 서비스의 AI 모델을 개선하는 데 사용하기 위한 동의입니다. 모델 개선은 서비스를 제공하기 위한 처리와는 목적이 다르기 때문에 별도 항목으로 동의를 받습니다.</p>\n<p><strong>1. 현재 제공 상태를 먼저 알려드립니다</strong></p>\n<p>현재 서비스는 아동의 그림·대화·음성을 AI 모델 학습에 사용하고 있지 않습니다. 지금 사용 중인 모델은 외부에 공개된 그림 데이터로 학습된 것이며, 아이들이 서비스에서 만든 데이터는 학습에 쓰이지 않았습니다. 이 동의는 앞으로 모델 개선을 시작할 때의 근거를 미리 확보하기 위한 것이며, 실제로 학습을 시작하기 전에 별도로 안내드립니다.</p>\n<p><strong>2. 학습에 사용하려는 항목</strong></p>\n<p>1. 그림 이미지 중 완성본<br>2. 그리는 과정에서 기록된 획 데이터<br>3. 음성을 글자로 옮긴 텍스트. 이름·학교·지역·가족 호칭 등은 가려낸 뒤에만 사용합니다.<br>4. 대화의 질문과 아이가 고른 선택형 답변<br>5. 활동을 마칠 때 고른 감정</p>\n<p><strong>3. 학습에 사용하지 않는 항목</strong></p>\n<p>1. 아이의 음성 녹음 원본. 목소리는 그 자체로 개인을 알아볼 수 있어 제외합니다.<br>2. 관찰 리포트 본문. AI가 만든 해석을 다시 학습에 넣으면 표현이 굳어질 수 있어 제외합니다.<br>3. 중간 저장된 그림과 미리보기<br>4. 동의 증빙 기록<br>5. 아동의 별명, 생년월일, 계정 식별 정보 등 개인을 알아볼 수 있는 정보</p>\n<p><strong>4. 처리 방법</strong></p>\n<p>1. 학습에는 원본 저장소를 직접 사용하지 않고, 개인을 알아볼 수 없게 처리한 별도의 학습용 자료를 만들어 사용합니다.<br>2. 파일 이름과 경로에서 아동 식별 정보를 제거하고 의미 없는 값으로 바꿉니다.<br>3. 사진에 남는 촬영 기기·위치 등의 정보를 제거합니다.<br>4. 학습용 자료는 학습 목적으로만 사용하며 외부에 공유하지 않습니다.<br>5. 아동의 그림 원본과 발화 원문을 외부 사업자에게 학습 목적으로 제공하지 않습니다.</p>\n<p><strong>5. 보유 및 이용 기간, 그리고 기술적 한계</strong></p>\n<p>1. 동의를 철회하거나 아동을 삭제하거나 회원에서 탈퇴할 때까지 보유합니다.<br>2. 철회하시면 이후 만드는 학습용 자료에서 해당 아동의 데이터를 제외합니다.<br>3. 다만 이미 학습이 끝난 모델에서 특정 아동이 미친 영향을 나중에 되돌려 제거하는 것은 기술적으로 불가능합니다. 이 점을 미리 알려드리며, 그래서 학습은 사전 동의가 있는 데이터로만 진행합니다.<br>4. 학습용 자료의 보관 기간은 아직 확정되지 않았으며, 확정되면 별도로 고지합니다.</p>\n<p><strong>6. 동의를 거부할 권리와 그에 따른 불이익</strong></p>\n<p>보호자는 이 동의를 거부할 수 있으며, 거부하셔도 서비스 이용에 아무런 불이익이 없습니다. 그림 활동, 대화, 관찰 리포트를 그대로 이용하실 수 있습니다.</p>\n<p><strong>7. 동의 철회 방법</strong></p>\n<p>1. 앱의 설정 화면에서 동의 관리로 들어가 아이를 선택하고 이 항목을 철회할 수 있습니다.<br>2. 아동을 삭제하거나 회원에서 탈퇴하는 방법으로도 철회할 수 있습니다.</p>\n','2020-01-01 00:00:00.000000',1,'2026-07-27 08:04:04.512237'),(7,'MARKETING','USER',0,'v1','마케팅 및 알림 수신',NULL,'\n<p><strong>안내</strong></p>\n<p>서비스 소식과 이벤트 정보를 받아보기 위한 동의입니다. 보호자 본인에 대한 동의이며 선택 사항입니다.</p>\n<p><strong>1. 수집하는 항목</strong></p>\n<p>1. 푸시 알림을 보내기 위한 기기 토큰. 저장할 때 암호화합니다.<br>2. 기기 구분 값과 앱 버전<br>3. 알림 종류별 수신 설정</p>\n<p><strong>2. 이용 목적</strong></p>\n<p>1. 새로운 기능과 서비스 소식 안내<br>2. 이벤트와 혜택 정보 안내<br>3. 기기와 앱 버전에 맞는 알림 발송</p>\n<p><strong>3. 이 동의와 관계없이 발송되는 알림</strong></p>\n<p>분석 완료 안내, 약관 변경 안내, 데이터 보관 안내처럼 서비스 이용에 꼭 필요한 알림은 이 동의와 관계없이 발송됩니다. 이러한 알림은 앱의 알림 설정에서 종류별로 끄실 수 있습니다.</p>\n<p><strong>4. 현재 제공 상태</strong></p>\n<p>마케팅 정보 발송 기능은 아직 제공되지 않습니다. 발송을 시작하기 전에 별도로 안내드립니다.</p>\n<p><strong>5. 보유 및 이용 기간</strong></p>\n<p>동의를 철회하거나 회원에서 탈퇴할 때까지 보유합니다. 기기에서 앱을 삭제하거나 알림 권한을 해제하면 해당 기기의 토큰은 더 이상 사용되지 않습니다.</p>\n<p><strong>6. 제3자 제공과 처리위탁</strong></p>\n<p>1. 푸시 알림 전달에는 구글의 파이어베이스 클라우드 메시징을 이용합니다.<br>- 전송 항목: 기기 토큰, 알림 식별자와 알림 종류, 정해진 안내 문구<br>- 이용 목적: 기기로 알림 전달<br>- 전송하지 않는 항목: 아동의 별명, 활동 내용, 리포트 내용. 알림 문구는 미리 정해진 고정 문장이며 아이의 정보를 담지 않습니다.<br>2. 그 밖에 마케팅 목적으로 개인정보를 외부에 제공하거나 판매하지 않습니다.</p>\n<p><strong>7. 동의를 거부할 권리와 그에 따른 불이익</strong></p>\n<p>이 동의를 거부하셔도 서비스 이용에 아무런 불이익이 없습니다. 서비스의 모든 기능을 그대로 이용하실 수 있습니다.</p>\n<p><strong>8. 동의 철회 방법</strong></p>\n<p>1. 앱의 설정 화면에서 동의 관리로 들어가 이 항목을 철회할 수 있습니다.<br>2. 앱의 알림 설정에서 종류별로 수신 여부를 바꿀 수 있습니다.<br>3. 기기의 알림 권한을 해제하거나 회원에서 탈퇴하는 방법으로도 철회할 수 있습니다.</p>\n','2020-01-01 00:00:00.000000',1,'2026-07-27 08:04:04.512237'),(8,'CHILD_CLINICAL_RECORD','CHILD',0,'1.0','아이의 검사·평가 기록 보관 동의',NULL,NULL,'2026-08-08 00:00:00.000000',1,'2026-08-08 00:00:00.000000');
/*!40000 ALTER TABLE `consent_terms` ENABLE KEYS */;

--
-- Dumping data for table `ai_question_templates`
--

/*!40000 ALTER TABLE `ai_question_templates` DISABLE KEYS */;
INSERT INTO `ai_question_templates` (`id`, `drawing_type_id`, `created_by_user_id`, `updated_by_user_id`, `template_type`, `age_group`, `difficulty`, `question_purpose`, `question_text`, `is_active`, `created_at`, `updated_at`) VALUES (1,NULL,NULL,NULL,'FALLBACK','CUSTOM','CUSTOM','DRAWING_CONTEXT','그림을 그리는 동안 기분이 어땠어?',1,'2026-07-27 08:02:04.541878','2026-07-27 08:02:04.541878');
/*!40000 ALTER TABLE `ai_question_templates` ENABLE KEYS */;

--
-- Dumping data for table `ai_question_template_options`
--

/*!40000 ALTER TABLE `ai_question_template_options` DISABLE KEYS */;
INSERT INTO `ai_question_template_options` (`id`, `question_template_id`, `option_key`, `option_type`, `option_value`, `label`, `emoji`, `display_order`) VALUES (1,1,'HAPPY','EMOTION','HAPPY','기분이 좋았어요','😊',1),(2,1,'FUN','EMOTION','FUN','재미있었어요','😄',2),(3,1,'NOT_SURE','EMOTION','NOT_SURE','잘 모르겠어요','🤔',3);
/*!40000 ALTER TABLE `ai_question_template_options` ENABLE KEYS */;

--
-- Dumping data for table `ai_question_template_risk_responses`
--

/*!40000 ALTER TABLE `ai_question_template_risk_responses` DISABLE KEYS */;
/*!40000 ALTER TABLE `ai_question_template_risk_responses` ENABLE KEYS */;

--
-- Dumping data for table `activity_templates`
--

/*!40000 ALTER TABLE `activity_templates` DISABLE KEYS */;
/*!40000 ALTER TABLE `activity_templates` ENABLE KEYS */;

--
-- Dumping data for table `activity_template_attachments`
--

/*!40000 ALTER TABLE `activity_template_attachments` DISABLE KEYS */;
/*!40000 ALTER TABLE `activity_template_attachments` ENABLE KEYS */;

--
-- Dumping data for table `community_post_template_fields`
--

/*!40000 ALTER TABLE `community_post_template_fields` DISABLE KEYS */;
/*!40000 ALTER TABLE `community_post_template_fields` ENABLE KEYS */;

--
-- Dumping data for table `child_screening_referral_options`
--

/*!40000 ALTER TABLE `child_screening_referral_options` DISABLE KEYS */;
/*!40000 ALTER TABLE `child_screening_referral_options` ENABLE KEYS */;

--
-- Dumping data for table `flyway_schema_history`
--

/*!40000 ALTER TABLE `flyway_schema_history` DISABLE KEYS */;
INSERT INTO `flyway_schema_history` (`installed_rank`, `version`, `description`, `type`, `script`, `checksum`, `installed_by`, `installed_on`, `execution_time`, `success`) VALUES (1,'1','create initial schema','SQL','V1__create_initial_schema.sql',1273399057,'dodam','2026-07-22 04:39:27',1857,1),(2,'2','add drawing session creation constraints','SQL','V2__add_drawing_session_creation_constraints.sql',-1155700248,'dodam','2026-07-22 04:39:27',169,1),(3,'3','normalize json columns','SQL','V3__normalize_json_columns.sql',735162658,'dodam','2026-07-22 04:51:41',3755,1),(4,'4','add drawing asset upload constraints','SQL','V4__add_drawing_asset_upload_constraints.sql',-1972849310,'dodam','2026-07-22 05:58:43',325,1),(5,'5','support drawing analysis requests','SQL','V5__support_drawing_analysis_requests.sql',1280619862,'dodam','2026-07-22 08:47:54',561,1),(6,'6','support social only authentication','SQL','V6__support_social_only_authentication.sql',-741507667,'dodam','2026-07-22 14:08:05',534,1),(7,'7','support activity completion analysis','SQL','V7__support_activity_completion_analysis.sql',-1850863293,'dodam','2026-07-23 04:55:42',157,1),(8,'8','add user onboarding email','SQL','V8__add_user_onboarding_email.sql',297935411,'dodam','2026-07-23 13:12:57',1663,1),(9,'9','add consent term content html','SQL','V9__add_consent_term_content_html.sql',1183501443,'dodam','2026-07-23 13:12:57',222,1),(10,'10','align ai analysis results','SQL','V10__align_ai_analysis_results.sql',277315043,'dodam','2026-07-24 06:13:56',1456,1),(11,'11','add report failure reason','SQL','V11__add_report_failure_reason.sql',1504339333,'dodam','2026-07-24 09:09:12',240,1),(12,'12','seed drawing types','SQL','V12__seed_drawing_types.sql',-1928545964,'dodam','2026-07-24 12:16:35',14,1),(13,'13','support conversation completion','SQL','V13__support_conversation_completion.sql',-1091953636,'dodam','2026-07-25 14:51:11',138,1),(14,'14','add device id to notification device tokens','SQL','V14__add_device_id_to_notification_device_tokens.sql',-1104186343,'dodam','2026-07-26 14:59:18',126,1),(15,'15','seed fallback question template','SQL','V15__seed_fallback_question_template.sql',-39212322,'dodam','2026-07-26 23:02:04',30,1),(16,'16','support apple auth provider','SQL','V16__support_apple_auth_provider.sql',644962492,'dodam','2026-07-27 04:22:44',138,1),(17,'17','seed consent terms','SQL','V17__seed_consent_terms.sql',1653435921,'dodam','2026-07-27 08:04:04',31,1),(18,'18','support htp assessments','SQL','V18__support_htp_assessments.sql',1270530006,'dodam','2026-07-28 05:33:49',172,1),(19,'19','support htp aggregate reports','SQL','V19__support_htp_aggregate_reports.sql',-1917784929,'dodam','2026-07-28 15:57:07',265,1),(20,'20','support abandoned drawing sessions','SQL','V20__support_abandoned_drawing_sessions.sql',1215943480,'dodam','2026-07-29 04:58:13',349,1),(21,'21','support htp image upload','SQL','V21__support_htp_image_upload.sql',1337951960,'dodam','2026-07-29 06:03:45',308,1),(22,'22','allow expert withdrawal','SQL','V22__allow_expert_withdrawal.sql',-1018058145,'dodam','2026-07-29 17:25:07',182,1),(23,'23','support child tutorial progress','SQL','V23__support_child_tutorial_progress.sql',1453719517,'dodam','2026-07-30 01:22:36',51,1),(24,'24','support user data retention settings','SQL','V24__support_user_data_retention_settings.sql',-676876130,'dodam','2026-07-30 04:08:04',42,1),(25,'25','support expert profile target age','SQL','V25__support_expert_profile_target_age.sql',2140997672,'dodam','2026-07-30 04:21:30',97,1),(26,'26','unify timestamps to kst','SQL','V26__unify_timestamps_to_kst.sql',173943063,'dodam','2026-07-30 05:56:19',74,1),(27,'27','support child profile image files','SQL','V27__support_child_profile_image_files.sql',-1349554039,'dodam','2026-07-31 04:03:35',80,1),(28,'28','constrain child preferred character','SQL','V28__constrain_child_preferred_character.sql',1318152725,'dodam','2026-07-31 04:03:35',93,1),(29,'29','seed consent term contents','SQL','V29__seed_consent_term_contents.sql',-1373903290,'dodam','2026-08-02 14:13:41',27,1),(30,'30','support expert credential types','SQL','V30__support_expert_credential_types.sql',-1421366146,'dodam','2026-08-03 02:01:04',125,1),(31,'31','support expert verification reviews','SQL','V31__support_expert_verification_reviews.sql',830493884,'dodam','2026-08-03 03:13:12',207,1),(32,'32','widen ai model version columns','SQL','V32__widen_ai_model_version_columns.sql',758420552,'dodam','2026-08-03 04:45:36',250,1),(33,'33','support community safety','SQL','V33__support_community_safety.sql',2089734007,'dodam','2026-08-03 05:23:10',104,1),(34,'34','support community attachment files','SQL','V34__support_community_attachment_files.sql',-1825235659,'dodam','2026-08-03 07:23:23',75,1),(35,'35','create user guardian pins','SQL','V35__create_user_guardian_pins.sql',189802941,'dodam','2026-08-04 06:43:50',81,1),(36,'36','extend child preferred character','SQL','V36__extend_child_preferred_character.sql',761091809,'dodam','2026-08-04 07:47:59',112,1),(37,'37','create report public interpretations','SQL','V37__create_report_public_interpretations.sql',-1772375930,'dodam','2026-08-05 01:34:25',263,1),(38,'38','create report drawn items','SQL','V38__create_report_drawn_items.sql',1561364770,'dodam','2026-08-05 04:42:29',150,1),(39,'39','create report crisis alerts','SQL','V39__create_report_crisis_alerts.sql',-1088786010,'dodam','2026-08-05 06:32:57',151,1),(40,'40','create report subjects','SQL','V40__create_report_subjects.sql',1798165005,'dodam','2026-08-05 17:25:41',256,1),(41,'41','add question tts voice','SQL','V41__add_question_tts_voice.sql',-733973186,'dodam','2026-08-06 00:17:30',56,1),(42,'42','add question tts tone profile','SQL','V42__add_question_tts_tone_profile.sql',-1816601743,'dodam','2026-08-06 02:46:11',323,1),(43,'43','add report ai raw report','SQL','V43__add_report_ai_raw_report.sql',1019521082,'dodam','2026-08-06 06:45:56',134,1),(44,'44','add report interpretation confidence','SQL','V44__add_report_interpretation_confidence.sql',361200416,'dodam','2026-08-06 09:22:15',132,1),(45,'45','add report diary insights','SQL','V45__add_report_diary_insights.sql',694299927,'dodam','2026-08-08 08:38:04',304,1),(46,'46','add diary session insights','SQL','V46__add_diary_session_insights.sql',827879637,'dodam','2026-08-08 08:38:04',142,1),(47,'47','add diary developmental observations','SQL','V47__add_diary_developmental_observations.sql',284286058,'dodam','2026-08-08 08:38:04',96,1),(48,'48','add child screening records','SQL','V48__add_child_screening_records.sql',-1908548393,'dodam','2026-08-08 08:38:04',129,1),(49,'49','add conversation answer supersede','SQL','V49__add_conversation_answer_supersede.sql',1460089450,'dodam','2026-08-08 13:27:48',549,1),(50,'50','split report failure status','SQL','V50__split_report_failure_status.sql',657298138,'dodam','2026-08-08 13:27:49',536,1),(51,'51','add developmental context v2','SQL','V51__add_developmental_context_v2.sql',1325811203,'dodam','2026-08-08 18:52:02',357,1),(52,'52','add caregiver question connection','SQL','V52__add_caregiver_question_connection.sql',361756279,'dodam','2026-08-09 06:10:26',229,1),(53,'53','add diary report v3','SQL','V53__add_diary_report_v3.sql',-536121027,'dodam','2026-08-09 15:15:31',334,1);
/*!40000 ALTER TABLE `flyway_schema_history` ENABLE KEYS */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-08-10  0:12:14
