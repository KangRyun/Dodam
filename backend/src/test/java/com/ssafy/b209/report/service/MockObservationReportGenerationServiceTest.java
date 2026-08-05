package com.ssafy.b209.report.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.observation.AiObservationClient;
import com.ssafy.b209.infrastructure.ai.observation.AiObservationClientException;
import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ConversationSummaryDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservationDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservedFeatureDraft;
import com.ssafy.b209.report.exception.MockObservationReportErrorCode;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
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
  @Captor private ArgumentCaptor<ObservationGenerationRequest> requestCaptor;

  private MockObservationReportGenerationService service;

  @BeforeEach
  void setUp() {
    service =
        new MockObservationReportGenerationService(
            persistenceService, observationClient, () -> REQUEST_UUID);
  }

  @Test
  void generatesAndPersistsWhenContextIsPending() {
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any())).willReturn(validResult(REQUEST_UUID.toString()));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    ObservationGenerationRequest request = requestCaptor.getValue();
    org.assertj.core.api.Assertions.assertThat(request.analysisType()).isEqualTo("FINAL");
    org.assertj.core.api.Assertions.assertThat(request.questionCount()).isEqualTo(3);
    org.assertj.core.api.Assertions.assertThat(request.answeredCount()).isEqualTo(2);
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
                    List.of(
                        new ObservationGenerationContext.DetectedObjectRef(910L, "HOUSE_DOOR"))),
                new ObservationGenerationContext.SubjectContext(
                    null, "공룡이 풍선을 들고 있어요.", List.of(), List.of(), 901L, List.of())),
            List.of(new ObservationGenerationContext.SelectedEmotionRef(920L, "HAPPY")),
            List.of(100L));
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context));
    given(observationClient.generate(any())).willReturn(validResult(REQUEST_UUID.toString()));

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
    given(observationClient.generate(any())).willReturn(validResult(REQUEST_UUID.toString()));

    service.generate(ANALYSIS_ID);

    verify(observationClient).generate(requestCaptor.capture());
    ObservationGenerationRequest request = requestCaptor.getValue();
    ObservationGenerationRequest.SubjectSummary summary = request.subjectSummaries().getFirst();

    org.assertj.core.api.Assertions.assertThat(summary.observationEvidenceSourceId())
        .isEqualTo(900L);
    org.assertj.core.api.Assertions.assertThat(summary.detectedObjects())
        .containsExactly(
            new ObservationGenerationRequest.SubjectDetectedObject(910L, "HOUSE_DOOR"));
    org.assertj.core.api.Assertions.assertThat(request.selectedEmotionRefs())
        .containsExactly(new ObservationGenerationRequest.SelectedEmotionRef(920L, "HAPPY"));
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
    given(observationClient.generate(any())).willReturn(validResult(REQUEST_UUID.toString()));

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
    given(observationClient.generate(any())).willReturn(validResult(REQUEST_UUID.toString()));

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
                List.of(new ObservationGenerationContext.DetectedObjectRef(910L, "HOUSE_DOOR")))),
        List.of(new ObservationGenerationContext.SelectedEmotionRef(920L, "HAPPY")),
        List.of(100L));
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
        List.of(100L));
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
        .willReturn(resultWithoutDisclaimer(REQUEST_UUID.toString()));

    service.generate(ANALYSIS_ID);

    verify(persistenceService, never()).complete(any(), any());
    verify(persistenceService)
        .markFailed(eq(ANALYSIS_ID), eq(REPORT_ID), eq("DISCLAIMER_MISSING"), any());
  }

  @Test
  void marksFailedWhenRequestIdDoesNotMatch() {
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any())).willReturn(validResult("other-request-id"));

    service.generate(ANALYSIS_ID);

    verify(persistenceService, never()).complete(any(), any());
    verify(persistenceService)
        .markFailed(eq(ANALYSIS_ID), eq(REPORT_ID), eq("REQUEST_ID_MISMATCH"), any());
  }

  @Test
  void marksFailedWhenPersistenceThrows() {
    given(persistenceService.loadContext(ANALYSIS_ID)).willReturn(Optional.of(context()));
    given(observationClient.generate(any())).willReturn(validResult(REQUEST_UUID.toString()));
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
    given(observationClient.generate(any())).willReturn(validResult(REQUEST_UUID.toString()));
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
        List.of(100L));
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
