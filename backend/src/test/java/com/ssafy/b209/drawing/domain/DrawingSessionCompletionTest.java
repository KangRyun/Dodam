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

  @Test
  void restartsFailedReportingSessionForReportRegeneration() {
    DrawingSession session = sessionAt(DrawingSessionStatus.FAILED, DrawingStage.REPORTING);

    session.restartReporting();

    assertThat(session.getSessionStatus()).isEqualTo(DrawingSessionStatus.IN_PROGRESS);
    assertThat(session.getCurrentStage()).isEqualTo(DrawingStage.REPORTING);
    assertThat(session.getCompletedAt()).isNull();
  }

  /**
   * 완료된 활동도 리포트를 다시 만들 수 있어야 한다 (P0-2).
   *
   * <p>리포트 실패가 더는 활동을 FAILED로 내리지 않으니, 재생성 대상 세션은 대부분 COMPLETED 상태다. 예전 조건({@code FAILED +
   * REPORTING})만 받으면 재생성 경로가 통째로 막힌다.
   *
   * <p>세션 상태는 건드리지 않는다. 아이가 한 활동은 끝난 것이고, 다시 만드는 것은 리포트뿐이다.
   */
  @Test
  void allowsReportRegenerationOnCompletedSessionWithoutReopeningActivity() {
    DrawingSession session = sessionAt(DrawingSessionStatus.COMPLETED, DrawingStage.COMPLETED);

    session.restartReporting();

    assertThat(session.getSessionStatus()).isEqualTo(DrawingSessionStatus.COMPLETED);
    assertThat(session.getCurrentStage()).isEqualTo(DrawingStage.COMPLETED);
  }

  @Test
  void rejectsReportRegenerationOnUnfinishedSession() {
    DrawingSession session = sessionAt(DrawingSessionStatus.IN_PROGRESS, DrawingStage.DRAWING);

    assertThatThrownBy(session::restartReporting).isInstanceOf(IllegalStateException.class);
  }

  private DrawingSession sessionAt(DrawingSessionStatus status, DrawingStage stage) {
    DrawingSession session = new DrawingSession();
    ReflectionTestUtils.setField(session, "sessionStatus", status);
    ReflectionTestUtils.setField(session, "currentStage", stage);
    return session;
  }
}
