package com.ssafy.b209.analysis.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import jakarta.persistence.EntityManager;
import java.math.BigDecimal;
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
class DrawingAnalysisRepositoryTest {

  private static final LocalDateTime REQUESTED_AT = LocalDateTime.parse("2026-07-22T05:00:00");

  @Autowired private EntityManager entityManager;
  @Autowired private ChildRepository childRepository;
  @Autowired private DrawingTypeRepository drawingTypeRepository;
  @Autowired private DrawingSessionRepository drawingSessionRepository;
  @Autowired private DrawingAssetRepository drawingAssetRepository;
  @Autowired private DrawingAnalysisRepository drawingAnalysisRepository;

  private DrawingSession session;
  private DrawingAnalysis analysis;

  @BeforeEach
  void setUp() {
    Child child =
        childRepository.save(
            ChildFixture.create(
                null,
                LocalDate.of(2018, 7, 22),
                ChildTutorialStatus.NOT_STARTED,
                ChildProfileStatus.ACTIVE,
                null));
    DrawingType drawingType =
        drawingTypeRepository.save(
            DrawingTypeFixture.create(
                null,
                "ANALYSIS_QUERY",
                "Analysis Query",
                DrawingTypeSelectableBy.BOTH,
                6,
                10,
                true));
    session =
        drawingSessionRepository.save(
            DrawingSession.start(
                child,
                drawingType,
                DrawingInputMethod.CANVAS,
                REQUESTED_AT.minusMinutes(5),
                "analysis-query-session"));
    DrawingAsset asset =
        drawingAssetRepository.save(
            DrawingAsset.snapshot(
                session,
                DrawingAssetType.FINAL,
                1,
                "drawing/final.png",
                "image/png",
                1024,
                "a".repeat(64),
                REQUESTED_AT.minusSeconds(1),
                REQUESTED_AT.minusSeconds(1)));
    analysis =
        DrawingAnalysis.processing(
            session,
            asset,
            DrawingAnalysisScope.FINAL,
            DrawingAnalysisType.OBJECT_DETECTION,
            "550e8400-e29b-41d4-a716-446655440000",
            REQUESTED_AT);
  }

  @Test
  void fetchesSessionAssetAndDetectionsInDisplayOrder() {
    analysis.succeed(
        "mock-drawing-detector",
        "1.0",
        List.of(detection("THIRD", 2), detection("FIRST", 0), detection("SECOND", 1)),
        REQUESTED_AT.plusSeconds(1));
    drawingAnalysisRepository.saveAndFlush(analysis);
    entityManager.clear();

    DrawingAnalysis found =
        drawingAnalysisRepository
            .findDetailBySessionIdAndAnalysisId(session.getId(), analysis.getId())
            .orElseThrow();

    assertThat(found.getDrawingSession().getId()).isEqualTo(session.getId());
    assertThat(found.getDrawingAsset().getId()).isNotNull();
    assertThat(found.getDetections())
        .extracting(DrawingDetectedObject::getLabel)
        .containsExactly("FIRST", "SECOND", "THIRD");
  }

  @Test
  void excludesAnalysisForAnotherOrDeletedSession() {
    drawingAnalysisRepository.saveAndFlush(analysis);
    Long sessionId = session.getId();
    Long analysisId = analysis.getId();
    entityManager.clear();

    assertThat(
            drawingAnalysisRepository.findDetailBySessionIdAndAnalysisId(
                sessionId + 999, analysisId))
        .isEmpty();

    entityManager
        .createNativeQuery("update drawing_sessions set deleted_at = ? where id = ?")
        .setParameter(1, REQUESTED_AT.plusMinutes(1))
        .setParameter(2, sessionId)
        .executeUpdate();
    entityManager.clear();

    assertThat(drawingAnalysisRepository.findDetailBySessionIdAndAnalysisId(sessionId, analysisId))
        .isEmpty();
  }

  private DrawingDetectedObject detection(String label, int displayOrder) {
    return DrawingDetectedObject.detected(
        label,
        new BigDecimal("0.95"),
        new BigDecimal("120"),
        new BigDecimal("80"),
        new BigDecimal("640"),
        new BigDecimal("520"),
        displayOrder,
        "1.0",
        REQUESTED_AT.plusSeconds(1));
  }
}
