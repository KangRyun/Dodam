package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.dto.response.ActiveDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionDetailResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.repository.ReportRepository;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DrawingSessionQueryServiceTest {

  private static final Long CHILD_ID = 3L;
  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long SESSION_ID = 10L;
  private static final LocalDateTime STARTED_AT = LocalDateTime.of(2026, 7, 22, 4, 0);
  private static final LocalDateTime CLIENT_SAVED_AT = LocalDateTime.of(2026, 7, 22, 4, 5);
  private static final LocalDateTime SAVED_AT = LocalDateTime.of(2026, 7, 22, 4, 5, 1);

  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  @Mock private DrawingAnalysisRepository drawingAnalysisRepository;
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ReportRepository reportRepository;
  @Mock private DrawingSession session;
  @Mock private DrawingSession duplicateSession;
  @Mock private DrawingAsset draft;
  @Mock private DrawingAsset asset;
  @Mock private DrawingAnalysis analysis;
  @Mock private DrawingSessionEmotion emotion;
  @Mock private ConversationSession conversation;
  @Mock private Report report;
  @Mock private Child child;
  @Mock private DrawingType drawingType;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private DrawingSessionQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new DrawingSessionQueryService(
            drawingSessionRepository,
            drawingAssetRepository,
            drawingSessionEmotionRepository,
            drawingAnalysisRepository,
            conversationSessionRepository,
            reportRepository,
            currentUserResolver,
            accessValidator);
  }

  @Test
  void listsSnapshotSummariesForAnAccessibleSession() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(asset.getId()).willReturn(20L);
    given(asset.getAssetType()).willReturn(DrawingAssetType.INTERMEDIATE);
    given(asset.getAssetVersion()).willReturn(1);
    given(asset.getMimeType()).willReturn("image/png");
    given(asset.getFileSizeBytes()).willReturn(1024L);
    given(asset.getCapturedAt()).willReturn(CLIENT_SAVED_AT);
    given(asset.getCreatedAt()).willReturn(SAVED_AT);
    given(drawingAssetRepository.findAllByDrawingSessionIdOrderByCreatedAtDescIdDesc(SESSION_ID))
        .willReturn(List.of(asset));

    var snapshots = service.getSnapshots(SESSION_ID);

    assertThat(snapshots).hasSize(1);
    assertThat(snapshots.getFirst().drawingAssetId()).isEqualTo(20L);
    assertThat(snapshots.getFirst().assetType()).isEqualTo(DrawingAssetType.INTERMEDIATE);
    assertThat(snapshots.getFirst().capturedAt())
        .isEqualTo(CLIENT_SAVED_AT.toInstant(ZoneOffset.UTC));
  }

  @Test
  void returnsAuthorizedSessionDetailWithLatestResources() {
    givenDetailSession();
    given(
            drawingSessionEmotionRepository.findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(
                SESSION_ID))
        .willReturn(List.of(emotion));
    given(emotion.getEmotionCode()).willReturn(DrawingEmotionCode.HAPPY);
    given(drawingAssetRepository.findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(SESSION_ID))
        .willReturn(Optional.of(asset));
    given(asset.getId()).willReturn(20L);
    given(asset.getAssetType()).willReturn(DrawingAssetType.DRAFT);
    given(asset.getAssetVersion()).willReturn(2);
    given(asset.getMimeType()).willReturn("image/png");
    given(asset.getFileSizeBytes()).willReturn(2048L);
    given(asset.getCapturedAt()).willReturn(CLIENT_SAVED_AT);
    given(asset.getCreatedAt()).willReturn(SAVED_AT);
    given(
            drawingAnalysisRepository.findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(
                SESSION_ID))
        .willReturn(Optional.of(analysis));
    given(analysis.getId()).willReturn(30L);
    given(analysis.getScope()).willReturn(DrawingAnalysisScope.INTERMEDIATE);
    given(analysis.getTaskType()).willReturn(DrawingAnalysisType.OBJECT_DETECTION);
    given(analysis.getState()).willReturn(DrawingAnalysisState.SUCCESS);
    given(analysis.getRequestedAt()).willReturn(SAVED_AT);
    given(analysis.getCompletedAt()).willReturn(SAVED_AT.plusSeconds(1));
    given(conversationSessionRepository.findByDrawingSessionId(SESSION_ID))
        .willReturn(Optional.of(conversation));
    given(conversation.getId()).willReturn(40L);
    given(reportRepository.findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(SESSION_ID))
        .willReturn(Optional.of(report));
    given(report.getId()).willReturn(50L);
    given(
            drawingAssetRepository.existsByDrawingSessionIdAndAssetType(
                SESSION_ID, DrawingAssetType.DRAFT))
        .willReturn(true);

    DrawingSessionDetailResponse response = service.getDrawingSessionDetail(SESSION_ID);

    assertThat(response.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.child().childId()).isEqualTo(CHILD_ID);
    assertThat(response.child().nickname()).isEqualTo("fixture-child");
    assertThat(response.selectedEmotions()).containsExactly(DrawingEmotionCode.HAPPY);
    assertThat(response.latestAsset().drawingAssetId()).isEqualTo(20L);
    assertThat(response.latestAnalysis().drawingAnalysisId()).isEqualTo(30L);
    assertThat(response.conversationId()).isEqualTo(40L);
    assertThat(response.reportId()).isEqualTo(50L);
    assertThat(response.recoverableDraft()).isTrue();
  }

  @Test
  void returnsNullOptionalResourcesAndEmptyEmotions() {
    givenDetailSession();
    given(
            drawingSessionEmotionRepository.findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(
                SESSION_ID))
        .willReturn(List.of());
    given(drawingAssetRepository.findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(SESSION_ID))
        .willReturn(Optional.empty());
    given(
            drawingAnalysisRepository.findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(
                SESSION_ID))
        .willReturn(Optional.empty());
    given(conversationSessionRepository.findByDrawingSessionId(SESSION_ID))
        .willReturn(Optional.empty());
    given(reportRepository.findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(SESSION_ID))
        .willReturn(Optional.empty());

    DrawingSessionDetailResponse response = service.getDrawingSessionDetail(SESSION_ID);

    assertThat(response.selectedEmotions()).isEmpty();
    assertThat(response.latestAsset()).isNull();
    assertThat(response.latestAnalysis()).isNull();
    assertThat(response.conversationId()).isNull();
    assertThat(response.reportId()).isNull();
    assertThat(response.recoverableDraft()).isFalse();
  }

  @Test
  void rejectsUnauthorizedDetailBeforeReadingSession() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND))
        .given(accessValidator)
        .requireDrawingSessionAccess(GUARDIAN_USER_ID, SESSION_ID);

    assertError(
        () -> service.getDrawingSessionDetail(SESSION_ID),
        DrawingErrorCode.DRAWING_SESSION_NOT_FOUND);

    verifyNoInteractions(
        drawingSessionRepository,
        drawingAssetRepository,
        drawingSessionEmotionRepository,
        drawingAnalysisRepository,
        conversationSessionRepository,
        reportRepository);
  }

  @Test
  void rejectsUnownedChildBeforeReadingActiveSession() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(new BusinessException(com.ssafy.b209.child.exception.ChildErrorCode.CHILD_NOT_FOUND))
        .given(accessValidator)
        .requireChildAccess(GUARDIAN_USER_ID, CHILD_ID);

    assertThatThrownBy(() -> service.getActiveDrawingSession(CHILD_ID))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(drawingSessionRepository, drawingAssetRepository);
  }

  @Test
  void returnsTheActiveSessionAndItsLatestDraftMetadata() {
    given(drawingSessionRepository.findActiveSessionsByChildId(CHILD_ID))
        .willReturn(List.of(session));
    given(session.getId()).willReturn(SESSION_ID);
    given(session.getChild()).willReturn(child);
    given(child.getId()).willReturn(CHILD_ID);
    given(session.getDrawingType()).willReturn(drawingType);
    given(drawingType.getId()).willReturn(7L);
    given(drawingType.getCode()).willReturn("HOUSE");
    given(drawingType.getName()).willReturn("집");
    given(session.getInputMethod()).willReturn(DrawingInputMethod.CANVAS);
    given(session.getSessionStatus()).willReturn(DrawingSessionStatus.IN_PROGRESS);
    given(session.getCurrentStage()).willReturn(DrawingStage.DRAWING);
    given(session.getStartedAt()).willReturn(STARTED_AT);
    given(drawingAssetRepository.findLatestDraft(SESSION_ID)).willReturn(Optional.of(draft));
    given(draft.getId()).willReturn(20L);
    given(draft.getAssetVersion()).willReturn(4);
    given(draft.getLastEventSequence()).willReturn(31L);
    given(draft.getMimeType()).willReturn("image/png");
    given(draft.getFileSizeBytes()).willReturn(2048L);
    given(draft.getCapturedAt()).willReturn(CLIENT_SAVED_AT);
    given(draft.getCreatedAt()).willReturn(SAVED_AT);

    ActiveDrawingSessionResponse response = service.getActiveDrawingSession(CHILD_ID);

    assertThat(response.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.childId()).isEqualTo(CHILD_ID);
    assertThat(response.drawingType().drawingTypeId()).isEqualTo(7L);
    assertThat(response.drawingType().code()).isEqualTo("HOUSE");
    assertThat(response.inputMethod()).isEqualTo(DrawingInputMethod.CANVAS);
    assertThat(response.sessionStatus()).isEqualTo(DrawingSessionStatus.IN_PROGRESS);
    assertThat(response.currentStage()).isEqualTo(DrawingStage.DRAWING);
    assertThat(response.startedAt()).isEqualTo(STARTED_AT.toInstant(ZoneOffset.UTC));
    assertThat(response.latestDraft().drawingAssetId()).isEqualTo(20L);
    assertThat(response.latestDraft().assetVersion()).isEqualTo(4);
    assertThat(response.latestDraft().lastEventSequence()).isEqualTo(31L);
    assertThat(response.latestDraft().clientSavedAt())
        .isEqualTo(CLIENT_SAVED_AT.toInstant(ZoneOffset.UTC));
    assertThat(response.latestDraft().savedAt()).isEqualTo(SAVED_AT.toInstant(ZoneOffset.UTC));
    assertThat(response.latestDraft().previewUrl()).isNull();
  }

  @Test
  void returnsNullLatestDraftWhenTheActiveSessionHasNoSavedDraft() {
    given(drawingSessionRepository.findActiveSessionsByChildId(CHILD_ID))
        .willReturn(List.of(session));
    given(session.getId()).willReturn(SESSION_ID);
    given(session.getChild()).willReturn(child);
    given(child.getId()).willReturn(CHILD_ID);
    given(session.getDrawingType()).willReturn(drawingType);
    given(session.getStartedAt()).willReturn(STARTED_AT);
    given(drawingAssetRepository.findLatestDraft(SESSION_ID)).willReturn(Optional.empty());

    ActiveDrawingSessionResponse response = service.getActiveDrawingSession(CHILD_ID);

    assertThat(response.latestDraft()).isNull();
  }

  @Test
  void reportsNotFoundWithoutLookingForADraftWhenNoActiveSessionExists() {
    given(drawingSessionRepository.findActiveSessionsByChildId(CHILD_ID)).willReturn(List.of());

    assertError(
        () -> service.getActiveDrawingSession(CHILD_ID),
        DrawingErrorCode.ACTIVE_DRAWING_SESSION_NOT_FOUND);
    verifyNoInteractions(drawingAssetRepository);
  }

  @Test
  void reportsDataIntegrityFailureWithoutChoosingOneOfMultipleActiveSessions() {
    given(drawingSessionRepository.findActiveSessionsByChildId(CHILD_ID))
        .willReturn(List.of(session, duplicateSession));

    assertError(
        () -> service.getActiveDrawingSession(CHILD_ID),
        DrawingErrorCode.MULTIPLE_ACTIVE_DRAWING_SESSIONS);
    verifyNoInteractions(drawingAssetRepository);
  }

  private void assertError(Runnable invocation, DrawingErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }

  private void givenDetailSession() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(drawingSessionRepository.findDetailById(SESSION_ID)).willReturn(Optional.of(session));
    given(session.getId()).willReturn(SESSION_ID);
    given(session.getChild()).willReturn(child);
    given(child.getId()).willReturn(CHILD_ID);
    given(child.getNickname()).willReturn("fixture-child");
    given(session.getDrawingType()).willReturn(drawingType);
    given(drawingType.getId()).willReturn(7L);
    given(drawingType.getCode()).willReturn("HOUSE");
    given(drawingType.getName()).willReturn("집");
    given(session.getInputMethod()).willReturn(DrawingInputMethod.CANVAS);
    given(session.getTitle()).willReturn("우리 집");
    given(session.getSessionStatus()).willReturn(DrawingSessionStatus.IN_PROGRESS);
    given(session.getCurrentStage()).willReturn(DrawingStage.REFLECTION);
    given(session.getStartedAt()).willReturn(STARTED_AT);
  }
}
