package com.ssafy.b209.conversation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.conversation.repository.SttVoiceAnswerMessageRepository;
import com.ssafy.b209.conversation.service.VoiceAnswerIdempotencyStore;
import com.ssafy.b209.infrastructure.ai.AiSttClient;
import com.ssafy.b209.infrastructure.ai.AiSttClientException;
import com.ssafy.b209.infrastructure.ai.AiSttResponse;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.function.Supplier;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 업로드(288)와 STT 처리(289) 사이의 프로덕션 트리거 배선을 검증한다.
 *
 * <p>{@code ConversationVoicePipelineIntegrationTest}는 각 endpoint의 상태 경계를 보느라 트리거를 꺼두고 처리기를 직접
 * 호출한다. 이 클래스는 반대로 <strong>어떤 수동 호출도 하지 않고</strong> 업로드만으로 speech_status가 종결 상태까지 가는지 확인한다. 트리거가
 * 빠지면 폴링(290)이 영구 PENDING을 보게 되므로 음성 기능 전체가 멈춘다.
 *
 * <p>정체 회수 스케줄러는 주기 실행 자체가 시간에 의존하므로 여기서는 대상 선정 질의만 직접 호출해 검증하고, 반복 실행은 단위 테스트가 맡는다.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
@TestPropertySource(properties = "app.stt.trigger.enabled=true")
class ConversationVoiceSttTriggerIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long CHILD_ID = 1L;
  private static final Long CONVERSATION_ID = 100L;
  private static final Long COMPLETED_CONVERSATION_ID = 101L;
  private static final Long QUESTION_MESSAGE_ID = 1000L;
  private static final Duration TRIGGER_TIMEOUT = Duration.ofSeconds(10);
  private static final Path AUDIO_ROOT = createAudioRoot();

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_stt_trigger")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private SttVoiceAnswerMessageRepository messageRepository;

  @MockitoBean private VoiceAnswerIdempotencyStore idempotencyStore;
  @MockitoBean private AiSttClient aiSttClient;

  @DynamicPropertySource
  static void audioStorageProperties(DynamicPropertyRegistry registry) {
    registry.add("app.storage.audio.root", AUDIO_ROOT::toString);
  }

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
  void startsSttFromUploadAloneAndExposesTranscriptThroughPolling() throws Exception {
    given(aiSttClient.transcribe(any()))
        .willReturn(AiSttResponse.legacy("파란 집을 그렸어요", "whisper-1", 120L));

    long messageId = uploadVoiceAnswer("stt-trigger-key-001");

    await()
        .atMost(TRIGGER_TIMEOUT)
        .untilAsserted(() -> assertThat(speechStatusOf(messageId)).isEqualTo("SUCCESS"));
    assertThat(sttTextOf(messageId)).isEqualTo("파란 집을 그렸어요");
  }

  @Test
  void endsAsFailedWithoutTranscriptWhenSttCallFails() throws Exception {
    willThrow(new AiSttClientException(AiSttClientException.Type.AI_UPSTREAM_ERROR))
        .given(aiSttClient)
        .transcribe(any());

    long messageId = uploadVoiceAnswer("stt-trigger-key-002");

    await()
        .atMost(TRIGGER_TIMEOUT)
        .untilAsserted(() -> assertThat(speechStatusOf(messageId)).isEqualTo("FAILED"));
    assertThat(sttTextOf(messageId)).isNull();
  }

  @Test
  void selectsOnlyAgedPendingAnswersOfConversingSessionsForRecovery() {
    insertVoiceAnswer(2001L, CONVERSATION_ID, 2, "PENDING", 30);
    insertVoiceAnswer(2002L, CONVERSATION_ID, 3, "PENDING", 0);
    insertVoiceAnswer(2003L, COMPLETED_CONVERSATION_ID, 2, "PENDING", 30);
    insertVoiceAnswer(2004L, CONVERSATION_ID, 4, "PROCESSING", 30);

    List<Long> stale =
        messageRepository.findStalePendingIds(
            LocalDateTime.now(ZoneOffset.UTC).minusMinutes(2), PageRequest.of(0, 10));

    assertThat(stale).containsExactly(2001L);
  }

  private long uploadVoiceAnswer(String idempotencyKey) throws Exception {
    mockMvc
        .perform(
            multipart("/api/v1/conversations/{conversationId}/answers/voice", CONVERSATION_ID)
                .file(new MockMultipartFile("audio", "answer.wav", "audio/wav", wav()))
                .file(metadataPart())
                .header("Idempotency-Key", idempotencyKey))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.messageType").value("ANSWER_VOICE"))
        .andExpect(jsonPath("$.data.speechStatus").value("PENDING"));
    return jdbcTemplate.queryForObject(
        "SELECT id FROM conversation_messages WHERE message_type = 'VOICE_ANSWER' "
            + "ORDER BY id DESC LIMIT 1",
        Long.class);
  }

  private String speechStatusOf(long messageId) {
    return jdbcTemplate.queryForObject(
        "SELECT speech_status FROM conversation_messages WHERE id = ?", String.class, messageId);
  }

  private String sttTextOf(long messageId) {
    return jdbcTemplate.queryForObject(
        "SELECT stt_text FROM conversation_messages WHERE id = ?", String.class, messageId);
  }

  private void insertVoiceAnswer(
      long messageId,
      long conversationSessionId,
      int sequence,
      String speechStatus,
      int ageMinutes) {
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, parent_message_id, message_sequence, sender_type, "
            + "message_type, audio_storage_key, audio_checksum_sha256, speech_status, "
            + "is_skipped, created_at) "
            + "VALUES (?, ?, ?, ?, 'CHILD', 'VOICE_ANSWER', ?, REPEAT('a', 64), ?, FALSE, "
            + "DATE_SUB(UTC_TIMESTAMP(6), INTERVAL ? MINUTE))",
        messageId,
        conversationSessionId,
        QUESTION_MESSAGE_ID,
        sequence,
        "2026/07/26/recovery-" + messageId + ".wav",
        speechStatus,
        ageMinutes);
  }

  private MockMultipartFile metadataPart() {
    String metadata =
        """
        {
          "questionMessageId": %d,
          "clientStartedAt": "2026-07-26T02:00:00Z",
          "clientEndedAt": "2026-07-26T02:00:01Z",
          "stopReason": "USER_FINISH"
        }
        """
            .formatted(QUESTION_MESSAGE_ID);
    return new MockMultipartFile(
        "metadata",
        "metadata.json",
        MediaType.APPLICATION_JSON_VALUE,
        metadata.getBytes(StandardCharsets.UTF_8));
  }

  private void insertFixtures() {
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'trigger-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, 'trigger-child', '2020-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
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
            + "VALUES (1, 'VOICE_DRAWING', 'Voice Drawing', 'GENERAL', 'BOTH', 3, 12, TRUE, 1)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at) "
            + "VALUES (10, ?, 1, 'CANVAS', 'IN_PROGRESS', 'CONVERSING', UTC_TIMESTAMP(6))",
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO conversation_sessions "
            + "(id, drawing_session_id, conversation_status, difficulty_snapshot, "
            + "max_question_count, question_count, started_at) "
            + "VALUES (?, 10, 'CONVERSING', 'PRESCHOOL', 5, 1, UTC_TIMESTAMP(6))",
        CONVERSATION_ID);
    // conversation_sessions.drawing_session_id는 UNIQUE라 종료된 세션은 별도 그림 세션이 필요하다.
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at) "
            + "VALUES (11, ?, 1, 'CANVAS', 'IN_PROGRESS', 'CONVERSING', UTC_TIMESTAMP(6))",
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO conversation_sessions "
            + "(id, drawing_session_id, conversation_status, difficulty_snapshot, "
            + "max_question_count, question_count, started_at, completed_at) "
            + "VALUES (?, 11, 'COMPLETED', 'PRESCHOOL', 5, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))",
        COMPLETED_CONVERSATION_ID);
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, parent_message_id, message_sequence, sender_type, "
            + "message_type, raw_text, is_skipped, created_at) "
            + "VALUES (?, ?, NULL, 1, 'AI', 'QUESTION', '무엇을 그렸는지 알려줄래요?', FALSE, "
            + "UTC_TIMESTAMP(6))",
        QUESTION_MESSAGE_ID,
        CONVERSATION_ID);
    jdbcTemplate.update(
        "INSERT INTO consent_terms "
            + "(id, term_code, target_scope, is_required, version, title, effective_at, is_active) "
            + "VALUES (1, 'VOICE_PROCESSING', 'CHILD', TRUE, 'v1', '음성 처리 동의', "
            + "'2020-01-01 00:00:00', TRUE)");
    jdbcTemplate.update(
        "INSERT INTO consent_records "
            + "(consent_term_id, actor_user_id, subject_child_id, subject_reference_hash, action) "
            + "VALUES (1, ?, ?, REPEAT('c', 64), 'AGREE')",
        GUARDIAN_USER_ID,
        CHILD_ID);
  }

  private void resetTables() {
    jdbcTemplate.update("DELETE FROM conversation_message_selected_options");
    jdbcTemplate.update("DELETE FROM conversation_message_options");
    jdbcTemplate.update("DELETE FROM conversation_message_targets");
    jdbcTemplate.update("DELETE FROM conversation_messages");
    jdbcTemplate.update("DELETE FROM conversation_sessions");
    jdbcTemplate.update("DELETE FROM consent_records");
    jdbcTemplate.update("DELETE FROM consent_terms");
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

  /** 저장 계층의 형식·길이 검증을 통과하는 1초짜리 8kHz 8bit PCM WAV를 만든다. */
  private static byte[] wav() {
    int sampleRate = 8000;
    ByteBuffer buffer = ByteBuffer.allocate(44 + sampleRate).order(ByteOrder.LITTLE_ENDIAN);
    buffer.put("RIFF".getBytes(StandardCharsets.US_ASCII));
    buffer.putInt(36 + sampleRate);
    buffer.put("WAVEfmt ".getBytes(StandardCharsets.US_ASCII));
    buffer.putInt(16);
    buffer.putShort((short) 1);
    buffer.putShort((short) 1);
    buffer.putInt(sampleRate);
    buffer.putInt(sampleRate);
    buffer.putShort((short) 1);
    buffer.putShort((short) 8);
    buffer.put("data".getBytes(StandardCharsets.US_ASCII));
    buffer.putInt(sampleRate);
    return buffer.array();
  }

  private static Path createAudioRoot() {
    try {
      return Files.createTempDirectory("conversation-voice-stt-trigger-");
    } catch (IOException exception) {
      throw new IllegalStateException("STT 트리거 통합 테스트 Storage Root를 생성할 수 없습니다.", exception);
    }
  }
}
