package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.infrastructure.ai.AiSttClient;
import com.ssafy.b209.infrastructure.ai.AiSttClientException;
import com.ssafy.b209.infrastructure.ai.AiSttResponse;
import com.ssafy.b209.storage.audio.StoredAudioReader;
import java.math.BigDecimal;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;

/** 289 오케스트레이터가 상태에 따라 중복 AI 호출을 막고 결과 저장을 위임하는지 검증한다. */
@ExtendWith({MockitoExtension.class, OutputCaptureExtension.class})
class SttProcessingServiceTest {
  private static final long MESSAGE_ID = 71L;

  @Mock private SttProcessingPersistenceService persistenceService;
  @Mock private StoredAudioReader audioReader;
  @Mock private AiSttClient aiSttClient;

  private SttProcessingService service;

  @BeforeEach
  void setUp() {
    service = new SttProcessingService(persistenceService, audioReader, aiSttClient);
  }

  @Test
  void doesNotCallAiAgainWhenAnotherWorkerIsProcessing() {
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.PROCESSING, "PROCESSING", null, null, false));

    SttProcessingResult result = service.process(MESSAGE_ID);

    assertThat(result.status()).isEqualTo(SttProcessingResult.Status.PROCESSING);
    verify(audioReader, never()).open(any());
    verify(aiSttClient, never()).transcribe(any());
  }

  @Test
  void reusesSuccessResultWithoutSttCall() {
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(
            claim(
                SttClaimResult.Action.SUCCESS,
                "SUCCESS",
                "기존 결과",
                new BigDecimal("0.9000"),
                false));

    SttProcessingResult result = service.process(MESSAGE_ID);

    assertThat(result.status()).isEqualTo(SttProcessingResult.Status.SUCCESS);
    assertThat(result.text()).isEqualTo("기존 결과");
    verify(aiSttClient, never()).transcribe(any());
  }

  @Test
  void persistsValidatedSuccessWithBigDecimalConfidence() {
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, false));
    given(aiSttClient.transcribe(any())).willReturn(AiSttResponse.legacy("놀았어요", "whisper-1", 20L));
    given(persistenceService.completeSuccess(eq(MESSAGE_ID), eq("놀았어요"), any(), eq(false)))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.SUCCESS, "놀았어요", null, false));

    SttProcessingResult result = service.process(MESSAGE_ID);

    assertThat(result.status()).isEqualTo(SttProcessingResult.Status.SUCCESS);
    verify(persistenceService).completeSuccess(eq(MESSAGE_ID), eq("놀았어요"), any(), eq(false));
  }

  @Test
  void rejectsRecognizedTextWhenAiReportsNoSpeech() {
    // 실측(2026-08-05): 무음 녹음이 "구독, 좋아요 …"로 저장돼 다음 질문의 근거가 됐다.
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, false));
    given(aiSttClient.transcribe(any()))
        .willReturn(
            new AiSttResponse(
                "구독, 좋아요, 알림설정 부탁드립니다.", null, "whisper-1", 20L, "FAILED", "NO_SPEECH", false));
    given(persistenceService.completeFailure(MESSAGE_ID, false))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.FAILED, null, null, false));

    SttProcessingResult result = service.process(MESSAGE_ID);

    assertThat(result.status()).isEqualTo(SttProcessingResult.Status.FAILED);
    verify(persistenceService).completeFailure(MESSAGE_ID, false);
    verify(persistenceService, never()).completeSuccess(any(), any(), any(), anyBoolean());
  }

  @Test
  void rejectsLowConfidenceFailureWithoutStoringText() {
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, false));
    given(aiSttClient.transcribe(any()))
        .willReturn(
            new AiSttResponse("웅얼웅얼", null, "whisper-1", 20L, "FAILED", "LOW_CONFIDENCE", false));
    given(persistenceService.completeFailure(MESSAGE_ID, false))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.FAILED, null, null, false));

    assertThat(service.process(MESSAGE_ID).status()).isEqualTo(SttProcessingResult.Status.FAILED);
    verify(persistenceService, never()).completeSuccess(any(), any(), any(), anyBoolean());
  }

  @Test
  void rejectsBlankTextEvenWhenLegacyAiOmitsStatus() {
    // 구 AI가 배포된 상태에서도 빈 답변이 아이 발화로 기록되면 안 된다.
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, false));
    given(aiSttClient.transcribe(any())).willReturn(AiSttResponse.legacy("   ", "whisper-1", 20L));
    given(persistenceService.completeFailure(MESSAGE_ID, false))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.FAILED, null, null, false));

    assertThat(service.process(MESSAGE_ID).status()).isEqualTo(SttProcessingResult.Status.FAILED);
    verify(persistenceService, never()).completeSuccess(any(), any(), any(), anyBoolean());
  }

  @Test
  void logsRejectionReasonWithoutRecognizedText(CapturedOutput output) {
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, false));
    given(aiSttClient.transcribe(any()))
        .willReturn(
            new AiSttResponse(
                "구독, 좋아요, 알림설정 부탁드립니다.", null, "whisper-1", 20L, "FAILED", "NO_SPEECH", false));
    given(persistenceService.completeFailure(MESSAGE_ID, false))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.FAILED, null, null, false));

    service.process(MESSAGE_ID);

    assertThat(output).contains("reason=NO_SPEECH").contains("messageId=" + MESSAGE_ID);
    assertThat(output).doesNotContain("구독");
  }

  @Test
  void raisesGuardianConfirmationWhenAiIsUnsureButAccepts() {
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, false));
    given(aiSttClient.transcribe(any()))
        .willReturn(new AiSttResponse("친구랑 놀았어", null, "whisper-1", 20L, "SUCCESS", null, true));
    given(persistenceService.completeSuccess(eq(MESSAGE_ID), eq("친구랑 놀았어"), any(), eq(true)))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.SUCCESS, "친구랑 놀았어", null, true));

    SttProcessingResult result = service.process(MESSAGE_ID);

    assertThat(result.needsGuardianConfirmation()).isTrue();
    verify(persistenceService).completeSuccess(eq(MESSAGE_ID), eq("친구랑 놀았어"), any(), eq(true));
  }

  @Test
  void keepsExistingGuardianConfirmationWhenAiDoesNotAskForIt() {
    // 한 번 필요해진 확인은 AI가 확신한다고 내려가지 않는다(OR 결합).
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, true));
    given(aiSttClient.transcribe(any()))
        .willReturn(new AiSttResponse("놀았어요", null, "whisper-1", 20L, "SUCCESS", null, false));
    given(persistenceService.completeSuccess(eq(MESSAGE_ID), eq("놀았어요"), any(), eq(true)))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.SUCCESS, "놀았어요", null, true));

    service.process(MESSAGE_ID);

    verify(persistenceService).completeSuccess(eq(MESSAGE_ID), eq("놀았어요"), any(), eq(true));
  }

  @Test
  void marksFailedWithoutKeepingTextWhenAiCallFails() {
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, false));
    given(aiSttClient.transcribe(any()))
        .willThrow(new AiSttClientException(AiSttClientException.Type.READ_TIMEOUT));
    given(persistenceService.completeFailure(MESSAGE_ID, false))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.FAILED, null, null, true));

    SttProcessingResult result = service.process(MESSAGE_ID);

    assertThat(result.status()).isEqualTo(SttProcessingResult.Status.FAILED);
    assertThat(result.text()).isNull();
    verify(persistenceService).completeFailure(MESSAGE_ID, false);
  }

  @Test
  void logsFailureTypeAndMessageIdWithoutSensitiveDataWhenAiCallFails(CapturedOutput output) {
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, false));
    given(aiSttClient.transcribe(any()))
        .willThrow(new AiSttClientException(AiSttClientException.Type.INVALID_REQUEST));
    given(persistenceService.completeFailure(MESSAGE_ID, false))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.FAILED, null, null, false));

    SttProcessingResult result = service.process(MESSAGE_ID);

    assertThat(result.status()).isEqualTo(SttProcessingResult.Status.FAILED);
    verify(persistenceService).completeFailure(MESSAGE_ID, false);
    assertThat(output)
        .contains("WARN")
        .contains("type=INVALID_REQUEST")
        .contains("messageId=" + MESSAGE_ID);
    assertThat(output).doesNotContain("2026/07/23/voice.wav");
  }

  @Test
  void logsExceptionClassNameForNonAiSttRuntimeFailure(CapturedOutput output) {
    given(persistenceService.claim(MESSAGE_ID))
        .willReturn(claim(SttClaimResult.Action.CLAIMED, "PENDING", null, null, false));
    given(aiSttClient.transcribe(any())).willThrow(new IllegalStateException("boom"));
    given(persistenceService.completeFailure(MESSAGE_ID, false))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.FAILED, null, null, false));

    SttProcessingResult result = service.process(MESSAGE_ID);

    assertThat(result.status()).isEqualTo(SttProcessingResult.Status.FAILED);
    assertThat(output)
        .contains("WARN")
        .contains("exception=IllegalStateException")
        .contains("messageId=" + MESSAGE_ID);
    assertThat(output).doesNotContain("boom");
  }

  private SttClaimResult claim(
      SttClaimResult.Action action,
      String speechStatus,
      String text,
      BigDecimal confidence,
      boolean needsConfirmation) {
    return new SttClaimResult(
        action,
        MESSAGE_ID,
        "2026/07/23/voice.wav",
        "PRESCHOOL",
        speechStatus,
        text,
        confidence,
        needsConfirmation);
  }
}
