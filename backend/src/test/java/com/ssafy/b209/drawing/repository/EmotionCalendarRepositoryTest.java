package com.ssafy.b209.drawing.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.repository.ReportRepository;
import jakarta.persistence.EntityManager;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class EmotionCalendarRepositoryTest {

  /** KST 2026-07-01 00:00에 해당하는 UTC 저장 값이다. */
  private static final LocalDateTime FROM_INCLUSIVE = LocalDateTime.of(2026, 6, 30, 15, 0);

  /** KST 2026-08-01 00:00에 해당하는 UTC 저장 값이다. */
  private static final LocalDateTime TO_EXCLUSIVE = LocalDateTime.of(2026, 7, 31, 15, 0);

  @Autowired private EntityManager entityManager;
  @Autowired private ChildRepository childRepository;
  @Autowired private DrawingTypeRepository drawingTypeRepository;
  @Autowired private DrawingSessionRepository drawingSessionRepository;
  @Autowired private DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  @Autowired private DrawingAssetRepository drawingAssetRepository;
  @Autowired private DrawingAnalysisRepository drawingAnalysisRepository;
  @Autowired private ReportRepository reportRepository;

  private Child child;
  private Child otherChild;
  private DrawingType house;
  private Long childId;

  @BeforeEach
  void setUp() {
    child = saveChild();
    otherChild = saveChild();
    childId = child.getId();
    house =
        drawingTypeRepository.save(
            DrawingTypeFixture.create(
                null, "HOUSE", "집", DrawingTypeSelectableBy.BOTH, 6, 10, true));
  }

  @Test
  void returnsOneRowPerSelectedEmotionOfAnActivity() {
    DrawingSession session =
        saveSession(child, LocalDateTime.of(2026, 7, 3, 1, 0), "calendar-multi");
    saveEmotion(session, DrawingEmotionCode.CALM, 1);
    saveEmotion(session, DrawingEmotionCode.HAPPY, 0);
    flushAndClear();

    List<EmotionCalendarRowProjection> rows = findRows();

    assertThat(rows).hasSize(2);
    assertThat(rows)
        .extracting(EmotionCalendarRowProjection::getEmotionCode)
        .containsExactly("HAPPY", "CALM");
    assertThat(rows)
        .extracting(EmotionCalendarRowProjection::getDrawingSessionId)
        .containsOnly(session.getId());
  }

  @Test
  void returnsASingleRowWithoutEmotionCodeWhenNoEmotionWasSelected() {
    DrawingSession session =
        saveSession(child, LocalDateTime.of(2026, 7, 3, 1, 0), "calendar-no-emotion");
    flushAndClear();

    List<EmotionCalendarRowProjection> rows = findRows();

    assertThat(rows).hasSize(1);
    assertThat(rows.get(0).getDrawingSessionId()).isEqualTo(session.getId());
    assertThat(rows.get(0).getEmotionCode()).isNull();
    assertThat(rows.get(0).getCompletedReportCount()).isZero();
  }

  @Test
  void ordersRowsByStartedAtThenSelectionOrder() {
    DrawingSession later = saveSession(child, LocalDateTime.of(2026, 7, 3, 9, 0), "calendar-later");
    saveEmotion(later, DrawingEmotionCode.SCARED, 1);
    saveEmotion(later, DrawingEmotionCode.SAD, 0);
    DrawingSession earlier =
        saveSession(child, LocalDateTime.of(2026, 7, 3, 1, 0), "calendar-earlier");
    saveEmotion(earlier, DrawingEmotionCode.HAPPY, 0);
    flushAndClear();

    List<EmotionCalendarRowProjection> rows = findRows();

    assertThat(rows)
        .extracting(EmotionCalendarRowProjection::getEmotionCode)
        .containsExactly("HAPPY", "SAD", "SCARED");
  }

  @Test
  void excludesSoftDeletedAndDeletedAndAbandonedActivities() {
    DrawingSession kept = saveSession(child, LocalDateTime.of(2026, 7, 3, 1, 0), "calendar-kept");
    DrawingSession failed =
        saveSession(child, LocalDateTime.of(2026, 7, 4, 1, 0), "calendar-failed");
    DrawingSession softDeleted =
        saveSession(child, LocalDateTime.of(2026, 7, 5, 1, 0), "calendar-soft-deleted");
    DrawingSession deletedStatus =
        saveSession(child, LocalDateTime.of(2026, 7, 6, 1, 0), "calendar-deleted");
    DrawingSession abandoned =
        saveSession(child, LocalDateTime.of(2026, 7, 7, 1, 0), "calendar-abandoned");
    entityManager.flush();
    setStatus(failed.getId(), "FAILED");
    setStatus(deletedStatus.getId(), "DELETED");
    setStatus(abandoned.getId(), "ABANDONED");
    softDelete(softDeleted.getId(), LocalDateTime.of(2026, 7, 5, 2, 0));
    entityManager.clear();

    List<EmotionCalendarRowProjection> rows = findRows();

    assertThat(rows)
        .extracting(EmotionCalendarRowProjection::getDrawingSessionId)
        .containsExactly(kept.getId(), failed.getId());
  }

  @Test
  void excludesActivitiesOutsideTheRequestedRangeAndOtherChildren() {
    DrawingSession beforeRange =
        saveSession(child, LocalDateTime.of(2026, 6, 30, 14, 59), "calendar-before");
    DrawingSession firstInRange =
        saveSession(child, LocalDateTime.of(2026, 6, 30, 15, 0), "calendar-first");
    DrawingSession lastInRange =
        saveSession(child, LocalDateTime.of(2026, 7, 31, 14, 59), "calendar-last");
    DrawingSession afterRange =
        saveSession(child, LocalDateTime.of(2026, 7, 31, 15, 0), "calendar-after");
    DrawingSession otherChildSession =
        saveSession(otherChild, LocalDateTime.of(2026, 7, 10, 1, 0), "calendar-other-child");
    flushAndClear();

    List<EmotionCalendarRowProjection> rows = findRows();

    assertThat(rows)
        .extracting(EmotionCalendarRowProjection::getDrawingSessionId)
        .containsExactly(firstInRange.getId(), lastInRange.getId())
        .doesNotContain(beforeRange.getId(), afterRange.getId(), otherChildSession.getId());
  }

  @Test
  void countsOnlyCompletedReportsWithoutMultiplyingRowsByEmotions() {
    DrawingSession session =
        saveSession(child, LocalDateTime.of(2026, 7, 3, 1, 0), "calendar-reports");
    saveEmotion(session, DrawingEmotionCode.HAPPY, 0);
    saveEmotion(session, DrawingEmotionCode.CALM, 1);
    DrawingAnalysis analysis = saveAnalysis(session, "calendar-analysis-1");
    saveCompletedReport(session, analysis, 1);
    saveFailedReport(session, analysis, 2);
    flushAndClear();

    List<EmotionCalendarRowProjection> rows = findRows();

    assertThat(rows).hasSize(2);
    assertThat(rows)
        .extracting(EmotionCalendarRowProjection::getCompletedReportCount)
        .containsOnly(1L);
  }

  private List<EmotionCalendarRowProjection> findRows() {
    return drawingSessionRepository.findEmotionCalendarRows(childId, FROM_INCLUSIVE, TO_EXCLUSIVE);
  }

  private Child saveChild() {
    return childRepository.save(
        ChildFixture.create(
            null,
            LocalDate.of(2018, 7, 24),
            ChildTutorialStatus.COMPLETED,
            ChildProfileStatus.ACTIVE,
            null));
  }

  private DrawingSession saveSession(Child owner, LocalDateTime startedAt, String key) {
    return drawingSessionRepository.save(
        DrawingSession.start(owner, house, DrawingInputMethod.CANVAS, startedAt, key));
  }

  private void saveEmotion(DrawingSession session, DrawingEmotionCode code, int selectionOrder) {
    drawingSessionEmotionRepository.save(
        DrawingSessionEmotion.create(session, code, selectionOrder));
  }

  private DrawingAnalysis saveAnalysis(DrawingSession session, String key) {
    DrawingAsset asset =
        drawingAssetRepository.save(
            DrawingAsset.draft(
                session,
                1,
                "drafts/" + session.getId() + "/1.png",
                "image/png",
                1024,
                "1".repeat(64),
                1,
                LocalDateTime.of(2026, 7, 3, 1, 10),
                LocalDateTime.of(2026, 7, 3, 1, 10)));
    return drawingAnalysisRepository.save(
        DrawingAnalysis.processing(
            session,
            asset,
            DrawingAnalysisScope.FINAL,
            DrawingAnalysisType.OBJECT_DETECTION,
            key,
            LocalDateTime.of(2026, 7, 3, 1, 20)));
  }

  private void saveCompletedReport(DrawingSession session, DrawingAnalysis analysis, int version) {
    Report report =
        Report.generating(session, analysis, version, LocalDateTime.of(2026, 7, 3, 1, 30));
    report.complete(false, "참고용 자료입니다.", LocalDateTime.of(2026, 7, 3, 1, 40));
    reportRepository.save(report);
  }

  private void saveFailedReport(DrawingSession session, DrawingAnalysis analysis, int version) {
    Report report =
        Report.generating(session, analysis, version, LocalDateTime.of(2026, 7, 3, 1, 50));
    report.fail("생성에 실패했습니다.", "TIMEOUT", LocalDateTime.of(2026, 7, 3, 1, 55));
    reportRepository.save(report);
  }

  private void setStatus(Long sessionId, String status) {
    entityManager
        .createNativeQuery("update drawing_sessions set session_status = ? where id = ?")
        .setParameter(1, status)
        .setParameter(2, sessionId)
        .executeUpdate();
  }

  private void softDelete(Long sessionId, LocalDateTime deletedAt) {
    entityManager
        .createNativeQuery("update drawing_sessions set deleted_at = ? where id = ?")
        .setParameter(1, deletedAt)
        .setParameter(2, sessionId)
        .executeUpdate();
  }

  private void flushAndClear() {
    entityManager.flush();
    entityManager.clear();
  }
}
