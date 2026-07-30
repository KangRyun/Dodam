package com.ssafy.b209.report.service;

import com.ssafy.b209.infrastructure.ai.observation.AiObservationClient;
import com.ssafy.b209.infrastructure.ai.observation.AiObservationClientException;
import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.exception.MockObservationReportErrorCode;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

/**
 * 최종 분석 관찰 리포트 생성을 Transaction 밖에서 조율한다.
 *
 * <p>맥락 조회와 저장은 {@link ObservationReportPersistenceService}가 담당하고, 이 서비스는 활성 {@link
 * AiObservationClient} 호출과 응답 검증을 수행한다. 대상이 이미 완료됐으면 재생성 없이 종료해 멱등성을 보장한다.
 */
@Service
public class MockObservationReportGenerationService {

  private static final Logger log =
      LoggerFactory.getLogger(MockObservationReportGenerationService.class);
  private static final String ANALYSIS_TYPE_FINAL = "FINAL";

  private final ObservationReportPersistenceService persistenceService;
  private final AiObservationClient observationClient;
  private final Supplier<UUID> requestIdSupplier;

  /**
   * 관찰 리포트 생성 조율에 필요한 저장 경계와 Client를 주입받는다.
   *
   * @param persistenceService 맥락 조회와 결과 저장을 담당하는 서비스
   * @param observationClient 활성화된 관찰 리포트 생성 Client
   */
  @Autowired
  public MockObservationReportGenerationService(
      ObservationReportPersistenceService persistenceService,
      AiObservationClient observationClient) {
    this(persistenceService, observationClient, UUID::randomUUID);
  }

  MockObservationReportGenerationService(
      ObservationReportPersistenceService persistenceService,
      AiObservationClient observationClient,
      Supplier<UUID> requestIdSupplier) {
    this.persistenceService = Objects.requireNonNull(persistenceService);
    this.observationClient = Objects.requireNonNull(observationClient);
    this.requestIdSupplier = Objects.requireNonNull(requestIdSupplier);
  }

  /**
   * 대기 중인 최종 분석의 관찰 리포트를 생성해 리포트를 완료 상태로 채운다.
   *
   * <p>대상이 없거나 이미 완료됐으면 아무 작업도 하지 않는다. Client 호출, 응답 검증, 저장 중 실패가 발생하면 분석과 리포트를 실패 상태로 기록하고 예외를
   * 전파하지 않는다.
   *
   * @param analysisId 완료 접수가 생성한 대기 중 최종 분석 식별자
   */
  public void generate(Long analysisId) {
    Optional<ObservationGenerationContext> contextOptional =
        persistenceService.loadContext(analysisId);
    if (contextOptional.isEmpty()) {
      return;
    }
    ObservationGenerationContext context = contextOptional.get();
    String requestId = requestIdSupplier.get().toString();
    ObservationGenerationRequest request = buildRequest(requestId, context);

    ObservationGenerationResult result;
    try {
      result = observationClient.generate(request);
    } catch (AiObservationClientException exception) {
      log.warn(
          "관찰 리포트 생성 호출에 실패했습니다. analysisId={}, failureType={}", analysisId, exception.getType());
      persistenceService.markFailed(
          analysisId,
          context.reportId(),
          exception.getType().name(),
          MockObservationReportErrorCode.OBSERVATION_GENERATION_FAILED.getMessage());
      return;
    }

    String invalidReason = validate(requestId, result);
    if (invalidReason != null) {
      log.warn("관찰 리포트 생성 응답이 유효하지 않습니다. analysisId={}, reason={}", analysisId, invalidReason);
      persistenceService.markFailed(
          analysisId,
          context.reportId(),
          invalidReason,
          MockObservationReportErrorCode.OBSERVATION_INVALID_RESPONSE.getMessage());
      return;
    }

    try {
      persistenceService.complete(context, result);
    } catch (RuntimeException exception) {
      log.error(
          "관찰 리포트 저장에 실패했습니다. analysisId={}, exceptionType={}",
          analysisId,
          exception.getClass().getSimpleName());
      persistenceService.markFailed(
          analysisId,
          context.reportId(),
          "REPORT_STORAGE_FAILED",
          MockObservationReportErrorCode.REPORT_STORAGE_FAILED.getMessage());
    }
  }

  private ObservationGenerationRequest buildRequest(
      String requestId, ObservationGenerationContext context) {
    return new ObservationGenerationRequest(
        requestId,
        context.analysisId(),
        context.drawingSessionId(),
        ANALYSIS_TYPE_FINAL,
        context.questionDifficulty(),
        context.questionCount(),
        context.answeredCount(),
        context.skippedCount(),
        context.unrecognizedSpeechCount(),
        context.selectedEmotions(),
        context.expressedEmotionText(),
        context.representativeUtterance(),
        toSubjectSummaries(context));
  }

  /**
   * 주제별 수집 맥락을 AI 계약의 {@code subjectSummaries}로 옮긴다 (S15P11B209-741).
   *
   * <p>계약({@code docs/ai/ai-observation-report-contract.md})과 1:1 — 비어 있으면 AI가 기존
   * 집계·대표 발화 경로로 동작한다(롤아웃 호환).
   */
  private List<ObservationGenerationRequest.SubjectSummary> toSubjectSummaries(
      ObservationGenerationContext context) {
    return context.subjectContexts().stream()
        .map(
            subject ->
                new ObservationGenerationRequest.SubjectSummary(
                    subject.drawingSubject(),
                    subject.drawingDescription(),
                    subject.detectedObjectCodes(),
                    subject.qaPairs().stream()
                        .map(
                            line ->
                                new ObservationGenerationRequest.SubjectQaPair(
                                    line.questionText(), line.answerText(), line.answerType()))
                        .toList()))
        .toList();
  }

  private String validate(String requestId, ObservationGenerationResult result) {
    if (result == null || result.observationDraft() == null) {
      return "INVALID_RESPONSE";
    }
    if (!requestId.equals(result.requestId())) {
      return "REQUEST_ID_MISMATCH";
    }
    if (isBlank(result.modelName()) || isBlank(result.modelVersion())) {
      return "MODEL_MISSING";
    }
    if (isBlank(result.observationDraft().disclaimer())) {
      return "DISCLAIMER_MISSING";
    }
    if (isBlank(result.limitationsText())) {
      return "LIMITATIONS_MISSING";
    }
    return null;
  }

  private static boolean isBlank(String value) {
    return value == null || value.isBlank();
  }
}
