package com.ssafy.b209.auth.authorization;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@ActiveProfiles("integration-test")
class GuardianResourceAccessRepositoryIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long OTHER_GUARDIAN_USER_ID = 42L;
  private static final Long CHILD_ID = 7L;
  private static final Long DRAWING_SESSION_ID = 9L;

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam")
          .withUsername("test")
          .withPassword("test");

  @Autowired private GuardianResourceAccessRepository repository;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    jdbcTemplate.update("delete from drawing_sessions");
    jdbcTemplate.update("delete from guardian_child_relations");
    jdbcTemplate.update("delete from drawing_types");
    jdbcTemplate.update("delete from children");
    jdbcTemplate.update("delete from users");
    jdbcTemplate.update(
        "insert into users (id, role, nickname, account_status) values "
            + "(?, 'GUARDIAN', 'guardian-one', 'ACTIVE'), "
            + "(?, 'GUARDIAN', 'guardian-two', 'ACTIVE')",
        GUARDIAN_USER_ID,
        OTHER_GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "insert into children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "values (?, 'child', '2020-07-23', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
        CHILD_ID);
    jdbcTemplate.update(
        "insert into guardian_child_relations "
            + "(guardian_user_id, child_id, relationship_type) values (?, ?, 'MOTHER')",
        GUARDIAN_USER_ID,
        CHILD_ID);
    jdbcTemplate.update(
        "insert into drawing_types "
            + "(id, code, name, activity_category, selectable_by, is_active, display_order) "
            + "values (3, 'ACCESS_TEST', 'Access Test', 'GENERAL', 'GUARDIAN', true, 1)");
    jdbcTemplate.update(
        "insert into drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage) "
            + "values (?, ?, 3, 'CANVAS', 'IN_PROGRESS', 'DRAWING')",
        DRAWING_SESSION_ID,
        CHILD_ID);
  }

  @Test
  void grantsOnlyConnectedGuardianAccessToChildAndDrawingSession() {
    assertThat(repository.hasChildAccess(GUARDIAN_USER_ID, CHILD_ID)).isTrue();
    assertThat(repository.hasDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID)).isTrue();

    assertThat(repository.hasChildAccess(OTHER_GUARDIAN_USER_ID, CHILD_ID)).isFalse();
    assertThat(repository.hasDrawingSessionAccess(OTHER_GUARDIAN_USER_ID, DRAWING_SESSION_ID))
        .isFalse();
  }

  @Test
  void rejectsSoftDeletedChildAndDrawingSession() {
    jdbcTemplate.update(
        "update drawing_sessions set session_status = 'DELETED', deleted_at = current_timestamp(6) where id = ?",
        DRAWING_SESSION_ID);

    assertThat(repository.hasDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID)).isFalse();

    jdbcTemplate.update(
        "update children set profile_status = 'DELETED', deleted_at = current_timestamp(6) where id = ?",
        CHILD_ID);

    assertThat(repository.hasChildAccess(GUARDIAN_USER_ID, CHILD_ID)).isFalse();
  }
}
