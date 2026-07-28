package com.ssafy.b209.drawing.htp.repository;

import static org.assertj.core.api.Assertions.assertThat;

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
import com.ssafy.b209.drawing.htp.domain.HtpAssessment;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import jakarta.persistence.EntityManager;
import java.time.LocalDate;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class HtpAssessmentRepositoryTest {

  @Autowired private EntityManager entityManager;
  @Autowired private ChildRepository childRepository;
  @Autowired private DrawingTypeRepository drawingTypeRepository;
  @Autowired private DrawingSessionRepository drawingSessionRepository;
  @Autowired private HtpAssessmentRepository htpAssessmentRepository;

  @Test
  void savesAndLoadsTheActiveAssessmentWithItsCurrentStep() {
    LocalDateTime startedAt = LocalDateTime.of(2026, 7, 28, 10, 0);
    Child child = childRepository.save(child());
    DrawingType htpType = drawingTypeRepository.save(htpType());
    DrawingSession session =
        drawingSessionRepository.save(
            DrawingSession.start(
                child, htpType, DrawingInputMethod.CANVAS, startedAt, "htp-house-key"));
    HtpAssessment assessment =
        htpAssessmentRepository.save(
            HtpAssessment.start(
                child, htpType, session, startedAt, startedAt.plusHours(24), "htp-start-key"));

    entityManager.flush();
    entityManager.clear();

    HtpAssessment found =
        htpAssessmentRepository.findActiveByChildIdForUpdate(child.getId()).orElseThrow();

    assertThat(found.getId()).isEqualTo(assessment.getId());
    assertThat(found.getCurrentStep().getDrawingSubject()).isEqualTo(HtpDrawingSubject.HOUSE);
    assertThat(found.getCurrentStep().getDrawingSession().getId()).isEqualTo(session.getId());
  }

  @Test
  void findsAnAssessmentByItsStartIdempotencyKey() {
    LocalDateTime startedAt = LocalDateTime.of(2026, 7, 28, 10, 0);
    Child child = childRepository.save(child());
    DrawingType htpType = drawingTypeRepository.save(htpType());
    DrawingSession session =
        drawingSessionRepository.save(
            DrawingSession.start(
                child, htpType, DrawingInputMethod.CANVAS, startedAt, "htp-house-key"));
    HtpAssessment assessment =
        htpAssessmentRepository.save(
            HtpAssessment.start(
                child, htpType, session, startedAt, startedAt.plusHours(24), "htp-start-key"));

    entityManager.flush();
    entityManager.clear();

    assertThat(htpAssessmentRepository.findByIdempotencyKey("htp-start-key"))
        .map(HtpAssessment::getId)
        .contains(assessment.getId());
  }

  private Child child() {
    return ChildFixture.create(
        null,
        LocalDate.of(2018, 7, 28),
        ChildTutorialStatus.COMPLETED,
        ChildProfileStatus.ACTIVE,
        null);
  }

  private DrawingType htpType() {
    return DrawingTypeFixture.create(
        null, "HTP", "집·나무·사람 그림", DrawingTypeSelectableBy.GUARDIAN, 4, 12, true);
  }
}
