package com.ssafy.b209.database;

import static org.assertj.core.api.Assertions.assertThat;

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
    assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("3");
    assertThat(tableExists("flyway_schema_history")).isTrue();
    assertThat(tableCount()).isEqualTo(63);
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

  private boolean columnExists(String tableName, String columnName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?",
            tableName,
            columnName)
        > 0;
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
