package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.service.DrawingAnalysisPersistenceService;
import com.ssafy.b209.analysis.service.DrawingAnalysisRequestSummary;
import com.ssafy.b209.analysis.service.DrawingAnalysisService;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.CompleteDrawingStageRequest;
import com.ssafy.b209.drawing.dto.response.CompleteDrawingStageResponse;
import com.ssafy.b209.drawing.dto.response.UploadDrawingSnapshotResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.StoreImageCommand;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DrawingStageCompletionServiceTest {

  private static final long SESSION_ID = 10L;
  private static final long GUARDIAN_ID = 20L;
  private static final long ASSET_ID = 30L;
  private static final long ANALYSIS_ID = 40L;
  private static final String KEY = "drawing-complete-key-0001";

  @Mock private DrawingSnapshotService drawingSnapshotService;
  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private DrawingAnalysisService drawingAnalysisService;
  @Mock private DrawingAnalysisPersistenceService analysisPersistenceService;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;
  @Mock private StoreImageCommand finalImage;

  private DrawingStageCompletionService service;

  @BeforeEach
  void setUp() {
    service =
        new DrawingStageCompletionService(
            drawingSnapshotService,
            drawingAssetRepository,
            drawingAnalysisService,
            analysisPersistenceService,
            currentUserResolver,
            accessValidator);
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
  }

  @Test
  void storesFinalImageAndReturnsTheCompletedAnalysisState() {
    CompleteDrawingStageRequest request = validRequest();
    given(analysisPersistenceService.findByRequestId(KEY))
        .willReturn(Optional.empty(), Optional.of(succeededSummary()));
    given(drawingSnapshotService.upload(eq(SESSION_ID), eq(finalImage), any()))
        .willReturn(snapshotResponse());

    CompleteDrawingStageResponse response = service.complete(SESSION_ID, KEY, finalImage, request);

    assertThat(response.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.finalAssetId()).isEqualTo(ASSET_ID);
    assertThat(response.currentStage()).isEqualTo(DrawingStage.CONVERSING);
    assertThat(response.analysis().status()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
    assertThat(response.nextAction()).isEqualTo("SELECT_EMOTION");
    verify(drawingAnalysisService)
        .requestAnalysis(
            SESSION_ID,
            new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION),
            KEY);
  }

  @Test
  void returnsTheStoredResultWithoutDuplicatingSideEffects() {
    given(analysisPersistenceService.findByRequestId(KEY))
        .willReturn(Optional.of(succeededSummary()));

    CompleteDrawingStageResponse response = service.complete(SESSION_ID, KEY, null, validRequest());

    assertThat(response.finalAssetId()).isEqualTo(ASSET_ID);
    verify(drawingSnapshotService, never()).upload(any(), any(), any());
    verify(drawingAnalysisService, never()).requestAnalysis(any(), any(), any());
  }

  @Test
  void reusesAStoredFinalAssetWhenThePreviousRequestStoppedBeforeAnalysisCreation() {
    DrawingAsset existingFinal = org.mockito.Mockito.mock(DrawingAsset.class);
    given(existingFinal.getId()).willReturn(ASSET_ID);
    given(
            drawingAssetRepository.findFirstByDrawingSessionIdAndAssetTypeOrderByAssetVersionDesc(
                SESSION_ID, DrawingAssetType.FINAL))
        .willReturn(Optional.of(existingFinal));
    given(analysisPersistenceService.findByRequestId(KEY))
        .willReturn(Optional.empty(), Optional.of(succeededSummary()));

    CompleteDrawingStageResponse response =
        service.complete(SESSION_ID, KEY, finalImage, validRequest());

    assertThat(response.finalAssetId()).isEqualTo(ASSET_ID);
    verify(drawingSnapshotService, never()).upload(any(), any(), any());
    verify(drawingAnalysisService)
        .requestAnalysis(
            SESSION_ID,
            new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION),
            KEY);
  }

  @Test
  void rejectsTheSameIdempotencyKeyForAnotherSession() {
    DrawingAnalysisRequestSummary otherSession =
        new DrawingAnalysisRequestSummary(
            ANALYSIS_ID,
            99L,
            ASSET_ID,
            DrawingAnalysisType.OBJECT_DETECTION,
            DrawingAnalysisState.SUCCESS,
            DrawingSessionStatus.IN_PROGRESS,
            DrawingStage.CONVERSING);
    given(analysisPersistenceService.findByRequestId(KEY)).willReturn(Optional.of(otherSession));

    assertError(
        () -> service.complete(SESSION_ID, KEY, null, validRequest()),
        DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT);
  }

  @Test
  void returnsFailedAnalysisAsAFallbackWhenTheAiClientFails() {
    given(analysisPersistenceService.findByRequestId(KEY))
        .willReturn(Optional.empty(), Optional.of(failedSummary()));
    given(drawingSnapshotService.upload(eq(SESSION_ID), eq(finalImage), any()))
        .willReturn(snapshotResponse());
    willThrow(new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED))
        .given(drawingAnalysisService)
        .requestAnalysis(
            SESSION_ID,
            new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION),
            KEY);

    CompleteDrawingStageResponse response =
        service.complete(SESSION_ID, KEY, finalImage, validRequest());

    assertThat(response.analysis().status()).isEqualTo(DrawingAnalysisStatus.FAILED);
    assertThat(response.currentStage()).isEqualTo(DrawingStage.CONVERSING);
    assertThat(response.nextAction()).isEqualTo("SELECT_EMOTION");
  }

  @Test
  void validatesTheIdempotencyKeyMetadataAndInitialImage() {
    assertError(
        () -> service.complete(SESSION_ID, "short", finalImage, validRequest()),
        DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
    assertError(
        () -> service.complete(SESSION_ID, KEY, finalImage, null),
        DrawingErrorCode.DRAWING_SNAPSHOT_METADATA_INVALID);
    assertError(
        () -> service.complete(SESSION_ID, KEY, null, validRequest()),
        DrawingErrorCode.DRAWING_SNAPSHOT_FILE_REQUIRED);
  }

  private CompleteDrawingStageRequest validRequest() {
    return new CompleteDrawingStageRequest(
        null, 15L, 120_000L, OffsetDateTime.of(2026, 7, 25, 10, 0, 0, 0, ZoneOffset.UTC));
  }

  private UploadDrawingSnapshotResponse snapshotResponse() {
    return new UploadDrawingSnapshotResponse(
        ASSET_ID,
        SESSION_ID,
        DrawingAssetType.FINAL,
        1,
        "image/png",
        100L,
        1200,
        800,
        "checksum",
        Instant.parse("2026-07-25T10:00:00Z"),
        Instant.parse("2026-07-25T10:00:01Z"));
  }

  private DrawingAnalysisRequestSummary succeededSummary() {
    return summary(DrawingAnalysisState.SUCCESS);
  }

  private DrawingAnalysisRequestSummary failedSummary() {
    return summary(DrawingAnalysisState.FAILED);
  }

  private DrawingAnalysisRequestSummary summary(DrawingAnalysisState state) {
    return new DrawingAnalysisRequestSummary(
        ANALYSIS_ID,
        SESSION_ID,
        ASSET_ID,
        DrawingAnalysisType.OBJECT_DETECTION,
        state,
        DrawingSessionStatus.IN_PROGRESS,
        DrawingStage.CONVERSING);
  }

  private void assertError(Runnable invocation, DrawingErrorCode expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
