package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.ReportActivityNoteView;
import com.ssafy.b209.report.domain.ReportActivitySummaryView;
import com.ssafy.b209.report.domain.ReportDetailView;
import com.ssafy.b209.report.domain.ReportDetectedObjectView;
import com.ssafy.b209.report.domain.ReportDrawingAssetView;
import com.ssafy.b209.report.domain.ReportDrawingEmotionView;
import com.ssafy.b209.report.domain.ReportDrawingSessionView;
import com.ssafy.b209.report.domain.ReportDrawingTypeView;
import com.ssafy.b209.report.domain.ReportFollowUpGuideView;
import com.ssafy.b209.report.domain.ReportKeyConversationView;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.exception.ReportDetailErrorCode;
import com.ssafy.b209.report.repository.ReportActivityNoteViewRepository;
import com.ssafy.b209.report.repository.ReportActivitySummaryViewRepository;
import com.ssafy.b209.report.repository.ReportConversationSummaryViewRepository;
import com.ssafy.b209.report.repository.ReportDetailViewRepository;
import com.ssafy.b209.report.repository.ReportDetectedObjectViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingAssetViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingEmotionViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingSessionViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingTypeViewRepository;
import com.ssafy.b209.report.repository.ReportFollowUpGuideViewRepository;
import com.ssafy.b209.report.repository.ReportKeyConversationViewRepository;
import java.lang.reflect.Constructor;
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
            detectedObjectRepository);
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
            List.of(
                asset("FINAL", 1, "https://cdn.example/final-v1.png"),
                asset("FINAL", 2, "https://cdn.example/final-v2.png"),
                asset("THUMBNAIL", 1, "https://cdn.example/thumb.png")));
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
    when(detectedObjectRepository.findByAnalysisIdOrderByDetectionOrderAsc(ANALYSIS_ID))
        .thenReturn(List.of(detectedObject("집", 0), detectedObject("나무", 1)));

    ReportDetailResponse response = service.getReport(GUARDIAN_ID, REPORT_ID);

    assertThat(response.reportId()).isEqualTo(REPORT_ID);
    assertThat(response.reportStatus()).isEqualTo("COMPLETED");
    assertThat(response.drawingSession().drawingTypeCode()).isEqualTo("HOUSE_TREE_PERSON");
    assertThat(response.drawingSession().drawingTypeName()).isEqualTo("집-나무-사람");
    assertThat(response.drawingSession().durationMs()).isEqualTo(300000L);
    assertThat(response.drawing().finalImageUrl()).isEqualTo("https://cdn.example/final-v2.png");
    assertThat(response.drawing().thumbnailUrl()).isEqualTo("https://cdn.example/thumb.png");
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

  private ReportDrawingAssetView asset(String assetType, int version, String url) {
    ReportDrawingAssetView asset = instantiate(ReportDrawingAssetView.class);
    ReflectionTestUtils.setField(asset, "drawingSessionId", SESSION_ID);
    ReflectionTestUtils.setField(asset, "assetType", assetType);
    ReflectionTestUtils.setField(asset, "assetVersion", version);
    ReflectionTestUtils.setField(asset, "fileUrl", url);
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

  private ReportDetectedObjectView detectedObject(String name, int order) {
    ReportDetectedObjectView object = instantiate(ReportDetectedObjectView.class);
    ReflectionTestUtils.setField(object, "analysisId", ANALYSIS_ID);
    ReflectionTestUtils.setField(object, "objectName", name);
    ReflectionTestUtils.setField(object, "detectionOrder", order);
    return object;
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
