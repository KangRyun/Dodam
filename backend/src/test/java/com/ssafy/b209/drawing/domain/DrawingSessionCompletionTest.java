package com.ssafy.b209.drawing.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class DrawingSessionCompletionTest {

  @Test
  void movesReflectionSessionToReportingWithoutCompletingIt() {
    DrawingSession session = sessionAt(DrawingSessionStatus.IN_PROGRESS, DrawingStage.REFLECTION);

    session.startReporting();

    assertThat(session.getSessionStatus()).isEqualTo(DrawingSessionStatus.IN_PROGRESS);
    assertThat(session.getCurrentStage()).isEqualTo(DrawingStage.REPORTING);
    assertThat(session.getCompletedAt()).isNull();
  }

  @Test
  void rejectsCompletionOutsideReflectionStage() {
    DrawingSession session = sessionAt(DrawingSessionStatus.IN_PROGRESS, DrawingStage.CONVERSING);

    assertThatThrownBy(session::startReporting).isInstanceOf(IllegalStateException.class);
  }

  private DrawingSession sessionAt(DrawingSessionStatus status, DrawingStage stage) {
    DrawingSession session = new DrawingSession();
    ReflectionTestUtils.setField(session, "sessionStatus", status);
    ReflectionTestUtils.setField(session, "currentStage", stage);
    return session;
  }
}
