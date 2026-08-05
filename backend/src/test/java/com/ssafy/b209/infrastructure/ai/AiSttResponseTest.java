package com.ssafy.b209.infrastructure.ai;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigDecimal;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * 정본 §19.6 STT 응답 계약 검증과 실패 판정을 확인한다.
 *
 * <p>배경(2026-08-05 실측): 무음 녹음에서 나온 whisper 정형구가 아이 답변으로 저장됐다. 이 DTO가 실패를 실패로 알려야 저장 경로가 막힌다.
 */
class AiSttResponseTest {

  private static AiSttResponse response(String text, String status, String reason) {
    return new AiSttResponse(text, null, "whisper-1", 20L, status, reason, false);
  }

  @Nested
  class ContractValidation {

    @Test
    void acceptsLegacyResponseWithoutStatusFields() {
      assertThatCode(() -> AiSttResponse.legacy("놀았어요", "whisper-1", 20L).validateContract())
          .doesNotThrowAnyException();
    }

    @Test
    void acceptsFailedResponseWithKnownReason() {
      assertThatCode(() -> response("", "FAILED", "NO_SPEECH").validateContract())
          .doesNotThrowAnyException();
    }

    @ParameterizedTest
    @ValueSource(strings = {"NO_SPEECH", "LOW_CONFIDENCE", "UNSUPPORTED_AUDIO", "TIMEOUT"})
    void acceptsEveryReasonDefinedByContract(String reason) {
      assertThatCode(() -> response("", "FAILED", reason).validateContract())
          .doesNotThrowAnyException();
    }

    @Test
    void rejectsUnknownStatusInsteadOfTreatingItAsSuccess() {
      // 모르는 상태를 성공으로 넘기면 AI가 거절한 텍스트가 저장될 수 있다(fail-closed).
      assertThatThrownBy(() -> response("텍스트", "PARTIAL", null).validateContract())
          .isInstanceOf(AiSttClientException.class)
          .hasMessage(AiSttClientException.Type.RESPONSE_SCHEMA_INVALID.name());
    }

    @Test
    void rejectsUnknownFailureReason() {
      assertThatThrownBy(() -> response("", "FAILED", "MICROPHONE_OFF").validateContract())
          .isInstanceOf(AiSttClientException.class);
    }

    @Test
    void rejectsFailedResponseWithoutReason() {
      assertThatThrownBy(() -> response("", "FAILED", null).validateContract())
          .isInstanceOf(AiSttClientException.class);
    }

    @Test
    void stillRejectsNonNullConfidence() {
      // whisper-1은 신뢰도를 주지 않는다. 값이 오면 우리가 모르는 스키마다.
      AiSttResponse withConfidence =
          new AiSttResponse(
              "놀았어요", new BigDecimal("0.9"), "whisper-1", 20L, "SUCCESS", null, false);
      assertThatThrownBy(withConfidence::validateContract).isInstanceOf(AiSttClientException.class);
    }

    @Test
    void stillRejectsNullText() {
      AiSttResponse nullText =
          new AiSttResponse(null, null, "whisper-1", 20L, "SUCCESS", null, false);
      assertThatThrownBy(nullText::validateContract).isInstanceOf(AiSttClientException.class);
    }
  }

  @Nested
  class FailureDecision {

    @Test
    void treatsExplicitFailedStatusAsFailure() {
      assertThat(response("구독, 좋아요, 알림설정 부탁드립니다.", "FAILED", "NO_SPEECH").failed()).isTrue();
    }

    @Test
    void treatsBlankTextAsFailureEvenWhenStatusSaysSuccess() {
      assertThat(response("   ", "SUCCESS", null).failed()).isTrue();
    }

    @Test
    void treatsBlankTextAsFailureForLegacyResponse() {
      assertThat(AiSttResponse.legacy("", "whisper-1", 20L).failed()).isTrue();
    }

    @Test
    void acceptsRecognizedTextWithSuccessStatus() {
      assertThat(response("이건 우리 집이야", "SUCCESS", null).failed()).isFalse();
    }

    @Test
    void acceptsRecognizedTextForLegacyResponse() {
      assertThat(AiSttResponse.legacy("이건 우리 집이야", "whisper-1", 20L).failed()).isFalse();
    }

    @Test
    void reportsBlankTextAsNoSpeechWhenReasonIsMissing() {
      assertThat(AiSttResponse.legacy("", "whisper-1", 20L).resolvedFailureReason())
          .isEqualTo("NO_SPEECH");
    }

    @Test
    void keepsReasonGivenByAi() {
      assertThat(response("", "FAILED", "TIMEOUT").resolvedFailureReason()).isEqualTo("TIMEOUT");
    }
  }

  @Nested
  class ConfirmationFlag {

    @Test
    void defaultsToFalseWhenAiOmitsField() {
      assertThat(AiSttResponse.legacy("놀았어요", "whisper-1", 20L).needsConfirmationOrDefault())
          .isFalse();
    }

    @Test
    void readsTrueWhenAiAsksForConfirmation() {
      AiSttResponse unsure =
          new AiSttResponse("놀았어요", null, "whisper-1", 20L, "SUCCESS", null, true);
      assertThat(unsure.needsConfirmationOrDefault()).isTrue();
    }
  }
}
