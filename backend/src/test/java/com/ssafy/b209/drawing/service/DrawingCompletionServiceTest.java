package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.CompleteDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingCompletionResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.repository.ReportRepository;
import com.ssafy.b209.report.service.ReportGenerationRequestedEvent;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class DrawingCompletionServiceTest {

  private static final long SESSION_ID = 100L;
  private static final long GUARDIAN_ID = 41L;
  private static final String KEY = "completion-key";

  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;
  @Mock private DrawingSessionRepository sessionRepository;
  @Mock private DrawingAssetRepository assetRepository;
  @Mock private ConversationSessionRepository conversationRepository;
  @Mock private DrawingAnalysisRepository analysisRepository;
  @Mock private ReportRepository reportRepository;
  @Mock private org.springframework.context.ApplicationEventPublisher eventPublisher;
  @Mock private DrawingSession session;
  @Mock private DrawingAsset finalAsset;
  @Mock private ConversationSession conversation;

  private DrawingCompletionService service;

  @BeforeEach
  void setUp() {
    service =
        new DrawingCompletionService(
            currentUserResolver,
            accessValidator,
            sessionRepository,
            assetRepository,
            conversationRepository,
            analysisRepository,
            reportRepository,
            eventPublisher,
            Clock.fixed(Instant.parse("2026-07-23T10:30:00Z"), ZoneOffset.UTC));
    lenient().when(currentUserResolver.requireUserId()).thenReturn(GUARDIAN_ID);
    lenient()
        .when(sessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .thenReturn(Optional.of(session));
    lenient().when(session.getId()).thenReturn(SESSION_ID);
    lenient().when(session.canRequestCompletion()).thenReturn(true);
    lenient().when(session.getSessionStatus()).thenReturn(DrawingSessionStatus.IN_PROGRESS);
    lenient().when(session.getCurrentStage()).thenReturn(DrawingStage.REPORTING);
    lenient().when(analysisRepository.findByRequestId(KEY)).thenReturn(Optional.empty());
    lenient()
        .when(
            assetRepository.findFirstByDrawingSessionIdAndAssetTypeOrderByAssetVersionDesc(
                SESSION_ID, DrawingAssetType.FINAL))
        .thenReturn(Optional.of(finalAsset));
    lenient()
        .when(conversationRepository.findByDrawingSessionId(SESSION_ID))
        .thenReturn(Optional.of(conversation));
    lenient().when(conversation.isCompleted()).thenReturn(true);
    lenient()
        .when(analysisRepository.saveAndFlush(any(DrawingAnalysis.class)))
        .thenAnswer(
            invocation -> {
              DrawingAnalysis analysis = invocation.getArgument(0);
              ReflectionTestUtils.setField(analysis, "id", 701L);
              return analysis;
            });
    lenient()
        .when(reportRepository.saveAndFlush(any(Report.class)))
        .thenAnswer(
            invocation -> {
              Report report = invocation.getArgument(0);
              ReflectionTestUtils.setField(report, "id", 900L);
              return report;
            });
  }

  @Test
  void acceptsFinalAnalysisAndRequestedReport() {
    DrawingCompletionResponse response =
        service.complete(SESSION_ID, KEY, new CompleteDrawingSessionRequest(false, true));

    verify(accessValidator).requireDrawingSessionAccess(GUARDIAN_ID, SESSION_ID);
    verify(session).startReporting();
    verify(eventPublisher).publishEvent(new ReportGenerationRequestedEvent(701L));
    assertThat(response.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.analysisId()).isEqualTo(701L);
    assertThat(response.analysisStatus()).isEqualTo(DrawingAnalysisState.PENDING);
    assertThat(response.reportId()).isEqualTo(900L);
    assertThat(response.reportStatus()).isEqualTo(ReportStatus.GENERATING);
  }

  @Test
  void omitsReportWhenItWasNotRequested() {
    DrawingCompletionResponse response =
        service.complete(SESSION_ID, KEY, new CompleteDrawingSessionRequest(false, false));

    verify(reportRepository, never()).saveAndFlush(any());
    verify(eventPublisher, never()).publishEvent(any());
    assertThat(response.reportId()).isNull();
    assertThat(response.reportStatus()).isNull();
  }

  @Test
  void returnsPreviouslyAcceptedResultForSameKey() {
    DrawingAnalysis existing = org.mockito.Mockito.mock(DrawingAnalysis.class);
    Report report = org.mockito.Mockito.mock(Report.class);
    given(analysisRepository.findByRequestId(KEY)).willReturn(Optional.of(existing));
    given(existing.getDrawingSession()).willReturn(session);
    given(existing.getId()).willReturn(701L);
    given(existing.getTaskType()).willReturn(DrawingAnalysisType.ACTIVITY_REPORT);
    given(existing.getState()).willReturn(DrawingAnalysisState.PENDING);
    given(reportRepository.findByAnalysisId(701L)).willReturn(Optional.of(report));
    given(report.getId()).willReturn(900L);
    given(report.getStatus()).willReturn(ReportStatus.GENERATING);

    DrawingCompletionResponse response =
        service.complete(SESSION_ID, KEY, new CompleteDrawingSessionRequest(false, true));

    verify(analysisRepository, never()).saveAndFlush(any());
    assertThat(response.analysisId()).isEqualTo(701L);
    assertThat(response.reportId()).isEqualTo(900L);
  }

  @Test
  void rejectsTheSameKeyWhenTheCompletionOptionsDiffer() {
    DrawingAnalysis existing = org.mockito.Mockito.mock(DrawingAnalysis.class);
    given(analysisRepository.findByRequestId(KEY)).willReturn(Optional.of(existing));
    given(existing.getDrawingSession()).willReturn(session);
    given(existing.getTaskType()).willReturn(DrawingAnalysisType.ACTIVITY_REPORT);

    assertThatThrownBy(
            () -> service.complete(SESSION_ID, KEY, new CompleteDrawingSessionRequest(true, false)))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT));
  }

  @Test
  void rejectsControlCharactersInIdempotencyKey() {
    assertThatThrownBy(
            () ->
                service.complete(
                    SESSION_ID, "completion\nkey", new CompleteDrawingSessionRequest(false, false)))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(DrawingErrorCode.IDEMPOTENCY_KEY_INVALID));

    verify(accessValidator, never()).requireDrawingSessionAccess(any(), any());
  }

  @Test
  void rejectsSkippingWhenConversationAlreadyExists() {
    assertThatThrownBy(
            () -> service.complete(SESSION_ID, KEY, new CompleteDrawingSessionRequest(true, true)))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(DrawingErrorCode.DRAWING_CONVERSATION_NOT_COMPLETED));

    verify(analysisRepository, never()).saveAndFlush(any());
  }
}
