package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.dto.response.DrawingSessionHistoryPageResponse;
import com.ssafy.b209.drawing.htp.domain.HtpAssessment;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.repository.ReportRepository;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

@ExtendWith(MockitoExtension.class)
class DrawingSessionHistoryQueryServiceTest {

  private static final Long CHILD_ID = 3L;
  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long SESSION_ID = 10L;
  private static final LocalDateTime STARTED_AT = LocalDateTime.of(2026, 7, 22, 4, 0);
  private static final LocalDateTime COMPLETED_AT = LocalDateTime.of(2026, 7, 22, 4, 30);
  private static final Pageable PAGEABLE =
      PageRequest.of(0, 20, Sort.by(Sort.Direction.DESC, "startedAt"));

  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  @Mock private DrawingAnalysisRepository drawingAnalysisRepository;
  @Mock private ReportRepository reportRepository;
  @Mock private HtpAssessmentRepository htpAssessmentRepository;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  @Mock private DrawingSession session;
  @Mock private DrawingType drawingType;
  @Mock private DrawingAsset thumbnail;
  @Mock private DrawingSessionEmotion emotion;
  @Mock private DrawingAnalysis analysis;
  @Mock private Report report;

  private DrawingSessionHistoryQueryService service() {
    return new DrawingSessionHistoryQueryService(
        drawingSessionRepository,
        drawingAssetRepository,
        drawingSessionEmotionRepository,
        drawingAnalysisRepository,
        reportRepository,
        htpAssessmentRepository,
        new DrawingAssetFileUrlFactory(),
        currentUserResolver,
        accessValidator);
  }

  @Test
  void assemblesHistoryItemFromBatchedResources() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    givenSession();
    given(session.getTitle()).willReturn("우리 집");
    given(session.getCompletedAt()).willReturn(COMPLETED_AT);
    givenPageOf(session);
    given(htpAssessmentRepository.findByStepDrawingSessionIdIn(List.of(SESSION_ID)))
        .willReturn(List.of());

    given(thumbnail.getDrawingSession()).willReturn(session);
    given(thumbnail.getId()).willReturn(30L);
    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    List.of(SESSION_ID), DrawingAssetType.THUMBNAIL))
        .willReturn(List.of(thumbnail));

    given(emotion.getDrawingSession()).willReturn(session);
    given(emotion.getEmotionCode()).willReturn(DrawingEmotionCode.HAPPY);
    given(
            drawingSessionEmotionRepository
                .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(
                    List.of(SESSION_ID)))
        .willReturn(List.of(emotion));

    given(analysis.getDrawingSession()).willReturn(session);
    given(analysis.getState()).willReturn(DrawingAnalysisState.SUCCESS);
    given(
            drawingAnalysisRepository
                .findByDrawingSessionIdInAndScopeOrderByDrawingSessionIdAscRequestedAtDescIdDesc(
                    List.of(SESSION_ID), DrawingAnalysisScope.FINAL))
        .willReturn(List.of(analysis));

    given(report.getDrawingSession()).willReturn(session);
    given(report.getId()).willReturn(50L);
    given(report.getStatus()).willReturn(ReportStatus.COMPLETED);
    given(
            reportRepository.findByDrawingSessionIdInOrderByDrawingSessionIdAscCreatedAtDescIdDesc(
                List.of(SESSION_ID)))
        .willReturn(List.of(report));

    DrawingSessionHistoryPageResponse response =
        service().getHistory(CHILD_ID, null, null, null, null, null, PAGEABLE);

    assertThat(response.content()).hasSize(1);
    var item = response.content().getFirst();
    assertThat(item.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(item.thumbnailUrl()).isEqualTo("/api/v1/drawing-assets/30/file");
    assertThat(item.drawingType().code()).isEqualTo("HOUSE");
    assertThat(item.title()).isEqualTo("우리 집");
    assertThat(item.inputMethod()).isEqualTo(DrawingInputMethod.CANVAS);
    assertThat(item.sessionStatus()).isEqualTo(DrawingSessionStatus.COMPLETED);
    assertThat(item.currentStage()).isEqualTo(DrawingStage.COMPLETED);
    assertThat(item.selectedEmotions()).containsExactly(DrawingEmotionCode.HAPPY);
    assertThat(item.analysisStatus()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
    assertThat(item.reportId()).isEqualTo(50L);
    assertThat(item.reportStatus()).isEqualTo(ReportStatus.COMPLETED);
    assertThat(item.startedAt()).isEqualTo(STARTED_AT.toInstant(ZoneOffset.UTC));
    assertThat(item.completedAt()).isEqualTo(COMPLETED_AT.toInstant(ZoneOffset.UTC));
    assertThat(response.totalElements()).isEqualTo(1);
    assertThat(response.first()).isTrue();

    verify(drawingAssetRepository, times(1))
        .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
            List.of(SESSION_ID), DrawingAssetType.THUMBNAIL);
    verify(reportRepository, times(1))
        .findByDrawingSessionIdInOrderByDrawingSessionIdAscCreatedAtDescIdDesc(List.of(SESSION_ID));
  }

  @Test
  void mapsPartialSuccessAnalysisToSucceededWithoutFailing() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    givenSession();
    given(session.getTitle()).willReturn(null);
    given(session.getCompletedAt()).willReturn(null);
    givenPageOf(session);
    given(htpAssessmentRepository.findByStepDrawingSessionIdIn(List.of(SESSION_ID)))
        .willReturn(List.of());

    given(analysis.getDrawingSession()).willReturn(session);
    given(analysis.getState()).willReturn(DrawingAnalysisState.PARTIAL_SUCCESS);
    given(
            drawingAnalysisRepository
                .findByDrawingSessionIdInAndScopeOrderByDrawingSessionIdAscRequestedAtDescIdDesc(
                    List.of(SESSION_ID), DrawingAnalysisScope.FINAL))
        .willReturn(List.of(analysis));
    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    List.of(SESSION_ID), DrawingAssetType.THUMBNAIL))
        .willReturn(List.of());
    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    List.of(SESSION_ID), DrawingAssetType.FINAL))
        .willReturn(List.of());
    given(
            drawingSessionEmotionRepository
                .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(
                    List.of(SESSION_ID)))
        .willReturn(List.of());
    given(
            reportRepository.findByDrawingSessionIdInOrderByDrawingSessionIdAscCreatedAtDescIdDesc(
                List.of(SESSION_ID)))
        .willReturn(List.of());

    DrawingSessionHistoryPageResponse response =
        service().getHistory(CHILD_ID, null, null, null, null, null, PAGEABLE);

    assertThat(response.content().getFirst().analysisStatus())
        .isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
  }

  @Test
  void returnsNullResourcesAndEmptyEmotionsWhenAbsent() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    givenSession();
    given(session.getTitle()).willReturn(null);
    given(session.getCompletedAt()).willReturn(null);
    givenPageOf(session);
    given(htpAssessmentRepository.findByStepDrawingSessionIdIn(List.of(SESSION_ID)))
        .willReturn(List.of());

    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    List.of(SESSION_ID), DrawingAssetType.THUMBNAIL))
        .willReturn(List.of());
    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    List.of(SESSION_ID), DrawingAssetType.FINAL))
        .willReturn(List.of());
    given(
            drawingSessionEmotionRepository
                .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(
                    List.of(SESSION_ID)))
        .willReturn(List.of());
    given(
            drawingAnalysisRepository
                .findByDrawingSessionIdInAndScopeOrderByDrawingSessionIdAscRequestedAtDescIdDesc(
                    List.of(SESSION_ID), DrawingAnalysisScope.FINAL))
        .willReturn(List.of());
    given(
            reportRepository.findByDrawingSessionIdInOrderByDrawingSessionIdAscCreatedAtDescIdDesc(
                List.of(SESSION_ID)))
        .willReturn(List.of());

    DrawingSessionHistoryPageResponse response =
        service().getHistory(CHILD_ID, null, null, null, null, null, PAGEABLE);

    var item = response.content().getFirst();
    assertThat(item.thumbnailUrl()).isNull();
    assertThat(item.selectedEmotions()).isEmpty();
    assertThat(item.analysisStatus()).isNull();
    assertThat(item.reportId()).isNull();
    assertThat(item.reportStatus()).isNull();
    assertThat(item.completedAt()).isNull();
  }

  @Test
  void usesLatestFinalImageAsThumbnailFallback() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    givenSession();
    given(session.getTitle()).willReturn(null);
    given(session.getCompletedAt()).willReturn(COMPLETED_AT);
    givenPageOf(session);
    given(htpAssessmentRepository.findByStepDrawingSessionIdIn(List.of(SESSION_ID)))
        .willReturn(List.of());

    DrawingAsset finalAsset = org.mockito.Mockito.mock(DrawingAsset.class);
    given(finalAsset.getId()).willReturn(31L);
    given(finalAsset.getDrawingSession()).willReturn(session);
    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    List.of(SESSION_ID), DrawingAssetType.THUMBNAIL))
        .willReturn(List.of());
    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    List.of(SESSION_ID), DrawingAssetType.FINAL))
        .willReturn(List.of(finalAsset));

    DrawingSessionHistoryPageResponse response =
        service().getHistory(CHILD_ID, null, null, null, null, null, PAGEABLE);

    assertThat(response.content().getFirst().thumbnailUrl())
        .isEqualTo("/api/v1/drawing-assets/31/file");
  }

  @Test
  void groupsHtpStepsIntoOneHistoryItem() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);

    DrawingSession houseSession = org.mockito.Mockito.mock(DrawingSession.class);
    DrawingSession treeSession = org.mockito.Mockito.mock(DrawingSession.class);
    DrawingSession personSession = org.mockito.Mockito.mock(DrawingSession.class);
    HtpAssessment assessment = org.mockito.Mockito.mock(HtpAssessment.class);
    HtpAssessmentStep houseStep = org.mockito.Mockito.mock(HtpAssessmentStep.class);
    HtpAssessmentStep treeStep = org.mockito.Mockito.mock(HtpAssessmentStep.class);
    HtpAssessmentStep personStep = org.mockito.Mockito.mock(HtpAssessmentStep.class);
    DrawingType htpType = org.mockito.Mockito.mock(DrawingType.class);

    given(houseSession.getId()).willReturn(10L);
    given(treeSession.getId()).willReturn(11L);
    given(personSession.getId()).willReturn(12L);
    given(personSession.getDrawingType()).willReturn(htpType);
    given(htpType.getId()).willReturn(9L);
    given(htpType.getCode()).willReturn("HTP");
    given(htpType.getName()).willReturn("집·나무·사람 그림");
    given(personSession.getInputMethod()).willReturn(DrawingInputMethod.CANVAS);
    given(personSession.getSessionStatus()).willReturn(DrawingSessionStatus.COMPLETED);
    given(personSession.getCurrentStage()).willReturn(DrawingStage.COMPLETED);
    given(houseStep.getStepOrder()).willReturn(1);
    given(houseStep.getDrawingSubject()).willReturn(HtpDrawingSubject.HOUSE);
    given(houseStep.getDrawingSession()).willReturn(houseSession);
    given(treeStep.getStepOrder()).willReturn(2);
    given(treeStep.getDrawingSubject()).willReturn(HtpDrawingSubject.TREE);
    given(treeStep.getDrawingSession()).willReturn(treeSession);
    given(personStep.getStepOrder()).willReturn(3);
    given(personStep.getDrawingSubject()).willReturn(HtpDrawingSubject.PERSON);
    given(personStep.getDrawingSession()).willReturn(personSession);
    given(assessment.getId()).willReturn(40L);
    given(assessment.getStatus()).willReturn(HtpAssessmentStatus.COMPLETED);
    given(assessment.getCreatedAt()).willReturn(STARTED_AT);
    given(assessment.getCompletedAt()).willReturn(COMPLETED_AT);
    given(assessment.getSteps()).willReturn(List.of(houseStep, treeStep, personStep));

    given(
            drawingSessionRepository.findHistoryPage(
                eq(CHILD_ID), any(), any(), any(), any(), any(), any(Pageable.class)))
        .willReturn(new PageImpl<>(List.of(personSession), PAGEABLE, 1));
    given(htpAssessmentRepository.findByStepDrawingSessionIdIn(List.of(12L)))
        .willReturn(List.of(assessment));

    DrawingSessionHistoryPageResponse response =
        service().getHistory(CHILD_ID, null, null, null, null, null, PAGEABLE);

    var item = response.content().getFirst();
    assertThat(item.activityKind()).isEqualTo("HTP");
    assertThat(item.htpAssessmentId()).isEqualTo(40L);
    assertThat(item.htpStatus()).isEqualTo(HtpAssessmentStatus.COMPLETED);
    assertThat(item.htpDrawings())
        .extracting("drawingSubject")
        .containsExactly(HtpDrawingSubject.HOUSE, HtpDrawingSubject.TREE, HtpDrawingSubject.PERSON);
    assertThat(item.htpDrawings()).extracting("drawingSessionId").containsExactly(10L, 11L, 12L);
  }

  @Test
  void returnsEmptyPageWithoutBatchQueriesWhenNoSessions() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(
            drawingSessionRepository.findHistoryPage(
                eq(CHILD_ID), any(), any(), any(), any(), any(), any(Pageable.class)))
        .willReturn(new PageImpl<>(List.of(), PAGEABLE, 0));

    DrawingSessionHistoryPageResponse response =
        service().getHistory(CHILD_ID, null, null, null, null, null, PAGEABLE);

    assertThat(response.content()).isEmpty();
    assertThat(response.totalElements()).isZero();
    verifyNoInteractions(
        drawingAssetRepository,
        drawingSessionEmotionRepository,
        drawingAnalysisRepository,
        reportRepository,
        htpAssessmentRepository);
  }

  @Test
  void appliesDateFiltersAsInclusiveStartAndExclusiveNextDay() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(
            drawingSessionRepository.findHistoryPage(
                CHILD_ID,
                LocalDate.of(2026, 7, 1).atStartOfDay(),
                LocalDate.of(2026, 7, 11).atStartOfDay(),
                "HOUSE",
                DrawingSessionStatus.COMPLETED,
                ReportStatus.COMPLETED,
                PAGEABLE))
        .willReturn(new PageImpl<>(List.of(), PAGEABLE, 0));

    service()
        .getHistory(
            CHILD_ID,
            LocalDate.of(2026, 7, 1),
            LocalDate.of(2026, 7, 10),
            "HOUSE",
            DrawingSessionStatus.COMPLETED,
            ReportStatus.COMPLETED,
            PAGEABLE);

    verify(drawingSessionRepository)
        .findHistoryPage(
            CHILD_ID,
            LocalDate.of(2026, 7, 1).atStartOfDay(),
            LocalDate.of(2026, 7, 11).atStartOfDay(),
            "HOUSE",
            DrawingSessionStatus.COMPLETED,
            ReportStatus.COMPLETED,
            PAGEABLE);
  }

  @Test
  void rejectsDateRangeWhoseExclusiveUpperBoundOverflows() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);

    assertThatThrownBy(
            () -> service().getHistory(CHILD_ID, null, LocalDate.MAX, null, null, null, PAGEABLE))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(
        drawingSessionRepository,
        drawingAssetRepository,
        drawingSessionEmotionRepository,
        drawingAnalysisRepository,
        reportRepository,
        htpAssessmentRepository);
  }

  @Test
  void rejectsUnownedChildBeforeReadingSessions() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(new BusinessException(ChildErrorCode.CHILD_NOT_FOUND))
        .given(accessValidator)
        .requireChildAccess(GUARDIAN_USER_ID, CHILD_ID);

    assertThatThrownBy(() -> service().getHistory(CHILD_ID, null, null, null, null, null, PAGEABLE))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(ChildErrorCode.CHILD_NOT_FOUND));

    verifyNoInteractions(
        drawingSessionRepository,
        drawingAssetRepository,
        drawingSessionEmotionRepository,
        drawingAnalysisRepository,
        reportRepository,
        htpAssessmentRepository);
  }

  private void givenSession() {
    given(session.getId()).willReturn(SESSION_ID);
    given(session.getDrawingType()).willReturn(drawingType);
    given(drawingType.getId()).willReturn(7L);
    given(drawingType.getCode()).willReturn("HOUSE");
    given(drawingType.getName()).willReturn("집");
    given(session.getInputMethod()).willReturn(DrawingInputMethod.CANVAS);
    given(session.getSessionStatus()).willReturn(DrawingSessionStatus.COMPLETED);
    given(session.getCurrentStage()).willReturn(DrawingStage.COMPLETED);
    given(session.getStartedAt()).willReturn(STARTED_AT);
  }

  private void givenPageOf(DrawingSession... sessions) {
    Page<DrawingSession> page = new PageImpl<>(List.of(sessions), PAGEABLE, sessions.length);
    given(
            drawingSessionRepository.findHistoryPage(
                eq(CHILD_ID), any(), any(), any(), any(), any(), any(Pageable.class)))
        .willReturn(page);
  }
}
