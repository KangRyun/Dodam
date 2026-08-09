package com.ssafy.b209.conversation.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class ConversationSessionCompletionTest {

  @Test
  void completesConversingSessionOnlyOnce() {
    ConversationSession session = session();
    LocalDateTime completedAt = LocalDateTime.of(2026, 7, 24, 7, 30);

    session.complete(ConversationCompletionReason.GUARDIAN_REQUEST, completedAt);
    session.complete(
        ConversationCompletionReason.CHILD_REQUEST, LocalDateTime.of(2026, 7, 24, 7, 31));

    assertThat(session.isCompleted()).isTrue();
    assertThat(session.getCompletionReason())
        .isEqualTo(ConversationCompletionReason.GUARDIAN_REQUEST);
    assertThat(session.getCompletedAt()).isEqualTo(completedAt);
  }

  @Test
  void rejectsCompletionFromFailedState() {
    ConversationSession session = session();
    ReflectionTestUtils.setField(session, "conversationStatus", "FAILED");

    assertThatThrownBy(
            () ->
                session.complete(
                    ConversationCompletionReason.NO_MORE_QUESTION,
                    LocalDateTime.of(2026, 7, 24, 7, 30)))
        .isInstanceOf(IllegalStateException.class);
  }

  private ConversationSession session() {
    return ConversationSession.start(10L, "LOW", 5, LocalDateTime.of(2026, 7, 24, 7, 0));
  }
}
