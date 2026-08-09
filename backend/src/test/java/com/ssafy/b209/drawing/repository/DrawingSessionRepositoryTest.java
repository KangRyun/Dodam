package com.ssafy.b209.drawing.repository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import jakarta.persistence.EntityManager;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class DrawingSessionRepositoryTest {

  @Autowired private EntityManager entityManager;

  @Autowired private DataSource dataSource;

  @Autowired private ChildRepository childRepository;

  @Autowired private DrawingTypeRepository drawingTypeRepository;

  @Autowired private DrawingSessionRepository drawingSessionRepository;

  @Test
  void usesTheMySqlModeDatasourceConfiguredForTheTestProfile() throws SQLException {
    try (Connection connection = dataSource.getConnection()) {
      assertThat(connection.getMetaData().getURL())
          .startsWith("jdbc:h2:mem:dodam-test-")
          .doesNotContain("jdbc:h2:mem:dodam-test;");

      try (PreparedStatement statement =
              connection.prepareStatement(
                  "select setting_value from information_schema.settings where setting_name = 'MODE'");
          ResultSet resultSet = statement.executeQuery()) {
        assertThat(resultSet.next()).isTrue();
        assertThat(resultSet.getString(1)).isEqualTo("MySQL");
      }
    }
  }

  @Test
  void savesDrawingSessionWithItsChildAndDrawingTypeRelationships() {
    PersistedReferences references = persistReferences(null);
    DrawingSession saved = saveSession(references, "relationship-key");

    entityManager.flush();
    entityManager.clear();

    DrawingSession found = drawingSessionRepository.findById(saved.getId()).orElseThrow();

    assertThat(found.getChild().getId()).isEqualTo(references.child().getId());
    assertThat(found.getDrawingType().getId()).isEqualTo(references.drawingType().getId());
  }

  @Test
  void persistsDrawingSessionEnumsAsExactSchemaStrings() {
    DrawingSession saved = saveSession(persistReferences(null), "enum-key");

    entityManager.flush();

    Object[] values =
        (Object[])
            entityManager
                .createNativeQuery(
                    "select input_method, session_status, current_stage from drawing_sessions where id = ?")
                .setParameter(1, saved.getId())
                .getSingleResult();

    assertThat(values).containsExactly("CANVAS", "IN_PROGRESS", "DRAWING");
  }

  @Test
  void preservesSuppliedUtcStartedAtAndLeavesCompletionAndDeletionTimesNull() {
    LocalDateTime startedAt = LocalDateTime.of(2026, 7, 21, 10, 30, 15, 123_000_000);
    DrawingSession saved = saveSession(persistReferences(null), "started-at-key", startedAt);

    entityManager.flush();
    entityManager.clear();

    DrawingSession found = drawingSessionRepository.findById(saved.getId()).orElseThrow();

    assertThat(found.getStartedAt()).isEqualTo(startedAt);
    assertThat(found.getCompletedAt()).isNull();
    assertThat(found.getDeletedAt()).isNull();
  }

  @Test
  void findsAnInProgressNonDeletedSessionForItsChild() {
    PersistedReferences references = persistReferences(null);
    DrawingSession saved = saveSession(references, "active-key");

    entityManager.flush();
    entityManager.clear();

    DrawingSession found =
        drawingSessionRepository.findActiveByChildId(references.child().getId()).orElseThrow();

    assertThat(found.getId()).isEqualTo(saved.getId());
  }

  @Test
  void findsAllAndOnlyInProgressNonDeletedSessionsForTheRequestedChild() {
    PersistedReferences references = persistReferences(null);
    DrawingSession firstActive = saveSession(references, "active-list-first");
    DrawingSession secondActive = saveSession(references, "active-list-second");
    DrawingSession completed = saveSession(references, "active-list-completed");
    DrawingSession deleted = saveSession(references, "active-list-deleted");
    Child anotherChild = childRepository.save(child(null));
    DrawingSession anotherChildSession =
        saveSession(
            new PersistedReferences(anotherChild, references.drawingType()),
            "active-list-another-child");

    entityManager.flush();
    entityManager
        .createNativeQuery("update drawing_sessions set session_status = 'COMPLETED' where id = ?")
        .setParameter(1, completed.getId())
        .executeUpdate();
    entityManager
        .createNativeQuery("update drawing_sessions set deleted_at = ? where id = ?")
        .setParameter(1, LocalDateTime.of(2026, 7, 22, 9, 0))
        .setParameter(2, deleted.getId())
        .executeUpdate();
    entityManager.clear();

    assertThat(drawingSessionRepository.findActiveSessionsByChildId(references.child().getId()))
        .extracting(DrawingSession::getId)
        .containsExactly(firstActive.getId(), secondActive.getId())
        .doesNotContain(completed.getId(), deleted.getId(), anotherChildSession.getId());
  }

  @Test
  void excludesCompletedSessionsFromTheActiveSessionLookup() {
    PersistedReferences references = persistReferences(null);
    DrawingSession saved = saveSession(references, "completed-key");

    entityManager.flush();
    entityManager
        .createNativeQuery("update drawing_sessions set session_status = 'COMPLETED' where id = ?")
        .setParameter(1, saved.getId())
        .executeUpdate();
    entityManager.clear();

    assertThat(drawingSessionRepository.findActiveByChildId(references.child().getId())).isEmpty();
  }

  @Test
  void excludesDeletedSessionsFromTheActiveSessionLookup() {
    PersistedReferences references = persistReferences(null);
    DrawingSession saved = saveSession(references, "deleted-key");

    entityManager.flush();
    entityManager
        .createNativeQuery("update drawing_sessions set deleted_at = ? where id = ?")
        .setParameter(1, LocalDateTime.of(2026, 7, 21, 11, 0))
        .setParameter(2, saved.getId())
        .executeUpdate();
    entityManager.clear();

    assertThat(drawingSessionRepository.findActiveByChildId(references.child().getId())).isEmpty();
  }

  @Test
  void findsTheExactSessionByIdempotencyKeyForUpdate() {
    DrawingSession saved = saveSession(persistReferences(null), "lock-key");

    entityManager.flush();
    entityManager.clear();

    DrawingSession found =
        drawingSessionRepository.findByIdempotencyKeyForUpdate("lock-key").orElseThrow();

    assertThat(found.getId()).isEqualTo(saved.getId());
  }

  @Test
  void findsOnlyNonDeletedChildrenForUpdate() {
    Child available = childRepository.save(child(null));
    Child deleted = childRepository.save(child(LocalDateTime.of(2026, 7, 21, 11, 0)));

    entityManager.flush();
    entityManager.clear();

    assertThat(childRepository.findNotDeletedByIdForUpdate(available.getId()))
        .map(Child::getId)
        .contains(available.getId());
    assertThat(childRepository.findNotDeletedByIdForUpdate(deleted.getId())).isEmpty();
  }

  @Test
  void rejectsDuplicateNonNullIdempotencyKeysWhenFlushed() {
    PersistedReferences references = persistReferences(null);
    saveSession(references, "duplicate-key");
    entityManager.flush();
    entityManager.clear();

    Throwable exception =
        catchThrowable(
            () ->
                drawingSessionRepository.saveAndFlush(
                    DrawingSession.start(
                        entityManager.getReference(Child.class, references.child().getId()),
                        entityManager.getReference(
                            DrawingType.class, references.drawingType().getId()),
                        DrawingInputMethod.CANVAS,
                        LocalDateTime.of(2026, 7, 21, 10, 30),
                        "duplicate-key")));

    Throwable rootCause = rootCause(exception);

    assertThat(rootCause).isInstanceOf(SQLException.class);
    SQLException sqlException = (SQLException) rootCause;
    assertThat(sqlException.getSQLState()).isEqualTo("23505");
    assertThat(sqlException.getMessage()).containsIgnoringCase("IDEMPOTENCY_KEY");
  }

  private PersistedReferences persistReferences(LocalDateTime childDeletedAt) {
    Child child = childRepository.save(child(childDeletedAt));
    DrawingType drawingType =
        drawingTypeRepository.save(
            DrawingTypeFixture.create(
                null, "HOUSE", "House", DrawingTypeSelectableBy.BOTH, 6, 10, true));
    return new PersistedReferences(child, drawingType);
  }

  private Child child(LocalDateTime deletedAt) {
    return ChildFixture.create(
        null,
        LocalDate.of(2018, 7, 21),
        ChildTutorialStatus.NOT_STARTED,
        ChildProfileStatus.ACTIVE,
        deletedAt);
  }

  private DrawingSession saveSession(PersistedReferences references, String idempotencyKey) {
    return saveSession(
        references, idempotencyKey, LocalDateTime.of(2026, 7, 21, 10, 30, 15, 123_000_000));
  }

  private DrawingSession saveSession(
      PersistedReferences references, String idempotencyKey, LocalDateTime startedAt) {
    return drawingSessionRepository.save(
        DrawingSession.start(
            references.child(),
            references.drawingType(),
            DrawingInputMethod.CANVAS,
            startedAt,
            idempotencyKey));
  }

  private Throwable rootCause(Throwable throwable) {
    Throwable current = throwable;
    while (current != null && current.getCause() != null) {
      current = current.getCause();
    }
    return current;
  }

  private record PersistedReferences(Child child, DrawingType drawingType) {}
}
