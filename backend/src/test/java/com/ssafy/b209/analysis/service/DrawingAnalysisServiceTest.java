package com.ssafy.b209.analysis.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisTriggerReason;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisRetryReason;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.dto.RetryDrawingAnalysisRequest;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClient;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClientException;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataAccessResourceFailureException;

@ExtendWith(MockitoExtension.class)
class DrawingAnalysisServiceTest {

  private static final long SESSION_ID = 10L;
  private static final long GUARDIAN_USER_ID = 41L;
  private static final long ASSET_ID = 20L;
  private static final long ANALYSIS_ID = 30L;
  private static final Instant REQUESTED_AT = Instant.parse("2026-07-22T05:00:00Z");
  private static final Instant PROCESSED_AT = Instant.parse("2026-07-22T05:00:01Z");
  private static final UUID REQUEST_ID = UUID.fromString("550e8400-e29b-41d4-a716-446655440000");

  @Mock private DrawingAnalysisPersistenceService persistenceService;
  @Mock private DrawingAnalysisClient drawingAnalysisClient;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private DrawingAnalysisService service;

  @BeforeEach
  void setUp() {
    Validator validator = Validation.buildDefaultValidatorFactory().getValidator();
    service =
        new DrawingAnalysisService(
            persistenceService,
            drawingAnalysisClient,
            validator,
            Clock.fixed(REQUESTED_AT, ZoneOffset.UTC),
            currentUserResolver,
            accessValidator,
            () -> REQUEST_ID);
  }

  @Test
  void rejectsUnownedSessionBeforeStartingOrCallingAi() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(
            new BusinessException(
                com.ssafy.b209.drawing.exception.DrawingErrorCode.DRAWING_SESSION_NOT_FOUND))
        .given(accessValidator)
        .requireDrawingSessionAccess(GUARDIAN_USER_ID, SESSION_ID);

    assertThatThrownBy(
            () ->
                service.requestAnalysis(
                    SESSION_ID,
                    new CreateDrawingAnalysisRequest(
                        ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION)))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(persistenceService, drawingAnalysisClient);
  }

  @Test
  void requestsAnalysisAndReturnsStoredSuccessResult() {
    givenStartedAnalysis();
    given(drawingAnalysisClient.analyze(any())).willReturn(successResponse(ANALYSIS_ID));
    given(persistenceService.completeCanonical(eq(ANALYSIS_ID), any(), any()))
        .willReturn(org.mockito.Mockito.mock(DrawingAnalysis.class));

    CreateDrawingAnalysisResponse response =
        service.requestAnalysis(
            SESSION_ID,
            new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION));

    assertThat(response.drawingAnalysisId()).isEqualTo(ANALYSIS_ID);
    assertThat(response.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.drawingAssetId()).isEqualTo(ASSET_ID);
    assertThat(response.requestId()).isEqualTo(REQUEST_ID.toString());
    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
    assertThat(response.model().name()).isEqualTo("mock-drawing-detector");
    assertThat(response.detections()).hasSize(1);
    assertThat(response.requestedAt()).isEqualTo(REQUESTED_AT);
    assertThat(response.processedAt()).isEqualTo(REQUESTED_AT);

    ArgumentCaptor<com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand> requestCaptor =
        ArgumentCaptor.forClass(com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand.class);
    verify(drawingAnalysisClient).analyze(requestCaptor.capture());
    assertThat(requestCaptor.getValue().requestId()).isEqualTo(REQUEST_ID.toString());
    assertThat(requestCaptor.getValue().analysisId()).isEqualTo(ANALYSIS_ID);
    assertThat(requestCaptor.getValue().storageKey()).isEqualTo("drawing/final.png");
    assertThat(requestCaptor.getValue().mimeType()).isEqualTo("image/png");
  }

  @Test
  void usesCallerProvidedRequestIdForDrawingStageCompletion() {
    String idempotencyKey = "drawing-complete-key-0001";
    given(
            persistenceService.startForDrawingCompletion(
                SESSION_ID,
                ASSET_ID,
                DrawingAnalysisType.OBJECT_DETECTION,
                idempotencyKey,
                DrawingAnalysisTriggerReason.USER_REQUEST,
                LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)))
        .willReturn(
            new StartedDrawingAnalysis(
                ANALYSIS_ID,
                SESSION_ID,
                ASSET_ID,
                idempotencyKey,
                com.ssafy.b209.analysis.domain.DrawingAnalysisScope.FINAL,
                DrawingAnalysisActivityType.HTP,
                DrawingAnalysisSubject.HOUSE,
                "drawing/final.png",
                "image/png",
                1200,
                800,
                "checksum",
                LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)));
    given(drawingAnalysisClient.analyze(any())).willReturn(successResponse(ANALYSIS_ID));
    given(persistenceService.completeCanonical(eq(ANALYSIS_ID), any(), any()))
        .willReturn(org.mockito.Mockito.mock(DrawingAnalysis.class));

    CreateDrawingAnalysisResponse response =
        service.requestAnalysis(
            SESSION_ID,
            new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION),
            idempotencyKey);

    assertThat(response.requestId()).isEqualTo(idempotencyKey);
    verify(persistenceService)
        .startForDrawingCompletion(
            SESSION_ID,
            ASSET_ID,
            DrawingAnalysisType.OBJECT_DETECTION,
            idempotencyKey,
            DrawingAnalysisTriggerReason.USER_REQUEST,
            LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC));
  }

  @Test
  void acceptsSuccessfulResponseWithEmptyDetections() {
    givenStartedAnalysis();
    var response = successResponse(ANALYSIS_ID, List.of());
    given(drawingAnalysisClient.analyze(any())).willReturn(response);
    given(persistenceService.completeCanonical(eq(ANALYSIS_ID), any(), any()))
        .willReturn(org.mockito.Mockito.mock(DrawingAnalysis.class));

    CreateDrawingAnalysisResponse result =
        service.requestAnalysis(
            SESSION_ID,
            new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION));

    assertThat(result.detections()).isEmpty();
  }

  @Test
  void recordsFailureWhenClientCallFails() {
    givenStartedAnalysis();
    given(drawingAnalysisClient.analyze(any()))
        .willThrow(new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.TIMEOUT));

    assertError(
        () ->
            service.requestAnalysis(
                SESSION_ID,
                new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION)),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED);

    verify(persistenceService)
        .fail(
            eq(ANALYSIS_ID),
            eq("TIMEOUT"),
            eq(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED.getMessage()),
            eq(LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)));
  }

  @Test
  void recordsFailureWhenTheClientThrowsAnUnexpectedRuntimeException() {
    givenStartedAnalysis();
    given(drawingAnalysisClient.analyze(any()))
        .willThrow(new IllegalStateException("unexpected client failure"));

    assertError(
        () ->
            service.requestAnalysis(
                SESSION_ID,
                new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION)),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED);

    verify(persistenceService)
        .fail(
            eq(ANALYSIS_ID),
            eq("UNEXPECTED_CLIENT_ERROR"),
            eq(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED.getMessage()),
            eq(LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)));
  }

  @Test
  void recordsInvalidResponseWhenAnalysisIdDoesNotMatch() {
    givenStartedAnalysis();
    given(drawingAnalysisClient.analyze(any())).willReturn(successResponse(11111111L));

    assertError(
        () ->
            service.requestAnalysis(
                SESSION_ID,
                new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION)),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_INVALID_RESPONSE);

    verify(persistenceService)
        .fail(
            eq(ANALYSIS_ID),
            eq("INVALID_RESPONSE"),
            eq(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_INVALID_RESPONSE.getMessage()),
            eq(LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)));
  }

  @Test
  void recordsFailureWhenResultSaveFails() {
    givenStartedAnalysis();
    given(drawingAnalysisClient.analyze(any())).willReturn(successResponse(ANALYSIS_ID));
    given(persistenceService.completeCanonical(eq(ANALYSIS_ID), any(), any()))
        .willThrow(new DataAccessResourceFailureException("db unavailable"));

    assertError(
        () ->
            service.requestAnalysis(
                SESSION_ID,
                new CreateDrawingAnalysisRequest(ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION)),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_SAVE_FAILED);

    verify(persistenceService)
        .fail(
            eq(ANALYSIS_ID),
            eq("RESULT_SAVE_FAILED"),
            eq(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_SAVE_FAILED.getMessage()),
            eq(LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)));
  }

  @Test
  void retriesAFailedAnalysisAfterCheckingGuardianAccess() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(persistenceService.findRetrySource(ANALYSIS_ID))
        .willReturn(new RetryDrawingAnalysisSource(ANALYSIS_ID, SESSION_ID));
    given(
            persistenceService.startRetry(
                ANALYSIS_ID,
                true,
                REQUEST_ID.toString(),
                LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)))
        .willReturn(
            new StartedDrawingAnalysis(
                31L,
                SESSION_ID,
                ASSET_ID,
                REQUEST_ID.toString(),
                com.ssafy.b209.analysis.domain.DrawingAnalysisScope.FINAL,
                DrawingAnalysisActivityType.HTP,
                DrawingAnalysisSubject.HOUSE,
                "drawing/final.png",
                "image/png",
                null,
                null,
                null,
                LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)));
    given(drawingAnalysisClient.analyze(any())).willReturn(successResponse(31L));
    given(persistenceService.completeCanonical(eq(31L), any(), any()))
        .willReturn(org.mockito.Mockito.mock(DrawingAnalysis.class));

    CreateDrawingAnalysisResponse response =
        service.retryAnalysis(
            ANALYSIS_ID,
            new RetryDrawingAnalysisRequest(DrawingAnalysisRetryReason.USER_REQUEST, true));

    verify(accessValidator).requireDrawingSessionAccess(GUARDIAN_USER_ID, SESSION_ID);
    assertThat(response.drawingAnalysisId()).isEqualTo(31L);
    assertThat(response.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
  }

  private void givenStartedAnalysis() {
    given(
            persistenceService.start(
                SESSION_ID,
                ASSET_ID,
                DrawingAnalysisType.OBJECT_DETECTION,
                REQUEST_ID.toString(),
                DrawingAnalysisTriggerReason.USER_REQUEST,
                LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)))
        .willReturn(
            new StartedDrawingAnalysis(
                ANALYSIS_ID,
                SESSION_ID,
                ASSET_ID,
                REQUEST_ID.toString(),
                com.ssafy.b209.analysis.domain.DrawingAnalysisScope.FINAL,
                DrawingAnalysisActivityType.HTP,
                DrawingAnalysisSubject.HOUSE,
                "drawing/final.png",
                "image/png",
                null,
                null,
                null,
                LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)));
  }

  private com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
      successResponse(Long analysisId) {
    var detection =
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
            .DetectedObject(
            "HOUSE",
            "집",
            new BigDecimal("0.95"),
            new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
                .BoundingBox(
                new BigDecimal("0.1"),
                new BigDecimal("0.1"),
                new BigDecimal("0.4"),
                new BigDecimal("0.5")),
            new BigDecimal("0.2"),
            0);
    return successResponse(analysisId, List.of(detection));
  }

  private com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
      successResponse(
          Long analysisId,
          List<
                  com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
                      .DetectedObject>
              detections) {
    var model =
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.ModelRef(
            "mock-drawing-detector", "1.0");
    return new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse(
        analysisId,
        com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.AnalysisStatus
            .SUCCESS,
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.ModelInfo(
            model, null, null, null),
        detections,
        java.util.Map.of(),
        java.util.Map.of(),
        null,
        null,
        List.of(),
        List.of(),
        List.of(),
        10L);
  }

  private void assertError(Runnable invocation, DrawingAnalysisErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
