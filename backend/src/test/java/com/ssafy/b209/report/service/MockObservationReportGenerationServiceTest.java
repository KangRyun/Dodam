package com.ssafy.b209.report.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.drawing.service.StrokeBehaviorAggregate;
import com.ssafy.b209.drawing.service.StrokeBehaviorSummary;
import com.ssafy.b209.drawing.service.StrokeBehaviorSummaryService;
import com.ssafy.b209.drawing.service.SubjectStrokeSession;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.observation.AiObservationClient;
import com.ssafy.b209.infrastructure.ai.observation.AiObservationClientException;
import com.ssafy.b209.report.dto.ObservationGeneration;
import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ConversationSummaryDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservationDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservedFeatureDraft;
import com.ssafy.b209.report.exception.MockObservationReportErrorCode;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

@ExtendWith(MockitoExtension.class)
class MockObservationReportGenerationServiceTest {

  private static final long ANALYSIS_ID = 701L;
  private static final long REPORT_ID = 900L;
  private static final UUID REQUEST_UUID = UUID.fromString("00000000-0000-0000-0000-0000000000aa");

  @Mock private ObservationReportPersistenceService persistenceService;
  @Mock private AiObservationClient observationClient;
  @Mock private StrokeBehaviorSummaryService behaviorSummaryService;
  @Captor private ArgumentCaptor<ObservationGenerationRequest> requestCaptor;

  private MockObservationReportGenerationService service;

  @BeforeEach
  void setUp() {
    service =
        new MockObservationReportGenerationService(
            persistenceService, observationClient, behaviorSummaryService, () -> REQUEST_UUID);
  }

  @Test
  void generatesAndPersistsWhenContextIsPending() {
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    ObservationGenerationRequest request = requestCaptor.getValue();
    org.assertj.core.api.Assertions.assertThat(request.analysisType()).isEqualTo("FINAL");
    org.assertj.core.api.Assertions.assertThat(request.questionCount()).isEqualTo(3);
    org.assertj.core.api.Assertions.assertThat(request.answeredCount()).isEqualTo(2);
    // 연령 규준 축(S15P11B209-1001) — 컨텍스트의 만 나이가 AI 요청까지 흘러야
    // 프롬프트의 연령 발달 문맥이 실린다. 빠지면 조용히 "나이 없음" 경로가 된다.
    org.assertj.core.api.Assertions.assertThat(request.childAge()).isEqualTo(7);
    verify(persistenceService).complete(any(ObservationGenerationContext.class), any());
    verify(persistenceService, never()).markFailed(any(), any(), any(), any());
  }

  @Test
  void mapsSubjectContextsIntoSubjectSummaries() {
    // 주제별 수집 맥락(741)이 AI 계약 subjectSummaries(740)로 1:1 매핑되는지 검증한다.
    ObservationGenerationContext context =
        new ObservationGenerationContext(
            ANALYSIS_ID,
            100L,
            REPORT_ID,
            50L,
            "NORMAL",
            3,
            2,
            1,
            0,
            List.of("HAPPY"),
            "행복했어요",
            List.of(),
            List.of(
                new ObservationGenerationContext.SubjectContext(
                    "HOUSE",
                    "가운데에 집이 크게 그려져 있어요.",
                    List.of("HOUSE_DOOR"),
                    List.of(
                        new ObservationGenerationContext.KeyConversationLine(
                            1L, "이 집에는 누가 살아?", 2L, "엄마랑 나!", "VOICE_ANSWER", false)),
                    900L,
                    List.of(houseDoorRef())),
                new ObservationGenerationContext.SubjectContext(
                    null, "공룡이 풍선을 들고 있어요.", List.of(), List.of(), 901L, List.of())),
            List.of(new ObservationGenerationContext.SelectedEmotionRef(920L, "HAPPY")),
            List.of(new ObservationGenerationContext.ActivitySessionRef(100L, null)),
        7);
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    List<ObservationGenerationRequest.SubjectSummary> summaries =
        requestCaptor.getValue().subjectSummaries();
    org.assertj.core.api.Assertions.assertThat(summaries).hasSize(2);
    org.assertj.core.api.Assertions.assertThat(summaries.get(0).drawingSubject())
        .isEqualTo("HOUSE");
    org.assertj.core.api.Assertions.assertThat(summaries.get(0).drawingDescription())
        .isEqualTo("가운데에 집이 크게 그려져 있어요.");
    org.assertj.core.api.Assertions.assertThat(summaries.get(0).detectedObjectCodes())
        .containsExactly("HOUSE_DOOR");
    org.assertj.core.api.Assertions.assertThat(summaries.get(0).qaPairs())
        .containsExactly(
            new ObservationGenerationRequest.SubjectQaPair(
                "이 집에는 누가 살아?", "엄마랑 나!", "VOICE_ANSWER", 1L, 2L, false));
    // 그림일기 항목 — 주제 없음(null)이 그대로 전달된다.
    org.assertj.core.api.Assertions.assertThat(summaries.get(1).drawingSubject()).isNull();
  }

  @Test
  void sendsServerIssuedEvidenceIdentifiersSoGateCanVerifyIndependence() {
    // AI 는 서버가 발급한 식별자만 근거(sourceRef)로 쓴다 — 조합키 조립은 계약 §4에서 금지된다.
    // 이 값들을 보내지 않으면 구조 게이트가 NO_EVIDENCE 로 모든 카드를 탈락시켜
    // publicInterpretations 가 항상 빈 배열이 된다(S15P11B209-906).
    given(persistenceService.loadContext(ANALYSIS_ID))
        .willReturn(Optional.of(contextWithIdentifiers()));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    ObservationGenerationRequest request = requestCaptor.getValue();
    ObservationGenerationRequest.SubjectSummary summary = request.subjectSummaries().getFirst();

    // AI 계약의 근거 식별자는 전부 str 이다. 숫자로 보내면 요청 전체가 422 로 거부된다.
    org.assertj.core.api.Assertions.assertThat(summary.observationEvidenceSourceId())
        .isEqualTo("900");
    org.assertj.core.api.Assertions.assertThat(summary.detectedObjects())
        .containsExactly(
            new ObservationGenerationRequest.SubjectDetectedObject(
                "910",
                "HOUSE_DOOR",
                new BigDecimal("0.100000"),
                new BigDecimal("0.200000"),
                new BigDecimal("0.300000"),
                new BigDecimal("0.400000"),
                new BigDecimal("0.120000"),
                new BigDecimal("0.9100")));
    org.assertj.core.api.Assertions.assertThat(request.selectedEmotionRefs())
        .containsExactly(new ObservationGenerationRequest.SelectedEmotionRef("920", "HAPPY"));
    org.assertj.core.api.Assertions.assertThat(summary.qaPairs())
        .extracting(
            ObservationGenerationRequest.SubjectQaPair::questionMessageId,
            ObservationGenerationRequest.SubjectQaPair::answerMessageId)
        .containsExactly(org.assertj.core.groups.Tuple.tuple(1L, 2L));
  }

  @Test
  void carriesSttConfirmationFlagFromOriginalMessage() {
    // 미확정 STT 는 근거·보호자 인용에서 제외돼야 한다(계약 §4-4). 이 값이 상수면 조건이 절대
    // 참이 되지 않아 규칙 전체가 조용히 무효가 되므로, 원 메시지 값이 그대로 실리는지 고정한다.
    given(persistenceService.loadContext(ANALYSIS_ID))
        .willReturn(Optional.of(contextWithUnconfirmedSpeech()));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    org.assertj.core.api.Assertions.assertThat(
            requestCaptor.getValue().subjectSummaries().getFirst().qaPairs())
        .extracting(ObservationGenerationRequest.SubjectQaPair::sttNeedsConfirmation)
        .containsExactly(true, false);
  }

  @Test
  void sendsEmptyIdentifiersWithoutFailingWhenSourceRowsAreMissing() {
    // 식별자를 못 구했다고 요청을 실패시키지 않는다. 억지로 만들면(조합키) 게이트가 무의미해지므로
    // 빈 값으로 보내고 그 근거는 게이트가 판단한다.
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    org.assertj.core.api.Assertions.assertThat(requestCaptor.getValue().selectedEmotionRefs())
        .isEmpty();
    org.assertj.core.api.Assertions.assertThat(requestCaptor.getValue().subjectSummaries())
        .isEmpty();
  }

  private ObservationGenerationContext contextWithIdentifiers() {
    return new ObservationGenerationContext(
        ANALYSIS_ID,
        100L,
        REPORT_ID,
        50L,
        "NORMAL",
        3,
        2,
        1,
        0,
        List.of("HAPPY"),
        "행복했어요",
        List.of(),
        List.of(
            new ObservationGenerationContext.SubjectContext(
                "HOUSE",
                "가운데에 집이 크게 그려져 있어요.",
                List.of("HOUSE_DOOR"),
                List.of(
                    new ObservationGenerationContext.KeyConversationLine(
                        1L, "이 집에는 누가 살아?", 2L, "엄마랑 나!", "VOICE_ANSWER", false)),
                900L,
                List.of(houseDoorRef()))),
        List.of(new ObservationGenerationContext.SelectedEmotionRef(920L, "HAPPY")),
        List.of(new ObservationGenerationContext.ActivitySessionRef(100L, null)),
        7);
  }

  private ObservationGenerationContext contextWithUnconfirmedSpeech() {
    return new ObservationGenerationContext(
        ANALYSIS_ID,
        100L,
        REPORT_ID,
        50L,
        "NORMAL",
        2,
        2,
        0,
        1,
        List.of(),
        null,
        List.of(),
        List.of(
            new ObservationGenerationContext.SubjectContext(
                "TREE",
                "나무가 화면 밖으로 나갔어요.",
                List.of(),
                List.of(
                    new ObservationGenerationContext.KeyConversationLine(
                        3L, "이 나무는 몇 살이야?", 4L, "잘 안 들렸어요", "VOICE_ANSWER", true),
                    new ObservationGenerationContext.KeyConversationLine(
                        5L, "누가 심었어?", 6L, "내가 심었어", "OPTION_ANSWER", false)),
                901L,
                List.of())),
        List.of(),
        List.of(new ObservationGenerationContext.ActivitySessionRef(100L, null)),
        7);
  }

  @Test
  void skipsWhenContextIsAbsentForIdempotency() {
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.empty());

    service.generate(ANALYSIS_ID);

    verify(observationClient, never()).generate(any());
    verify(persistenceService, never()).complete(any(), any());
    verify(persistenceService, never()).markFailed(any(), any(), any(), any());
  }

  @Test
  void marksFailedWhenClientCallFails() {
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any()))
        .willThrow(new AiObservationClientException(AiObservationClientException.Type.TIMEOUT));

    service.generate(ANALYSIS_ID);

    verify(persistenceService, never()).complete(any(), any());
    verify(persistenceService).markFailed(eq(ANALYSIS_ID), eq(REPORT_ID), eq("TIMEOUT"), any());
  }

  @Test
  void marksFailedWhenDisclaimerIsMissing() {
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any()))
        .willReturn(
            new ObservationGeneration(resultWithoutDisclaimer(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(persistenceService, never()).complete(any(), any());
    verify(persistenceService)
        .markFailed(eq(ANALYSIS_ID), eq(REPORT_ID), eq("DISCLAIMER_MISSING"), any());
  }

  @Test
  void marksFailedWhenRequestIdDoesNotMatch() {
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult("other-request-id"), null));

    service.generate(ANALYSIS_ID);

    verify(persistenceService, never()).complete(any(), any());
    verify(persistenceService)
        .markFailed(eq(ANALYSIS_ID), eq(REPORT_ID), eq("REQUEST_ID_MISMATCH"), any());
  }

  @Test
  void marksFailedWhenPersistenceThrows() {
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));
    org.mockito.BDDMockito.willThrow(new RuntimeException("db down"))
        .given(persistenceService)
        .complete(any(), any());

    service.generate(ANALYSIS_ID);

    verify(persistenceService)
        .markFailed(eq(ANALYSIS_ID), eq(REPORT_ID), eq("REPORT_STORAGE_FAILED"), any());
  }

  @Test
  void keepsStorageFailureClassificationFromPersistenceLayer() {
    // S15P11B209-815: 저장 계층이 분류한 실패를 REPORT_STORAGE_FAILED로 덮으면
    // generation-status의 failureReason이 실제 원인과 무관해진다.
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));
    org.mockito.BDDMockito.willThrow(
            new BusinessException(
                MockObservationReportErrorCode.REPORT_STORAGE_CONFLICT,
                new DataIntegrityViolationException("data too long")))
        .given(persistenceService)
        .complete(any(), any());

    service.generate(ANALYSIS_ID);

    verify(persistenceService)
        .markFailed(eq(ANALYSIS_ID), eq(REPORT_ID), eq("REPORT_STORAGE_CONFLICT"), any());
  }

  @Test
  void sendsAggregatedBehaviorMetricsToTheAi() {
    // 계약에 자리는 있었지만 서버가 채우지 않아 AI 프롬프트의 [형식적 분석] 블록이 운영에서 한 번도 만들어지지 않았다.
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(behaviorSummaryService.summarizeAllOrNoneBySubject(diarySessions()))
        .willReturn(
            Optional.of(
                aggregate(
                    new StrokeBehaviorSummary(
                        600_000L,
                        240_000L,
                        42,
                        4,
                        2,
                        3,
                        1,
                        5,
                        Set.of("#ff0000", "#00ff00", "#0000ff"),
                        true,
                        false))));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    ObservationGenerationRequest.BehaviorMetrics metrics =
        requestCaptor.getValue().behaviorMetrics();
    org.assertj.core.api.Assertions.assertThat(metrics)
        .isEqualTo(
            new ObservationGenerationRequest.BehaviorMetrics(
                600_000L, 240_000L, 42, 4, 2, 3, 1, 5, 3, true, null, false, List.of()));
  }

  @Test
  void sumsEveryHtpStepBeforeSendingBehaviorMetrics() {
    // HTP 리포트는 집·나무·사람 세 활동이다. 한 세션만 보내면 AI 가 받는 그리기 시간이 3분의 1이 된다.
    ObservationGenerationContext htpContext = contextWithSessions(htpActivitySessions());
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(htpContext));
    given(behaviorSummaryService.summarizeAllOrNoneBySubject(htpSessions()))
        .willReturn(
            Optional.of(
                new StrokeBehaviorAggregate(
                    new StrokeBehaviorSummary(
                        900_000L, 300_000L, 90, 9, 3, 6, 2, 7, Set.of("#ff0000"), false, true),
                    List.of(
                        new StrokeBehaviorAggregate.SubjectDuration("HOUSE", 500_000L, 160_000L),
                        new StrokeBehaviorAggregate.SubjectDuration("TREE", 250_000L, 90_000L),
                        new StrokeBehaviorAggregate.SubjectDuration(
                            "PERSON", 150_000L, 50_000L)))));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    org.assertj.core.api.Assertions.assertThat(
            requestCaptor.getValue().behaviorMetrics().drawingDurationMs())
        .isEqualTo(900_000L);
    org.assertj.core.api.Assertions.assertThat(
            requestCaptor.getValue().behaviorMetrics().truncated())
        .isTrue();
  }

  @Test
  void sendsNullBehaviorMetricsWhenAggregationHasNothingToReport() {
    // 집계 결과가 없으면 0으로 채우지 않는다. AI 는 null 을 받아 [형식적 분석] 블록을 아예 만들지 않는다.
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(behaviorSummaryService.summarizeAllOrNoneBySubject(diarySessions()))
        .willReturn(Optional.empty());
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    org.assertj.core.api.Assertions.assertThat(requestCaptor.getValue().behaviorMetrics()).isNull();
    verify(persistenceService, never()).markFailed(any(), any(), any(), any());
  }

  @Test
  void keepsGeneratingWhenBehaviorAggregationFails() {
    // 형식 지표는 관찰의 부가 재료다. MongoDB 장애로 리포트 전체를 잃는 것은 균형에 맞지 않는다.
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(behaviorSummaryService.summarizeAllOrNoneBySubject(diarySessions()))
        .willThrow(new IllegalStateException("mongo down"));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    org.assertj.core.api.Assertions.assertThat(requestCaptor.getValue().behaviorMetrics()).isNull();
    verify(persistenceService).complete(any(ObservationGenerationContext.class), any());
  }

  @Test
  void neverTurnsAnUnmeasuredCountIntoZero() {
    // 🔴 이 작업에서 가장 중요한 성질이다. null(집계 못 함)을 0으로 채우면 AI 가 "멈춤 없이 몰입해 그렸다"는
    //   없는 관찰을 리포트에 적는다. 매핑은 값을 옮기기만 하고 만들지 않는다.
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(behaviorSummaryService.summarizeAllOrNoneBySubject(diarySessions()))
        .willReturn(
            Optional.of(
                aggregate(
                    new StrokeBehaviorSummary(
                        null, null, null, null, null, null, null, null, null, false, false))));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    ObservationGenerationRequest.BehaviorMetrics metrics =
        requestCaptor.getValue().behaviorMetrics();
    org.assertj.core.api.Assertions.assertThat(metrics.drawingDurationMs()).isNull();
    org.assertj.core.api.Assertions.assertThat(metrics.activeDrawingMs()).isNull();
    org.assertj.core.api.Assertions.assertThat(metrics.pauseCount()).isNull();
    org.assertj.core.api.Assertions.assertThat(metrics.undoCount()).isNull();
    org.assertj.core.api.Assertions.assertThat(metrics.eraseCount()).isNull();
    org.assertj.core.api.Assertions.assertThat(metrics.toolChangeCount()).isNull();
    org.assertj.core.api.Assertions.assertThat(metrics.colorChangeCount()).isNull();
    org.assertj.core.api.Assertions.assertThat(metrics.strokeCount()).isNull();
    // 색 집합을 집계하지 못했으면 가짓수도 모른다 — 0가지로 세면 "색을 쓰지 않았다"가 된다.
    org.assertj.core.api.Assertions.assertThat(metrics.colorsUsedCount()).isNull();
  }

  @Test
  void neverInventsAnAveragePressureValue() {
    // 계약에 자리가 있지만 집계기가 만들지 않는 값이다. 자리를 채우려고 지어내면 없는 측정이 관찰 재료가 된다.
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(behaviorSummaryService.summarizeAllOrNoneBySubject(diarySessions()))
        .willReturn(
            Optional.of(
                aggregate(
                    new StrokeBehaviorSummary(1L, 1L, 0, 0, 0, 0, 0, 0, Set.of(), true, false))));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    org.assertj.core.api.Assertions.assertThat(
            requestCaptor.getValue().behaviorMetrics().averagePressure())
        .isNull();
    // pressureAvailable 은 측정 가능 여부라 0회 집계와 무관하게 그대로 전달된다.
    org.assertj.core.api.Assertions.assertThat(
            requestCaptor.getValue().behaviorMetrics().pressureAvailable())
        .isTrue();
  }

  @Test
  void sendsPerSubjectDurationsSoTheAiCanCompareTheThreeDrawings() {
    // 🔴 S15P11B209-975 의 핵심. 합계만 보내면 "집을 그릴 때 가장 오래 머물렀어요" 같은 관찰을 만들 재료가 없다.
    ObservationGenerationContext htpContext = contextWithSessions(htpActivitySessions());
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(htpContext));
    given(behaviorSummaryService.summarizeAllOrNoneBySubject(htpSessions()))
        .willReturn(
            Optional.of(
                new StrokeBehaviorAggregate(
                    new StrokeBehaviorSummary(
                        900_000L, 300_000L, 90, 9, 3, 6, 2, 7, Set.of("#ff0000"), false, false),
                    List.of(
                        new StrokeBehaviorAggregate.SubjectDuration("HOUSE", 500_000L, 160_000L),
                        new StrokeBehaviorAggregate.SubjectDuration("TREE", 250_000L, 90_000L),
                        new StrokeBehaviorAggregate.SubjectDuration(
                            "PERSON", 150_000L, 50_000L)))));
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    org.assertj.core.api.Assertions.assertThat(
            requestCaptor.getValue().behaviorMetrics().subjectDurations())
        .extracting(
            ObservationGenerationRequest.SubjectDuration::drawingSubject,
            ObservationGenerationRequest.SubjectDuration::drawingDurationMs)
        .containsExactly(
            org.assertj.core.api.Assertions.tuple("HOUSE", 500_000L),
            org.assertj.core.api.Assertions.tuple("TREE", 250_000L),
            org.assertj.core.api.Assertions.tuple("PERSON", 150_000L));
  }

  @Test
  void asksTheAggregatorForEverySessionEvenWhenASubjectHasNoObservationOrConversation() {
    // 🔴 주제 매핑을 subjectContexts 로 하면 이 세션이 빠진다 — 그쪽은 서술·탐지 코드·문답이 모두 빈
    //   주제를 걸러낸 목록이라, 그리기만 하고 대화를 하지 않은 그림이 사라진다. 그러면 남은 둘만으로
    //   "가장 오래 머문 그림"이 정해져 아이에 대한 없는 관찰이 만들어진다. 필터링 전 목록을 써야 한다.
    ObservationGenerationContext htpContext = contextWithSessions(htpActivitySessions());
    // subjectContexts 는 비어 있다 — 세 주제 모두 서술·문답이 없는 상태를 재현한다.
    org.assertj.core.api.Assertions.assertThat(htpContext.subjectContexts()).isEmpty();
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(htpContext));
    given(behaviorSummaryService.summarizeAllOrNoneBySubject(any())).willReturn(Optional.empty());
    given(observationClient.generate(any()))
        .willReturn(new ObservationGeneration(validResult(REQUEST_UUID.toString()), null));

    service.generate(ANALYSIS_ID);

    // 집계기에 세 세션이 주제와 함께 그대로 전달되는지 — 이음매를 이음매에서 검증한다.
    verify(behaviorSummaryService).summarizeAllOrNoneBySubject(htpSessions());
  }

  /** 그림일기·단독 세션 하나. 주제가 없다. */
  private static List<SubjectStrokeSession> diarySessions() {
    return List.of(new SubjectStrokeSession(100L, null));
  }

  /** HTP 세 단계의 (세션, 주제) 쌍이다. */
  private static List<SubjectStrokeSession> htpSessions() {
    return List.of(
        new SubjectStrokeSession(100L, "HOUSE"),
        new SubjectStrokeSession(101L, "TREE"),
        new SubjectStrokeSession(102L, "PERSON"));
  }

  /** 위와 같은 세 단계를 생성 맥락 형태로 담은 것이다. */
  private static List<ObservationGenerationContext.ActivitySessionRef> htpActivitySessions() {
    return List.of(
        new ObservationGenerationContext.ActivitySessionRef(100L, "HOUSE"),
        new ObservationGenerationContext.ActivitySessionRef(101L, "TREE"),
        new ObservationGenerationContext.ActivitySessionRef(102L, "PERSON"));
  }

  /** 주제 구분이 없는 활동의 집계 결과 — 주제별 내역은 빈 목록이다. */
  private static StrokeBehaviorAggregate aggregate(StrokeBehaviorSummary total) {
    return new StrokeBehaviorAggregate(total, List.of());
  }

  /** 정규화 기하를 갖춘 탐지 참조. 실제 저장 값처럼 BigDecimal scale 을 유지한다. */
  private static ObservationGenerationContext.DetectedObjectRef houseDoorRef() {
    return new ObservationGenerationContext.DetectedObjectRef(
        910L,
        "HOUSE_DOOR",
        new BigDecimal("0.100000"),
        new BigDecimal("0.200000"),
        new BigDecimal("0.300000"),
        new BigDecimal("0.400000"),
        new BigDecimal("0.120000"),
        new BigDecimal("0.9100"));
  }

  private ObservationGenerationContext contextWithSessions(
      List<ObservationGenerationContext.ActivitySessionRef> activitySessions) {
    return new ObservationGenerationContext(
        ANALYSIS_ID,
        100L,
        REPORT_ID,
        50L,
        "NORMAL",
        3,
        2,
        1,
        0,
        List.of("HAPPY"),
        "행복했어요",
        List.of(),
        List.of(),
        List.of(),
        activitySessions,
        7);
  }

  private ObservationGenerationContext context() {
    return new ObservationGenerationContext(
        ANALYSIS_ID,
        100L,
        REPORT_ID,
        50L,
        "NORMAL",
        3,
        2,
        1,
        0,
        List.of("HAPPY"),
        "행복했어요",
        List.of(),
        List.of(),
        List.of(),
        List.of(new ObservationGenerationContext.ActivitySessionRef(100L, null)),
        7);
  }

  private ObservationGenerationResult validResult(String requestId) {
    return new ObservationGenerationResult(
        requestId,
        "mock-observation-generator",
        "1.0",
        new BigDecimal("0.80"),
        new ObservationDraft(
            "AI_DRAFT",
            "전체 요약",
            "긍정 신호",
            "관찰 필요 지점",
            "근거 요약",
            "보호자 안내",
            "후속 질문",
            false,
            "본 결과는 진단이 아닙니다.",
            List.of(new ObservedFeatureDraft("CODE", "제목", "설명", "근거", "REVIEWED_GUARDIAN"))),
        new ConversationSummaryDraft("대화 요약", "주제", "즐거움", "SELECTED", "즐거웠어요"),
        List.of("주의사항"),
        List.of(),
        List.of(),
        "한계 문구");
  }

  private ObservationGenerationResult resultWithoutDisclaimer(String requestId) {
    return new ObservationGenerationResult(
        requestId,
        "mock-observation-generator",
        "1.0",
        new BigDecimal("0.80"),
        new ObservationDraft(
            "AI_DRAFT", "전체 요약", "긍정 신호", "관찰", "근거", "안내", "질문", false, "  ", List.of()),
        new ConversationSummaryDraft("대화 요약", "주제", "즐거움", "SELECTED", null),
        List.of(),
        List.of(),
        List.of(),
        "한계 문구");
  }
}
