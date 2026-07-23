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
import com.ssafy.b209.analysis.dto.BoundingBoxResponse;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisModelResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisRetryReason;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.dto.DrawingDetectionResponse;
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
    given(drawingAnalysisClient.analyze(any())).willReturn(successResponse(REQUEST_ID.toString()));
    given(
            persistenceService.complete(
                eq(ANALYSIS_ID), eq("mock-drawing-detector"), eq("1.0"), any(), any()))
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
    assertThat(response.processedAt()).isEqualTo(PROCESSED_AT);

    ArgumentCaptor<com.ssafy.b209.analysis.dto.DrawingAnalysisRequest> requestCaptor =
        ArgumentCaptor.forClass(com.ssafy.b209.analysis.dto.DrawingAnalysisRequest.class);
    verify(drawingAnalysisClient).analyze(requestCaptor.capture());
    assertThat(requestCaptor.getValue().requestId()).isEqualTo(REQUEST_ID.toString());
    assertThat(requestCaptor.getValue().imageReference().storageKey())
        .isEqualTo("drawing/final.png");
    assertThat(requestCaptor.getValue().imageReference().contentType()).isEqualTo("image/png");
  }

  @Test
  void acceptsSuccessfulResponseWithEmptyDetections() {
    givenStartedAnalysis();
    DrawingAnalysisResponse response =
        new DrawingAnalysisResponse(
            REQUEST_ID.toString(),
            DrawingAnalysisStatus.SUCCEEDED,
            new DrawingAnalysisModelResponse("mock-drawing-detector", "1.0"),
            List.of(),
            null,
            PROCESSED_AT);
    given(drawingAnalysisClient.analyze(any())).willReturn(response);
    given(persistenceService.complete(eq(ANALYSIS_ID), any(), any(), eq(List.of()), any()))
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
  void recordsInvalidResponseWhenRequestIdDoesNotMatch() {
    givenStartedAnalysis();
    given(drawingAnalysisClient.analyze(any()))
        .willReturn(successResponse("11111111-1111-4111-8111-111111111111"));

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
    given(drawingAnalysisClient.analyze(any())).willReturn(successResponse(REQUEST_ID.toString()));
    given(persistenceService.complete(eq(ANALYSIS_ID), any(), any(), any(), any()))
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
                "drawing/final.png",
                "image/png",
                LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)));
    given(drawingAnalysisClient.analyze(any())).willReturn(successResponse(REQUEST_ID.toString()));
    given(persistenceService.complete(eq(31L), any(), any(), any(), any()))
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
                LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)))
        .willReturn(
            new StartedDrawingAnalysis(
                ANALYSIS_ID,
                SESSION_ID,
                ASSET_ID,
                REQUEST_ID.toString(),
                "drawing/final.png",
                "image/png",
                LocalDateTime.ofInstant(REQUESTED_AT, ZoneOffset.UTC)));
  }

  private DrawingAnalysisResponse successResponse(String requestId) {
    return new DrawingAnalysisResponse(
        requestId,
        DrawingAnalysisStatus.SUCCEEDED,
        new DrawingAnalysisModelResponse("mock-drawing-detector", "1.0"),
        List.of(
            new DrawingDetectionResponse(
                "HOUSE",
                new BigDecimal("0.95"),
                new BoundingBoxResponse(
                    new BigDecimal("120"),
                    new BigDecimal("80"),
                    new BigDecimal("640"),
                    new BigDecimal("520")))),
        null,
        PROCESSED_AT);
  }

  private void assertError(Runnable invocation, DrawingAnalysisErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
