package com.ssafy.b209.conversation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.conversation.service.ConversationQuestionIdempotencyStore;
import com.ssafy.b209.infrastructure.ai.AiQuestionClient;
import com.ssafy.b209.infrastructure.ai.AiQuestionClientException;
import java.util.List;
import java.util.function.Supplier;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * AI 질문 생성이 실패했을 때 폴백 질문으로 대화가 계속되는지 실 MySQL로 검증한다.
 *
 * <p>단위 테스트는 Template 조회 결과를 Mock으로 주입하므로 "폴백 데이터가 DB에 있는가"를 확인하지 못한다. 실제로 V15 이전에는 Template과 선택지가
 * 어떤 migration에도 없어 폴백이 {@code CONVERSATION_503_001}로 실패했고, 이 클래스는 그 조합(코드 + 시드 데이터)을 함께 검증한다.
 *
 * <p>외부 응답 방식 {@code EMOJI}는 내부 {@code OPTION}으로 매핑되어 Template 선택지를 요구하므로, 선택지 시드가 빠지면 이 테스트가 먼저
 * 실패한다.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class ConversationFallbackQuestionIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 71L;
  private static final Long CHILD_ID = 7L;
  private static final Long DRAWING_SESSION_ID = 70L;
  private static final Long CONVERSATION_ID = 700L;

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_fallback_question")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @MockitoBean private ConversationQuestionIdempotencyStore idempotencyStore;
  @MockitoBean private AiQuestionClient aiQuestionClient;

  @BeforeEach
  void setUp() {
    authenticate();
    given(idempotencyStore.execute(any(), any(), any(), any(), any()))
        .willAnswer(invocation -> ((Supplier<?>) invocation.getArgument(4)).get());
    resetTables();
    insertFixtures();
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void seedsFallbackTemplateSoAiFailureStillReturnsQuestion() throws Exception {
    willThrow(new AiQuestionClientException(AiQuestionClientException.Type.OTHER))
        .given(aiQuestionClient)
        .generate(any(), any());

    mockMvc
        .perform(
            post("/api/v1/conversations/{conversationId}/next-question", CONVERSATION_ID)
                .header("Idempotency-Key", "fallback-question-key-001")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"preferredResponseModes\":[\"EMOJI\",\"VOICE\"]}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.senderType").value("AI"))
        .andExpect(jsonPath("$.data.messageType").value("QUESTION"))
        .andExpect(jsonPath("$.data.text").isNotEmpty())
        .andExpect(jsonPath("$.data.options.length()").value(3))
        // 시드한 Emoji가 응답까지 실려야 한다. 노출 type은 OPTION 고정(저장 Snapshot의 STATIC과 다른 값).
        .andExpect(jsonPath("$.data.options[0].type").value("OPTION"))
        .andExpect(jsonPath("$.data.options[0].emoji").isNotEmpty());

    Long templateId =
        jdbcTemplate.queryForObject(
            "SELECT question_template_id FROM conversation_messages "
                + "WHERE conversation_session_id = ? AND sender_type = 'AI' "
                + "ORDER BY id DESC LIMIT 1",
            Long.class,
            CONVERSATION_ID);
    // 폴백으로 저장한 질문은 사용한 Template ID를 남긴다(AI 생성 질문은 null).
    assertThat(templateId).isNotNull();
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT template_type FROM ai_question_templates WHERE id = ?",
                String.class,
                templateId))
        .isEqualTo("FALLBACK");

    // 선택지 Snapshot도 Emoji를 보관해야 대화 내역 조회(151)가 같은 화면을 재현할 수 있다.
    assertThat(
            jdbcTemplate.queryForList(
                "SELECT emoji FROM conversation_message_options "
                    + "WHERE emoji IS NOT NULL AND emoji <> ''",
                String.class))
        .hasSize(3);
  }

  @Test
  void keepsSingleActiveFallbackTemplateAfterMigration() {
    // 조회는 templateType과 is_active만 보고 첫 행을 고른다. 활성 행이 여러 개면 나머지는 도달하지 않는 데이터가 된다.
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM ai_question_templates "
                    + "WHERE template_type = 'FALLBACK' AND is_active = TRUE",
                Integer.class))
        .isEqualTo(1);
  }

  private void insertFixtures() {
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'fallback-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, 'fallback-child', '2019-03-02', 'LOWER_ELEMENTARY', 'COMPLETED', "
            + "'ACTIVE')",
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
            + "VALUES (70, 'FALLBACK_DRAWING', 'Fallback Drawing', 'GENERAL', 'BOTH', 3, 12, "
            + "TRUE, 1)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at) "
            + "VALUES (?, ?, 70, 'CANVAS', 'IN_PROGRESS', 'CONVERSING', UTC_TIMESTAMP(6))",
        DRAWING_SESSION_ID,
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO conversation_sessions "
            + "(id, drawing_session_id, conversation_status, difficulty_snapshot, "
            + "max_question_count, question_count, started_at) "
            + "VALUES (?, ?, 'CONVERSING', 'LOWER_ELEMENTARY', 5, 0, UTC_TIMESTAMP(6))",
        CONVERSATION_ID,
        DRAWING_SESSION_ID);
  }

  private void resetTables() {
    // ai_question_templates·ai_question_template_options는 지우지 않는다 — V15가 시드한 검증 대상이다.
    jdbcTemplate.update("DELETE FROM conversation_message_selected_options");
    jdbcTemplate.update("DELETE FROM conversation_message_options");
    jdbcTemplate.update("DELETE FROM conversation_message_targets");
    jdbcTemplate.update("DELETE FROM conversation_messages");
    jdbcTemplate.update("DELETE FROM conversation_sessions");
    jdbcTemplate.update("DELETE FROM drawing_sessions");
    jdbcTemplate.update("DELETE FROM drawing_types");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update("DELETE FROM users");
  }

  private void authenticate() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(GUARDIAN_USER_ID), null, List.of()));
  }
}
