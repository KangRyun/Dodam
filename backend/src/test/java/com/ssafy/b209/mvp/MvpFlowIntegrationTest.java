package com.ssafy.b209.mvp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.service.OAuthProviderClient;
import com.ssafy.b209.auth.service.RefreshTokenSessionStore;
import com.ssafy.b209.auth.service.VerifiedOAuthIdentity;
import com.ssafy.b209.conversation.dto.AiQuestionResponse;
import com.ssafy.b209.conversation.dto.QuestionOption;
import com.ssafy.b209.conversation.dto.SafetyResult;
import com.ssafy.b209.conversation.service.ConversationQuestionIdempotencyStore;
import com.ssafy.b209.conversation.service.ConversationStartIdempotencyStore;
import com.ssafy.b209.conversation.service.VoiceAnswerIdempotencyStore;
import com.ssafy.b209.infrastructure.ai.AiQuestionClient;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
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
 * 핵심 MVP 그리기 루프를 하나의 엔드투엔드 happy-path로 관통하는 통합 테스트다.
 *
 * <p>실제 OAuth 로그인으로 JWT를 발급받아 이후 모든 요청을 Bearer 인증으로 수행하고, 각 단계가 발급한 실제 식별자를 다음 단계 입력으로 이어 붙인다. 아동
 * 등록 → 그림 세션 생성 → 스트로크 배치 → 최종 스냅샷 업로드 → 그림 분석 요청·조회 → 대화 시작·질문·선택형 답변·내역 조회 → 회고 저장 → 완료 접수(202) →
 * 세션 상세로 리포트 식별자와 COMPLETED 단계를 확인한다.
 *
 * <p>백엔드에 HTTP 전이가 없는 두 지점(그림 단계 DRAWING→ANALYZING, 대화 상태 CONVERSING→COMPLETED)은 단면 통합 테스트 관례대로
 * jdbcTemplate로 직접 전이한다. 리포트 생성은 완료 접수 커밋 이후 동기 {@code @TransactionalEventListener(AFTER_COMMIT)}로
 * 수행되므로 완료 요청 직후 DB 상태를 검증할 수 있다. 따라서 이 테스트는 롤백 트랜잭션을 사용하지 않는다.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
@TestPropertySource(
    properties = {
      "app.auth.jwt.secret=0123456789abcdef0123456789abcdef",
      "app.auth.filter.legacy-header-enabled=false"
    })
class MvpFlowIntegrationTest {

  private static final String DEVICE_ID = "mvp-device-001";
  private static final String PROVIDER_SUBJECT = "kakao-mvp-user";
  private static final byte[] PNG =
      new byte[] {(byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01};
  private static final Path STORAGE_ROOT = createStorageRoot();

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_mvp_flow")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private ObjectMapper objectMapper;
  @Autowired private JdbcTemplate jdbcTemplate;

  @MockitoBean private OAuthProviderClient providerClient;
  @MockitoBean private RefreshTokenSessionStore sessionStore;
  @MockitoBean private AiQuestionClient aiQuestionClient;
  @MockitoBean private ConversationStartIdempotencyStore startIdempotencyStore;
  @MockitoBean private ConversationQuestionIdempotencyStore questionIdempotencyStore;
  @MockitoBean private VoiceAnswerIdempotencyStore voiceAnswerIdempotencyStore;

  @DynamicPropertySource
  static void storageProperties(DynamicPropertyRegistry registry) {
    registry.add("app.storage.image.root", () -> STORAGE_ROOT.toString());
  }

  @BeforeEach
  void setUp() {
    resetTables();
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, recommended_age_min, "
            + "recommended_age_max, is_active, display_order) "
            + "VALUES (1, 'FREE_DRAWING', 'Free Drawing', 'GENERAL', 'BOTH', 3, 12, TRUE, 1)");

    given(providerClient.verify(eq(AuthProvider.KAKAO), any()))
        .willReturn(new VerifiedOAuthIdentity(AuthProvider.KAKAO, PROVIDER_SUBJECT, null));
    given(aiQuestionClient.generate(any(), any())).willReturn(optionQuestionResponse());
    given(startIdempotencyStore.execute(any(), any(), any(), any(), any()))
        .willAnswer(invocation -> ((Supplier<?>) invocation.getArgument(4)).get());
    given(questionIdempotencyStore.execute(any(), any(), any(), any(), any()))
        .willAnswer(invocation -> ((Supplier<?>) invocation.getArgument(4)).get());
    given(voiceAnswerIdempotencyStore.execute(any(), any(), any(), any(), any()))
        .willAnswer(invocation -> ((Supplier<?>) invocation.getArgument(4)).get());
  }

  @Test
  void runsCoreMvpHappyPathEndToEnd() throws Exception {
    // 1) 실제 OAuth 로그인으로 사용자와 JWT를 발급받는다.
    JsonNode loginResponse = login();
    long userId = loginResponse.at("/data/user/userId").asLong();
    String accessToken = loginResponse.at("/data/accessToken").asText();
    assertThat(userId).isPositive();
    assertThat(accessToken).isNotBlank();

    // 2) 아동을 등록하고 이후 단계에서 사용할 childId를 이어받는다.
    long childId = registerChild(accessToken);

    // 3) 그림 세션을 생성한다(DRAWING 단계로 시작).
    long drawingSessionId = createDrawingSession(accessToken, childId);

    // 4) 스트로크 배치와 최종 스냅샷을 업로드한다(DRAWING 단계 유지).
    submitStrokeBatch(accessToken, drawingSessionId);
    long finalAssetId = uploadFinalSnapshot(accessToken, drawingSessionId);

    // 5) 최종 그림 분석을 요청하고 저장된 결과를 조회한다.
    long analysisId = requestAnalysis(accessToken, drawingSessionId, finalAssetId);
    getAnalysis(accessToken, drawingSessionId, analysisId);

    // 브리지: DRAWING→ANALYZING HTTP 전이가 백엔드에 없어 대화 시작 사전 조건을 직접 맞춘다.
    jdbcTemplate.update(
        "UPDATE drawing_sessions SET current_stage = 'ANALYZING' WHERE id = ?", drawingSessionId);

    // 6) 대화 세션을 시작하고 다음 질문·선택형 답변·내역을 관통한다.
    long conversationId = startConversation(accessToken, drawingSessionId, analysisId);
    long questionMessageId = requestNextQuestion(accessToken, conversationId, analysisId);
    submitOptionAnswer(accessToken, conversationId, questionMessageId);
    assertMessageHistory(accessToken, conversationId);

    // 브리지: CONVERSING→COMPLETED 대화 상태 전이 HTTP가 없어 완료 사전 조건을 직접 맞춘다.
    jdbcTemplate.update(
        "UPDATE conversation_sessions SET conversation_status = 'COMPLETED' WHERE id = ?",
        conversationId);

    // 7) 회고를 저장한다(CONVERSING→REFLECTION 단계 전이).
    saveReflection(accessToken, drawingSessionId);

    // 8) 완료를 접수하면 커밋 후 동기 리포트 생성으로 세션이 COMPLETED로 전이된다.
    completeDrawingSession(accessToken, drawingSessionId);
    assertReportGeneratedAndSessionCompleted(drawingSessionId);

    // 9) 세션 상세에서 리포트 식별자와 COMPLETED 단계를 확인한다.
    long reportId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM reports WHERE drawing_session_id = ?", Long.class, drawingSessionId);
    mockMvc
        .perform(
            get("/api/v1/drawing-sessions/{drawingSessionId}", drawingSessionId)
                .with(bearer(accessToken)))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.currentStage").value("COMPLETED"))
        .andExpect(jsonPath("$.data.reportId").value((int) reportId));
  }

  private JsonNode login() throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/auth/oauth/kakao")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        objectMapper.writeValueAsString(
                            Map.of("accessToken", "provider-token", "deviceId", DEVICE_ID))))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.grantType").value("Bearer"))
            .andExpect(jsonPath("$.data.accessToken").isNotEmpty())
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    return objectMapper.readTree(body);
  }

  private long registerChild(String accessToken) throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/children")
                    .with(bearer(accessToken))
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        """
                        {
                          "nickname": "별이",
                          "birthDate": "2018-05-10",
                          "relationshipType": "MOTHER",
                          "preferredCharacter": "MONGLE",
                          "questionDifficulty": "LOWER_ELEMENTARY",
                          "responseModes": ["EMOJI", "VOICE"]
                        }
                        """))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.data.childId").isNumber())
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    return objectMapper.readTree(body).at("/data/childId").asLong();
  }

  private long createDrawingSession(String accessToken, long childId) throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/drawing-sessions")
                    .with(bearer(accessToken))
                    .header("Idempotency-Key", "mvp-create-session-key")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        """
                        {
                          "childId": %d,
                          "drawingTypeId": 1,
                          "inputMethod": "CANVAS",
                          "clientStartedAt": "2026-07-21T11:30:00+09:00",
                          "canvas": {"width": 1920, "height": 1080, "backgroundColor": "#FFFFFF"}
                        }
                        """
                            .formatted(childId)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.data.sessionStatus").value("IN_PROGRESS"))
            .andExpect(jsonPath("$.data.currentStage").value("DRAWING"))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    return objectMapper.readTree(body).at("/data/drawingSessionId").asLong();
  }

  private void submitStrokeBatch(String accessToken, long drawingSessionId) throws Exception {
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/stroke-batches", drawingSessionId)
                .with(bearer(accessToken))
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "batchSequence": 1,
                      "firstEventSequence": 1,
                      "lastEventSequence": 1,
                      "clientCreatedAt": "2026-07-21T11:32:10.120+09:00",
                      "events": [{
                        "sequence": 1,
                        "eventType": "STROKE",
                        "tool": "PEN",
                        "color": "#FFCC00",
                        "width": 8.0,
                        "points": [{"x":0.18,"y":0.42,"t":0},{"x":0.19,"y":0.43,"t":16}]
                      }],
                      "metrics": {
                        "undoCountDelta": 0,
                        "redoCountDelta": 0,
                        "eraseCountDelta": 0,
                        "pauseDurationMsDelta": 0
                      }
                    }
                    """))
        .andExpect(status().isCreated());
  }

  private long uploadFinalSnapshot(String accessToken, long drawingSessionId) throws Exception {
    MockMultipartFile file = new MockMultipartFile("file", "drawing.png", "image/png", PNG);
    MockMultipartFile metadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {"assetType":"FINAL","assetVersion":1,"capturedAt":"2026-07-21T11:40:00+09:00"}
            """
                .getBytes(StandardCharsets.UTF_8));
    String body =
        mockMvc
            .perform(
                multipart("/api/v1/drawing-sessions/{drawingSessionId}/snapshots", drawingSessionId)
                    .file(file)
                    .file(metadata)
                    .with(bearer(accessToken)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.data.assetType").value("FINAL"))
            .andExpect(jsonPath("$.data.storageKey").doesNotExist())
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    return objectMapper.readTree(body).at("/data/drawingAssetId").asLong();
  }

  private long requestAnalysis(String accessToken, long drawingSessionId, long finalAssetId)
      throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", drawingSessionId)
                    .with(bearer(accessToken))
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        """
                        {"drawingAssetId":%d,"analysisType":"OBJECT_DETECTION"}
                        """
                            .formatted(finalAssetId)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.data.drawingAssetId").value((int) finalAssetId))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    long analysisId = objectMapper.readTree(body).at("/data/drawingAnalysisId").asLong();
    assertThat(analysisId).isPositive();
    return analysisId;
  }

  private void getAnalysis(String accessToken, long drawingSessionId, long analysisId)
      throws Exception {
    mockMvc
        .perform(
            get(
                    "/api/v1/drawing-sessions/{drawingSessionId}/analyses/{drawingAnalysisId}",
                    drawingSessionId,
                    analysisId)
                .with(bearer(accessToken)))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.drawingAnalysisId").value((int) analysisId));
  }

  private long startConversation(String accessToken, long drawingSessionId, long analysisId)
      throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/drawing-sessions/{drawingSessionId}/conversations", drawingSessionId)
                    .with(bearer(accessToken))
                    .header("Idempotency-Key", "mvp-conversation-start-key")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        """
                        {"analysisId":%d,"maxQuestionCount":5}
                        """
                            .formatted(analysisId)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.data.status").value("CONVERSING"))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    return objectMapper.readTree(body).at("/data/conversationId").asLong();
  }

  private long requestNextQuestion(String accessToken, long conversationId, long analysisId)
      throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/conversations/{conversationId}/next-question", conversationId)
                    .with(bearer(accessToken))
                    .header("Idempotency-Key", "mvp-next-question-key")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        """
                        {"basisAnalysisId":%d,"preferredResponseModes":["EMOJI"]}
                        """
                            .formatted(analysisId)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.senderType").value("AI"))
            .andExpect(jsonPath("$.data.messageType").value("QUESTION"))
            .andExpect(jsonPath("$.data.options[0].optionId").value("HOUSE"))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    return objectMapper.readTree(body).at("/data/messageId").asLong();
  }

  private void submitOptionAnswer(String accessToken, long conversationId, long questionMessageId)
      throws Exception {
    // 저장된 질문 선택지 Snapshot을 그대로 회신해야 저장을 허용하므로 DB에서 원본 값을 읽어 답변을 구성한다.
    Map<String, Object> storedOption =
        jdbcTemplate.queryForMap(
            "SELECT option_key, option_type, option_value, label "
                + "FROM conversation_message_options "
                + "WHERE conversation_message_id = ? ORDER BY display_order LIMIT 1",
            questionMessageId);
    Map<String, Object> selectedOption =
        Map.of(
            "optionId", storedOption.get("option_key"),
            "type", storedOption.get("option_type"),
            "value", storedOption.get("option_value"),
            "labelSnapshot", storedOption.get("label"));
    String requestBody =
        objectMapper.writeValueAsString(
            Map.of(
                "questionMessageId",
                questionMessageId,
                "selectedOptions",
                List.of(selectedOption)));

    mockMvc
        .perform(
            post("/api/v1/conversations/{conversationId}/answers/option", conversationId)
                .with(bearer(accessToken))
                .header("Idempotency-Key", "mvp-option-answer-key")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.messageId").isNumber())
        .andExpect(jsonPath("$.data.messageType").value("ANSWER_OPTION"));
  }

  private void assertMessageHistory(String accessToken, long conversationId) throws Exception {
    mockMvc
        .perform(
            get("/api/v1/conversations/{conversationId}/messages", conversationId)
                .with(bearer(accessToken)))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(2))
        .andExpect(jsonPath("$.data.content[0].senderType").value("AI"))
        .andExpect(jsonPath("$.data.content[0].messageType").value("QUESTION"))
        .andExpect(jsonPath("$.data.content[1].senderType").value("CHILD"))
        .andExpect(jsonPath("$.data.content[1].messageType").value("ANSWER_OPTION"));
  }

  private void saveReflection(String accessToken, long drawingSessionId) throws Exception {
    mockMvc
        .perform(
            put("/api/v1/drawing-sessions/{drawingSessionId}/reflection", drawingSessionId)
                .with(bearer(accessToken))
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "title": "우리 가족",
                      "selectedEmotions": ["HAPPY"],
                      "expressedEmotionText": "재밌었어요",
                      "skipped": false
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.currentStage").value("REFLECTION"));
  }

  private void completeDrawingSession(String accessToken, long drawingSessionId) throws Exception {
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/complete", drawingSessionId)
                .with(bearer(accessToken))
                .header("Idempotency-Key", "mvp-complete-key")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"conversationSkipped\":false,\"requestReport\":true}"))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.currentStage").value("REPORTING"))
        .andExpect(jsonPath("$.data.reportStatus").value("GENERATING"));
  }

  private void assertReportGeneratedAndSessionCompleted(long drawingSessionId) {
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT report_status FROM reports WHERE drawing_session_id = ?",
                String.class,
                drawingSessionId))
        .isEqualTo("COMPLETED");
    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT session_status, current_stage, completed_at "
                    + "FROM drawing_sessions WHERE id = ?",
                drawingSessionId))
        .containsEntry("session_status", "COMPLETED")
        .containsEntry("current_stage", "COMPLETED")
        .doesNotContainEntry("completed_at", null);
  }

  private org.springframework.test.web.servlet.request.RequestPostProcessor bearer(
      String accessToken) {
    return request -> {
      request.addHeader(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken);
      return request;
    };
  }

  private AiQuestionResponse optionQuestionResponse() {
    return new AiQuestionResponse(
        "무엇을 그렸는지 알려줄래요?",
        "OBJECT_DESCRIPTION",
        List.of(new QuestionOption("HOUSE", "집"), new QuestionOption("TREE", "나무")),
        null,
        false,
        new SafetyResult("PASSED", "safety-2026-07", null),
        "mock-question-model",
        "1.0",
        "prompt-2026.07",
        12);
  }

  private void resetTables() {
    jdbcTemplate.update("DELETE FROM storage_deletion_jobs");
    jdbcTemplate.update("DELETE FROM reports");
    jdbcTemplate.update("DELETE FROM analysis_detected_objects");
    jdbcTemplate.update("DELETE FROM analyses");
    jdbcTemplate.update("DELETE FROM conversation_message_selected_options");
    jdbcTemplate.update("DELETE FROM conversation_message_options");
    jdbcTemplate.update("DELETE FROM conversation_message_targets");
    jdbcTemplate.update("DELETE FROM conversation_messages");
    jdbcTemplate.update("DELETE FROM conversation_sessions");
    jdbcTemplate.update("DELETE FROM stroke_event_points");
    jdbcTemplate.update("DELETE FROM stroke_events");
    jdbcTemplate.update("DELETE FROM stroke_batches");
    jdbcTemplate.update("DELETE FROM drawing_session_emotions");
    jdbcTemplate.update("DELETE FROM drawing_assets");
    jdbcTemplate.update("DELETE FROM drawing_sessions");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM child_response_modes");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update("DELETE FROM auth_accounts");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update("DELETE FROM drawing_types");
  }

  private static Path createStorageRoot() {
    try {
      return Files.createTempDirectory("mvp-flow-integration-");
    } catch (IOException exception) {
      throw new IllegalStateException("통합 테스트 Storage Root를 생성할 수 없습니다.", exception);
    }
  }
}
