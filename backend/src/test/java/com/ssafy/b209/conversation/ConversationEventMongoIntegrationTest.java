package com.ssafy.b209.conversation;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.conversation.config.ConversationEventRetentionProperties;
import com.ssafy.b209.conversation.document.ConversationEventDocument;
import com.ssafy.b209.conversation.document.ConversationEventType;
import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import com.ssafy.b209.conversation.dto.EndConversationRequest;
import com.ssafy.b209.conversation.dto.OptionAnswerRequest;
import com.ssafy.b209.conversation.dto.SelectedOptionCommand;
import com.ssafy.b209.conversation.dto.SkipQuestionRequest;
import com.ssafy.b209.conversation.repository.ConversationEventDocumentRepository;
import com.ssafy.b209.conversation.service.ConversationEndService;
import com.ssafy.b209.conversation.service.ConversationEventContext;
import com.ssafy.b209.conversation.service.ConversationEventRecorder;
import com.ssafy.b209.conversation.service.OptionAnswerService;
import com.ssafy.b209.conversation.service.QuestionSkipService;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.time.temporal.ChronoUnit;
import java.util.List;
import org.bson.Document;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

/**
 * 대화 행동 이벤트가 <b>실제 대화 흐름에서</b> MongoDB로 적재되는지 관통 검증한다 (S15P11B209-973).
 *
 * <p><b>이 클래스가 존재하는 이유는 S15P11B209-902다.</b> 그때는 저장 메서드 3개를 만들어 놓고 어느 흐름에서도 호출하지 않아, 몇 주 동안 아무것도
 * 저장되지 않았는데도 단위 테스트는 초록이었다 — 테스트가 저장 메서드를 <b>직접</b> 불렀기 때문이다. 컴파일도 배포도 성공했고, 화면만 빈 채로 나갔다. 그래서 여기서는
 * {@link ConversationEventRecorder}를 직접 부르지 않는다. 아이가 실제로 거치는 Use Case Service를 그대로 호출하고, 그 부수효과로
 * 문서가 생겼는지만 본다. 훅을 지우면 이 테스트가 빨개진다 — 그것이 이 클래스의 존재 목적이다.
 *
 * <p><b>왜 칩 답변·건너뛰기·종료만 여기서 관통하나</b>: 이 셋은 외부 경계(AI·음성 파일)가 없어 실제 Service를 그대로 호출할 수 있다. 나머지 두 훅(질문
 * 제시·음성 답변)은 AI Client와 음성 저장소를 끼고 있어 호출부 검증을 각자의 단위 테스트에서 한다 ({@code
 * ConversationNextQuestionServiceTest}·{@code VoiceAnswerServiceTest}의 "이벤트를 남긴다" 테스트). 두 축을 합치면
 * <b>모든 훅이 불린다</b>(단위) + <b>불리면 실제로 Mongo에 남는다</b>(여기)가 모두 덮인다.
 */
class ConversationEventMongoIntegrationTest extends IntegrationTestSupport {

  private static final Long GUARDIAN_USER_ID = 91L;
  private static final Long CHILD_ID = 9L;
  private static final Long DRAWING_SESSION_ID = 90L;
  private static final Long CONVERSATION_ID = 900L;
  private static final Long QUESTION_MESSAGE_ID = 9000L;
  private static final int QUESTION_MESSAGE_SEQUENCE = 1;
  private static final String DIRECT_TEXT = "무지개가 예뻐서 그렸어";

  @Autowired private OptionAnswerService optionAnswerService;
  @Autowired private QuestionSkipService questionSkipService;
  @Autowired private ConversationEndService conversationEndService;
  @Autowired private ConversationEventRecorder eventRecorder;
  @Autowired private ConversationEventDocumentRepository eventRepository;
  @Autowired private ConversationEventRetentionProperties retentionProperties;
  @Autowired private MongoTemplate mongoTemplate;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void seedConversationInProgress() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(GUARDIAN_USER_ID), null, List.of()));
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'event-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, 'event-child', '2020-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations (guardian_user_id, child_id, relationship_type) "
            + "VALUES (?, ?, 'MOTHER')",
        GUARDIAN_USER_ID,
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, recommended_age_min, "
            + "recommended_age_max, is_active, display_order) "
            + "VALUES (1, 'FREE_DRAWING', 'Free Drawing', 'GENERAL', 'BOTH', 3, 12, TRUE, 1)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, started_by_user_id, input_method, session_status, "
            + "current_stage, started_at) "
            + "VALUES (?, ?, 1, ?, 'CANVAS', 'IN_PROGRESS', 'CONVERSING', UTC_TIMESTAMP(6))",
        DRAWING_SESSION_ID,
        CHILD_ID,
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO conversation_sessions "
            + "(id, drawing_session_id, conversation_status, difficulty_snapshot, "
            + "max_question_count, question_count, started_at) "
            + "VALUES (?, ?, 'CONVERSING', 'PRESCHOOL', 5, 3, UTC_TIMESTAMP(6))",
        CONVERSATION_ID,
        DRAWING_SESSION_ID);
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, parent_message_id, message_sequence, sender_type, "
            + "message_type, raw_text, is_skipped, created_at) "
            + "VALUES (?, ?, NULL, ?, 'AI', 'QUESTION', '무엇을 그렸는지 알려줄래요?', FALSE, UTC_TIMESTAMP(6))",
        QUESTION_MESSAGE_ID,
        CONVERSATION_ID,
        QUESTION_MESSAGE_SEQUENCE);
    jdbcTemplate.update(
        "INSERT INTO conversation_message_options "
            + "(id, conversation_message_id, option_key, option_type, option_value, label, "
            + "display_order) "
            + "VALUES (1, ?, 'RAINBOW', 'STATIC', 'RAINBOW', '무지개', 0), "
            + "(2, ?, 'HOUSE', 'STATIC', 'HOUSE', '집', 1)",
        QUESTION_MESSAGE_ID,
        QUESTION_MESSAGE_ID);
  }

  @AfterEach
  void clearAuthentication() {
    SecurityContextHolder.clearContext();
  }

  /**
   * 칩 답변 Use Case가 실제로 이벤트를 남기는지, 그리고 남긴 것이 <b>행동뿐</b>인지 확인한다.
   *
   * <p>{@code directText} 로 아이가 실제로 할 법한 문장을 넣는다. 그 문장이 문서 어디에도 없어야 한다 — 필드 이름을 하나씩 단언하면 나중에 추가된
   * 필드가 새는 것을 못 잡으므로, 저장된 BSON을 통째로 문자열화해 확인한다.
   */
  @Test
  void submittingAChipAnswerThroughTheRealServiceRecordsBehaviorButNeverTheWords() {
    optionAnswerService.submit(
        GUARDIAN_USER_ID,
        CONVERSATION_ID,
        new OptionAnswerRequest(
            QUESTION_MESSAGE_ID,
            List.of(new SelectedOptionCommand("RAINBOW", "STATIC", "RAINBOW", "무지개")),
            DIRECT_TEXT));

    ConversationEventDocument event = onlyEvent();
    assertThat(event.eventType()).isEqualTo(ConversationEventType.ANSWER_CHIP);
    assertThat(event.sessionId()).isEqualTo(CONVERSATION_ID);
    assertThat(event.childId()).isEqualTo(CHILD_ID);
    assertThat(event.drawingSessionId()).isEqualTo(DRAWING_SESSION_ID);
    assertThat(event.questionMessageId()).isEqualTo(QUESTION_MESSAGE_ID);
    assertThat(event.selectedOptionCount()).isEqualTo(1);
    assertThat(event.directTextProvided()).isTrue();
    // 선행 QUESTION_SHOWN 이 없으므로 지연은 추정하지 않고 비운다.
    assertThat(event.responseLatencyMs()).isNull();
    assertThat(event.questionSeq()).isNull();

    String storedJson = rawDocuments().getFirst().toJson();
    assertThat(storedJson).doesNotContain(DIRECT_TEXT);
    assertThat(storedJson).doesNotContain("무지개");
    assertThat(storedJson).doesNotContain("RAINBOW");
  }

  /** 건너뛰기 Use Case가 사유와 함께 이벤트를 남기는지 확인한다. */
  @Test
  void skippingAQuestionThroughTheRealServiceRecordsTheSkip() {
    questionSkipService.skip(
        CONVERSATION_ID,
        new SkipQuestionRequest(
            QUESTION_MESSAGE_ID, ConversationCompletionReason.CHILD_REQUEST, null));

    ConversationEventDocument event = onlyEvent();
    assertThat(event.eventType()).isEqualTo(ConversationEventType.SKIP);
    assertThat(event.childId()).isEqualTo(CHILD_ID);
    assertThat(event.questionMessageId()).isEqualTo(QUESTION_MESSAGE_ID);
    assertThat(event.reason()).isEqualTo("CHILD_REQUEST");
    // 메시지를 만들지 않는 행동이다.
    assertThat(event.messageSeq()).isNull();
  }

  /**
   * 같은 버튼을 두 번 눌러도 건너뛰기 이벤트는 한 번만 남는지 확인한다.
   *
   * <p>재요청을 그대로 기록하면 소비자가 세는 "건너뛴 질문 수"가 탭 횟수만큼 부풀어, 실제보다 산만한 아이로 읽힌다.
   */
  @Test
  void tappingSkipTwiceRecordsOnlyOneEvent() {
    SkipQuestionRequest request = new SkipQuestionRequest(QUESTION_MESSAGE_ID, null, null);

    questionSkipService.skip(CONVERSATION_ID, request);
    questionSkipService.skip(CONVERSATION_ID, request);

    assertThat(eventRepository.findBySessionIdOrderBySeqAsc(CONVERSATION_ID))
        .singleElement()
        .extracting(ConversationEventDocument::eventType)
        .isEqualTo(ConversationEventType.SKIP);
  }

  /** 대화 종료 Use Case가 사유·질문 수와 함께 이벤트를 남기는지 확인한다. */
  @Test
  void endingTheConversationThroughTheRealServiceRecordsTheEnd() {
    conversationEndService.end(
        CONVERSATION_ID,
        new EndConversationRequest(ConversationCompletionReason.CHILD_REQUEST, null));

    ConversationEventDocument event = onlyEvent();
    assertThat(event.eventType()).isEqualTo(ConversationEventType.SESSION_END);
    assertThat(event.childId()).isEqualTo(CHILD_ID);
    assertThat(event.drawingSessionId()).isEqualTo(DRAWING_SESSION_ID);
    assertThat(event.reason()).isEqualTo("CHILD_REQUEST");
    assertThat(event.questionCount()).isEqualTo(3);
    // 질문에 딸린 행동이 아니다.
    assertThat(event.questionMessageId()).isNull();
    assertThat(event.responseLatencyMs()).isNull();
  }

  /**
   * 선행 질문 제시 이벤트가 있으면 응답 지연과 질문 순번이 채워지는지 확인한다.
   *
   * <p>여기서만 {@link ConversationEventRecorder}를 직접 부른다 — 검증 대상이 "질문 제시 훅이 불리는가"가 아니라 "제시 이벤트가 있을 때
   * 뒤따르는 답변이 그것을 기준으로 지연을 계산하는가"이기 때문이다. 훅이 불리는지는 위의 관통 테스트들이 본다.
   */
  @Test
  void anAnswerAfterAQuestionShownCarriesTheResponseLatencyAndQuestionSequence() {
    eventRecorder.recordQuestionShown(
        new ConversationEventContext(CONVERSATION_ID, CHILD_ID, DRAWING_SESSION_ID),
        QUESTION_MESSAGE_ID,
        QUESTION_MESSAGE_SEQUENCE);

    optionAnswerService.submit(
        GUARDIAN_USER_ID,
        CONVERSATION_ID,
        new OptionAnswerRequest(
            QUESTION_MESSAGE_ID,
            List.of(new SelectedOptionCommand("HOUSE", "STATIC", "HOUSE", "집")),
            null));

    List<ConversationEventDocument> events =
        eventRepository.findBySessionIdOrderBySeqAsc(CONVERSATION_ID);
    assertThat(events)
        .extracting(ConversationEventDocument::eventType)
        .containsExactly(ConversationEventType.QUESTION_SHOWN, ConversationEventType.ANSWER_CHIP);
    ConversationEventDocument answer = events.getLast();
    assertThat(answer.responseLatencyMs()).isNotNull().isGreaterThanOrEqualTo(0L);
    assertThat(answer.questionSeq()).isEqualTo(QUESTION_MESSAGE_SEQUENCE);
    assertThat(answer.directTextProvided()).isFalse();
    // 순번은 발생 순서대로 커진다 — 소비자가 이 순서로 대화 흐름을 재구성한다.
    assertThat(answer.seq()).isGreaterThan(events.getFirst().seq());
  }

  /**
   * 보관 기간이 문서마다 실려 나가는지 확인한다.
   *
   * <p>TTL 인덱스({@code expireAfterSeconds: 0})는 문서에 적힌 {@code expireAt} 만 본다. 이 값이 비면 <b>인덱스가 있어도
   * 아무것도 지워지지 않는다</b> — 보관 기간이 지난 아동 데이터가 남는다는 뜻이다 (CLAUDE.md 9절).
   */
  @Test
  void everyEventCarriesTheRetentionDeadlineTheTtlIndexReads() {
    conversationEndService.end(
        CONVERSATION_ID,
        new EndConversationRequest(ConversationCompletionReason.GUARDIAN_REQUEST, null));

    ConversationEventDocument event = onlyEvent();
    assertThat(event.expireAt())
        .isEqualTo(event.occurredAt().plus(retentionProperties.retentionDays(), ChronoUnit.DAYS));
    // BSON Date(UTC epoch)로 저장돼 파드 시간대와 무관해야 한다.
    assertThat(rawDocuments().getFirst().get("expireAt")).isInstanceOf(java.util.Date.class);
  }

  /**
   * 아동 삭제가 그 아동의 이벤트만 즉시 지우는지 확인한다.
   *
   * <p>TTL은 "언젠가"라서 동의 철회 성격의 삭제를 맡길 수 없다 (저장소-아키텍처 §5).
   */
  @Test
  void deletingByChildRemovesOnlyThatChildsEvents() {
    eventRecorder.recordQuestionShown(
        new ConversationEventContext(CONVERSATION_ID, CHILD_ID, DRAWING_SESSION_ID), 1L, 1);
    eventRecorder.recordQuestionShown(
        new ConversationEventContext(CONVERSATION_ID, CHILD_ID, DRAWING_SESSION_ID), 2L, 2);
    eventRecorder.recordQuestionShown(new ConversationEventContext(901L, 8L, 91L), 3L, 1);

    long deleted = eventRepository.deleteByChildId(CHILD_ID);

    assertThat(deleted).isEqualTo(2);
    assertThat(eventRepository.count()).isEqualTo(1);
    assertThat(eventRepository.findBySessionIdOrderBySeqAsc(901L))
        .singleElement()
        .extracting(ConversationEventDocument::childId)
        .isEqualTo(8L);
  }

  /** 활동 삭제가 그 활동의 이벤트만 지우는지 확인한다. 같은 아동의 다른 활동은 남아야 한다. */
  @Test
  void deletingByDrawingSessionRemovesOnlyThatActivitysEvents() {
    eventRecorder.recordQuestionShown(
        new ConversationEventContext(CONVERSATION_ID, CHILD_ID, DRAWING_SESSION_ID), 1L, 1);
    eventRecorder.recordQuestionShown(new ConversationEventContext(901L, CHILD_ID, 91L), 2L, 1);

    long deleted = eventRepository.deleteByChildIdAndDrawingSessionId(CHILD_ID, DRAWING_SESSION_ID);

    assertThat(deleted).isEqualTo(1);
    assertThat(eventRepository.findBySessionIdOrderBySeqAsc(901L)).hasSize(1);
  }

  private ConversationEventDocument onlyEvent() {
    List<ConversationEventDocument> events =
        eventRepository.findBySessionIdOrderBySeqAsc(CONVERSATION_ID);
    assertThat(events).hasSize(1);
    return events.getFirst();
  }

  private List<Document> rawDocuments() {
    // 매핑을 거치지 않은 원본을 본다. record로 읽으면 "record에 없는 필드"는 조용히 사라져,
    //   실수로 새어 나간 값을 오히려 못 보게 된다.
    return mongoTemplate.findAll(Document.class, "conversation_events");
  }
}
