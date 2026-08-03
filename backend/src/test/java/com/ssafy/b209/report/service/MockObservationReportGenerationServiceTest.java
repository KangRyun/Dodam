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
                            1L, "이 집에는 누가 살아?", 2L, "엄마랑 나!", "VOICE_ANSWER"))),
                new ObservationGenerationContext.SubjectContext(
                    null, "공룡이 풍선을 들고 있어요.", List.of(), List.of())));
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
                "이 집에는 누가 살아?", "엄마랑 나!", "VOICE_ANSWER"));
    // 그림일기 항목 — 주제 없음(null)이 그대로 전달된다.
    org.assertj.core.api.Assertions.assertThat(summaries.get(1).drawingSubject()).isNull();
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
        List.of());
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
