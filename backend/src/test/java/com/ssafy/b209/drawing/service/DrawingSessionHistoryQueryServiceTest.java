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

    given(thumbnail.getDrawingSession()).willReturn(session);
    given(thumbnail.getFileUrl()).willReturn("https://cdn.example.com/thumb.png");
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
    assertThat(item.thumbnailUrl()).isEqualTo("https://cdn.example.com/thumb.png");
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

    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    List.of(SESSION_ID), DrawingAssetType.THUMBNAIL))
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
        reportRepository);
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
        reportRepository);
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
        reportRepository);
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
