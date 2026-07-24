package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/** DB 메시지 유형을 공개 API 표현으로 변환하는 공용 매퍼의 전체 케이스를 검증한다. */
class ConversationMessageTypeMapperTest {

  @ParameterizedTest
  @CsvSource({
    "VOICE_ANSWER,ANSWER_VOICE",
    "OPTION_ANSWER,ANSWER_OPTION",
    "TEXT_ANSWER,ANSWER_TEXT",
    "SYSTEM_NOTICE,SYSTEM",
    "QUESTION,QUESTION"
  })
  void mapsStoredTypeToPublicType(String stored, String expected) {
    assertThat(ConversationMessageTypeMapper.toPublicMessageType(stored)).isEqualTo(expected);
  }

  @Test
  void returnsOriginalValueForUnmappedType() {
    assertThat(ConversationMessageTypeMapper.toPublicMessageType("UNKNOWN")).isEqualTo("UNKNOWN");
  }
}
