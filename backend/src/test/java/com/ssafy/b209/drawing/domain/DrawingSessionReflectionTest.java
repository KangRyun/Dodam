package com.ssafy.b209.drawing.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import java.time.LocalDate;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class DrawingSessionReflectionTest {

  @Test
  void savesReflectionFromConversingStage() {
    DrawingSession session = session();
    ReflectionTestUtils.setField(session, "currentStage", DrawingStage.CONVERSING);

    assertThat(session.canSaveReflection()).isTrue();

    session.saveReflection("우리 가족", "함께 있어서 좋았어");

    assertThat(session.getTitle()).isEqualTo("우리 가족");
    assertThat(session.getExpressedEmotionText()).isEqualTo("함께 있어서 좋았어");
    assertThat(session.getCurrentStage()).isEqualTo(DrawingStage.REFLECTION);
    assertThat(session.canSaveReflection()).isTrue();
  }

  @Test
  void doesNotAllowReflectionFromDrawingStage() {
    DrawingSession session = session();

    assertThat(session.canSaveReflection()).isFalse();
    assertThatThrownBy(() -> session.saveReflection("제목", null))
        .isInstanceOf(IllegalStateException.class);
  }

  @Test
  void completesReportingSessionWithServerTimestamp() {
    DrawingSession session = session();
    ReflectionTestUtils.setField(session, "currentStage", DrawingStage.REFLECTION);
    session.startReporting();
    LocalDateTime completedAt = LocalDateTime.of(2026, 7, 23, 3, 0);

    session.completeReporting(completedAt);

    assertThat(session.getSessionStatus()).isEqualTo(DrawingSessionStatus.COMPLETED);
    assertThat(session.getCurrentStage()).isEqualTo(DrawingStage.COMPLETED);
    assertThat(session.getCompletedAt()).isEqualTo(completedAt);
  }

  @Test
  void rejectsCompletionBeforeReportingStage() {
    DrawingSession session = session();

    assertThatThrownBy(() -> session.completeReporting(LocalDateTime.of(2026, 7, 23, 3, 0)))
        .isInstanceOf(IllegalStateException.class);
  }

  @Test
  void failsReportingSessionWithoutMarkingItCompleted() {
    DrawingSession session = session();
    ReflectionTestUtils.setField(session, "currentStage", DrawingStage.REFLECTION);
    session.startReporting();

    session.failReporting();

    assertThat(session.getSessionStatus()).isEqualTo(DrawingSessionStatus.FAILED);
    assertThat(session.getCurrentStage()).isEqualTo(DrawingStage.REPORTING);
    assertThat(session.getCompletedAt()).isNull();
  }

  private DrawingSession session() {
    return DrawingSession.start(
        ChildFixture.create(
            1L,
            LocalDate.of(2020, 7, 23),
            ChildTutorialStatus.COMPLETED,
            ChildProfileStatus.ACTIVE,
            null),
        DrawingTypeFixture.create(
            1L, "REFLECTION_TEST", "Reflection Test", DrawingTypeSelectableBy.BOTH, 3, 12, true),
        DrawingInputMethod.CANVAS,
        LocalDateTime.of(2026, 7, 23, 2, 0),
        "reflection-test-key");
  }
}
