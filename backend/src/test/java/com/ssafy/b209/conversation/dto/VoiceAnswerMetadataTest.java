package com.ssafy.b209.conversation.dto;

import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.global.exception.BusinessException;
import java.time.Instant;
import org.junit.jupiter.api.Test;

/** 음성 multipart metadata의 필수값·stopReason·시간 순서 검증을 확인한다. */
class VoiceAnswerMetadataTest {

  @Test
  void rejectsMissingStopReason() {
    VoiceAnswerMetadata metadata =
        new VoiceAnswerMetadata(
            11L,
            Instant.parse("2026-07-23T00:00:00Z"),
            Instant.parse("2026-07-23T00:00:01Z"),
            null);

    assertThatThrownBy(metadata::validate).isInstanceOf(BusinessException.class);
  }

  @Test
  void rejectsClientTimeInReverseOrder() {
    VoiceAnswerMetadata metadata =
        new VoiceAnswerMetadata(
            11L,
            Instant.parse("2026-07-23T00:00:01Z"),
            Instant.parse("2026-07-23T00:00:00Z"),
            VoiceAnswerStopReason.SILENCE);

    assertThatThrownBy(metadata::validate).isInstanceOf(BusinessException.class);
  }
}
