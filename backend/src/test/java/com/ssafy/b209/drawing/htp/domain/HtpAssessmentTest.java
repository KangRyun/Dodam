package com.ssafy.b209.drawing.htp.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import java.time.LocalDate;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class HtpAssessmentTest {

  private static final LocalDateTime STARTED_AT = LocalDateTime.of(2026, 7, 28, 10, 0);
  private static final LocalDateTime EXPIRES_AT = STARTED_AT.plusHours(24);

  @Test
  void startsWithHouseStepAndItsDrawingSession() {
    DrawingSession houseSession = session("htp-house-key");

    HtpAssessment assessment =
        HtpAssessment.start(
            child(), htpType(), houseSession, STARTED_AT, EXPIRES_AT, "htp-start-key");

    assertThat(assessment.getStatus()).isEqualTo(HtpAssessmentStatus.IN_PROGRESS);
    assertThat(assessment.getCurrentStepOrder()).isEqualTo(1);
    assertThat(assessment.getExpiresAt()).isEqualTo(EXPIRES_AT);
    assertThat(assessment.getIdempotencyKey()).isEqualTo("htp-start-key");
    assertThat(assessment.getSteps()).hasSize(1);
    assertThat(assessment.getCurrentStep().getDrawingSubject()).isEqualTo(HtpDrawingSubject.HOUSE);
    assertThat(assessment.getCurrentStep().getDrawingSession()).isSameAs(houseSession);
  }

  @Test
  void advancesHouseToTreeOnlyAfterCurrentSessionCompleted() {
    DrawingSession houseSession = session("htp-house-key");
    HtpAssessment assessment =
        HtpAssessment.start(
            child(), htpType(), houseSession, STARTED_AT, EXPIRES_AT, "htp-start-key");
    DrawingSession treeSession = session("htp-tree-key");

    assertThatThrownBy(() -> assessment.advance(treeSession, STARTED_AT.plusHours(1)))
        .isInstanceOf(IllegalStateException.class);

    completeHtpStep(houseSession, STARTED_AT.plusMinutes(30));
    assessment.advance(treeSession, STARTED_AT.plusHours(1));

    assertThat(assessment.getCurrentStepOrder()).isEqualTo(2);
    assertThat(assessment.getCurrentStep().getDrawingSubject()).isEqualTo(HtpDrawingSubject.TREE);
    assertThat(assessment.getCurrentStep().getDrawingSession()).isSameAs(treeSession);
  }

  @Test
  void advancesInFixedHouseTreePersonOrderAndDoesNotCreateFourthStep() {
    DrawingSession houseSession = session("htp-house-key");
    HtpAssessment assessment =
        HtpAssessment.start(
            child(), htpType(), houseSession, STARTED_AT, EXPIRES_AT, "htp-start-key");
    completeHtpStep(houseSession, STARTED_AT.plusMinutes(20));

    DrawingSession treeSession = session("htp-tree-key");
    assessment.advance(treeSession, STARTED_AT.plusMinutes(30));
    completeHtpStep(treeSession, STARTED_AT.plusMinutes(50));

    DrawingSession personSession = session("htp-person-key");
    assessment.advance(personSession, STARTED_AT.plusHours(1));
    completeHtpStep(personSession, STARTED_AT.plusHours(2));

    assertThat(assessment.getSteps())
        .extracting(HtpAssessmentStep::getDrawingSubject)
        .containsExactly(HtpDrawingSubject.HOUSE, HtpDrawingSubject.TREE, HtpDrawingSubject.PERSON);
    assertThatThrownBy(() -> assessment.advance(session("htp-fourth-key"), STARTED_AT.plusHours(3)))
        .isInstanceOf(IllegalStateException.class);
  }

  @Test
  void rejectsAdvancingExpiredOrAbandonedAssessment() {
    DrawingSession houseSession = session("htp-house-key");
    HtpAssessment expired =
        HtpAssessment.start(
            child(), htpType(), houseSession, STARTED_AT, EXPIRES_AT, "htp-start-key");
    completeHtpStep(houseSession, STARTED_AT.plusMinutes(30));

    assertThatThrownBy(() -> expired.advance(session("htp-tree-key"), EXPIRES_AT.plusNanos(1)))
        .isInstanceOf(IllegalStateException.class);

    DrawingSession abandonedSession = session("htp-abandoned-key");
    HtpAssessment abandoned =
        HtpAssessment.start(
            child(), htpType(), abandonedSession, STARTED_AT, EXPIRES_AT, "htp-abandon-start");
    abandoned.abandon(STARTED_AT.plusMinutes(10));

    assertThat(abandoned.getStatus()).isEqualTo(HtpAssessmentStatus.ABANDONED);
    assertThatThrownBy(
            () -> abandoned.advance(session("htp-tree-2-key"), STARTED_AT.plusMinutes(20)))
        .isInstanceOf(IllegalStateException.class);
  }

  private void completeHtpStep(DrawingSession session, LocalDateTime completedAt) {
    session.startDrawingAnalysis();
    session.finishDrawingAnalysis();
    session.enterReflection();
    session.completeHtpStep(completedAt);
  }

  private DrawingSession session(String idempotencyKey) {
    return DrawingSession.start(
        child(), htpType(), DrawingInputMethod.CANVAS, STARTED_AT, idempotencyKey);
  }

  private Child child() {
    return ChildFixture.create(
        1L,
        LocalDate.of(2018, 7, 28),
        ChildTutorialStatus.COMPLETED,
        ChildProfileStatus.ACTIVE,
        null);
  }

  private DrawingType htpType() {
    return DrawingTypeFixture.create(
        10L, "HTP", "집·나무·사람 그림", DrawingTypeSelectableBy.GUARDIAN, 4, 12, true);
  }
}
