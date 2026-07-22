package com.ssafy.b209.drawing.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import java.time.LocalDate;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class DrawingSessionDomainTest {

  @Test
  void startInitializesAnInProgressDrawingSession() {
    Child child = child(10L);
    DrawingType drawingType = drawingType(20L);
    LocalDateTime startedAt = LocalDateTime.of(2026, 7, 21, 10, 30);

    DrawingSession session =
        DrawingSession.start(child, drawingType, DrawingInputMethod.CANVAS, startedAt, "request-1");

    assertThat(session.getChild()).isSameAs(child);
    assertThat(session.getDrawingType()).isSameAs(drawingType);
    assertThat(session.getInputMethod()).isEqualTo(DrawingInputMethod.CANVAS);
    assertThat(session.getId()).isNull();
    assertThat(session.getSessionStatus()).isEqualTo(DrawingSessionStatus.IN_PROGRESS);
    assertThat(session.getCurrentStage()).isEqualTo(DrawingStage.DRAWING);
    assertThat(session.getStartedAt()).isEqualTo(startedAt);
    assertThat(session.getStartedByUserId()).isNull();
    assertThat(session.getCompletedAt()).isNull();
    assertThat(session.getDeletedAt()).isNull();
    assertThat(session.getIdempotencyKey()).isEqualTo("request-1");
  }

  @Test
  void startRejectsMissingOrBlankCoreValues() {
    Child child = child(10L);
    DrawingType drawingType = drawingType(20L);
    LocalDateTime startedAt = LocalDateTime.of(2026, 7, 21, 10, 30);

    assertThatThrownBy(
            () ->
                DrawingSession.start(
                    null, drawingType, DrawingInputMethod.CANVAS, startedAt, "key"))
        .isInstanceOf(NullPointerException.class);
    assertThatThrownBy(
            () -> DrawingSession.start(child, null, DrawingInputMethod.CANVAS, startedAt, "key"))
        .isInstanceOf(NullPointerException.class);
    assertThatThrownBy(() -> DrawingSession.start(child, drawingType, null, startedAt, "key"))
        .isInstanceOf(NullPointerException.class);
    assertThatThrownBy(
            () -> DrawingSession.start(child, drawingType, DrawingInputMethod.CANVAS, null, "key"))
        .isInstanceOf(NullPointerException.class);
    assertThatThrownBy(
            () ->
                DrawingSession.start(
                    child, drawingType, DrawingInputMethod.CANVAS, startedAt, null))
        .isInstanceOf(NullPointerException.class);
    assertThatThrownBy(
            () ->
                DrawingSession.start(child, drawingType, DrawingInputMethod.CANVAS, startedAt, " "))
        .isInstanceOf(IllegalArgumentException.class);
  }

  @Test
  void matchesCoreRequestComparesOnlyChildDrawingTypeAndInputMethod() {
    DrawingSession session =
        DrawingSession.start(
            child(10L),
            drawingType(20L),
            DrawingInputMethod.CANVAS,
            LocalDateTime.of(2026, 7, 21, 10, 30),
            "request-1");

    assertThat(session.matchesCoreRequest(10L, 20L, DrawingInputMethod.CANVAS)).isTrue();
    assertThat(session.matchesCoreRequest(11L, 20L, DrawingInputMethod.CANVAS)).isFalse();
    assertThat(session.matchesCoreRequest(10L, 21L, DrawingInputMethod.CANVAS)).isFalse();
    assertThat(session.matchesCoreRequest(10L, 20L, DrawingInputMethod.UPLOAD)).isFalse();
  }

  private Child child(Long id) {
    return ChildFixture.create(
        id,
        LocalDate.of(2018, 7, 21),
        ChildTutorialStatus.NOT_STARTED,
        ChildProfileStatus.ACTIVE,
        null);
  }

  private DrawingType drawingType(Long id) {
    return DrawingTypeFixture.create(
        id, "HOUSE", "House", DrawingTypeSelectableBy.BOTH, 6, 10, true);
  }
}
