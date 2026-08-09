package com.ssafy.b209.conversation.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import java.util.List;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.data.domain.PageRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

/**
 * {@code findRecentContextMessages}가 AI 다음 질문 요청에 실을 대화 문맥을 올바르게 고르는지 검증한다.
 *
 * <p>단위 테스트로는 못 잡는다: 이 서비스 테스트들은 저장소를 Mock으로 두어 JPQL 조건 자체를 실행하지 않는다. 조건이 틀려도 Mock이 원하는 값을 돌려주므로
 * 통과한다.
 *
 * <p>지키려는 규칙은 <strong>건너뛴 질문은 문맥에 남고, 건너뛴 답변은 빠진다</strong>이다. 질문 건너뛰기는 답변이 아니라 질문 행에 {@code
 * is_skipped}를 찍으므로, 건너뜀 전체를 제외하면 그 질문이 AI 문맥에서 사라진다. 그러면 AI가 받는 재료가 질문 직전과 같아져 같은 질문을 다시 만들고, 아이가
 * 넘겨도 같은 질문이 반복된다(2026-08-05 실기기 확인: 질문 1019를 건너뛰자 1020이 같은 질문으로 생성됨).
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class ConversationHistoryMessageRepositoryTest {

  private static final long CHILD_ID = 73L;
  private static final long DRAWING_TYPE_ID = 73L;
  private static final long SESSION_ID = 730L;
  private static final long CONVERSATION_ID = 731L;

  @Autowired private ConversationHistoryMessageRepository conversationHistoryMessageRepository;

  @Autowired private DataSource dataSource;

  private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUpFixture() {
    jdbcTemplate = new JdbcTemplate(dataSource);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, '별이', '2019-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, is_active, display_order) "
            + "VALUES (?, 'TREE_CONTEXT', '나무', 'GENERAL', 'BOTH', TRUE, 1)",
        DRAWING_TYPE_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, idempotency_key) "
            + "VALUES (?, ?, ?, 'CANVAS', 'IN_PROGRESS', 'CONVERSING', "
            + "'2026-08-05 01:00:00', 'skip-context-key')",
        SESSION_ID,
        CHILD_ID,
        DRAWING_TYPE_ID);
    jdbcTemplate.update(
        // H2 스키마는 Flyway가 아니라 Hibernate가 만들어 마이그레이션의 DEFAULT가 없다 — NOT NULL 값을 모두 적는다.
        "INSERT INTO conversation_sessions "
            + "(id, drawing_session_id, conversation_status, difficulty_snapshot, "
            + "max_question_count, question_count, started_at) "
            + "VALUES (?, ?, 'CONVERSING', 'NORMAL', 10, 3, '2026-08-05 01:10:00')",
        CONVERSATION_ID,
        SESSION_ID);
  }

  @Test
  void keepsSkippedQuestionSoTheAiKnowsItAlreadyAsked() {
    insertQuestion(2001L, 1, "무엇을 그렸니?", false);
    insertAnswer(2002L, 2001L, 2, "나무요", false);
    // 아이가 넘긴 질문 — 답변 행이 생기지 않고 질문 행에 is_skipped 가 찍힌다.
    insertQuestion(2003L, 3, "그 나무는 어떤 모습이야?", true);

    List<ConversationHistoryMessage> context =
        conversationHistoryMessageRepository.findRecentContextMessages(
            CONVERSATION_ID, PageRequest.of(0, 10));

    assertThat(context).extracting(ConversationHistoryMessage::getId).contains(2003L);
  }

  @Test
  void dropsSkippedAnswerBecauseItIsNotConversationContext() {
    insertQuestion(2101L, 1, "무엇을 그렸니?", false);
    insertAnswer(2102L, 2101L, 2, "나무요", true);

    List<ConversationHistoryMessage> context =
        conversationHistoryMessageRepository.findRecentContextMessages(
            CONVERSATION_ID, PageRequest.of(0, 10));

    assertThat(context)
        .extracting(ConversationHistoryMessage::getId)
        .containsExactly(2101L)
        .doesNotContain(2102L);
  }

  @Test
  void returnsMessagesInDescendingSequenceSoCallerCanReverseThem() {
    insertQuestion(2201L, 1, "무엇을 그렸니?", false);
    insertAnswer(2202L, 2201L, 2, "나무요", false);
    insertQuestion(2203L, 3, "그 나무는 어떤 모습이야?", true);

    List<ConversationHistoryMessage> context =
        conversationHistoryMessageRepository.findRecentContextMessages(
            CONVERSATION_ID, PageRequest.of(0, 10));

    assertThat(context)
        .extracting(ConversationHistoryMessage::getId)
        .containsExactly(2203L, 2202L, 2201L);
  }

  private void insertQuestion(long id, int sequence, String text, boolean skipped) {
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, message_sequence, sender_type, message_type, "
            + "raw_text, is_skipped, needs_guardian_confirmation, created_at) "
            + "VALUES (?, ?, ?, 'AI', 'QUESTION', ?, ?, FALSE, '2026-08-05 01:20:00')",
        id,
        CONVERSATION_ID,
        sequence,
        text,
        skipped);
  }

  private void insertAnswer(long id, long parentId, int sequence, String text, boolean skipped) {
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, parent_message_id, message_sequence, sender_type, "
            + "message_type, raw_text, is_skipped, needs_guardian_confirmation, created_at) "
            + "VALUES (?, ?, ?, ?, 'CHILD', 'VOICE_ANSWER', ?, ?, FALSE, '2026-08-05 01:21:00')",
        id,
        CONVERSATION_ID,
        parentId,
        sequence,
        text,
        skipped);
  }
}
