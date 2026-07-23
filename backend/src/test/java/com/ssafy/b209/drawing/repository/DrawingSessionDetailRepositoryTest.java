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
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class DrawingSessionDetailRepositoryTest {

  private static final LocalDateTime BASE_TIME = LocalDateTime.of(2026, 7, 23, 1, 0);

  @Autowired private EntityManager entityManager;
  @Autowired private ChildRepository childRepository;
  @Autowired private DrawingTypeRepository drawingTypeRepository;
  @Autowired private DrawingSessionRepository drawingSessionRepository;
  @Autowired private DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  @Autowired private DrawingAssetRepository drawingAssetRepository;
  @Autowired private DrawingAnalysisRepository drawingAnalysisRepository;
  @Autowired private ReportRepository reportRepository;

  private DrawingSession session;

  @BeforeEach
  void setUp() {
    Child child =
        childRepository.save(
            ChildFixture.create(
                null,
                LocalDate.of(2018, 7, 23),
                ChildTutorialStatus.COMPLETED,
                ChildProfileStatus.ACTIVE,
                null));
    DrawingType drawingType =
        drawingTypeRepository.save(
            DrawingTypeFixture.create(
                null, "HOUSE-DETAIL", "집", DrawingTypeSelectableBy.BOTH, 6, 10, true));
    session =
        drawingSessionRepository.save(
            DrawingSession.start(
                child, drawingType, DrawingInputMethod.CANVAS, BASE_TIME, "detail-session-key"));
  }

  @Test
  void findsSessionDetailAndPreservesEmotionSelectionOrder() {
    drawingSessionEmotionRepository.save(
        DrawingSessionEmotion.create(session, DrawingEmotionCode.CALM, 1));
    drawingSessionEmotionRepository.save(
        DrawingSessionEmotion.create(session, DrawingEmotionCode.HAPPY, 0));
    entityManager.flush();
    entityManager.clear();

    assertThat(drawingSessionRepository.findDetailById(session.getId())).isPresent();
    assertThat(
            drawingSessionEmotionRepository.findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(
                session.getId()))
        .extracting(DrawingSessionEmotion::getEmotionCode)
        .containsExactly(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM);
  }

  @Test
  void findsLatestAssetAnalysisAndReportByTimeThenId() {
    DrawingAsset olderAsset = saveDraft(1, BASE_TIME.plusMinutes(1));
    DrawingAsset latestAsset = saveDraft(2, BASE_TIME.plusMinutes(2));
    DrawingAnalysis olderAnalysis =
        saveAnalysis(olderAsset, "analysis-old", BASE_TIME.plusMinutes(3));
    DrawingAnalysis latestAnalysis =
        saveAnalysis(latestAsset, "analysis-latest", BASE_TIME.plusMinutes(4));
    reportRepository.save(Report.generating(session, olderAnalysis, 1, BASE_TIME.plusMinutes(5)));
    Report latestReport =
        reportRepository.save(
            Report.generating(session, latestAnalysis, 2, BASE_TIME.plusMinutes(6)));
    entityManager.flush();
    entityManager.clear();

    assertThat(
            drawingAssetRepository
                .findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(session.getId())
                .orElseThrow()
                .getId())
        .isEqualTo(latestAsset.getId());
    assertThat(
            drawingAnalysisRepository
                .findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(session.getId())
                .orElseThrow()
                .getId())
        .isEqualTo(latestAnalysis.getId());
    assertThat(
            reportRepository
                .findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(session.getId())
                .orElseThrow()
                .getId())
        .isEqualTo(latestReport.getId());
  }

  @Test
  void excludesSoftDeletedSessionFromDetailLookup() {
    entityManager.flush();
    entityManager
        .createNativeQuery("update drawing_sessions set deleted_at = ? where id = ?")
        .setParameter(1, BASE_TIME.plusHours(1))
        .setParameter(2, session.getId())
        .executeUpdate();
    entityManager.clear();

    assertThat(drawingSessionRepository.findDetailById(session.getId())).isEmpty();
  }

  private DrawingAsset saveDraft(int version, LocalDateTime createdAt) {
    return drawingAssetRepository.save(
        DrawingAsset.draft(
            session,
            version,
            "drafts/" + session.getId() + "/" + version + ".png",
            "image/png",
            1024,
            String.valueOf(version).repeat(64),
            (long) version,
            createdAt,
            createdAt));
  }

  private DrawingAnalysis saveAnalysis(
      DrawingAsset asset, String requestId, LocalDateTime requestedAt) {
    return drawingAnalysisRepository.save(
        DrawingAnalysis.processing(
            session,
            asset,
            DrawingAnalysisScope.INTERMEDIATE,
            DrawingAnalysisType.OBJECT_DETECTION,
            requestId,
            requestedAt));
  }
}
