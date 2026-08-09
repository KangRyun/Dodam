package com.ssafy.b209.report.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
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
import com.ssafy.b209.drawing.htp.domain.HtpAssessment;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import jakarta.persistence.EntityManager;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import org.hibernate.SessionFactory;
import org.hibernate.stat.Statistics;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * 그림 심리 상담 리포트가 활동 세션을 기준으로 탐지 객체를 한 번에 읽는지 확인한다.
 *
 * <p>집·나무·사람 활동은 세 세션의 결과를 모아야 해서 세션마다 조회를 반복하기 쉬운 자리다. Hibernate 통계로 실행 Statement 수를 고정해 배치 조회가
 * 나중에 깨지지 않게 한다.
 */
@DataJpaTest(properties = "spring.jpa.properties.hibernate.generate_statistics=true")
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class ReportDetectedObjectViewRepositoryTest {

  private static final LocalDateTime STARTED_AT = LocalDateTime.parse("2026-08-02T01:00:00");

  @Autowired private EntityManager entityManager;
  @Autowired private ChildRepository childRepository;
  @Autowired private DrawingTypeRepository drawingTypeRepository;
  @Autowired private DrawingSessionRepository drawingSessionRepository;
  @Autowired private DrawingAssetRepository drawingAssetRepository;
  @Autowired private DrawingAnalysisRepository drawingAnalysisRepository;
  @Autowired private HtpAssessmentRepository htpAssessmentRepository;
  @Autowired private ReportDetectedObjectViewRepository detectedObjectRepository;

  private Child child;
  private int sequence;

  @BeforeEach
  void setUp() {
    child =
        childRepository.save(
            ChildFixture.create(
                null,
                LocalDate.of(2018, 8, 2),
                ChildTutorialStatus.COMPLETED,
                ChildProfileStatus.ACTIVE,
                null));
  }

  @Test
  void collectsEveryHtpSessionInSubjectOrderEvenWhenOneSessionHasNoDetection() {
    DrawingType htpType = drawingTypeRepository.save(htpType());
    DrawingSession houseSession = startSession(htpType);
    HtpAssessment assessment =
        htpAssessmentRepository.save(
            HtpAssessment.start(
                child, htpType, houseSession, STARTED_AT, STARTED_AT.plusHours(24), "htp-start"));
    DrawingSession treeSession = advanceTo(assessment, houseSession, htpType);
    DrawingSession personSession = advanceTo(assessment, treeSession, htpType);

    succeededDetection(treeSession, STARTED_AT.plusMinutes(2), "나무");
    succeededDetection(houseSession, STARTED_AT.plusMinutes(1), "집", "창문");
    flushAndClear();

    assertThat(objectNamesOf(houseSession)).containsExactly("집", "창문", "나무");
    assertThat(objectNamesOf(personSession)).containsExactly("집", "창문", "나무");
  }

  @Test
  void readsEveryHtpSessionWithASingleStatement() {
    DrawingType htpType = drawingTypeRepository.save(htpType());
    DrawingSession houseSession = startSession(htpType);
    HtpAssessment assessment =
        htpAssessmentRepository.save(
            HtpAssessment.start(
                child, htpType, houseSession, STARTED_AT, STARTED_AT.plusHours(24), "htp-start"));
    DrawingSession treeSession = advanceTo(assessment, houseSession, htpType);
    advanceTo(assessment, treeSession, htpType);

    succeededDetection(houseSession, STARTED_AT.plusMinutes(1), "집");
    succeededDetection(treeSession, STARTED_AT.plusMinutes(2), "나무");
    flushAndClear();

    Statistics statistics =
        entityManager.getEntityManagerFactory().unwrap(SessionFactory.class).getStatistics();
    statistics.clear();
    detectedObjectRepository.findActivityDetectedObjects(houseSession.getId());

    assertThat(statistics.getPrepareStatementCount()).isEqualTo(1L);
  }

  @Test
  void readsOnlyTheOwnSessionForNonHtpActivity() {
    DrawingType diaryType = drawingTypeRepository.save(diaryType());
    DrawingSession session = startSession(diaryType);
    DrawingSession otherSession = startSession(diaryType);

    succeededDetection(session, STARTED_AT.plusMinutes(1), "강아지");
    succeededDetection(otherSession, STARTED_AT.plusMinutes(1), "다른 활동의 고양이");
    flushAndClear();

    assertThat(objectNamesOf(session)).containsExactly("강아지");
  }

  @Test
  void excludesIntermediateDraftsAndReportAnalyses() {
    DrawingType diaryType = drawingTypeRepository.save(diaryType());
    DrawingSession session = startSession(diaryType);

    detection(
        session,
        DrawingAnalysisScope.INTERMEDIATE,
        DrawingAnalysisType.OBJECT_DETECTION,
        DrawingAnalysisState.SUCCESS,
        STARTED_AT.plusMinutes(9),
        "그리는 중 초안");
    detection(
        session,
        DrawingAnalysisScope.FINAL,
        DrawingAnalysisType.ACTIVITY_REPORT,
        DrawingAnalysisState.SUCCESS,
        STARTED_AT.plusMinutes(8),
        "리포트 생성 분석");
    detection(
        session,
        DrawingAnalysisScope.FINAL,
        DrawingAnalysisType.OBJECT_DETECTION,
        DrawingAnalysisState.PARTIAL_SUCCESS,
        STARTED_AT.plusMinutes(1),
        "부분 성공 결과");
    flushAndClear();

    assertThat(objectNamesOf(session)).containsExactly("부분 성공 결과");
  }

  @Test
  void ordersTheNewestDetectionAnalysisOfASessionFirst() {
    DrawingType diaryType = drawingTypeRepository.save(diaryType());
    DrawingSession session = startSession(diaryType);

    DrawingAnalysis older = succeededDetection(session, STARTED_AT.plusMinutes(1), "지난 결과");
    DrawingAnalysis newer = succeededDetection(session, STARTED_AT.plusMinutes(5), "최신 결과");
    flushAndClear();

    assertThat(detectedObjectRepository.findActivityDetectedObjects(session.getId()))
        .extracting(ReportDetectedObjectRow::analysisId)
        .containsExactly(newer.getId(), older.getId());
  }

  @Test
  void returnsNothingWhenActivityHasNoDetectionAnalysis() {
    DrawingType diaryType = drawingTypeRepository.save(diaryType());
    DrawingSession session = startSession(diaryType);
    flushAndClear();

    assertThat(detectedObjectRepository.findActivityDetectedObjects(session.getId())).isEmpty();
  }

  private List<String> objectNamesOf(DrawingSession session) {
    return detectedObjectRepository.findActivityDetectedObjects(session.getId()).stream()
        .map(ReportDetectedObjectRow::objectName)
        .toList();
  }

  private DrawingSession advanceTo(
      HtpAssessment assessment, DrawingSession currentSession, DrawingType htpType) {
    currentSession.startDrawingAnalysis();
    currentSession.finishDrawingAnalysis(true);
    assessment
        .getCurrentStep()
        .completeDrawingSession("htp-complete-" + currentSession.getId(), STARTED_AT);
    DrawingSession nextSession = startSession(htpType);
    assessment.advance(nextSession, STARTED_AT);
    return nextSession;
  }

  private DrawingSession startSession(DrawingType drawingType) {
    return drawingSessionRepository.save(
        DrawingSession.start(
            child, drawingType, DrawingInputMethod.CANVAS, STARTED_AT, "session-key-" + next()));
  }

  private DrawingAnalysis succeededDetection(
      DrawingSession session, LocalDateTime requestedAt, String... objectNames) {
    return detection(
        session,
        DrawingAnalysisScope.FINAL,
        DrawingAnalysisType.OBJECT_DETECTION,
        DrawingAnalysisState.SUCCESS,
        requestedAt,
        objectNames);
  }

  private DrawingAnalysis detection(
      DrawingSession session,
      DrawingAnalysisScope scope,
      DrawingAnalysisType taskType,
      DrawingAnalysisState state,
      LocalDateTime requestedAt,
      String... objectNames) {
    int suffix = next();
    DrawingAsset asset =
        drawingAssetRepository.save(
            DrawingAsset.snapshot(
                session,
                DrawingAssetType.FINAL,
                suffix,
                "drawing/final-" + suffix + ".png",
                "image/png",
                1024,
                "%064d".formatted(suffix),
                requestedAt,
                requestedAt));
    DrawingAnalysis analysis =
        DrawingAnalysis.processing(
            session, asset, scope, taskType, "analysis-key-" + suffix, requestedAt);
    List<DrawingDetectedObject> detections = new ArrayList<>();
    for (int order = 0; order < objectNames.length; order++) {
      detections.add(detectedObject(objectNames[order], order, requestedAt));
    }
    analysis.complete(state, "mock-detector", "1.0", detections, requestedAt.plusSeconds(1));
    return drawingAnalysisRepository.save(analysis);
  }

  private DrawingDetectedObject detectedObject(
      String objectName, int detectionOrder, LocalDateTime createdAt) {
    return DrawingDetectedObject.detected(
        "OBJ_" + detectionOrder,
        objectName,
        new BigDecimal("0.9000"),
        new BigDecimal("0.100000"),
        new BigDecimal("0.100000"),
        new BigDecimal("0.200000"),
        new BigDecimal("0.200000"),
        new BigDecimal("0.040000"),
        detectionOrder,
        "1.0",
        createdAt);
  }

  private int next() {
    return ++sequence;
  }

  private void flushAndClear() {
    entityManager.flush();
    entityManager.clear();
  }

  private DrawingType htpType() {
    return DrawingTypeFixture.create(
        null, "HTP", "집·나무·사람 그림", DrawingTypeSelectableBy.GUARDIAN, 4, 12, true);
  }

  private DrawingType diaryType() {
    return DrawingTypeFixture.create(
        null, "ART_DIARY", "그림일기", DrawingTypeSelectableBy.BOTH, 4, 12, true);
  }
}
