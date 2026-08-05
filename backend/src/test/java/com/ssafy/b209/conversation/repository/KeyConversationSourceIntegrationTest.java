package com.ssafy.b209.conversation.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.conversation.dto.KeyConversationSource;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * {@code findKeyConversationSources} 네이티브 쿼리가 STT 확인 여부를 실 MySQL 에서 올바른 타입으로 돌려주는지 검증한다
 * (S15P11B209-906).
 *
 * <p>단위 테스트로는 못 잡는다: 네이티브 쿼리 Projection 의 {@code boolean} 매핑은 JDBC 드라이버가 컬럼을 어떤 자바 타입으로 주는지에 달려 있다.
 * 이 리포는 과거 MySQL {@code EXISTS} 결과를 {@code boolean} 으로 직접 매핑해 {@code ClassCastException} 으로 500이 난
 * 적이 있다 — {@code TINYINT(1)} 도 같은 위험이 있어 실제 DB 로 확인한다.
 *
 * <p>이 값이 실데이터로 흐르지 않으면 "미확정 STT 는 근거·대표 발화에서 제외한다"는 규칙(보호자 계약 §4-4)이 조건 자체가 참이 되지 않아 조용히 무효가 된다.
 */
class KeyConversationSourceIntegrationTest extends IntegrationTestSupport {

  private static final long CHILD_ID = 71L;
  private static final long SESSION_ID = 710L;
  private static final long CONVERSATION_ID = 711L;

  @Autowired private ConversationMessageRepository conversationMessageRepository;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUpFixture() {
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, '별이', '2019-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, is_active, display_order) "
            + "VALUES (71, 'HOUSE', '집', 'GENERAL', 'BOTH', TRUE, 1)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, idempotency_key) "
            + "VALUES (?, ?, 71, 'CANVAS', 'COMPLETED', 'COMPLETED', "
            + "'2026-08-05 01:00:00', 'key-conversation-key')",
        SESSION_ID,
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO conversation_sessions "
            + "(id, drawing_session_id, conversation_status, difficulty_snapshot, started_at) "
            + "VALUES (?, ?, 'COMPLETED', 'NORMAL', '2026-08-05 01:10:00')",
        CONVERSATION_ID,
        SESSION_ID);
    insertQuestion(1001L, 1, "이 집에는 누가 살아?");
    insertAnswer(1002L, 1001L, 2, "잘 안 들렸어요", true);
    insertQuestion(1003L, 3, "누구랑 같이 있어?");
    insertAnswer(1004L, 1003L, 4, "엄마랑 나", false);
  }

  @Test
  void readsGuardianConfirmationFlagPerAnswerThroughRealDriver() {
    List<KeyConversationSource> sources =
        conversationMessageRepository.findKeyConversationSources(CONVERSATION_ID);

    assertThat(sources).hasSize(2);
    assertThat(sources)
        .extracting(
            KeyConversationSource::getAnswerMessageId,
            KeyConversationSource::getAnswerNeedsGuardianConfirmation)
        .containsExactly(
            org.assertj.core.groups.Tuple.tuple(1002L, true),
            org.assertj.core.groups.Tuple.tuple(1004L, false));
  }

  @Test
  void keepsMessageIdentifiersSoEvidenceCanBeReferenced() {
    // AI 는 서버가 발급한 이 식별자만 근거로 참조한다(조합키 금지) — 없으면 게이트가 전부 탈락시킨다.
    List<KeyConversationSource> sources =
        conversationMessageRepository.findKeyConversationSources(CONVERSATION_ID);

    assertThat(sources)
        .allSatisfy(
            source -> {
              assertThat(source.getQuestionMessageId()).isNotNull();
              assertThat(source.getAnswerMessageId()).isNotNull();
            });
  }

  private void insertQuestion(long id, int sequence, String text) {
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, message_sequence, sender_type, message_type, "
            + "raw_text, is_skipped, needs_guardian_confirmation) "
            + "VALUES (?, ?, ?, 'AI', 'QUESTION', ?, FALSE, FALSE)",
        id,
        CONVERSATION_ID,
        sequence,
        text);
  }

  private void insertAnswer(
      long id, long parentId, int sequence, String text, boolean needsConfirmation) {
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, parent_message_id, message_sequence, sender_type, "
            + "message_type, raw_text, is_skipped, needs_guardian_confirmation) "
            + "VALUES (?, ?, ?, ?, 'CHILD', 'VOICE_ANSWER', ?, FALSE, ?)",
        id,
        CONVERSATION_ID,
        parentId,
        sequence,
        text,
        needsConfirmation);
  }
}
