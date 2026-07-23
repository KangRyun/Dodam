package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
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

/** 289 오케스트레이터가 상태에 따라 중복 AI 호출을 막고 결과 저장을 위임하는지 검증한다. */
@ExtendWith(MockitoExtension.class)
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
    given(aiSttClient.transcribe(any()))
        .willReturn(new AiSttResponse("놀았어요", null, "whisper-1", 20L));
    given(persistenceService.completeSuccess(eq(MESSAGE_ID), eq("놀았어요"), any(), eq(false)))
        .willReturn(
            new SttProcessingResult(
                MESSAGE_ID, SttProcessingResult.Status.SUCCESS, "놀았어요", null, false));

    SttProcessingResult result = service.process(MESSAGE_ID);

    assertThat(result.status()).isEqualTo(SttProcessingResult.Status.SUCCESS);
    verify(persistenceService).completeSuccess(eq(MESSAGE_ID), eq("놀았어요"), any(), eq(false));
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
