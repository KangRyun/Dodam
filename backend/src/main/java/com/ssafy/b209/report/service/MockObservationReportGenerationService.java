package com.ssafy.b209.report.service;

import com.ssafy.b209.drawing.service.StrokeBehaviorSummary;
import com.ssafy.b209.drawing.service.StrokeBehaviorSummaryService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ErrorCode;
import com.ssafy.b209.infrastructure.ai.observation.AiObservationClient;
import com.ssafy.b209.infrastructure.ai.observation.AiObservationClientException;
import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.exception.MockObservationReportErrorCode;
import java.sql.SQLException;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.NestedExceptionUtils;
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
  private final StrokeBehaviorSummaryService behaviorSummaryService;
  private final Supplier<UUID> requestIdSupplier;

  /**
   * 관찰 리포트 생성 조율에 필요한 저장 경계와 Client를 주입받는다.
   *
   * @param persistenceService 맥락 조회와 결과 저장을 담당하는 서비스
   * @param observationClient 활성화된 관찰 리포트 생성 Client
   * @param behaviorSummaryService 저장된 Stroke 배치에서 형식 지표를 집계하는 경계 (S15P11B209-837)
   */
  @Autowired
  public MockObservationReportGenerationService(
      ObservationReportPersistenceService persistenceService,
      AiObservationClient observationClient,
      StrokeBehaviorSummaryService behaviorSummaryService) {
    this(persistenceService, observationClient, behaviorSummaryService, UUID::randomUUID);
  }

  MockObservationReportGenerationService(
      ObservationReportPersistenceService persistenceService,
      AiObservationClient observationClient,
      StrokeBehaviorSummaryService behaviorSummaryService,
      Supplier<UUID> requestIdSupplier) {
    this.persistenceService = Objects.requireNonNull(persistenceService);
    this.observationClient = Objects.requireNonNull(observationClient);
    this.behaviorSummaryService = Objects.requireNonNull(behaviorSummaryService);
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
    } catch (BusinessException exception) {
      // 저장 계층이 이미 분류한 실패다. 여기서 REPORT_STORAGE_FAILED로 덮으면 generation-status의
      // failureReason이 실제 원인과 무관해진다(S15P11B209-815).
      ErrorCode errorCode = exception.getErrorCode();
      String failureCode = classificationOf(errorCode);
      log.error(
          "관찰 리포트 저장에 실패했습니다. analysisId={}, failureCode={}, rootCause={}",
          analysisId,
          failureCode,
          describeRootCause(exception));
      persistenceService.markFailed(
          analysisId, context.reportId(), failureCode, errorCode.getMessage());
    } catch (RuntimeException exception) {
      log.error(
          "관찰 리포트 저장에 실패했습니다. analysisId={}, exceptionType={}, rootCause={}",
          analysisId,
          exception.getClass().getSimpleName(),
          describeRootCause(exception));
      persistenceService.markFailed(
          analysisId,
          context.reportId(),
          "REPORT_STORAGE_FAILED",
          MockObservationReportErrorCode.REPORT_STORAGE_FAILED.getMessage());
    }
  }

  /**
   * 실패 분류 코드를 고른다.
   *
   * <p>이 경로의 다른 실패 코드(예: {@code TIMEOUT})가 모두 Enum 이름이라 형식을 맞춘다. Enum이 아닌 구현은 응답 코드로 대체한다.
   */
  private static String classificationOf(ErrorCode errorCode) {
    return errorCode instanceof Enum<?> enumCode ? enumCode.name() : errorCode.getCode();
  }

  /**
   * 진단에 필요한 최소 정보만으로 근본 원인을 설명한다.
   *
   * <p>예외 메시지에는 SQL 문과 Bind 값이 섞여 아동 발화나 AI 원문이 그대로 실릴 수 있어 남기지 않는다. 대신 원인 예외 유형과, 데이터베이스 오류면 값이 아닌
   * SQLState·Vendor 코드를 남긴다. 길이 초과는 SQLState {@code 22001}로 드러나 원인을 바로 좁힐 수 있다.
   */
  private static String describeRootCause(Throwable exception) {
    Throwable rootCause = NestedExceptionUtils.getMostSpecificCause(exception);
    String type = rootCause.getClass().getSimpleName();
    if (rootCause instanceof SQLException sqlException) {
      return "%s(sqlState=%s, vendorCode=%d)"
          .formatted(type, sqlException.getSQLState(), sqlException.getErrorCode());
    }
    return type;
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
        toSubjectSummaries(context),
        toSelectedEmotionRefs(context),
        behaviorMetrics(context));
  }

  /**
   * 이 리포트가 다루는 세션들의 형식 지표를 집계해 AI 계약 형태로 옮긴다 (S15P11B209-837).
   *
   * <p><b>이 값이 없으면 AI 프롬프트의 {@code [형식적 분석]} 블록이 통째로 만들어지지 않는다.</b> 계약에는 자리가 있었지만 서버가 채우지 않아 운영에서 한
   * 번도 실린 적이 없던 지표다.
   *
   * <p>{@link StrokeBehaviorSummaryService#summarizeAllOrNone(java.util.List)} 를 쓴다 — 보호자 화면용
   * {@code summarizeAll} 과 달리 <b>한 세션이라도 집계할 수 없으면 전체를 버린다.</b> 근거는 그 메서드 javadoc.
   *
   * <p>Transaction 밖에서 호출한다. 읽는 곳이 MongoDB 라 JPA 와 별개로 실패할 수 있고, 그때 리포트 생성 전체를 죽이는 것은 균형에 맞지 않는다 —
   * 형식 지표는 관찰의 부가 재료다. 실패하면 경고만 남기고 {@code null} 로 보내 AI 가 해당 블록 없이 리포트를 만든다.
   *
   * <p>예외 메시지는 남기지 않는다. Mongo 예외에 질의 조건이 섞여 아동 식별자가 로그로 새어 나갈 수 있다(가드레일 9절).
   *
   * @param context 대상 세션 목록을 가진 생성 맥락
   * @return 집계된 형식 지표이며 집계할 수 없거나 실패하면 {@code null}
   */
  private ObservationGenerationRequest.BehaviorMetrics behaviorMetrics(
      ObservationGenerationContext context) {
    List<Long> sessionIds = context.activitySessionIds();
    if (sessionIds == null || sessionIds.isEmpty()) {
      sessionIds = List.of(context.drawingSessionId());
    }
    try {
      return behaviorSummaryService.summarizeAllOrNone(sessionIds).map(Metrics::of).orElse(null);
    } catch (RuntimeException exception) {
      log.warn(
          "[837] 형식 지표 집계에 실패해 behaviorMetrics 없이 관찰 리포트를 요청한다: analysisId={}, exceptionType={}",
          context.analysisId(),
          exception.getClass().getName());
      return null;
    }
  }

  /**
   * 집계 결과를 AI 계약 형태로 옮긴다.
   *
   * <p>도메인 Record 를 계약 Record 로 바꾸기만 하며 <b>값을 만들지도 채우지도 않는다.</b> {@code null} 은 {@code null} 그대로 간다
   * — 여기서 0을 채우면 "집계하지 못함"이 "0회"라는 관찰 사실로 바뀐다.
   */
  private static final class Metrics {

    private Metrics() {}

    static ObservationGenerationRequest.BehaviorMetrics of(StrokeBehaviorSummary summary) {
      return new ObservationGenerationRequest.BehaviorMetrics(
          summary.drawingDurationMs(),
          summary.activeDrawingMs(),
          summary.pauseCount(),
          summary.undoCount(),
          summary.eraseCount(),
          summary.toolChangeCount(),
          summary.colorChangeCount(),
          summary.pressureAvailable(),
          // averagePressure — 집계기가 만들지 않는 값이다. 계약에 자리가 있다고 지어내지 않는다.
          null,
          summary.truncated());
    }
  }

  /**
   * 주제별 수집 맥락을 AI 계약의 {@code subjectSummaries}로 옮긴다 (S15P11B209-741).
   *
   * <p>계약({@code docs/ai/ai-observation-report-contract.md})과 1:1 — 비어 있으면 AI가 기존 집계·대표 발화 경로로
   * 동작한다(롤아웃 호환).
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
                                    line.questionText(),
                                    line.answerText(),
                                    line.answerType(),
                                    line.questionMessageId(),
                                    line.answerMessageId(),
                                    line.sttNeedsConfirmation()))
                        .toList(),
                    evidenceSourceId(subject.observationResultId()),
                    subject.detectedObjects().stream()
                        .map(
                            detected ->
                                new ObservationGenerationRequest.SubjectDetectedObject(
                                    evidenceSourceId(detected.detectedObjectId()),
                                    detected.objectCode(),
                                    detected.x(),
                                    detected.y(),
                                    detected.width(),
                                    detected.height(),
                                    // areaRatio 는 저장된 값만 옮긴다. 없으면 null 이며
                                    //   width * height 로 계산해 채우지 않는다(AI 계약 명시).
                                    detected.areaRatio(),
                                    detected.confidence()))
                        .toList()))
        .toList();
  }

  /**
   * 서버가 발급한 행 식별자를 AI 계약이 요구하는 문자열로 옮긴다 (S15P11B209-837).
   *
   * <p>AI 계약의 근거 식별자는 전부 {@code str} 이다. 숫자로 보내면 Pydantic 이 {@code "Input should be a valid
   * string"} 으로 요청 <b>전체</b>를 거부한다 — 필드 하나 때문에 리포트 생성이 통째로 실패한다. 실제로 2026-08-05 운영에서 {@code POST
   * /internal/v1/observations} 가 전량 422 로 실패했고, 그중 하나가 이 타입 불일치였다.
   *
   * @param id 서버가 발급한 행 식별자이며 없으면 {@code null}
   * @return 문자열로 옮긴 식별자이며 원본이 없으면 {@code null}
   */
  private static String evidenceSourceId(Long id) {
    return id == null ? null : String.valueOf(id);
  }

  /**
   * 선택 감정을 근거로 참조할 수 있는 형태로 옮긴다 (S15P11B209-906).
   *
   * <p>코드 목록({@code selectedEmotions})은 프롬프트 재료로 그대로 남기고, 근거 참조용 행 식별자를 함께 보낸다. AI 는 서버가 발급한 식별자만
   * {@code sourceRef} 로 쓰므로(조합키 금지) 이 값이 없으면 감정 근거가 공개 게이트를 통과할 수 없다.
   *
   * @param context 리포트 생성 맥락
   * @return 행 식별자와 감정 코드 쌍 목록
   */
  private List<ObservationGenerationRequest.SelectedEmotionRef> toSelectedEmotionRefs(
      ObservationGenerationContext context) {
    return context.selectedEmotionRefs().stream()
        .map(
            emotion ->
                new ObservationGenerationRequest.SelectedEmotionRef(
                    evidenceSourceId(emotion.emotionId()), emotion.emotionCode()))
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
