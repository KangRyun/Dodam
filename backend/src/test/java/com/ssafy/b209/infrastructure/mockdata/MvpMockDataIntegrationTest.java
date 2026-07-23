package com.ssafy.b209.infrastructure.mockdata;

import static org.assertj.core.api.Assertions.assertThat;

import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers
class MvpMockDataIntegrationTest {

  private static final long MOCK_ID = -136001L;

  @Container
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam")
          .withUsername("test")
          .withPassword("test");

  private static DataSource dataSource;
  private static JdbcTemplate jdbcTemplate;

  @BeforeAll
  static void migrateSchema() {
    dataSource =
        new DriverManagerDataSource(
            MYSQL_CONTAINER.getJdbcUrl(),
            MYSQL_CONTAINER.getUsername(),
            MYSQL_CONTAINER.getPassword());
    jdbcTemplate = new JdbcTemplate(dataSource);

    Flyway.configure().dataSource(dataSource).locations("classpath:db/migration").load().migrate();
  }

  @Test
  void seedsRelatedMvpDataIdempotently() throws Exception {
    MvpMockDataConfiguration configuration = new MvpMockDataConfiguration();

    configuration
        .mvpMockDataInitializer(dataSource)
        .run(new DefaultApplicationArguments(new String[0]));
    configuration
        .mvpMockDataInitializer(dataSource)
        .run(new DefaultApplicationArguments(new String[0]));

    assertThat(countById("users")).isEqualTo(1);
    assertThat(countById("auth_accounts")).isEqualTo(1);
    assertThat(countById("children")).isEqualTo(1);
    assertThat(countById("guardian_child_relations")).isEqualTo(1);
    assertThat(countById("drawing_types")).isEqualTo(1);
    assertThat(countById("drawing_sessions")).isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT child_id, drawing_type_id, started_by_user_id, "
                    + "session_status, current_stage "
                    + "FROM drawing_sessions WHERE id = ?",
                MOCK_ID))
        .containsEntry("child_id", MOCK_ID)
        .containsEntry("drawing_type_id", MOCK_ID)
        .containsEntry("started_by_user_id", MOCK_ID)
        .containsEntry("session_status", "IN_PROGRESS")
        .containsEntry("current_stage", "DRAWING");
  }

  private int countById(String tableName) {
    return jdbcTemplate.queryForObject(
        "SELECT COUNT(*) FROM " + tableName + " WHERE id = ?", Integer.class, MOCK_ID);
  }
}
