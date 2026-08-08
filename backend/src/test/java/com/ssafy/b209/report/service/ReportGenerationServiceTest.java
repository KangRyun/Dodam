package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.service.StageFinalImageFinder;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ReportGenerationStatusResponse;
import com.ssafy.b209.report.exception.ReportDetailErrorCode;
import com.ssafy.b209.report.exception.ReportGenerationErrorCode;
import com.ssafy.b209.report.repository.ReportRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class ReportGenerationServiceTest {

  private static final long GUARDIAN_ID = 41L;
  private static final long SESSION_ID = 100L;
  private static final long SOURCE_ANALYSIS_ID = 701L;
  private static final long SOURCE_REPORT_ID = 900L;
  private static final String IDEMPOTENCY_KEY = "report-regeneration-key";
  private static final LocalDateTime SOURCE_TIME = LocalDateTime.of(2026, 7, 23, 10, 30);

  @Mock private GuardianResourceAccessRepository accessRepository;
  @Mock private ReportRepository reportRepository;
  @Mock private DrawingSessionRepository sessionRepository;
  @Mock private StageFinalImageFinder stageFinalImageFinder;
  @Mock private DrawingAnalysisRepository analysisRepository;
  @Mock private ApplicationEventPublisher eventPublisher;
  @Mock private DrawingSession session;
  @Mock private DrawingAsset originalAsset;
  @Mock private DrawingAsset latestAsset;
  @Mock private DrawingAsset uploadedPhoto;

  private ReportGenerationService service;
  private DrawingAnalysis sourceAnalysis;
  private Report sourceReport;

  @BeforeEach
  void setUp() {
    service =
        new ReportGenerationService(
            accessRepository,
            reportRepository,
            sessionRepository,
            stageFinalImageFinder,
            analysisRepository,
            eventPublisher,
            Clock.fixed(Instant.parse("2026-07-23T10:32:00Z"), ZoneOffset.UTC));
    sourceAnalysis =
        DrawingAnalysis.pending(
            session,
            originalAsset,
            DrawingAnalysisType.ACTIVITY_REPORT,
            "original-completion-key",
            SOURCE_TIME);
    ReflectionTestUtils.setField(sourceAnalysis, "id", SOURCE_ANALYSIS_ID);
    sourceAnalysis.failFinal(
        "OBSERVATION_GENERATION_FAILED", "Report generation failed", SOURCE_TIME.plusMinutes(1));
    sourceReport = Report.generating(session, sourceAnalysis, 1, SOURCE_TIME);
    ReflectionTestUtils.setField(sourceReport, "id", SOURCE_REPORT_ID);
    sourceReport.fail(
        "Report generation failed. Please retry.",
        "OBSERVATION_GENERATION_FAILED",
        SOURCE_TIME.plusMinutes(1));
    lenient().when(session.getId()).thenReturn(SESSION_ID);
    lenient()
        .when(accessRepository.hasDrawingSessionAccess(GUARDIAN_ID, SESSION_ID))
        .thenReturn(true);
  }

  @Test
  void returnsLightweightGenerationStatus() {
    given(reportRepository.findById(SOURCE_REPORT_ID)).willReturn(Optional.of(sourceReport));
    given(reportRepository.findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(SESSION_ID))
        .willReturn(Optional.of(sourceReport));

    ReportGenerationStatusResponse response = service.getStatus(GUARDIAN_ID, SOURCE_REPORT_ID);

    assertThat(response.reportId()).isEqualTo(SOURCE_REPORT_ID);
    assertThat(response.reportStatus()).isEqualTo(ReportStatus.FAILED_FINAL);
    assertThat(response.retryable()).isTrue();
    assertThat(response.failureReason()).isEqualTo("OBSERVATION_GENERATION_FAILED");
  }

  @Test
  void regeneratesLatestFailedReportAsNextVersion() {
    prepareNewRegeneration();

    ReportGenerationStatusResponse response =
        service.regenerate(GUARDIAN_ID, SOURCE_REPORT_ID, IDEMPOTENCY_KEY);

    verify(session).restartReporting();
    verify(eventPublisher).publishEvent(new ReportGenerationRequestedEvent(702L));
    assertThat(response.reportId()).isEqualTo(901L);
    assertThat(response.analysisId()).isEqualTo(702L);
    assertThat(response.reportVersion()).isEqualTo(2);
    assertThat(response.reportStatus()).isEqualTo(ReportStatus.GENERATING);
    assertThat(response.retryable()).isFalse();
  }

  @Test
  void regeneratesWithTheStageFinalImageResolvedForTheSession() {
    prepareNewRegeneration(uploadedPhoto);

    service.regenerate(GUARDIAN_ID, SOURCE_REPORT_ID, IDEMPOTENCY_KEY);

    ArgumentCaptor<DrawingAnalysis> captor = ArgumentCaptor.captor();
    verify(analysisRepository).saveAndFlush(captor.capture());
    assertThat(captor.getValue().getDrawingAsset()).isSameAs(uploadedPhoto);
  }

  @Test
  void rejectsRegenerationWhenTheSessionHasNoStageFinalImage() {
    given(reportRepository.findByIdForUpdate(SOURCE_REPORT_ID))
        .willReturn(Optional.of(sourceReport));
    given(analysisRepository.findByRequestId(IDEMPOTENCY_KEY)).willReturn(Optional.empty());
    given(reportRepository.findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(SESSION_ID))
        .willReturn(Optional.of(sourceReport));
    given(sessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(session));
    given(stageFinalImageFinder.find(session)).willReturn(Optional.empty());

    assertThatThrownBy(() -> service.regenerate(GUARDIAN_ID, SOURCE_REPORT_ID, IDEMPOTENCY_KEY))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(ReportGenerationErrorCode.FINAL_ASSET_REQUIRED));

    verify(analysisRepository, never()).saveAndFlush(any());
  }

  @Test
  void returnsExistingRegenerationForSameIdempotencyKey() {
    DrawingAnalysis retry =
        DrawingAnalysis.pendingRetry(
            sourceAnalysis, latestAsset, IDEMPOTENCY_KEY, SOURCE_TIME.plusMinutes(2));
    ReflectionTestUtils.setField(retry, "id", 702L);
    Report retryReport = Report.generating(session, retry, 2, SOURCE_TIME.plusMinutes(2));
    ReflectionTestUtils.setField(retryReport, "id", 901L);
    given(reportRepository.findByIdForUpdate(SOURCE_REPORT_ID))
        .willReturn(Optional.of(sourceReport));
    given(analysisRepository.findByRequestId(IDEMPOTENCY_KEY)).willReturn(Optional.of(retry));
    given(reportRepository.findByAnalysisId(702L)).willReturn(Optional.of(retryReport));

    ReportGenerationStatusResponse response =
        service.regenerate(GUARDIAN_ID, SOURCE_REPORT_ID, IDEMPOTENCY_KEY);

    verify(analysisRepository, never()).saveAndFlush(any());
    verify(session, never()).restartReporting();
    assertThat(response.reportId()).isEqualTo(901L);
  }

  @Test
  void rejectsRegenerationOfCompletedReport() {
    Report completed = Report.generating(session, sourceAnalysis, 1, SOURCE_TIME);
    ReflectionTestUtils.setField(completed, "id", SOURCE_REPORT_ID);
    completed.complete(false, "Not a diagnosis.", SOURCE_TIME.plusMinutes(1));
    given(reportRepository.findByIdForUpdate(SOURCE_REPORT_ID)).willReturn(Optional.of(completed));
    given(analysisRepository.findByRequestId(IDEMPOTENCY_KEY)).willReturn(Optional.empty());
    given(reportRepository.findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(SESSION_ID))
        .willReturn(Optional.of(completed));

    assertThatThrownBy(() -> service.regenerate(GUARDIAN_ID, SOURCE_REPORT_ID, IDEMPOTENCY_KEY))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(ReportGenerationErrorCode.REGENERATION_NOT_ALLOWED));
  }

  @Test
  void rejectsStatusLookupWithoutGuardianAccess() {
    given(reportRepository.findById(SOURCE_REPORT_ID)).willReturn(Optional.of(sourceReport));
    given(accessRepository.hasDrawingSessionAccess(99L, SESSION_ID)).willReturn(false);

    assertThatThrownBy(() -> service.getStatus(99L, SOURCE_REPORT_ID))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(ReportDetailErrorCode.REPORT_ACCESS_DENIED));
  }

  @Test
  void rejectsOlderFailedReportWhenNewerVersionExists() {
    DrawingAnalysis retry =
        DrawingAnalysis.pendingRetry(
            sourceAnalysis, latestAsset, "newer-report-request", SOURCE_TIME.plusMinutes(2));
    ReflectionTestUtils.setField(retry, "id", 702L);
    Report newer = Report.generating(session, retry, 2, SOURCE_TIME.plusMinutes(2));
    ReflectionTestUtils.setField(newer, "id", 901L);
    newer.fail(
        "Newer report generation failed.",
        "OBSERVATION_GENERATION_FAILED",
        SOURCE_TIME.plusMinutes(3));
    given(reportRepository.findByIdForUpdate(SOURCE_REPORT_ID))
        .willReturn(Optional.of(sourceReport));
    given(analysisRepository.findByRequestId(IDEMPOTENCY_KEY)).willReturn(Optional.empty());
    given(reportRepository.findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(SESSION_ID))
        .willReturn(Optional.of(newer));

    assertThatThrownBy(() -> service.regenerate(GUARDIAN_ID, SOURCE_REPORT_ID, IDEMPOTENCY_KEY))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(ReportGenerationErrorCode.REGENERATION_NOT_ALLOWED));
  }

  @Test
  void rejectsIdempotencyKeyAlreadyUsedForAnotherSource() {
    DrawingAnalysis unrelated =
        DrawingAnalysis.pending(
            session,
            latestAsset,
            DrawingAnalysisType.OBJECT_DETECTION,
            IDEMPOTENCY_KEY,
            SOURCE_TIME.plusMinutes(2));
    ReflectionTestUtils.setField(unrelated, "id", 702L);
    given(reportRepository.findByIdForUpdate(SOURCE_REPORT_ID))
        .willReturn(Optional.of(sourceReport));
    given(analysisRepository.findByRequestId(IDEMPOTENCY_KEY)).willReturn(Optional.of(unrelated));

    assertThatThrownBy(() -> service.regenerate(GUARDIAN_ID, SOURCE_REPORT_ID, IDEMPOTENCY_KEY))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(ReportGenerationErrorCode.IDEMPOTENCY_KEY_CONFLICT));
  }

  @Test
  void rejectsMissingIdempotencyKeyBeforeLoadingReport() {
    assertThatThrownBy(() -> service.regenerate(GUARDIAN_ID, SOURCE_REPORT_ID, null))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(ReportGenerationErrorCode.IDEMPOTENCY_KEY_REQUIRED));

    verify(reportRepository, never()).findByIdForUpdate(any());
  }

  private void prepareNewRegeneration() {
    prepareNewRegeneration(latestAsset);
  }

  private void prepareNewRegeneration(DrawingAsset stageFinalImage) {
    given(reportRepository.findByIdForUpdate(SOURCE_REPORT_ID))
        .willReturn(Optional.of(sourceReport));
    given(analysisRepository.findByRequestId(IDEMPOTENCY_KEY)).willReturn(Optional.empty());
    given(reportRepository.findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(SESSION_ID))
        .willReturn(Optional.of(sourceReport));
    given(sessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(session));
    given(stageFinalImageFinder.find(session)).willReturn(Optional.of(stageFinalImage));
    given(analysisRepository.saveAndFlush(any(DrawingAnalysis.class)))
        .willAnswer(
            invocation -> {
              DrawingAnalysis analysis = invocation.getArgument(0);
              ReflectionTestUtils.setField(analysis, "id", 702L);
              return analysis;
            });
    given(reportRepository.saveAndFlush(any(Report.class)))
        .willAnswer(
            invocation -> {
              Report report = invocation.getArgument(0);
              ReflectionTestUtils.setField(report, "id", 901L);
              return report;
            });
  }
}
