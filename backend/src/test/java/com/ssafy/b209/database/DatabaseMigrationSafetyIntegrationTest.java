package com.ssafy.b209.database;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 기존 데이터가 있는 데이터베이스에서 파괴적 Migration이 안전 조건을 확인하는지 검증한다. */
@Testcontainers
class DatabaseMigrationSafetyIntegrationTest {

  @Container
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_safety")
          .withUsername("test")
          .withPassword("test");

  private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void migrateToV2() {
    jdbcTemplate =
        new JdbcTemplate(
            new DriverManagerDataSource(
                MYSQL_CONTAINER.getJdbcUrl(),
                MYSQL_CONTAINER.getUsername(),
                MYSQL_CONTAINER.getPassword()));

    flyway().clean();
    Flyway.configure()
        .dataSource(
            MYSQL_CONTAINER.getJdbcUrl(),
            MYSQL_CONTAINER.getUsername(),
            MYSQL_CONTAINER.getPassword())
        .target(MigrationVersion.fromVersion("2"))
        .load()
        .migrate();
  }

  @Test
  void refusesV3WhenLegacyJsonContainsData() {
    jdbcTemplate.update(
        "INSERT INTO users (id, role, notification_settings_json) "
            + "VALUES (1, 'GUARDIAN', JSON_OBJECT('marketing', false))");

    assertThatThrownBy(() -> flyway().migrate())
        .hasMessageContaining("ck_migration_v3_state_guard");

    assertThat(columnExists("users", "notification_settings_json")).isTrue();
    assertThat(tableExists("refresh_tokens")).isTrue();
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM users", Integer.class))
        .isEqualTo(1);
  }

  @Test
  void refusesV3WhenRefreshTokensExist() {
    jdbcTemplate.update("INSERT INTO users (id, role) VALUES (1, 'GUARDIAN')");
    jdbcTemplate.update(
        "INSERT INTO refresh_tokens (user_id, token_hash, expires_at) "
            + "VALUES (1, REPEAT('a', 64), DATE_ADD(NOW(6), INTERVAL 1 DAY))");

    assertThatThrownBy(() -> flyway().migrate())
        .hasMessageContaining("ck_migration_v3_state_guard");

    assertThat(tableExists("refresh_tokens")).isTrue();
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM refresh_tokens", Integer.class))
        .isEqualTo(1);
    assertThat(columnExists("expert_profiles", "users_id")).isTrue();
  }

  @Test
  void convertsWithdrawnUsersToDeletedStatus() {
    jdbcTemplate.update(
        "INSERT INTO users (id, role, account_status) VALUES (1, 'GUARDIAN', 'WITHDRAWN')");

    flyway().migrate();

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT account_status FROM users WHERE id = 1", String.class))
        .isEqualTo("DELETED");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT deleted_at IS NOT NULL FROM users WHERE id = 1", Boolean.class))
        .isTrue();
  }

  @Test
  void refusesV6WhenLocalAuthAccountsExist() {
    jdbcTemplate.update("INSERT INTO users (id, role) VALUES (1, 'GUARDIAN')");
    jdbcTemplate.update(
        "INSERT INTO auth_accounts "
            + "(user_id, provider, provider_subject, login_email, password_hash) "
            + "VALUES (1, 'LOCAL', 'legacy@example.com', 'legacy@example.com', 'encoded')");

    assertThatThrownBy(() -> flyway().migrate())
        .hasMessageContaining("ck_migration_v6_social_auth_guard");

    assertThat(columnExists("auth_accounts", "password_hash")).isTrue();
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM auth_accounts WHERE provider = 'LOCAL'", Integer.class))
        .isEqualTo(1);
  }

  private Flyway flyway() {
    return Flyway.configure()
        .dataSource(
            MYSQL_CONTAINER.getJdbcUrl(),
            MYSQL_CONTAINER.getUsername(),
            MYSQL_CONTAINER.getPassword())
        .cleanDisabled(false)
        .load();
  }

  private boolean tableExists(String tableName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?",
            tableName)
        > 0;
  }

  private boolean columnExists(String tableName, String columnName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?",
            tableName,
            columnName)
        > 0;
  }

  private int count(String sql, Object... args) {
    return jdbcTemplate.queryForObject(sql, Integer.class, args);
  }
}
