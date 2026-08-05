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
import com.ssafy.b209.support.SharedMongoContainer;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import javax.imageio.ImageIO;
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
 * 등록 → 그림 유형 조회 → 그림 세션 생성 → 스트로크 배치·Draft 저장 → 중간 분석 → 그림 단계 완료·FINAL 분석 → 대화 시작·질문·선택형 답변·종료 → 회고
 * 저장 → 완료 접수(202) → 세션 상세 조회를 실제 Flutter Remote Repository 계약과 같은 URI·Header·Payload로 수행한다.
 *
 * <p>상태 전이를 DB에서 직접 보정하지 않고 공개 API만 사용한다. 리포트 생성은 완료 접수 커밋 이후 동기
 * {@code @TransactionalEventListener(AFTER_COMMIT)}로 수행되므로 완료 요청 직후 DB 상태를 검증할 수 있다. 따라서 이 테스트는 롤백
 * 트랜잭션을 사용하지 않는다.
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
  private static final byte[] PNG = pngBytes(320, 320);

  private static byte[] pngBytes(int width, int height) {
    BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
    try (ByteArrayOutputStream output = new ByteArrayOutputStream()) {
      if (!ImageIO.write(image, "png", output)) {
        throw new IllegalStateException("PNG 인코딩에 실패했습니다.");
      }
      return output.toByteArray();
    } catch (IOException exception) {
      throw new UncheckedIOException(exception);
    }
  }

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
    // 스트로크 저장은 MongoDB 로 간다(S15P11B209-365). 이 클래스는 IntegrationTestSupport 를
    //   상속하지 않는 예외라, 여기서 직접 붙여 주지 않으면 배치 저장이 500 으로 죽는다.
    SharedMongoContainer.registerTo(registry);
  }

  @BeforeEach
  void setUp() {
    resetTables();
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, recommended_age_min, "
            + "recommended_age_max, is_active, display_order) "
            + "VALUES (1, 'ART_DIARY', '그림 일기', 'GENERAL', 'BOTH', 3, 12, TRUE, 1)");
    // 보호자 본인 대상 필수 약관은 아동 동의 이력을 남기지 않으므로 아동 대화 인가를 막지 않아야 한다.
    jdbcTemplate.update(
        "INSERT INTO consent_terms "
            + "(id, term_code, target_scope, is_required, version, title, effective_at, is_active) "
            + "VALUES (1, 'SERVICE_TOS', 'USER', TRUE, 'v1', '서비스 이용약관', "
            + "'2020-01-01 00:00:00', TRUE)");

    given(providerClient.verify(eq(AuthProvider.KAKAO), any()))
        .willReturn(new VerifiedOAuthIdentity(AuthProvider.KAKAO, PROVIDER_SUBJECT, null));
    given(aiQuestionClient.generate(any(), any())).willReturn(optionQuestionResponse());
    given(startIdempotencyStore.execute(any(), any(), any(), any(), any()))
        .willAnswer(invocation -> ((Supplier<?>) invocation.getArgument(4)).get());
    given(questionIdempotencyStore.execute(any(), any(), any(), any(), any()))
        .willAnswer(invocation -> ((Supplier<?>) invocation.getArgument(4)).get());
    given(questionIdempotencyStore.execute(any(), any(), any(), any(), any(), any()))
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

    // 3) Flutter가 조회한 그림 유형 식별자로 세션을 생성한다(DRAWING 단계로 시작).
    long drawingTypeId = findDrawingTypeId(accessToken, childId);
    long drawingSessionId = createDrawingSession(accessToken, childId, drawingTypeId);

    // 4) 스트로크 배치와 Draft를 저장하고 Draft 식별자로 중간 객체 탐지를 요청한다.
    submitStrokeBatch(accessToken, drawingSessionId);
    long draftAssetId = saveDraft(accessToken, drawingSessionId);
    long intermediateAnalysisId =
        requestAnalysis(accessToken, drawingSessionId, draftAssetId, "PAUSE");
    getAnalysis(accessToken, drawingSessionId, intermediateAnalysisId);

    // 5) 그림 단계 완료 API가 FINAL 저장과 대화 준비용 분석·상태 전이를 함께 수행한다.
    long finalAnalysisId = completeDrawingStage(accessToken, drawingSessionId);
    getAnalysis(accessToken, drawingSessionId, finalAnalysisId);

    // 6) 대화 세션을 시작하고 다음 질문·선택형 답변·내역을 관통한다.
    long conversationId = startConversation(accessToken, drawingSessionId, finalAnalysisId);
    long questionMessageId = requestNextQuestion(accessToken, conversationId, finalAnalysisId);
    submitOptionAnswer(accessToken, conversationId, questionMessageId);
    assertMessageHistory(accessToken, conversationId);

    // 7) 대화 종료 API가 대화와 그림 세션을 각각 COMPLETED·REFLECTION으로 전이한다.
    endConversation(accessToken, conversationId, questionMessageId);

    // 8) 제목과 감정을 저장한다.
    saveReflection(accessToken, drawingSessionId);

    // 9) 완료를 접수하면 커밋 후 동기 리포트 생성으로 세션이 COMPLETED로 전이된다.
    completeDrawingSession(accessToken, drawingSessionId);
    assertReportGeneratedAndSessionCompleted(drawingSessionId);

    // 10) 세션 상세에서 리포트 식별자와 COMPLETED 단계를 확인한다.
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
                          "preferredCharacter": "BASE",
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

  private long findDrawingTypeId(String accessToken, long childId) throws Exception {
    String body =
        mockMvc
            .perform(
                get("/api/v1/drawing-types")
                    .with(bearer(accessToken))
                    .queryParam("childId", String.valueOf(childId))
                    .queryParam("activeOnly", "true"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.content[0].code").value("ART_DIARY"))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    return objectMapper.readTree(body).at("/data/content/0/drawingTypeId").asLong();
  }

  private long createDrawingSession(String accessToken, long childId, long drawingTypeId)
      throws Exception {
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
                          "drawingTypeId": %d,
                          "inputMethod": "CANVAS",
                          "clientStartedAt": "2026-07-21T11:30:00+09:00"
                        }
                        """
                            .formatted(childId, drawingTypeId)))
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

  private long saveDraft(String accessToken, long drawingSessionId) throws Exception {
    MockMultipartFile preview = new MockMultipartFile("preview", "drawing.png", "image/png", PNG);
    MockMultipartFile canvasState =
        new MockMultipartFile(
            "canvasState",
            "canvas-state.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {"lastEventSequence":1,"clientSavedAt":"2026-07-21T11:39:00+09:00"}
            """
                .getBytes(StandardCharsets.UTF_8));
    String body =
        mockMvc
            .perform(
                multipart("/api/v1/drawing-sessions/{drawingSessionId}/draft", drawingSessionId)
                    .file(preview)
                    .file(canvasState)
                    .header("Idempotency-Key", "mvp-draft-0001")
                    .with(
                        request -> {
                          request.setMethod("PUT");
                          return request;
                        })
                    .with(bearer(accessToken)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.assetType").value("DRAFT"))
            .andExpect(jsonPath("$.data.lastEventSequence").value(1))
            .andExpect(jsonPath("$.data.previewUrl").isNotEmpty())
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    return objectMapper.readTree(body).at("/data/drawingAssetId").asLong();
  }

  private long requestAnalysis(
      String accessToken, long drawingSessionId, long drawingAssetId, String triggerReason)
      throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", drawingSessionId)
                    .with(bearer(accessToken))
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        """
                        {
                          "drawingAssetId":%d,
                          "analysisType":"OBJECT_DETECTION",
                          "triggerReason":"%s"
                        }
                        """
                            .formatted(drawingAssetId, triggerReason)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.data.drawingAssetId").value((int) drawingAssetId))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    long analysisId = objectMapper.readTree(body).at("/data/drawingAnalysisId").asLong();
    assertThat(analysisId).isPositive();
    return analysisId;
  }

  private long completeDrawingStage(String accessToken, long drawingSessionId) throws Exception {
    MockMultipartFile finalImage =
        new MockMultipartFile("finalImage", "drawing.png", "image/png", PNG);
    MockMultipartFile metadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {
              "lastEventSequence":1,
              "drawingDurationMs":600000,
              "clientCompletedAt":"2026-07-21T11:40:00+09:00"
            }
            """
                .getBytes(StandardCharsets.UTF_8));
    String body =
        mockMvc
            .perform(
                multipart(
                        "/api/v1/drawing-sessions/{drawingSessionId}/drawing-complete",
                        drawingSessionId)
                    .file(finalImage)
                    .file(metadata)
                    .header("Idempotency-Key", "mvp-drawing-complete-key")
                    .with(bearer(accessToken)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.finalAssetId").isNumber())
            .andExpect(jsonPath("$.data.currentStage").value("CONVERSING"))
            .andExpect(jsonPath("$.data.analysis.status").value("SUCCEEDED"))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    return objectMapper.readTree(body).at("/data/analysis/analysisId").asLong();
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

  private void endConversation(String accessToken, long conversationId, long lastQuestionMessageId)
      throws Exception {
    mockMvc
        .perform(
            post("/api/v1/conversations/{conversationId}/end", conversationId)
                .with(bearer(accessToken))
                .header("Idempotency-Key", "mvp-conversation-end-key")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "reason": "NO_MORE_QUESTION",
                      "lastQuestionMessageId": %d
                    }
                    """
                        .formatted(lastQuestionMessageId)))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.conversationStatus").value("COMPLETED"))
        .andExpect(jsonPath("$.data.nextStage").value("REFLECTION"));
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
    jdbcTemplate.update("DELETE FROM consent_records");
    jdbcTemplate.update("DELETE FROM consent_terms");
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
