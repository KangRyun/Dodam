package com.ssafy.b209.child.repository;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class ChildRepositoryTest {

  @Autowired private ChildRepository childRepository;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUpReadModelSchema() {
    jdbcTemplate.execute(
        "ALTER TABLE children ADD COLUMN IF NOT EXISTS profile_image_url VARCHAR(1000)");
    jdbcTemplate.execute(
        "ALTER TABLE children ADD COLUMN IF NOT EXISTS preferred_character VARCHAR(50)");
    jdbcTemplate.execute(
        "ALTER TABLE children ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL");
    jdbcTemplate.execute(
        "ALTER TABLE children ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL");
    jdbcTemplate.execute(
        "CREATE TABLE IF NOT EXISTS guardian_child_relations ("
            + "id BIGINT AUTO_INCREMENT PRIMARY KEY, guardian_user_id BIGINT NOT NULL, "
            + "child_id BIGINT NOT NULL, relationship_type VARCHAR(30) NOT NULL)");
    jdbcTemplate.execute(
        "CREATE TABLE IF NOT EXISTS child_response_modes ("
            + "id BIGINT AUTO_INCREMENT PRIMARY KEY, child_id BIGINT NOT NULL, "
            + "response_mode VARCHAR(20) NOT NULL, display_order SMALLINT NOT NULL)");
    jdbcTemplate.update("DELETE FROM child_response_modes");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM children");

    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, profile_image_url, preferred_character, "
            + "question_difficulty, tutorial_status, profile_status, created_at, updated_at) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        3L,
        "별이",
        Date.valueOf(LocalDate.of(2019, 3, 15)),
        "https://cdn.example/child/3",
        "MONGLE",
        "LOWER_ELEMENTARY",
        "IN_PROGRESS",
        "ACTIVE",
        Timestamp.valueOf(LocalDateTime.of(2026, 7, 20, 1, 2, 3)),
        Timestamp.valueOf(LocalDateTime.of(2026, 7, 21, 4, 5, 6)));
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations "
            + "(id, guardian_user_id, child_id, relationship_type) VALUES (1, 10, 3, 'MOTHER')");
  }

  @Test
  void findsOnlyAConnectedActiveChildAndMapsTheRelationship() {
    ChildDetailProjection child =
        childRepository.findDetailByGuardianUserIdAndChildId(10L, 3L).orElseThrow();

    assertThat(child.getChildId()).isEqualTo(3L);
    assertThat(child.getNickname()).isEqualTo("별이");
    assertThat(child.getBirthDate()).isEqualTo(LocalDate.of(2019, 3, 15));
    assertThat(child.getQuestionDifficulty()).isEqualTo("LOWER_ELEMENTARY");
    assertThat(child.getRelationshipType()).isEqualTo("MOTHER");
    assertThat(childRepository.findDetailByGuardianUserIdAndChildId(11L, 3L)).isEmpty();
  }

  @Test
  void excludesDeletedAndInactiveChildren() {
    jdbcTemplate.update("UPDATE children SET deleted_at = CURRENT_TIMESTAMP WHERE id = 3");
    assertThat(childRepository.findDetailByGuardianUserIdAndChildId(10L, 3L)).isEmpty();

    jdbcTemplate.update(
        "UPDATE children SET deleted_at = NULL, profile_status = 'DELETED' WHERE id = 3");
    assertThat(childRepository.findDetailByGuardianUserIdAndChildId(10L, 3L)).isEmpty();
  }

  @Test
  void summarizesRecentActivityFromNonDeletedDrawingSessionsWithoutExtraQueries() {
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status, "
            + "created_at, updated_at) "
            + "VALUES (4, ?, ?, ?, ?, ?, ?, ?)",
        "달이",
        Date.valueOf(LocalDate.of(2016, 1, 1)),
        "UPPER_ELEMENTARY",
        "NOT_STARTED",
        "ACTIVE",
        Timestamp.valueOf(LocalDateTime.of(2026, 7, 20, 2, 0, 0)),
        Timestamp.valueOf(LocalDateTime.of(2026, 7, 20, 2, 0, 0)));
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations "
            + "(id, guardian_user_id, child_id, relationship_type) VALUES (2, 10, 4, 'FATHER')");
    jdbcTemplate.update(
        "INSERT INTO drawing_types (id, code, name, activity_category, selectable_by, is_active) "
            + "VALUES (101, 'AGG_TEST', '집계 테스트', 'GENERAL', 'GUARDIAN', TRUE)");
    insertDrawingSession(201, 3, LocalDateTime.of(2026, 7, 18, 9, 0, 0), null);
    insertDrawingSession(202, 3, LocalDateTime.of(2026, 7, 20, 8, 15, 0), null);
    insertDrawingSession(203, 3, LocalDateTime.of(2026, 7, 21, 10, 0, 0), LocalDateTime.now());

    var summaries = childRepository.findSummariesByGuardianUserId(10L);

    assertThat(summaries).hasSize(2);
    ChildSummaryProjection firstChild = summaries.get(0);
    assertThat(firstChild.getChildId()).isEqualTo(3L);
    assertThat(firstChild.getPreferredCharacter()).isEqualTo("MONGLE");
    assertThat(firstChild.getTotalActivityCount()).isEqualTo(2L);
    assertThat(firstChild.getLastActivityAt()).isEqualTo(LocalDateTime.of(2026, 7, 20, 8, 15, 0));

    ChildSummaryProjection secondChild = summaries.get(1);
    assertThat(secondChild.getChildId()).isEqualTo(4L);
    assertThat(secondChild.getTotalActivityCount()).isZero();
    assertThat(secondChild.getLastActivityAt()).isNull();
  }

  @Test
  void ordersResponseModesByDisplayOrderAndThenIdentifier() {
    jdbcTemplate.update(
        "INSERT INTO child_response_modes "
            + "(id, child_id, response_mode, display_order) VALUES (30, 3, 'COLOR', 2)");
    jdbcTemplate.update(
        "INSERT INTO child_response_modes "
            + "(id, child_id, response_mode, display_order) VALUES (20, 3, 'EMOJI', 1)");
    jdbcTemplate.update(
        "INSERT INTO child_response_modes "
            + "(id, child_id, response_mode, display_order) VALUES (10, 3, 'VOICE', 1)");

    assertThat(childRepository.findResponseModesByChildId(3L))
        .containsExactly("VOICE", "EMOJI", "COLOR");
  }

  private void insertDrawingSession(
      long id, long childId, LocalDateTime startedAt, LocalDateTime deletedAt) {
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, deleted_at) VALUES (?, ?, 101, 'CANVAS', 'IN_PROGRESS', 'DRAWING', ?, ?)",
        id,
        childId,
        Timestamp.valueOf(startedAt),
        deletedAt == null ? null : Timestamp.valueOf(deletedAt));
  }
}
