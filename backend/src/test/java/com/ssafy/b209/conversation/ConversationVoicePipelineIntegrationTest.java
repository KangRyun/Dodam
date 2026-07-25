package com.ssafy.b209.conversation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.conversation.service.SttProcessingService;
import com.ssafy.b209.conversation.service.VoiceAnswerIdempotencyStore;
import com.ssafy.b209.infrastructure.ai.AiSttClient;
import com.ssafy.b209.infrastructure.ai.AiSttClientException;
import com.ssafy.b209.infrastructure.ai.AiSttResponse;
import com.ssafy.b209.infrastructure.ai.tts.AiTtsClient;
import com.ssafy.b209.infrastructure.ai.tts.MockAiTtsClient;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
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
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 대화 확장 4개 endpoint(음성 답변 업로드·STT 폴링·원본 재생·질문 TTS)를 실 MySQL과 실 파일 저장소로 관통 검증하는 통합 테스트다.
 *
 * <p>{@code MvpFlowIntegrationTest}가 happy-path 1회만 훑고 지나간 구간이며, 이 클래스는 오류·권한·상태 전이 경계까지 검증한다. 인증은
 * 다른 단면 통합 테스트와 같이 검증된 {@link AuthenticatedUser} Principal을 SecurityContext에 넣어 재현하고, 아동·활동·대화·질문
 * fixture는 jdbc로 직접 구성한다.
 *
 * <p>외부 경계만 대체한다. Redis 멱등성 Store는 pass-through로, 내부 AI STT·TTS Client는 Mockito로 대체하고 그 밖의 검증·저장·조회
 * 경로는 실제 코드를 실행한다. TTS 합성 Byte는 저장 계층의 형식·길이 검증을 통과해야 하므로 {@link MockAiTtsClient}가 만드는 실제 재생 가능한
 * MP3를 그대로 사용한다.
 *
 * <p><strong>브리지</strong>: PENDING 음성 답변을 STT 처리로 넘기는 프로덕션 트리거(HTTP·이벤트·스케줄러)가 존재하지 않아 289 파이프라인은
 * {@link SttProcessingService} 빈을 직접 호출해 전이시킨다. 트리거 부재는 프로덕션 갭이며 이 테스트의 범위 밖이다.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class ConversationVoicePipelineIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long OTHER_GUARDIAN_USER_ID = 42L;
  private static final Long CHILD_ID = 1L;
  private static final Long CONVERSATION_ID = 100L;
  private static final Long QUESTION_MESSAGE_ID = 1000L;
  private static final String QUESTION_TEXT = "무엇을 그렸는지 알려줄래요?";
  private static final Path AUDIO_ROOT = createAudioRoot();

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_conversation_voice")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private SttProcessingService sttProcessingService;

  @MockitoBean private VoiceAnswerIdempotencyStore idempotencyStore;
  @MockitoBean private AiSttClient aiSttClient;
  @MockitoBean private AiTtsClient aiTtsClient;

  @DynamicPropertySource
  static void audioStorageProperties(DynamicPropertyRegistry registry) {
    registry.add("app.storage.audio.root", AUDIO_ROOT::toString);
  }

  @BeforeEach
  void setUp() {
    authenticate(GUARDIAN_USER_ID);
    given(idempotencyStore.execute(any(), any(), any(), any(), any()))
        .willAnswer(invocation -> ((Supplier<?>) invocation.getArgument(4)).get());
    given(aiTtsClient.synthesize(any()))
        .willAnswer(invocation -> new MockAiTtsClient().synthesize(invocation.getArgument(0)));

    resetTables();
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) VALUES "
            + "(?, 'GUARDIAN', 'voice-guardian', 'ACTIVE'), "
            + "(?, 'GUARDIAN', 'other-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID,
        OTHER_GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, 'voice-child', '2020-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
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
    jdbcTemplate.update(
        "INSERT INTO conversation_messages "
            + "(id, conversation_session_id, parent_message_id, message_sequence, sender_type, "
            + "message_type, raw_text, is_skipped, created_at) "
            + "VALUES (?, ?, NULL, 1, 'AI', 'QUESTION', ?, FALSE, UTC_TIMESTAMP(6))",
        QUESTION_MESSAGE_ID,
        CONVERSATION_ID,
        QUESTION_TEXT);
    // 음성 처리 동의는 아동 대상 필수 약관이며 최신 이력이 AGREE여야 업로드가 허용된다.
    jdbcTemplate.update(
        "INSERT INTO consent_terms "
            + "(id, term_code, target_scope, is_required, version, title, effective_at, is_active) "
            + "VALUES (1, 'VOICE_PROCESSING', 'CHILD', TRUE, 'v1', '음성 처리 동의', "
            + "'2020-01-01 00:00:00', TRUE)");
    agreeVoiceProcessing();
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  // ---------------------------------------------------------------- 288 음성 답변 업로드

  @Test
  void storesPendingVoiceAnswerWithoutExposingInternalStorageLocation() throws Exception {
    String body =
        mockMvc
            .perform(uploadVoiceAnswer(QUESTION_MESSAGE_ID, "voice-answer-key-001"))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.data.messageId").isNumber())
            .andExpect(jsonPath("$.data.parentMessageId").value(QUESTION_MESSAGE_ID))
            .andExpect(jsonPath("$.data.sequence").value(2))
            .andExpect(jsonPath("$.data.senderType").value("CHILD"))
            .andExpect(jsonPath("$.data.speechStatus").value("PENDING"))
            .andExpect(jsonPath("$.data.sttText").doesNotExist())
            .andExpect(jsonPath("$.data.sttConfidence").doesNotExist())
            .andExpect(jsonPath("$.data.needsGuardianConfirmation").value(false))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    assertThat(body).doesNotContain("audioStorageKey").doesNotContain(AUDIO_ROOT.toString());

    long messageId = messageIdOfLatestVoiceAnswer();
    String storageKey =
        jdbcTemplate.queryForObject(
            "SELECT audio_storage_key FROM conversation_messages WHERE id = ?",
            String.class,
            messageId);
    assertThat(storageKey).isNotBlank();
    assertThat(Files.exists(AUDIO_ROOT.resolve(storageKey))).isTrue();
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT audio_checksum_sha256 FROM conversation_messages WHERE id = ?",
                String.class,
                messageId))
        .hasSize(64);
  }

  @Test
  void rejectsUploadWithoutUsableIdempotencyKey() throws Exception {
    mockMvc
        .perform(
            multipart("/api/v1/conversations/{conversationId}/answers/voice", CONVERSATION_ID)
                .file(audioPart())
                .file(metadataPart(QUESTION_MESSAGE_ID)))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("VOICE_ANSWER_METADATA_INVALID"));

    mockMvc
        .perform(uploadVoiceAnswer(QUESTION_MESSAGE_ID, "short"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("VOICE_ANSWER_METADATA_INVALID"));

    assertThat(voiceAnswerCount()).isZero();
  }

  @Test
  void rejectsUploadWithReversedRecordingWindow() throws Exception {
    String metadata =
        """
        {
          "questionMessageId": %d,
          "clientStartedAt": "2026-07-25T02:00:05Z",
          "clientEndedAt": "2026-07-25T02:00:00Z",
          "stopReason": "USER_FINISH"
        }
        """
            .formatted(QUESTION_MESSAGE_ID);

    mockMvc
        .perform(
            multipart("/api/v1/conversations/{conversationId}/answers/voice", CONVERSATION_ID)
                .file(audioPart())
                .file(
                    new MockMultipartFile(
                        "metadata",
                        "metadata.json",
                        MediaType.APPLICATION_JSON_VALUE,
                        metadata.getBytes(StandardCharsets.UTF_8)))
                .header("Idempotency-Key", "voice-answer-key-002"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("VOICE_ANSWER_METADATA_INVALID"));

    assertThat(voiceAnswerCount()).isZero();
  }

  @Test
  void rejectsUploadWhenVoiceProcessingConsentIsWithdrawn() throws Exception {
    withdrawVoiceProcessing();

    mockMvc
        .perform(uploadVoiceAnswer(QUESTION_MESSAGE_ID, "voice-answer-key-003"))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("VOICE_CONSENT_REQUIRED"));

    assertThat(voiceAnswerCount()).isZero();
    assertThat(storedAudioFileCount()).isZero();
  }

  @Test
  void rejectsUploadFromGuardianWithoutChildRelation() throws Exception {
    authenticate(OTHER_GUARDIAN_USER_ID);

    mockMvc
        .perform(uploadVoiceAnswer(QUESTION_MESSAGE_ID, "voice-answer-key-004"))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("CONVERSATION_ACCESS_DENIED"));

    assertThat(voiceAnswerCount()).isZero();
  }

  @Test
  void rejectsUploadWhenConversationIsNoLongerConversing() throws Exception {
    jdbcTemplate.update(
        "UPDATE conversation_sessions SET conversation_status = 'COMPLETED' WHERE id = ?",
        CONVERSATION_ID);

    mockMvc
        .perform(uploadVoiceAnswer(QUESTION_MESSAGE_ID, "voice-answer-key-005"))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("CONVERSATION_NOT_CONVERSING"));

    assertThat(voiceAnswerCount()).isZero();
  }

  @Test
  void rejectsUploadForQuestionOutsideConversation() throws Exception {
    mockMvc
        .perform(uploadVoiceAnswer(999_999L, "voice-answer-key-006"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("QUESTION_MESSAGE_NOT_FOUND"));

    assertThat(voiceAnswerCount()).isZero();
  }

  @Test
  void rejectsRecordingLongerThanSixtySeconds() throws Exception {
    mockMvc
        .perform(
            multipart("/api/v1/conversations/{conversationId}/answers/voice", CONVERSATION_ID)
                .file(new MockMultipartFile("audio", "answer.wav", "audio/wav", wav(61)))
                .file(metadataPart(QUESTION_MESSAGE_ID))
                .header("Idempotency-Key", "voice-answer-key-007"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("AUDIO_400_004"));

    assertThat(voiceAnswerCount()).isZero();
    assertThat(storedAudioFileCount()).isZero();
  }

  // ---------------------------------------------------------------- 290 STT 상태·결과 폴링

  @Test
  void pollsSttStatusFromPendingToSuccessAndExposesTranscript() throws Exception {
    long messageId = uploadAndReturnMessageId("voice-answer-key-101");

    mockMvc
        .perform(get("/api/v1/conversation-messages/{messageId}", messageId))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.speechStatus").value("PENDING"))
        .andExpect(jsonPath("$.data.messageType").value("ANSWER_VOICE"))
        .andExpect(jsonPath("$.data.sttText").doesNotExist());

    given(aiSttClient.transcribe(any()))
        .willReturn(new AiSttResponse("파란 집을 그렸어요", null, "whisper-1", 120L));
    sttProcessingService.process(messageId);

    mockMvc
        .perform(get("/api/v1/conversation-messages/{messageId}", messageId))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.messageId").value((int) messageId))
        .andExpect(jsonPath("$.data.parentMessageId").value(QUESTION_MESSAGE_ID))
        .andExpect(jsonPath("$.data.speechStatus").value("SUCCESS"))
        .andExpect(jsonPath("$.data.sttText").value("파란 집을 그렸어요"))
        // 최신 내부 STT 계약(whisper-1)은 신뢰도를 제공하지 않아 SUCCESS에서도 null이다.
        .andExpect(jsonPath("$.data.sttConfidence").doesNotExist());
  }

  @Test
  void keepsTranscriptEmptyWhenSttFails() throws Exception {
    long messageId = uploadAndReturnMessageId("voice-answer-key-102");
    willThrow(new AiSttClientException(AiSttClientException.Type.AI_UPSTREAM_ERROR))
        .given(aiSttClient)
        .transcribe(any());

    sttProcessingService.process(messageId);

    mockMvc
        .perform(get("/api/v1/conversation-messages/{messageId}", messageId))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.speechStatus").value("FAILED"))
        .andExpect(jsonPath("$.data.sttText").doesNotExist())
        .andExpect(jsonPath("$.data.sttConfidence").doesNotExist());
  }

  @Test
  void hidesTranscriptWhileProcessingHasNotSucceeded() throws Exception {
    long messageId = uploadAndReturnMessageId("voice-answer-key-103");
    jdbcTemplate.update(
        "UPDATE conversation_messages "
            + "SET speech_status = 'PROCESSING', stt_text = '중간 결과', stt_confidence = 0.9000 "
            + "WHERE id = ?",
        messageId);

    mockMvc
        .perform(get("/api/v1/conversation-messages/{messageId}", messageId))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.speechStatus").value("PROCESSING"))
        .andExpect(jsonPath("$.data.sttText").doesNotExist())
        .andExpect(jsonPath("$.data.sttConfidence").doesNotExist());
  }

  @Test
  void rejectsSttStatusForGuardianWithoutChildRelation() throws Exception {
    long messageId = uploadAndReturnMessageId("voice-answer-key-104");
    authenticate(OTHER_GUARDIAN_USER_ID);

    mockMvc
        .perform(get("/api/v1/conversation-messages/{messageId}", messageId))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("CONVERSATION_ACCESS_DENIED"));
  }

  @Test
  void returnsNotFoundForUnknownMessageStatus() throws Exception {
    mockMvc
        .perform(get("/api/v1/conversation-messages/{messageId}", 999_999L))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("CONVERSATION_MESSAGE_NOT_FOUND"));
  }

  // ---------------------------------------------------------------- 298 음성 원본 재생

  @Test
  void streamsUploadedVoiceAnswerWithoutCaching() throws Exception {
    byte[] uploaded = wav(1);
    long messageId = uploadAndReturnMessageId("voice-answer-key-201", uploaded);

    byte[] streamed =
        mockMvc
            .perform(get("/api/v1/conversation-messages/{messageId}/audio", messageId))
            .andExpect(status().isOk())
            .andExpect(header().string("Content-Type", "audio/wav"))
            .andExpect(header().string("Cache-Control", "no-store, private"))
            .andReturn()
            .getResponse()
            .getContentAsByteArray();

    assertThat(streamed).isEqualTo(uploaded);
  }

  @Test
  void returnsNotFoundWhenMessageHasNoStoredAudio() throws Exception {
    mockMvc
        .perform(get("/api/v1/conversation-messages/{messageId}/audio", QUESTION_MESSAGE_ID))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("CONVERSATION_AUDIO_NOT_AVAILABLE"));
  }

  @Test
  void returnsNotFoundWhenStoredAudioFileIsGone() throws Exception {
    long messageId = uploadAndReturnMessageId("voice-answer-key-202");
    String storageKey =
        jdbcTemplate.queryForObject(
            "SELECT audio_storage_key FROM conversation_messages WHERE id = ?",
            String.class,
            messageId);
    Files.delete(AUDIO_ROOT.resolve(storageKey));

    mockMvc
        .perform(get("/api/v1/conversation-messages/{messageId}/audio", messageId))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("CONVERSATION_AUDIO_NOT_AVAILABLE"));
  }

  @Test
  void rejectsAudioPlaybackForGuardianWithoutChildRelation() throws Exception {
    long messageId = uploadAndReturnMessageId("voice-answer-key-203");
    authenticate(OTHER_GUARDIAN_USER_ID);

    mockMvc
        .perform(get("/api/v1/conversation-messages/{messageId}/audio", messageId))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("CONVERSATION_ACCESS_DENIED"));
  }

  // ---------------------------------------------------------------- 299 질문 TTS

  @Test
  void generatesQuestionTtsAndServesItThroughTheAudioProxy() throws Exception {
    mockMvc
        .perform(requestTts(QUESTION_MESSAGE_ID, "\"voice\": \"CHILD_FRIENDLY\", \"speed\": 1.0"))
        .andExpect(status().isOk())
        .andExpect(
            jsonPath("$.data.audioUrl")
                .value("/api/v1/conversation-messages/" + QUESTION_MESSAGE_ID + "/audio"))
        .andExpect(jsonPath("$.data.expiresAt").doesNotExist())
        .andExpect(jsonPath("$.data.durationMs").isNumber())
        .andExpect(jsonPath("$.data.subtitle").value(QUESTION_TEXT));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT speech_status FROM conversation_messages WHERE id = ?",
                String.class,
                QUESTION_MESSAGE_ID))
        .isEqualTo("SUCCESS");

    byte[] streamed =
        mockMvc
            .perform(get("/api/v1/conversation-messages/{messageId}/audio", QUESTION_MESSAGE_ID))
            .andExpect(status().isOk())
            .andExpect(header().string("Content-Type", "audio/mpeg"))
            .andReturn()
            .getResponse()
            .getContentAsByteArray();
    assertThat(streamed).isNotEmpty();
  }

  @Test
  void reusesCachedQuestionTtsWithoutCallingAiAgain() throws Exception {
    mockMvc
        .perform(requestTts(QUESTION_MESSAGE_ID, "\"voice\": \"CHILD_FRIENDLY\", \"speed\": 1.0"))
        .andExpect(status().isOk());

    mockMvc
        .perform(requestTts(QUESTION_MESSAGE_ID, "\"voice\": \"CHILD_FRIENDLY\", \"speed\": 1.0"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.subtitle").value(QUESTION_TEXT))
        // 캐시 히트는 저장 Byte를 다시 계산하지 않으므로 길이를 제공하지 않는다.
        .andExpect(jsonPath("$.data.durationMs").doesNotExist());

    verify(aiTtsClient, times(1)).synthesize(any());
    assertThat(storedAudioFileCount()).isEqualTo(1);
  }

  @Test
  void rejectsTtsForMessagesThatAreNotAiQuestions() throws Exception {
    long messageId = uploadAndReturnMessageId("voice-answer-key-301");

    mockMvc
        .perform(requestTts(messageId, "\"voice\": \"CHILD_FRIENDLY\", \"speed\": 1.0"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("TTS_NOT_APPLICABLE"));
  }

  @Test
  void rejectsTtsWhenGenerationIsAlreadyInProgress() throws Exception {
    jdbcTemplate.update(
        "UPDATE conversation_messages SET speech_status = 'PROCESSING' WHERE id = ?",
        QUESTION_MESSAGE_ID);

    mockMvc
        .perform(requestTts(QUESTION_MESSAGE_ID, "\"voice\": \"CHILD_FRIENDLY\", \"speed\": 1.0"))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("TTS_GENERATION_IN_PROGRESS"));
  }

  @Test
  void rejectsTtsRequestWithSpeedOutsideAllowedRange() throws Exception {
    mockMvc
        .perform(requestTts(QUESTION_MESSAGE_ID, "\"voice\": \"CHILD_FRIENDLY\", \"speed\": 2.0"))
        .andExpect(status().isBadRequest());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM conversation_messages "
                    + "WHERE id = ? AND speech_status IS NOT NULL",
                Integer.class,
                QUESTION_MESSAGE_ID))
        .isZero();
  }

  @Test
  void rejectsTtsForGuardianWithoutChildRelation() throws Exception {
    authenticate(OTHER_GUARDIAN_USER_ID);

    mockMvc
        .perform(requestTts(QUESTION_MESSAGE_ID, "\"voice\": \"CHILD_FRIENDLY\", \"speed\": 1.0"))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("CONVERSATION_ACCESS_DENIED"));
  }

  // ---------------------------------------------------------------- 요청·fixture 도우미

  private org.springframework.test.web.servlet.RequestBuilder requestTts(
      long messageId, String bodyFields) {
    return post("/api/v1/conversation-messages/{messageId}/tts", messageId)
        .contentType(MediaType.APPLICATION_JSON)
        .content("{" + bodyFields + "}");
  }

  private org.springframework.test.web.servlet.RequestBuilder uploadVoiceAnswer(
      long questionMessageId, String idempotencyKey) {
    return multipart("/api/v1/conversations/{conversationId}/answers/voice", CONVERSATION_ID)
        .file(audioPart())
        .file(metadataPart(questionMessageId))
        .header("Idempotency-Key", idempotencyKey);
  }

  private long uploadAndReturnMessageId(String idempotencyKey) throws Exception {
    return uploadAndReturnMessageId(idempotencyKey, wav(1));
  }

  private long uploadAndReturnMessageId(String idempotencyKey, byte[] audio) throws Exception {
    mockMvc
        .perform(
            multipart("/api/v1/conversations/{conversationId}/answers/voice", CONVERSATION_ID)
                .file(new MockMultipartFile("audio", "answer.wav", "audio/wav", audio))
                .file(metadataPart(QUESTION_MESSAGE_ID))
                .header("Idempotency-Key", idempotencyKey))
        .andExpect(status().isCreated());
    return messageIdOfLatestVoiceAnswer();
  }

  private MockMultipartFile audioPart() {
    return new MockMultipartFile("audio", "answer.wav", "audio/wav", wav(1));
  }

  private MockMultipartFile metadataPart(long questionMessageId) {
    String metadata =
        """
        {
          "questionMessageId": %d,
          "clientStartedAt": "2026-07-25T02:00:00Z",
          "clientEndedAt": "2026-07-25T02:00:01Z",
          "stopReason": "USER_FINISH"
        }
        """
            .formatted(questionMessageId);
    return new MockMultipartFile(
        "metadata",
        "metadata.json",
        MediaType.APPLICATION_JSON_VALUE,
        metadata.getBytes(StandardCharsets.UTF_8));
  }

  private long messageIdOfLatestVoiceAnswer() {
    return jdbcTemplate.queryForObject(
        "SELECT id FROM conversation_messages WHERE message_type = 'VOICE_ANSWER' "
            + "ORDER BY id DESC LIMIT 1",
        Long.class);
  }

  private int voiceAnswerCount() {
    return jdbcTemplate.queryForObject(
        "SELECT COUNT(*) FROM conversation_messages WHERE message_type = 'VOICE_ANSWER'",
        Integer.class);
  }

  private long storedAudioFileCount() throws IOException {
    if (!Files.exists(AUDIO_ROOT)) {
      return 0;
    }
    try (var paths = Files.walk(AUDIO_ROOT)) {
      return paths.filter(Files::isRegularFile).filter(path -> !isStagingFile(path)).count();
    }
  }

  private boolean isStagingFile(Path path) {
    return path.toString().contains(".staging");
  }

  private void agreeVoiceProcessing() {
    jdbcTemplate.update(
        "INSERT INTO consent_records "
            + "(consent_term_id, actor_user_id, subject_child_id, subject_reference_hash, action) "
            + "VALUES (1, ?, ?, REPEAT('c', 64), 'AGREE')",
        GUARDIAN_USER_ID,
        CHILD_ID);
  }

  private void withdrawVoiceProcessing() {
    jdbcTemplate.update(
        "INSERT INTO consent_records "
            + "(consent_term_id, actor_user_id, subject_child_id, subject_reference_hash, action, "
            + "recorded_at) "
            + "VALUES (1, ?, ?, REPEAT('c', 64), 'WITHDRAW', "
            + "DATE_ADD(UTC_TIMESTAMP(6), INTERVAL 1 SECOND))",
        GUARDIAN_USER_ID,
        CHILD_ID);
  }

  private void authenticate(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }

  private void resetTables() {
    jdbcTemplate.update("DELETE FROM conversation_message_selected_options");
    jdbcTemplate.update("DELETE FROM conversation_message_options");
    jdbcTemplate.update("DELETE FROM conversation_message_targets");
    jdbcTemplate.update("DELETE FROM conversation_messages");
    jdbcTemplate.update("DELETE FROM conversation_sessions");
    jdbcTemplate.update("DELETE FROM drawing_sessions");
    jdbcTemplate.update("DELETE FROM consent_records");
    jdbcTemplate.update("DELETE FROM consent_terms");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM child_response_modes");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update("DELETE FROM drawing_types");
    jdbcTemplate.update("DELETE FROM users");
    deleteStoredAudio();
  }

  private void deleteStoredAudio() {
    if (!Files.exists(AUDIO_ROOT)) {
      return;
    }
    try (var paths = Files.walk(AUDIO_ROOT)) {
      paths
          .sorted(java.util.Comparator.reverseOrder())
          .filter(path -> !path.equals(AUDIO_ROOT))
          .forEach(
              path -> {
                try {
                  Files.deleteIfExists(path);
                } catch (IOException ignored) {
                  // 남은 임시 파일이 다음 테스트 fixture 구성을 막지 않는다.
                }
              });
    } catch (IOException exception) {
      throw new IllegalStateException("음성 저장소를 정리할 수 없습니다.", exception);
    }
  }

  /** 실제 signature·길이 검증을 통과하는 8kHz 8bit mono PCM WAV를 만든다. */
  private static byte[] wav(int seconds) {
    int sampleRate = 8000;
    int dataLength = sampleRate * seconds;
    ByteBuffer buffer = ByteBuffer.allocate(44 + dataLength).order(ByteOrder.LITTLE_ENDIAN);
    buffer.put("RIFF".getBytes(StandardCharsets.US_ASCII));
    buffer.putInt(36 + dataLength);
    buffer.put("WAVEfmt ".getBytes(StandardCharsets.US_ASCII));
    buffer.putInt(16);
    buffer.putShort((short) 1);
    buffer.putShort((short) 1);
    buffer.putInt(sampleRate);
    buffer.putInt(sampleRate);
    buffer.putShort((short) 1);
    buffer.putShort((short) 8);
    buffer.put("data".getBytes(StandardCharsets.US_ASCII));
    buffer.putInt(dataLength);
    return buffer.array();
  }

  private static Path createAudioRoot() {
    try {
      return Files.createTempDirectory("conversation-voice-integration-");
    } catch (IOException exception) {
      throw new IllegalStateException("음성 통합 테스트 Storage Root를 생성할 수 없습니다.", exception);
    }
  }
}
