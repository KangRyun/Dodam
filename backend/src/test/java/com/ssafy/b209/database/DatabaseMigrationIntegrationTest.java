package com.ssafy.b209.database;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.community.domain.PostFeed;
import com.ssafy.b209.community.domain.PostListSort;
import com.ssafy.b209.community.domain.PostListSort.SortDirection;
import com.ssafy.b209.community.domain.PostListSort.SortField;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.repository.CommunityPostListRepository;
import com.ssafy.b209.community.repository.PostListSearchCriteria;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Testcontainers MySQL 8.4.10에서 Flyway 초기 Migration과 핵심 데이터베이스 구조를 검증한다.
 *
 * <p>H2 기반 Context 테스트에서 확인할 수 없는 MySQL 전용 타입, FK, Unique와 Index의 실제 생성 여부를 검사한다. 테스트를 실행하려면 Docker
 * 환경이 필요하다.
 */
@Testcontainers
@SpringBootTest
@ActiveProfiles("integration-test")
class DatabaseMigrationIntegrationTest {

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam")
          .withUsername("test")
          .withPassword("test");

  @Autowired JdbcTemplate jdbcTemplate;

  @Autowired Flyway flyway;

  @Autowired CommunityPostListRepository communityPostListRepository;

  @Test
  void appliesAllMigrationsWithoutJsonOrRefreshTokenTable() {
    assertThat(MYSQL_CONTAINER.isRunning()).isTrue();
    assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("15");
    assertThat(tableExists("flyway_schema_history")).isTrue();
    assertThat(tableCount()).isEqualTo(67);
    assertThat(tableExists("refresh_tokens")).isFalse();
    assertThat(jsonColumnCount()).isZero();
    assertThat(
            jdbcTemplate.queryForList(
                "SELECT code FROM drawing_types "
                    + "WHERE code IN ('ART_DIARY', 'FREE_DRAWING', "
                    + "'EMOTION_COLORING', 'WEATHER_MIND') "
                    + "ORDER BY display_order",
                String.class))
        .containsExactly("ART_DIARY", "FREE_DRAWING", "EMOTION_COLORING", "WEATHER_MIND");
  }

  @Test
  void createsNormalizedChildTablesAndRelationships() {
    assertThat(tableExists("stroke_events")).isTrue();
    assertThat(tableExists("stroke_event_points")).isTrue();
    assertThat(tableExists("conversation_message_options")).isTrue();
    assertThat(tableExists("conversation_message_selected_options")).isTrue();
    assertThat(tableExists("report_evidence_references")).isTrue();
    assertThat(tableExists("audit_log_changes")).isTrue();
    assertThat(foreignKeyExists("stroke_events", "fk_stroke_events_batch_id")).isTrue();
    assertThat(foreignKeyExists("stroke_event_points", "fk_stroke_event_points_event_id")).isTrue();
    assertThat(
            foreignKeyExists(
                "conversation_message_selected_options",
                "fk_conversation_message_selected_options_question_option"))
        .isTrue();
    assertThat(
            foreignKeyExists("report_evidence_authors", "fk_report_evidence_authors_evidence_id"))
        .isTrue();
  }

  @Test
  void createsNormalizedUniqueConstraintsAndCorrectedColumns() {
    assertThat(indexExists("child_response_modes", "uk_child_response_modes_child_mode", true))
        .isTrue();
    assertThat(
            indexExists(
                "drawing_session_emotions", "uk_drawing_session_emotions_session_emotion", true))
        .isTrue();
    assertThat(indexExists("expert_follows", "uk_expert_follows_guardian_expert", true)).isTrue();
    assertThat(columnExists("conversation_sessions", "drawing_session_id")).isTrue();
    assertThat(columnExists("conversation_sessions", "conversation_id")).isFalse();
    assertThat(columnExists("conversation_sessions", "completion_reason")).isTrue();
    assertThat(
            checkConstraintContains(
                "conversation_sessions",
                "ck_conversation_sessions_completion_reason",
                "GUARDIAN_REQUEST"))
        .isTrue();
    assertThat(columnExists("analysis_behavior_features", "tool_change_count")).isTrue();
    assertThat(columnExists("analysis_behavior_features", "tool_chnage_count")).isFalse();
    assertThat(columnExists("users", "deleted_at")).isTrue();
    assertThat(checkConstraintContains("users", "ck_users_account_status", "DELETED")).isTrue();
    assertThat(columnExists("conversation_message_selected_options", "question_message_id"))
        .isTrue();
    assertThat(
            foreignKeyExists(
                "conversation_message_selected_options",
                "fk_conversation_message_selected_options_answer_question"))
        .isTrue();
    assertThat(
            foreignKeyExists(
                "conversation_message_selected_options",
                "fk_conversation_message_selected_options_question_option"))
        .isTrue();
  }

  @Test
  void supportsSocialOnlyAccountsAndImmediateUserDeletion() {
    assertThat(columnIsNullable("users", "role")).isTrue();
    assertThat(columnExists("auth_accounts", "provider_email")).isTrue();
    assertThat(columnIsNullable("auth_accounts", "provider_email")).isTrue();
    assertThat(columnExists("auth_accounts", "login_email")).isFalse();
    assertThat(columnExists("auth_accounts", "local_login_email")).isFalse();
    assertThat(columnExists("auth_accounts", "password_hash")).isFalse();
    assertThat(columnExists("auth_accounts", "provider_email_verified_at")).isTrue();
    assertThat(columnExists("auth_accounts", "email_verified_at")).isFalse();
    assertThat(tableExists("email_verifications")).isFalse();
    assertThat(checkConstraintContains("auth_accounts", "ck_auth_accounts_provider", "KAKAO"))
        .isTrue();
    assertThat(checkConstraintContains("auth_accounts", "ck_auth_accounts_provider", "LOCAL"))
        .isFalse();
    assertThat(foreignKeyDeleteRuleIs("expert_profiles", "fk_expert_profiles_user_id", "CASCADE"))
        .isTrue();

    jdbcTemplate.update("INSERT INTO users (id, role) VALUES (9201, NULL)");
    jdbcTemplate.update(
        "INSERT INTO auth_accounts (user_id, provider, provider_subject, provider_email) "
            + "VALUES (9201, 'KAKAO', '123456789', NULL)");
    jdbcTemplate.update("INSERT INTO users (id, role) VALUES (9202, NULL), (9203, NULL)");
    jdbcTemplate.update(
        "INSERT INTO auth_accounts (user_id, provider, provider_subject, provider_email) "
            + "VALUES (9202, 'GOOGLE', 'shared-provider-subject', 'google@example.com'), "
            + "(9203, 'NAVER', 'shared-provider-subject', NULL)");
    jdbcTemplate.update(
        "INSERT INTO expert_profiles (id, display_name, user_id) VALUES (9201, '탈퇴 테스트', 9201)");

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM auth_accounts "
                    + "WHERE provider IN ('KAKAO', 'GOOGLE', 'NAVER')",
                Integer.class))
        .isEqualTo(3);

    assertThatThrownBy(
            () ->
                jdbcTemplate.update(
                    "INSERT INTO auth_accounts (user_id, provider, provider_subject) "
                        + "VALUES (9201, 'LOCAL', 'legacy@example.com')"))
        .isInstanceOf(org.springframework.dao.DataAccessException.class);

    jdbcTemplate.update("DELETE FROM users WHERE id = 9201");

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM expert_profiles WHERE id = 9201", Integer.class))
        .isZero();
  }

  @Test
  void filtersCommunityPostsByFollowingExpertKeywordRoleAndLikeCount() {
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) VALUES "
            + "(9401, 'GUARDIAN', '조회자', 'ACTIVE'), "
            + "(9402, 'EXPERT', '전문가', 'ACTIVE'), "
            + "(9403, 'GUARDIAN', '다른 보호자', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO expert_profiles "
            + "(id, display_name, career_years, verification_status, user_id) "
            + "VALUES (9410, '전문가', 3, 'VERIFIED', 9402)");
    jdbcTemplate.update(
        "INSERT INTO expert_follows (id, guardian_user_id, expert_profile_id) "
            + "VALUES (9420, 9401, 9410)");
    jdbcTemplate.update(
        "INSERT INTO community_posts "
            + "(id, author_user_id, post_type, title, content, post_status) VALUES "
            + "(9431, 9402, 'EXPERT_COLUMN', '그림 상담 안내', '마음 읽기', 'ACTIVE'), "
            + "(9433, 9402, 'EXPERT_COLUMN', '그림 상담 기초', '첫 단계', 'ACTIVE'), "
            + "(9432, 9403, 'GUARDIAN_STORY', '그림 상담 후기', '보호자 경험', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO post_likes (post_id, user_id) VALUES (9431, 9401), (9431, 9403)");

    var page =
        communityPostListRepository.findPosts(
            new PostListSearchCriteria(
                PostType.EXPERT_COLUMN,
                "%그림 상담%",
                PostFeed.FOLLOWING,
                UserRole.EXPERT,
                0,
                20,
                new PostListSort(SortField.LIKE_COUNT, SortDirection.DESC),
                9401L));

    assertThat(page.totalElements()).isEqualTo(2);
    assertThat(page.content()).extracting(row -> row.postId()).containsExactly(9431L, 9433L);
    assertThat(page.content().getFirst().likeCount()).isEqualTo(2);
    assertThat(page.content().getFirst().likedByMe()).isTrue();

    var allPosts =
        communityPostListRepository.findPosts(
            new PostListSearchCriteria(
                null,
                null,
                PostFeed.ALL,
                null,
                0,
                20,
                new PostListSort(SortField.CREATED_AT, SortDirection.DESC),
                9401L));
    assertThat(allPosts.totalElements()).isGreaterThanOrEqualTo(3);
  }

  @Test
  void createsRepresentativePrimaryAndForeignKeys() {
    assertThat(primaryKeyExists("users")).isTrue();
    assertThat(primaryKeyExists("drawing_sessions")).isTrue();
    assertThat(primaryKeyExists("analyses")).isTrue();
    assertThat(foreignKeyExists("drawing_sessions", "fk_drawing_sessions_child_id")).isTrue();
    assertThat(foreignKeyExists("analyses", "fk_analyses_drawing_session_id")).isTrue();
    assertThat(foreignKeyExists("conversation_messages", "fk_conversation_messages_session_id"))
        .isTrue();
    assertThat(foreignKeyExists("comments", "fk_comments_post_id")).isTrue();
  }

  @Test
  void createsRepresentativeUniqueConstraintsAndIndexes() {
    assertThat(indexExists("auth_accounts", "uk_auth_accounts_provider_subject", true)).isTrue();
    assertThat(indexExists("stroke_batches", "uk_stroke_batches_session_sequence", true)).isTrue();
    assertThat(indexExists("analyses", "uk_analyses_idempotency_key", true)).isTrue();
    assertThat(
            indexExists("conversation_messages", "uk_conversation_messages_session_sequence", true))
        .isTrue();
    assertThat(indexExists("post_likes", "uk_post_likes_post_user", true)).isTrue();
    assertThat(indexExists("drawing_sessions", "idx_drawing_sessions_child_id", false)).isTrue();
    assertThat(indexExists("analyses", "idx_analyses_drawing_session_id", false)).isTrue();
    assertThat(indexExists("notifications", "idx_notifications_recipient_created_at", false))
        .isTrue();
    assertThat(columnExists("drawing_sessions", "idempotency_key")).isTrue();
    assertThat(indexExists("drawing_sessions", "uk_drawing_sessions_idempotency_key", true))
        .isTrue();
    assertThat(indexExists("drawing_sessions", "idx_drawing_sessions_active_child", false))
        .isTrue();
  }

  @Test
  void createsDrawingAssetUploadColumnsAndUniqueConstraints() {
    assertThat(columnExists("drawing_assets", "captured_at")).isTrue();
    assertThat(columnIsNullable("drawing_assets", "captured_at")).isFalse();
    assertThat(indexExists("drawing_assets", "uk_drawing_assets_session_type_version", true))
        .isTrue();
    assertThat(columnExists("drawing_assets", "final_drawing_session_id")).isTrue();
    assertThat(generatedColumnContains("drawing_assets", "final_drawing_session_id", "FINAL"))
        .isTrue();
    assertThat(indexExists("drawing_assets", "uk_drawing_assets_final_session", true)).isTrue();
  }

  @Test
  void createsDrawingAnalysisRequestColumnsAndConstraints() {
    assertThat(columnExists("analyses", "drawing_asset_id")).isTrue();
    assertThat(columnExists("analyses", "analysis_task_type")).isTrue();
    assertThat(columnExists("analyses", "active_drawing_asset_id")).isTrue();
    assertThat(foreignKeyExists("analyses", "fk_analyses_drawing_asset_id")).isTrue();
    assertThat(checkConstraintContains("analyses", "ck_analyses_task_type", "OBJECT_DETECTION"))
        .isTrue();
    assertThat(checkConstraintContains("analyses", "ck_analyses_task_type", "ACTIVITY_REPORT"))
        .isTrue();
    assertThat(indexExists("analyses", "idx_analyses_asset_task_status", false)).isTrue();
    assertThat(indexExists("analyses", "uk_analyses_active_asset_task", true)).isTrue();
    assertThat(decimalColumnHasPrecision("analysis_detected_objects", "bbox_x", 12, 6)).isTrue();
    assertThat(decimalColumnHasPrecision("analysis_detected_objects", "bbox_height", 12, 6))
        .isTrue();
    assertThat(columnExists("analysis_detected_objects", "coordinate_space")).isTrue();
    assertThat(columnExists("analysis_visual_features", "image_width_px")).isTrue();
    assertThat(columnExists("analysis_visual_features", "image_height_px")).isTrue();
    assertThat(columnExists("analysis_behavior_features", "pressure_available")).isTrue();
    assertThat(columnExists("analysis_behavior_features", "maximum_pressure")).isTrue();
    assertThat(
            checkConstraintContains(
                "analysis_detected_objects",
                "ck_analysis_detected_objects_bbox_coordinate",
                "coordinate_space"))
        .isTrue();
    assertThat(generatedColumnContains("analyses", "active_drawing_asset_id", "PARTIAL_SUCCESS"))
        .isTrue();
  }

  @Test
  void preventsActiveDuplicateAnalysisAndAllowsRetryAfterFailure() {
    jdbcTemplate.update(
        "INSERT INTO children (id, nickname, birth_date) VALUES (9101, '분석 테스트 아동', '2020-01-01')");
    jdbcTemplate.update(
        "INSERT INTO drawing_types (id, code, name, activity_category, selectable_by) "
            + "VALUES (9101, 'ANALYSIS_TEST', '분석 테스트', 'GENERAL', 'BOTH')");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage) "
            + "VALUES (9101, 9101, 9101, 'CANVAS', 'IN_PROGRESS', 'DRAWING')");
    jdbcTemplate.update(
        "INSERT INTO drawing_assets "
            + "(id, drawing_session_id, asset_type, asset_version, storage_key, mime_type, "
            + "file_size_bytes, checksum_sha256, captured_at) "
            + "VALUES (9101, 9101, 'FINAL', 1, 'analysis/final.png', 'image/png', "
            + "8, REPEAT('b', 64), NOW(6))");

    insertAnalysis(9101, "request-processing", "PROCESSING");
    assertThatThrownBy(() -> insertAnalysis(9101, "request-duplicate", "SUCCESS"))
        .isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);

    jdbcTemplate.update(
        "UPDATE analyses SET analysis_status = 'FAILED' WHERE idempotency_key = ?",
        "request-processing");
    insertAnalysis(9101, "request-retry", "SUCCESS");
  }

  @Test
  void enforcesDrawingAssetVersionAndFinalAssetUniqueness() {
    jdbcTemplate.update(
        "INSERT INTO children (id, nickname, birth_date) VALUES (9001, '테스트 아동', '2020-01-01')");
    jdbcTemplate.update(
        "INSERT INTO drawing_types (id, code, name, activity_category, selectable_by) "
            + "VALUES (9001, 'SNAPSHOT_TEST', '스냅샷 테스트', 'GENERAL', 'BOTH')");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage) "
            + "VALUES (9001, 9001, 9001, 'CANVAS', 'IN_PROGRESS', 'DRAWING'), "
            + "(9002, 9001, 9001, 'CANVAS', 'IN_PROGRESS', 'DRAWING')");

    insertDrawingAsset(9001, "INTERMEDIATE", 1, "first");

    assertThatThrownBy(() -> insertDrawingAsset(9001, "INTERMEDIATE", 1, "duplicate"))
        .isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);

    insertDrawingAsset(9001, "FINAL", 1, "final-first");
    assertThatThrownBy(() -> insertDrawingAsset(9001, "FINAL", 2, "final-second"))
        .isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);

    insertDrawingAsset(9002, "INTERMEDIATE", 1, "other-session");
  }

  @Test
  void createsReportFailureColumns() {
    assertThat(columnExists("reports", "failure_reason")).isTrue();
    assertThat(columnIsNullable("reports", "failure_reason")).isTrue();
    assertThat(columnExists("reports", "failed_at")).isTrue();
    assertThat(columnIsNullable("reports", "failed_at")).isTrue();
  }

  @Test
  void createsDeviceIdentifierColumnsAndUpsertKeyForPushTokens() {
    assertThat(columnExists("notification_device_tokens", "device_id")).isTrue();
    assertThat(columnIsNullable("notification_device_tokens", "device_id")).isFalse();
    assertThat(columnExists("notification_device_tokens", "app_version")).isTrue();
    assertThat(columnIsNullable("notification_device_tokens", "app_version")).isTrue();

    // (user_id, device_id) UNIQUE가 upsert 키다. 없으면 Token 갱신이 행 누적이 된다.
    assertThat(
            indexExists(
                "notification_device_tokens", "uk_notification_device_tokens_user_device", true))
        .isTrue();
    // 같은 Token이 다른 계정에 중복 등록되는 것을 막는 제약은 그대로 유지한다.
    assertThat(
            indexExists("notification_device_tokens", "uk_notification_device_tokens_hash", true))
        .isTrue();
  }

  @Test
  void seedsActiveFallbackQuestionTemplateWithOptions() {
    // AI 호출이 실패하면 서비스는 활성 FALLBACK Template과 그 선택지를 저장해 대화를 잇는다.
    // 이 데이터가 없으면 폴백 자체가 CONVERSATION_503_001로 실패하므로 시드 존재를 제약처럼 검증한다.
    Long templateId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM ai_question_templates "
                + "WHERE template_type = 'FALLBACK' AND is_active = TRUE "
                + "ORDER BY id ASC LIMIT 1",
            Long.class);
    assertThat(templateId).isNotNull();

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT question_text FROM ai_question_templates WHERE id = ?",
                String.class,
                templateId))
        .isNotBlank();

    // EMOJI 응답 방식은 내부 OPTION으로 매핑되어 선택지를 요구한다. 선택지가 비면 같은 503이 된다.
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM ai_question_template_options WHERE question_template_id = ?",
                Integer.class,
                templateId))
        .isGreaterThanOrEqualTo(2);

    assertThat(
            jdbcTemplate.queryForList(
                "SELECT option_key FROM ai_question_template_options "
                    + "WHERE question_template_id = ? AND (option_key = '' OR label = '')",
                templateId))
        .isEmpty();
  }

  private boolean columnExists(String tableName, String columnName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?",
            tableName,
            columnName)
        > 0;
  }

  private boolean columnIsNullable(String tableName, String columnName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ? "
                + "AND is_nullable = 'YES'",
            tableName,
            columnName)
        > 0;
  }

  private boolean generatedColumnContains(
      String tableName, String columnName, String expectedFragment) {
    return count(
            "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ? "
                + "AND generation_expression LIKE ?",
            tableName,
            columnName,
            "%" + expectedFragment + "%")
        > 0;
  }

  private boolean decimalColumnHasPrecision(
      String tableName, String columnName, int precision, int scale) {
    return count(
            "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ? "
                + "AND data_type = 'decimal' AND numeric_precision = ? AND numeric_scale = ?",
            tableName,
            columnName,
            precision,
            scale)
        > 0;
  }

  private void insertDrawingAsset(
      long drawingSessionId, String assetType, int assetVersion, String storageKey) {
    jdbcTemplate.update(
        "INSERT INTO drawing_assets "
            + "(drawing_session_id, asset_type, asset_version, storage_key, mime_type, "
            + "file_size_bytes, checksum_sha256, captured_at) "
            + "VALUES (?, ?, ?, ?, 'image/png', 8, REPEAT('a', 64), NOW(6))",
        drawingSessionId,
        assetType,
        assetVersion,
        storageKey);
  }

  private void insertAnalysis(long drawingAssetId, String requestId, String status) {
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(drawing_session_id, drawing_asset_id, analysis_type, analysis_task_type, "
            + "idempotency_key, analysis_status) "
            + "VALUES (9101, ?, 'FINAL', 'OBJECT_DETECTION', ?, ?)",
        drawingAssetId,
        requestId,
        status);
  }

  private int tableCount() {
    return jdbcTemplate.queryForObject(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()",
        Integer.class);
  }

  private int jsonColumnCount() {
    return jdbcTemplate.queryForObject(
        "SELECT COUNT(*) FROM information_schema.columns "
            + "WHERE table_schema = DATABASE() AND data_type = 'json'",
        Integer.class);
  }

  private boolean tableExists(String tableName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?",
            tableName)
        > 0;
  }

  private boolean primaryKeyExists(String tableName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.table_constraints "
                + "WHERE constraint_schema = DATABASE() AND table_name = ? "
                + "AND constraint_type = 'PRIMARY KEY'",
            tableName)
        > 0;
  }

  private boolean foreignKeyExists(String tableName, String constraintName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.table_constraints "
                + "WHERE constraint_schema = DATABASE() AND table_name = ? "
                + "AND constraint_name = ? AND constraint_type = 'FOREIGN KEY'",
            tableName,
            constraintName)
        > 0;
  }

  private boolean foreignKeyDeleteRuleIs(
      String tableName, String constraintName, String deleteRule) {
    return count(
            "SELECT COUNT(*) FROM information_schema.referential_constraints "
                + "WHERE constraint_schema = DATABASE() AND table_name = ? "
                + "AND constraint_name = ? AND delete_rule = ?",
            tableName,
            constraintName,
            deleteRule)
        > 0;
  }

  private boolean indexExists(String tableName, String indexName, boolean unique) {
    return count(
            "SELECT COUNT(*) FROM information_schema.statistics "
                + "WHERE table_schema = DATABASE() AND table_name = ? "
                + "AND index_name = ? AND non_unique = ?",
            tableName,
            indexName,
            unique ? 0 : 1)
        > 0;
  }

  private boolean checkConstraintContains(
      String tableName, String constraintName, String expectedFragment) {
    return count(
            "SELECT COUNT(*) FROM information_schema.table_constraints tc "
                + "JOIN information_schema.check_constraints cc "
                + "ON cc.constraint_schema = tc.constraint_schema "
                + "AND cc.constraint_name = tc.constraint_name "
                + "WHERE tc.constraint_schema = DATABASE() AND tc.table_name = ? "
                + "AND tc.constraint_name = ? AND cc.check_clause LIKE ?",
            tableName,
            constraintName,
            "%" + expectedFragment + "%")
        > 0;
  }

  private int count(String sql, Object... args) {
    return jdbcTemplate.queryForObject(sql, Integer.class, args);
  }
}
