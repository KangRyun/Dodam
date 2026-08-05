package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.drawing.service.DrawingAssetFileUrlFactory;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.ReportActivityNoteView;
import com.ssafy.b209.report.domain.ReportActivitySummaryView;
import com.ssafy.b209.report.domain.ReportDetailView;
import com.ssafy.b209.report.domain.ReportDrawingAssetView;
import com.ssafy.b209.report.domain.ReportDrawingEmotionView;
import com.ssafy.b209.report.domain.ReportDrawingSessionView;
import com.ssafy.b209.report.domain.ReportDrawingTypeView;
import com.ssafy.b209.report.domain.ReportDrawnItem;
import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import com.ssafy.b209.report.domain.ReportFollowUpGuideView;
import com.ssafy.b209.report.domain.ReportKeyConversationView;
import com.ssafy.b209.report.domain.ReportObservedFeatureView;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.exception.ReportDetailErrorCode;
import com.ssafy.b209.report.repository.ReportActivityNoteViewRepository;
import com.ssafy.b209.report.repository.ReportActivitySummaryViewRepository;
import com.ssafy.b209.report.repository.ReportConversationSummaryViewRepository;
import com.ssafy.b209.report.repository.ReportDetailViewRepository;
import com.ssafy.b209.report.repository.ReportDetectedObjectRow;
import com.ssafy.b209.report.repository.ReportDetectedObjectViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingAssetViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingEmotionViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingSessionViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingTypeViewRepository;
import com.ssafy.b209.report.repository.ReportDrawnItemRepository;
import com.ssafy.b209.report.repository.ReportFollowUpGuideViewRepository;
import com.ssafy.b209.report.repository.ReportKeyConversationViewRepository;
import com.ssafy.b209.report.repository.ReportObservedFeatureViewRepository;
import java.lang.reflect.Constructor;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.test.util.ReflectionTestUtils;

/** 리포트 상세 조회 서비스가 소유권을 검증하고 하위 데이터를 안전하게 조립하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class ReportDetailQueryServiceTest {
  private static final Long GUARDIAN_ID = 10L;
  private static final Long REPORT_ID = 500L;
  private static final Long SESSION_ID = 100L;
  private static final Long ANALYSIS_ID = 700L;
  private static final Long DETECTION_ANALYSIS_ID = 344L;
  private static final Long TREE_SESSION_ID = 101L;
  private static final Long PERSON_SESSION_ID = 102L;
  private static final Long TYPE_ID = 3L;
  private static final Long CHILD_ID = 1L;
  private static final LocalDateTime STARTED_AT = LocalDateTime.of(2026, 7, 21, 2, 0, 0);
  private static final LocalDateTime COMPLETED_AT = LocalDateTime.of(2026, 7, 21, 2, 5, 0);
  private static final LocalDateTime CREATED_AT = LocalDateTime.of(2026, 7, 21, 2, 6, 0);

  @Mock private GuardianResourceAccessRepository guardianAccessRepository;
  @Mock private ReportDetailViewRepository reportRepository;
  @Mock private ReportDrawingSessionViewRepository drawingSessionRepository;
  @Mock private ReportDrawingTypeViewRepository drawingTypeRepository;
  @Mock private ReportDrawingAssetViewRepository assetRepository;
  @Mock private ReportDrawingEmotionViewRepository emotionRepository;
  @Mock private ReportActivitySummaryViewRepository activitySummaryRepository;
  @Mock private ReportActivityNoteViewRepository activityNoteRepository;
  @Mock private ReportKeyConversationViewRepository keyConversationRepository;
  @Mock private ReportFollowUpGuideViewRepository followUpGuideRepository;
  @Mock private ReportConversationSummaryViewRepository conversationSummaryRepository;
  @Mock private ReportDetectedObjectViewRepository detectedObjectRepository;
  @Mock private ReportDrawnItemRepository drawnItemRepository;
  @Mock private ReportObservedFeatureViewRepository observedFeatureRepository;

  @Mock
  private com.ssafy.b209.report.repository.ReportPublicInterpretationRepository
      interpretationRepository;

  @Mock
  private com.ssafy.b209.report.repository.ReportEvidenceItemRepository evidenceItemRepository;

  @Mock private com.ssafy.b209.report.repository.ReportParentGuideRepository parentGuideRepository;

  @Mock private com.ssafy.b209.report.repository.ReportCrisisAlertRepository crisisAlertRepository;

  @Mock
  private com.ssafy.b209.report.repository.ReportMessageConfirmationViewRepository
      messageConfirmationRepository;

  @Mock private com.ssafy.b209.report.repository.ReportSubjectRepository subjectRepository;

  @Mock private com.ssafy.b209.report.repository.ReportReferenceRepository referenceRepository;

  @Mock private com.ssafy.b209.report.repository.ReportHtpStepViewRepository htpStepRepository;

  @Mock private com.ssafy.b209.report.repository.ReportChildViewRepository childRepository;

  private ReportDetailQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new ReportDetailQueryService(
            guardianAccessRepository,
            reportRepository,
            drawingSessionRepository,
            drawingTypeRepository,
            assetRepository,
            emotionRepository,
            activitySummaryRepository,
            activityNoteRepository,
            keyConversationRepository,
            followUpGuideRepository,
            conversationSummaryRepository,
            detectedObjectRepository,
            drawnItemRepository,
            observedFeatureRepository,
            interpretationRepository,
            evidenceItemRepository,
            parentGuideRepository,
            crisisAlertRepository,
            messageConfirmationRepository,
            subjectRepository,
            referenceRepository,
            htpStepRepository,
            childRepository,
            new DrawingAssetFileUrlFactory());
  }

  @Test
  void throwsWhenReportMissing() {
    when(reportRepository.findById(REPORT_ID)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.getReport(GUARDIAN_ID, REPORT_ID))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ReportDetailErrorCode.REPORT_NOT_FOUND);
  }

  @Test
  void throwsNotFoundWhenReportHidden() {
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.HIDDEN, "한계 문구")));

    assertThatThrownBy(() -> service.getReport(GUARDIAN_ID, REPORT_ID))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ReportDetailErrorCode.REPORT_NOT_FOUND);
  }

  @Test
  void throwsAccessDeniedWhenGuardianNotRelated() {
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.COMPLETED, "한계 문구")));
    when(guardianAccessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(false);

    assertThatThrownBy(() -> service.getReport(GUARDIAN_ID, REPORT_ID))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ReportDetailErrorCode.REPORT_ACCESS_DENIED);
  }

  @Test
  void assemblesCompletedReportSections() {
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.COMPLETED, "첫 번째 한계\n두 번째 한계")));
    when(guardianAccessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(true);
    when(drawingSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
    when(drawingTypeRepository.findById(TYPE_ID))
        .thenReturn(Optional.of(drawingType("HOUSE_TREE_PERSON", "집-나무-사람")));
    when(assetRepository.findByDrawingSessionIdAndAssetTypeInOrderByAssetVersionAsc(any(), any()))
        .thenReturn(
            List.of(asset(11L, "FINAL", 1), asset(12L, "FINAL", 2), asset(13L, "THUMBNAIL", 1)));
    when(emotionRepository.findByDrawingSessionIdOrderBySelectionOrderAsc(SESSION_ID))
        .thenReturn(List.of(emotion("HAPPY", (short) 0), emotion("CALM", (short) 1)));
    when(activitySummaryRepository.findById(REPORT_ID)).thenReturn(Optional.of(activitySummary()));
    when(activityNoteRepository.findByReportIdOrderByDisplayOrderAsc(REPORT_ID))
        .thenReturn(List.of(note("멈춤 4회 관찰", (short) 0)));
    when(keyConversationRepository.findByReportIdOrderByDisplayOrderAsc(REPORT_ID))
        .thenReturn(
            List.of(
                keyConversation(804L, "친구랑 있어서 좋아", "VOICE_ANSWER", (short) 0),
                keyConversation(806L, "파란색", "OPTION_ANSWER", (short) 1)));
    when(followUpGuideRepository.findByReportIdOrderByDisplayOrderAsc(REPORT_ID))
        .thenReturn(List.of(guide("오늘 그림에 대해 함께 이야기해 보세요", (short) 0)));
    when(detectedObjectRepository.findActivityDetectedObjects(SESSION_ID))
        .thenReturn(List.of(detectedObject(SESSION_ID, "집"), detectedObject(SESSION_ID, "나무")));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.reportId()).isEqualTo(REPORT_ID);
    assertThat(response.reportStatus()).isEqualTo("COMPLETED");
    assertThat(response.drawingSession().drawingTypeCode()).isEqualTo("HOUSE_TREE_PERSON");
    assertThat(response.drawingSession().drawingTypeName()).isEqualTo("집-나무-사람");
    assertThat(response.drawingSession().durationMs()).isEqualTo(300000L);
    assertThat(response.drawing().finalImageUrl()).isEqualTo("/api/v1/drawing-assets/12/file");
    assertThat(response.drawing().thumbnailUrl()).isEqualTo("/api/v1/drawing-assets/13/file");
    assertThat(response.childExpression().selectedEmotions()).containsExactly("HAPPY", "CALM");
    assertThat(response.childExpression().expressedEmotionText()).isEqualTo("행복한 하루였어요");
    assertThat(response.childExpression().representativeUtterances()).hasSize(2);
    assertThat(response.childExpression().representativeUtterances().get(0).source())
        .isEqualTo("STT");
    assertThat(response.childExpression().representativeUtterances().get(0).sttNeedsConfirmation())
        .isFalse();
    assertThat(response.childExpression().representativeUtterances().get(1).source())
        .isEqualTo("TEXT");
    assertThat(response.activityFacts().detectedObjects()).containsExactly("집", "나무");
    assertThat(response.activityFacts().drawingDurationMs()).isEqualTo(295000L);
    assertThat(response.activityFacts().pauseCount()).isEqualTo(4);
    assertThat(response.activityFacts().pressureAvailable()).isTrue();
    assertThat(response.activityFacts().notes()).containsExactly("멈춤 4회 관찰");
    assertThat(response.conversationSummary().questionCount()).isEqualTo(5);
    assertThat(response.conversationSummary().summary()).isEqualTo("아이가 편안하게 대화했습니다");
    assertThat(response.guardianConversationGuide()).containsExactly("오늘 그림에 대해 함께 이야기해 보세요");
    assertThat(response.limitations()).containsExactly("첫 번째 한계", "두 번째 한계");
    assertThat(response.expertReview().status()).isEqualTo("NOT_REQUESTED");
    assertThat(response.expertReview().available()).isFalse();
    assertThat(response.createdAt()).isEqualTo(CREATED_AT);
  }

  @Test
  void returnsPartialSectionsWhenSubDataMissing() {
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.GENERATING, "리포트 생성이 완료되지 않았습니다.")));
    when(guardianAccessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(true);
    when(drawingSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
    when(drawingTypeRepository.findById(TYPE_ID)).thenReturn(Optional.empty());
    when(activitySummaryRepository.findById(REPORT_ID)).thenReturn(Optional.empty());

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.reportStatus()).isEqualTo("GENERATING");
    assertThat(response.drawingSession().drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.drawingSession().drawingTypeCode()).isNull();
    assertThat(response.drawing().finalImageUrl()).isNull();
    assertThat(response.childExpression().representativeUtterances()).isEmpty();
    assertThat(response.activityFacts().detectedObjects()).isEmpty();
    assertThat(response.activityFacts().drawingDurationMs()).isNull();
    assertThat(response.activityFacts().pressureAvailable()).isFalse();
    assertThat(response.conversationSummary().questionCount()).isNull();
    assertThat(response.conversationSummary().summary()).isNull();
    assertThat(response.guardianConversationGuide()).isEmpty();
    assertThat(response.limitations()).containsExactly("리포트 생성이 완료되지 않았습니다.");
    assertThat(response.expertReview().status()).isEqualTo("NOT_REQUESTED");
  }

  @Test
  void usesFinalImageUrlAsThumbnailFallback() {
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.COMPLETED, null)));
    when(guardianAccessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(true);
    when(drawingSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
    when(assetRepository.findByDrawingSessionIdAndAssetTypeInOrderByAssetVersionAsc(any(), any()))
        .thenReturn(List.of(asset(12L, "FINAL", 2)));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.drawing().finalImageUrl()).isEqualTo("/api/v1/drawing-assets/12/file");
    assertThat(response.drawing().thumbnailUrl()).isEqualTo("/api/v1/drawing-assets/12/file");
  }

  @Test
  void usesUploadedOriginalAsFinalImageWhenSessionWasUploaded() {
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.COMPLETED, null)));
    when(guardianAccessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(true);
    when(drawingSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
    // 사진 업로드 세션은 최종 그림을 다시 그리지 않아 UPLOADED 원본만 남는다.
    when(assetRepository.findByDrawingSessionIdAndAssetTypeInOrderByAssetVersionAsc(any(), any()))
        .thenReturn(List.of(asset(21L, "UPLOADED", 1)));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.drawing().finalImageUrl()).isEqualTo("/api/v1/drawing-assets/21/file");
    assertThat(response.drawing().thumbnailUrl()).isEqualTo("/api/v1/drawing-assets/21/file");
  }

  @Test
  void prefersFinalSnapshotOverUploadedOriginalWhenBothExist() {
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.COMPLETED, null)));
    when(guardianAccessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(true);
    when(drawingSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
    when(assetRepository.findByDrawingSessionIdAndAssetTypeInOrderByAssetVersionAsc(any(), any()))
        .thenReturn(List.of(asset(21L, "UPLOADED", 1), asset(22L, "FINAL", 1)));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.drawing().finalImageUrl()).isEqualTo("/api/v1/drawing-assets/22/file");
  }

  @Test
  void listsDetectedObjectsOfEveryHtpSessionInSubjectOrder() {
    givenAccessibleReport();
    when(detectedObjectRepository.findActivityDetectedObjects(SESSION_ID))
        .thenReturn(
            List.of(
                detectedObject(SESSION_ID, "집"),
                detectedObject(SESSION_ID, "창문"),
                detectedObject(TREE_SESSION_ID, "나무"),
                detectedObject(PERSON_SESSION_ID, "사람")));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.activityFacts().detectedObjects()).containsExactly("집", "창문", "나무", "사람");
  }

  @Test
  void usesVlmDrawnItemsInStoredOrderAndDoesNotReadYoloLabels() {
    givenAccessibleReport();
    ReportDetailView report = report(ReportStatus.COMPLETED, "한계 문구");
    ReflectionTestUtils.setField(report, "hasDrawnItems", true);
    when(reportRepository.findById(REPORT_ID)).thenReturn(Optional.of(report));
    ReportDrawnItem house = mock(ReportDrawnItem.class);
    ReportDrawnItem roof = mock(ReportDrawnItem.class);
    ReportDrawnItem tree = mock(ReportDrawnItem.class);
    when(house.getName()).thenReturn("집");
    when(roof.getName()).thenReturn("빨간 지붕");
    when(tree.getName()).thenReturn("나무");
    when(drawnItemRepository.findByReportIdOrderByDisplayOrderAsc(REPORT_ID))
        .thenReturn(List.of(house, roof, tree));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.activityFacts().detectedObjects()).containsExactly("집", "빨간 지붕", "나무");
    verifyNoInteractions(detectedObjectRepository);
  }

  @Test
  void keepsAnExplicitEmptyVlmResultEmptyWithoutYoloFallback() {
    givenAccessibleReport();
    ReportDetailView report = report(ReportStatus.COMPLETED, "한계 문구");
    ReflectionTestUtils.setField(report, "hasDrawnItems", true);
    when(reportRepository.findById(REPORT_ID)).thenReturn(Optional.of(report));
    when(drawnItemRepository.findByReportIdOrderByDisplayOrderAsc(REPORT_ID)).thenReturn(List.of());

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.activityFacts().detectedObjects()).isEmpty();
    verifyNoInteractions(detectedObjectRepository);
  }

  @Test
  void keepsOnlyTheLatestDetectionAnalysisOfEachSession() {
    givenAccessibleReport();
    when(detectedObjectRepository.findActivityDetectedObjects(SESSION_ID))
        .thenReturn(
            List.of(
                detectedObject(SESSION_ID, 344L, "집"),
                detectedObject(SESSION_ID, 300L, "지난 분석 결과"),
                detectedObject(TREE_SESSION_ID, 345L, "나무")));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.activityFacts().detectedObjects()).containsExactly("집", "나무");
  }

  @Test
  void skipsSessionsWithoutDetectedObjectNames() {
    givenAccessibleReport();
    when(detectedObjectRepository.findActivityDetectedObjects(SESSION_ID))
        .thenReturn(
            List.of(
                detectedObject(SESSION_ID, "집"),
                detectedObject(TREE_SESSION_ID, null),
                detectedObject(PERSON_SESSION_ID, "   "),
                detectedObject(PERSON_SESSION_ID, "사람")));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.activityFacts().detectedObjects()).containsExactly("집", "사람");
  }

  @Test
  void returnsEmptyDetectedObjectsWhenActivityHasNoObjectDetectionAnalysis() {
    givenAccessibleReport();
    when(detectedObjectRepository.findActivityDetectedObjects(SESSION_ID)).thenReturn(List.of());

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.activityFacts().detectedObjects()).isEmpty();
  }

  @Test
  void returnsObservedFeaturesThatPassedReviewInDisplayOrder() {
    // 열리는 경로를 확인하는 검증이다. "노출되지 않는지"만 보는 검증만 있으면, 관찰 특징이 전부 숨겨진 채
    //   배포돼도 테스트는 전부 통과한다 — 실제로 그렇게 운영 리포트 97건이 아무에게도 도달하지 않았다.
    givenAccessibleReport();
    when(observedFeatureRepository.findByReportIdAndVisibilityScopeOrderByDisplayOrderAsc(
            REPORT_ID, ReportFeatureVisibility.REVIEWED_GUARDIAN))
        .thenReturn(
            List.of(
                observedFeature("집을 크게 그렸어요", "종이 가운데에 집을 크게 그렸어요.", "그림에서 확인했어요.", (short) 0),
                observedFeature(
                    "색을 여러 번 바꿨어요", "그리는 동안 색을 여러 번 바꿨어요.", "활동 기록에서 확인했어요.", (short) 1)));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.observedFeatures())
        .extracting(feature -> feature.title())
        .containsExactly("집을 크게 그렸어요", "색을 여러 번 바꿨어요");
    assertThat(response.observedFeatures().getFirst().evidenceSummary()).isEqualTo("그림에서 확인했어요.");
  }

  @Test
  void neverQueriesObservedFeaturesOutsideTheGuardianScope() {
    // EXPERT_ONLY 를 읽고 나서 거르는 방식이면 다음 사람이 필터를 빠뜨릴 수 있다. 아예 조회하지 않는다.
    givenAccessibleReport();

    service.getReport(GUARDIAN_ID, REPORT_ID);

    verify(observedFeatureRepository)
        .findByReportIdAndVisibilityScopeOrderByDisplayOrderAsc(
            REPORT_ID, ReportFeatureVisibility.REVIEWED_GUARDIAN);
    verifyNoMoreInteractions(observedFeatureRepository);
  }

  @Test
  void returnsEmptyObservedFeaturesWhenNothingPassedReview() {
    givenAccessibleReport();
    when(observedFeatureRepository.findByReportIdAndVisibilityScopeOrderByDisplayOrderAsc(
            REPORT_ID, ReportFeatureVisibility.REVIEWED_GUARDIAN))
        .thenReturn(List.of());

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.observedFeatures()).isEmpty();
  }

  private void givenAccessibleReport() {
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.COMPLETED, "한계 문구")));
    when(guardianAccessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(true);
    when(drawingSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
  }

  @Test
  void assemblesSubjectReportsInContractOrderWithResolvedInterpretationIndexes() {
    // 875 §5. 저장된 주제 스냅샷이 상세 응답에 HOUSE→TREE→PERSON 으로 실제로 나오는지 본다 —
    //   저장 쪽만 검증하면 조회가 List.of() 를 그대로 두고 있어도 초록이다(계약 §12-1 마지막 항목).
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.COMPLETED, null)));
    when(guardianAccessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(true);
    when(drawingSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
    when(drawingTypeRepository.findById(TYPE_ID))
        .thenReturn(Optional.of(drawingType("HTP", "집-나무-사람")));
    when(assetRepository.findByDrawingSessionIdAndAssetTypeInOrderByAssetVersionAsc(any(), any()))
        .thenReturn(List.of(asset(11L, "FINAL", 1)));
    when(htpStepRepository.countStepsSharingAssessment(SESSION_ID)).thenReturn(3L);

    // 공개 카드 두 장. 주제는 두 번째 카드만 가리킨다 — 응답 배열 인덱스로 1 이 나와야 한다.
    com.ssafy.b209.report.domain.ReportPublicInterpretation firstCard =
        publishedCard(901L, "EMOTION", "감정 표현");
    com.ssafy.b209.report.domain.ReportPublicInterpretation secondCard =
        publishedCard(902L, "RELATIONSHIP", "가족과의 연결");
    when(interpretationRepository.findByReportIdAndDisclosureStateOrderByDisplayOrderAsc(
            REPORT_ID, com.ssafy.b209.report.domain.ReportInterpretationDisclosureState.PUBLISHED))
        .thenReturn(List.of(firstCard, secondCard));
    when(subjectRepository.findByReportIdOrderByDisplayOrderAsc(REPORT_ID))
        .thenReturn(
            List.of(
                subject(0, "HOUSE", SESSION_ID, List.of("집을 가운데 크게 그렸어요."), secondCard),
                subject(1, "TREE", TREE_SESSION_ID, List.of("나무를 왼쪽에 그렸어요."), null),
                subject(2, "PERSON", PERSON_SESSION_ID, List.of(), null)));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.subjectReports())
        .extracting(com.ssafy.b209.report.dto.ReportSubjectResponse::subjectType)
        .containsExactly("HOUSE", "TREE", "PERSON");
    assertThat(response.subjectReports().get(0).visionObservations())
        .containsExactly("집을 가운데 크게 그렸어요.");
    // category 가 아니라 publicInterpretations 배열의 인덱스다(875 §5-1).
    assertThat(response.subjectReports().get(0).interpretationRefs()).containsExactly(1);
    assertThat(response.publicInterpretations().get(1).category()).isEqualTo("RELATIONSHIP");
    assertThat(response.subjectReports().get(1).interpretationRefs()).isEmpty();
    // 완성 그림 URL 은 주제의 세션에서 조회 시점에 발급한다.
    assertThat(response.subjectReports().get(0).imageUrl()).isNotNull();
    // 세 활동을 합친 기록임을 밝힌다(875 §8).
    assertThat(response.activityFacts().aggregatedHtp()).isTrue();
    assertThat(response.activityType()).isEqualTo("HTP");
  }

  @Test
  void omitsChildDisplayNameForDeletedChild() {
    // 보관 기간·탈퇴로 아동 데이터를 지웠는데 리포트 표지에 이름이 남으면 삭제가 끝나지 않은 것이 된다.
    when(reportRepository.findById(REPORT_ID))
        .thenReturn(Optional.of(report(ReportStatus.COMPLETED, null)));
    when(guardianAccessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(true);
    when(drawingSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
    when(childRepository.findById(CHILD_ID)).thenReturn(Optional.of(child("민준", true)));

    assertThat(service.getReport(GUARDIAN_ID, REPORT_ID).childDisplayName()).isNull();

    when(childRepository.findById(CHILD_ID)).thenReturn(Optional.of(child("민준", false)));
    assertThat(service.getReport(GUARDIAN_ID, REPORT_ID).childDisplayName()).isEqualTo("민준");
  }

  private com.ssafy.b209.report.domain.ReportChildView child(String nickname, boolean deleted) {
    com.ssafy.b209.report.domain.ReportChildView view =
        instantiate(com.ssafy.b209.report.domain.ReportChildView.class);
    ReflectionTestUtils.setField(view, "id", CHILD_ID);
    ReflectionTestUtils.setField(view, "nickname", nickname);
    ReflectionTestUtils.setField(view, "deletedAt", deleted ? CREATED_AT : null);
    return view;
  }

  private com.ssafy.b209.report.domain.ReportPublicInterpretation publishedCard(
      Long id, String category, String title) {
    com.ssafy.b209.report.domain.ReportPublicInterpretation card =
        com.ssafy.b209.report.domain.ReportPublicInterpretation.create(
            org.mockito.Mockito.mock(com.ssafy.b209.report.domain.Report.class),
            0,
            com.ssafy.b209.report.domain.ReportInterpretationCategory.valueOf(category),
            title,
            "그런 경향이 보일 수 있습니다.",
            "이번 활동에서 나타난 가능성입니다.",
            "가정에서 살펴봐 주세요.");
    ReflectionTestUtils.setField(card, "id", id);
    return card;
  }

  private com.ssafy.b209.report.domain.ReportSubject subject(
      int order,
      String subjectType,
      Long sessionId,
      List<String> observations,
      com.ssafy.b209.report.domain.ReportPublicInterpretation card) {
    com.ssafy.b209.report.domain.ReportSubject subject =
        com.ssafy.b209.report.domain.ReportSubject.create(
            org.mockito.Mockito.mock(com.ssafy.b209.report.domain.Report.class),
            order,
            subjectType,
            sessionId);
    observations.forEach(subject::addObservation);
    if (card != null) {
      subject.referenceInterpretation(card);
    }
    return subject;
  }

  private ReportDetailView report(ReportStatus status, String limitationsText) {
    ReportDetailView report = instantiate(ReportDetailView.class);
    ReflectionTestUtils.setField(report, "id", REPORT_ID);
    ReflectionTestUtils.setField(report, "drawingSessionId", SESSION_ID);
    ReflectionTestUtils.setField(report, "analysisId", ANALYSIS_ID);
    ReflectionTestUtils.setField(report, "reportVersion", 1);
    ReflectionTestUtils.setField(report, "status", status);
    ReflectionTestUtils.setField(report, "limitationsText", limitationsText);
    ReflectionTestUtils.setField(report, "createdAt", CREATED_AT);
    return report;
  }

  private ReportDrawingSessionView session() {
    ReportDrawingSessionView session = instantiate(ReportDrawingSessionView.class);
    ReflectionTestUtils.setField(session, "id", SESSION_ID);
    ReflectionTestUtils.setField(session, "childId", CHILD_ID);
    ReflectionTestUtils.setField(session, "drawingTypeId", TYPE_ID);
    ReflectionTestUtils.setField(session, "inputMethod", "CANVAS");
    ReflectionTestUtils.setField(session, "title", "우리 가족");
    ReflectionTestUtils.setField(session, "expressedEmotionText", "행복한 하루였어요");
    ReflectionTestUtils.setField(session, "startedAt", STARTED_AT);
    ReflectionTestUtils.setField(session, "completedAt", COMPLETED_AT);
    return session;
  }

  private ReportDrawingTypeView drawingType(String code, String name) {
    ReportDrawingTypeView type = instantiate(ReportDrawingTypeView.class);
    ReflectionTestUtils.setField(type, "id", TYPE_ID);
    ReflectionTestUtils.setField(type, "code", code);
    ReflectionTestUtils.setField(type, "name", name);
    return type;
  }

  private ReportDrawingAssetView asset(Long id, String assetType, int version) {
    ReportDrawingAssetView asset = instantiate(ReportDrawingAssetView.class);
    ReflectionTestUtils.setField(asset, "id", id);
    ReflectionTestUtils.setField(asset, "drawingSessionId", SESSION_ID);
    ReflectionTestUtils.setField(asset, "assetType", assetType);
    ReflectionTestUtils.setField(asset, "assetVersion", version);
    return asset;
  }

  private ReportDrawingEmotionView emotion(String code, short order) {
    ReportDrawingEmotionView emotion = instantiate(ReportDrawingEmotionView.class);
    ReflectionTestUtils.setField(emotion, "drawingSessionId", SESSION_ID);
    ReflectionTestUtils.setField(emotion, "emotionCode", code);
    ReflectionTestUtils.setField(emotion, "selectionOrder", order);
    return emotion;
  }

  private ReportActivitySummaryView activitySummary() {
    ReportActivitySummaryView summary = instantiate(ReportActivitySummaryView.class);
    ReflectionTestUtils.setField(summary, "reportId", REPORT_ID);
    ReflectionTestUtils.setField(summary, "drawingDurationMs", 295000L);
    ReflectionTestUtils.setField(summary, "pauseCount", 4);
    ReflectionTestUtils.setField(summary, "eraseCount", 2);
    ReflectionTestUtils.setField(summary, "pressureAvailable", true);
    ReflectionTestUtils.setField(summary, "conversationQuestionCount", 5);
    ReflectionTestUtils.setField(summary, "conversationAnsweredCount", 4);
    ReflectionTestUtils.setField(summary, "conversationSkippedCount", 1);
    ReflectionTestUtils.setField(summary, "conversationSummary", "아이가 편안하게 대화했습니다");
    return summary;
  }

  private ReportObservedFeatureView observedFeature(
      String title, String description, String evidenceSummary, short order) {
    ReportObservedFeatureView feature = instantiate(ReportObservedFeatureView.class);
    ReflectionTestUtils.setField(feature, "reportId", REPORT_ID);
    ReflectionTestUtils.setField(feature, "title", title);
    ReflectionTestUtils.setField(feature, "description", description);
    ReflectionTestUtils.setField(feature, "evidenceSummary", evidenceSummary);
    ReflectionTestUtils.setField(
        feature, "visibilityScope", ReportFeatureVisibility.REVIEWED_GUARDIAN);
    ReflectionTestUtils.setField(feature, "displayOrder", order);
    return feature;
  }

  private ReportActivityNoteView note(String text, short order) {
    ReportActivityNoteView note = instantiate(ReportActivityNoteView.class);
    ReflectionTestUtils.setField(note, "reportId", REPORT_ID);
    ReflectionTestUtils.setField(note, "noteText", text);
    ReflectionTestUtils.setField(note, "displayOrder", order);
    return note;
  }

  private ReportKeyConversationView keyConversation(
      Long answerMessageId, String answerText, String answerType, short order) {
    ReportKeyConversationView conversation = instantiate(ReportKeyConversationView.class);
    ReflectionTestUtils.setField(conversation, "reportId", REPORT_ID);
    ReflectionTestUtils.setField(conversation, "answerMessageId", answerMessageId);
    ReflectionTestUtils.setField(conversation, "answerText", answerText);
    ReflectionTestUtils.setField(conversation, "answerType", answerType);
    ReflectionTestUtils.setField(conversation, "displayOrder", order);
    return conversation;
  }

  private ReportFollowUpGuideView guide(String guidance, short order) {
    ReportFollowUpGuideView guide = instantiate(ReportFollowUpGuideView.class);
    ReflectionTestUtils.setField(guide, "reportId", REPORT_ID);
    ReflectionTestUtils.setField(guide, "guidance", guidance);
    ReflectionTestUtils.setField(guide, "displayOrder", order);
    return guide;
  }

  private ReportDetectedObjectRow detectedObject(Long drawingSessionId, String name) {
    return new ReportDetectedObjectRow(
        drawingSessionId, DETECTION_ANALYSIS_ID, name, new BigDecimal("0.80"));
  }

  private ReportDetectedObjectRow detectedObject(
      Long drawingSessionId, Long analysisId, String name) {
    return new ReportDetectedObjectRow(drawingSessionId, analysisId, name, new BigDecimal("0.80"));
  }

  private static <T> T instantiate(Class<T> type) {
    try {
      Constructor<T> constructor = type.getDeclaredConstructor();
      constructor.setAccessible(true);
      return constructor.newInstance();
    } catch (ReflectiveOperationException exception) {
      throw new IllegalStateException("Failed to instantiate " + type.getName(), exception);
    }
  }
}
