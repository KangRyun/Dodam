package com.ssafy.b209.conversation.repository;

import static org.assertj.core.api.Assertions.assertThat;

import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

/**
 * {@code existsAnswerForQuestion}이 인식이 거절된 음성 답변을 답변으로 세지 않는지 검증한다.
 *
 * <p>단위 테스트로는 못 잡는다: {@code OptionAnswerServiceTest}는 이 저장소를 Mock으로 두어 JPQL 조건을 실행하지 않는다.
 *
 * <p>지키려는 규칙은 <strong>실패한 음성 답변은 답변이 아니다</strong>이다. STT가 무음·저신뢰로 거절되면 아이 말은 저장되지 않고 앱이 같은 질문에 선택지를
 * 띄운다(정본 §25). 그 행을 답변으로 세면 아이가 칩을 눌러도 {@code ANSWER_ALREADY_SUBMITTED}로 막혀 대화가 그 질문에서 끊긴다.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class OptionAnswerDuplicateGuardRepositoryTest {

  private static final long CHILD_ID = 91L;
  private static final long DRAWING_TYPE_ID = 91L;
  private static final long SESSION_ID = 910L;
  private static final long CONVERSATION_ID = 911L;
  private static final long QUESTION_ID = 9101L;

  @Autowired private OptionAnswerMessageRepository optionAnswerMessageRepository;

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
            + "VALUES (?, 'DUP_GUARD', '나무', 'GENERAL', 'BOTH', TRUE, 1)",
        DRAWING_TYPE_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, idempotency_key) "
            + "VALUES (?, ?, ?, 'CANVAS', 'IN_PROGRESS', 'CONVERSING', "
            + "'2026-08-05 01:00:00', 'dup-guard-key')",
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
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, message_sequence, sender_type, message_type, "
            + "raw_text, is_skipped, needs_guardian_confirmation, created_at) "
            + "VALUES (?, ?, 1, 'AI', 'QUESTION', '무엇을 그렸니?', FALSE, FALSE, "
            + "'2026-08-05 01:20:00')",
        QUESTION_ID,
        CONVERSATION_ID);
  }

  @Test
  void doesNotCountRejectedVoiceAnswerSoChildCanAnswerWithChips() {
    insertVoiceAnswer(9102L, "FAILED", null);

    assertThat(optionAnswerMessageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .isFalse();
  }

  @Test
  void countsSucceededVoiceAnswer() {
    insertVoiceAnswer(9103L, "SUCCESS", "나무를 그렸어요");

    assertThat(optionAnswerMessageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .isTrue();
  }

  @Test
  void countsVoiceAnswerStillBeingProcessed() {
    // 처리 중인 답변을 '없는 답변'으로 보면 같은 질문에 답이 두 개 생긴다.
    insertVoiceAnswer(9104L, "PROCESSING", null);

    assertThat(optionAnswerMessageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .isTrue();
  }

  @Test
  void countsVoiceAnswerWithUnknownStatus() {
    // 상태를 알 수 없으면 답변으로 센다 — 판정 불가를 '답변 없음'으로 넘기면 중복 답변이 열린다.
    insertVoiceAnswer(9105L, null, null);

    assertThat(optionAnswerMessageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .isTrue();
  }

  @Test
  void countsOptionAnswerRegardlessOfSpeechStatus() {
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, parent_message_id, message_sequence, sender_type, "
            + "message_type, raw_text, is_skipped, needs_guardian_confirmation, created_at) "
            + "VALUES (9106, ?, ?, 3, 'CHILD', 'OPTION_ANSWER', NULL, FALSE, FALSE, "
            + "'2026-08-05 01:22:00')",
        CONVERSATION_ID,
        QUESTION_ID);

    assertThat(optionAnswerMessageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .isTrue();
  }

  @Test
  void reportsNoAnswerWhenOnlyQuestionExists() {
    assertThat(optionAnswerMessageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .isFalse();
  }

  private void insertVoiceAnswer(long id, String speechStatus, String sttText) {
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, parent_message_id, message_sequence, sender_type, "
            + "message_type, raw_text, stt_text, speech_status, is_skipped, "
            + "needs_guardian_confirmation, created_at) "
            + "VALUES (?, ?, ?, 2, 'CHILD', 'VOICE_ANSWER', NULL, ?, ?, FALSE, FALSE, "
            + "'2026-08-05 01:21:00')",
        id,
        CONVERSATION_ID,
        QUESTION_ID,
        sttText,
        speechStatus);
  }
}
