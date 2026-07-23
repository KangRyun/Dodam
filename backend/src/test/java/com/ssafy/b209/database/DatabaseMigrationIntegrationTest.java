package com.ssafy.b209.database;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

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

  @Test
  void appliesAllMigrationsWithoutJsonOrRefreshTokenTable() {
    assertThat(MYSQL_CONTAINER.isRunning()).isTrue();
    assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("9");
    assertThat(tableExists("flyway_schema_history")).isTrue();
    assertThat(tableCount()).isEqualTo(62);
    assertThat(tableExists("refresh_tokens")).isFalse();
    assertThat(jsonColumnCount()).isZero();
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
    assertThat(decimalColumnHasPrecision("analysis_detected_objects", "bbox_x", 12, 3)).isTrue();
    assertThat(decimalColumnHasPrecision("analysis_detected_objects", "bbox_height", 12, 3))
        .isTrue();
    assertThat(
            checkConstraintContains(
                "analysis_detected_objects", "ck_analysis_detected_objects_bbox", "bbox_width"))
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
