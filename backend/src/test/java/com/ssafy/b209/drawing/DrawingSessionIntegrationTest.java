package com.ssafy.b209.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.drawing.dto.request.CanvasConfigurationRequest;
import com.ssafy.b209.drawing.dto.request.CreateDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.CreateDrawingSessionResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import com.ssafy.b209.drawing.service.DrawingSessionService;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
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
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class DrawingSessionIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private DrawingSessionService drawingSessionService;
  @Autowired private ChildRepository childRepository;
  @Autowired private DrawingTypeRepository drawingTypeRepository;

  @BeforeEach
  void setUp() {
    setAuthenticatedGuardian();
    jdbcTemplate.update("DELETE FROM reports");
    jdbcTemplate.update("DELETE FROM conversation_sessions");
    jdbcTemplate.update("DELETE FROM analysis_detected_objects");
    jdbcTemplate.update("DELETE FROM analyses");
    jdbcTemplate.update("DELETE FROM drawing_session_emotions");
    jdbcTemplate.update("DELETE FROM drawing_assets");
    jdbcTemplate.update("DELETE FROM drawing_sessions");
    jdbcTemplate.execute("ALTER TABLE drawing_sessions AUTO_INCREMENT = 1");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM drawing_types");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'drawing-guardian', 'ACTIVE'), "
            + "(99, 'GUARDIAN', 'another-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (1, 'child-one', '2020-07-21', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE'), "
            + "(2, 'child-two', '2019-07-21', 'PRESCHOOL', 'COMPLETED', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations "
            + "(guardian_user_id, child_id, relationship_type) "
            + "VALUES (?, 1, 'MOTHER'), (?, 2, 'MOTHER')",
        GUARDIAN_USER_ID,
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, recommended_age_min, "
            + "recommended_age_max, is_active, display_order) "
            + "VALUES (1, 'FREE_DRAWING', 'Free Drawing', 'GENERAL', 'BOTH', 3, 12, TRUE, 1)");
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void createsCanvasSessionThroughHttpAndReturnsSameResourceForRetry() throws Exception {
    String body = canvasJson(1L);

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions")
                .header("Idempotency-Key", "integration-key-0001")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/drawing-sessions/1"))
        .andExpect(jsonPath("$.data.sessionStatus").value("IN_PROGRESS"))
        .andExpect(jsonPath("$.data.currentStage").value("DRAWING"))
        .andExpect(jsonPath("$.data.tutorialRequired").value(true));

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions")
                .header("Idempotency-Key", "integration-key-0001")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/drawing-sessions/1"));

    assertThat(sessionCount()).isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT session_status, current_stage, completed_at, deleted_at "
                    + "FROM drawing_sessions WHERE id = 1"))
        .containsEntry("session_status", "IN_PROGRESS")
        .containsEntry("current_stage", "DRAWING")
        .containsEntry("completed_at", null)
        .containsEntry("deleted_at", null);
  }

  @Test
  void storesNormalizedStrokeBatchIdempotentlyAndRejectsSequenceReuse() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions")
                .header("Idempotency-Key", "stroke-integration-session")
                .contentType(MediaType.APPLICATION_JSON)
                .content(canvasJson(1L)))
        .andExpect(status().isCreated());

    String payload = strokeBatchJson(101);
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/1/stroke-batches")
                .contentType(MediaType.APPLICATION_JSON)
                .content(payload))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.batchSequence").value(3))
        .andExpect(jsonPath("$.data.acceptedEventCount").value(1))
        .andExpect(jsonPath("$.data.lastEventSequence").value(101));

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/1/stroke-batches")
                .contentType(MediaType.APPLICATION_JSON)
                .content(payload))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.batchId").isNumber());

    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM stroke_batches", Integer.class))
        .isEqualTo(1);
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM stroke_events", Integer.class))
        .isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForObject("SELECT COUNT(*) FROM stroke_event_points", Integer.class))
        .isEqualTo(2);

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/1/stroke-batches")
                .contentType(MediaType.APPLICATION_JSON)
                .content(strokeBatchJson(102)))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("DRAWING_409_019"));
  }

  @Test
  void persistsRequiredReferenceColumnsThroughRepositories() {
    Child child =
        ChildFixture.create(
            null,
            LocalDate.of(2020, 7, 21),
            ChildTutorialStatus.NOT_STARTED,
            ChildProfileStatus.ACTIVE,
            null);
    DrawingType drawingType =
        DrawingTypeFixture.create(
            null, "MYSQL_PERSIST", "MySQL Persist", DrawingTypeSelectableBy.BOTH, 3, 12, true);

    Child savedChild = childRepository.saveAndFlush(child);
    DrawingType savedType = drawingTypeRepository.saveAndFlush(drawingType);

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT nickname FROM children WHERE id = ?", String.class, savedChild.getId()))
        .isEqualTo("fixture-child");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT activity_category FROM drawing_types WHERE id = ?",
                String.class,
                savedType.getId()))
        .isEqualTo("GENERAL");
  }

  @Test
  void serializesConcurrentRequestsForSameChildWithDifferentKeys() throws Exception {
    List<Object> outcomes =
        invokeConcurrently(
            () -> create("concurrent-child-key-1", 1L), () -> create("concurrent-child-key-2", 1L));

    assertThat(outcomes).filteredOn(CreateDrawingSessionResponse.class::isInstance).hasSize(1);
    assertThat(outcomes)
        .filteredOn(BusinessException.class::isInstance)
        .singleElement()
        .satisfies(
            outcome ->
                assertThat(((BusinessException) outcome).getErrorCode())
                    .isEqualTo(DrawingErrorCode.ACTIVE_DRAWING_SESSION_EXISTS));
    assertThat(sessionCount()).isEqualTo(1);
  }

  @Test
  void returnsSameSessionForConcurrentEquivalentRetries() throws Exception {
    List<Object> outcomes =
        invokeConcurrently(
            () -> create("concurrent-same-key", 1L), () -> create("concurrent-same-key", 1L));

    assertThat(outcomes).allMatch(CreateDrawingSessionResponse.class::isInstance);
    assertThat(outcomes)
        .extracting(outcome -> ((CreateDrawingSessionResponse) outcome).drawingSessionId())
        .containsOnly(
            outcomes.stream()
                .map(outcome -> ((CreateDrawingSessionResponse) outcome).drawingSessionId())
                .findFirst()
                .orElseThrow());
    assertThat(sessionCount()).isEqualTo(1);
  }

  @Test
  void rejectsConcurrentReuseOfSameKeyForDifferentChildren() throws Exception {
    List<Object> outcomes =
        invokeConcurrently(
            () -> create("concurrent-cross-child-key", 1L),
            () -> create("concurrent-cross-child-key", 2L));

    assertThat(outcomes).filteredOn(CreateDrawingSessionResponse.class::isInstance).hasSize(1);
    assertThat(outcomes)
        .filteredOn(BusinessException.class::isInstance)
        .singleElement()
        .satisfies(
            outcome ->
                assertThat(((BusinessException) outcome).getErrorCode())
                    .isEqualTo(DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT));
    assertThat(sessionCount()).isEqualTo(1);
  }

  @Test
  void returnsOwnedDrawingSessionDetailAndHidesInternalStorageKey() throws Exception {
    Long drawingSessionId = create("detail-integration-key", 1L).drawingSessionId();
    insertDetailResources(drawingSessionId);

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}", drawingSessionId))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.child.childId").value(1))
        .andExpect(jsonPath("$.data.child.nickname").value("child-one"))
        .andExpect(jsonPath("$.data.selectedEmotions[0]").value("HAPPY"))
        .andExpect(jsonPath("$.data.selectedEmotions[1]").value("CALM"))
        .andExpect(jsonPath("$.data.latestAsset.drawingAssetId").value(21))
        .andExpect(jsonPath("$.data.latestAsset.storageKey").doesNotExist())
        .andExpect(jsonPath("$.data.latestAnalysis.drawingAnalysisId").value(30))
        .andExpect(jsonPath("$.data.conversationId").value(40))
        .andExpect(jsonPath("$.data.reportId").value(50))
        .andExpect(jsonPath("$.data.recoverableDraft").value(true));
  }

  @Test
  void hidesDrawingSessionExistenceFromUnrelatedGuardian() throws Exception {
    Long drawingSessionId = create("detail-access-key", 1L).drawingSessionId();
    setAuthenticatedUser(99L);

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}", drawingSessionId))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("DRAWING_404_003"));
  }

  private CreateDrawingSessionResponse create(String key, long childId) {
    return drawingSessionService.createDrawingSession(key, request(childId));
  }

  private List<Object> invokeConcurrently(Callable<Object> first, Callable<Object> second)
      throws Exception {
    CountDownLatch ready = new CountDownLatch(2);
    CountDownLatch start = new CountDownLatch(1);
    try (ExecutorService executor = Executors.newFixedThreadPool(2)) {
      Future<Object> firstResult = executor.submit(guarded(first, ready, start));
      Future<Object> secondResult = executor.submit(guarded(second, ready, start));
      ready.await();
      start.countDown();
      return List.of(firstResult.get(), secondResult.get());
    }
  }

  private Callable<Object> guarded(
      Callable<Object> action, CountDownLatch ready, CountDownLatch start) {
    return () -> {
      setAuthenticatedGuardian();
      ready.countDown();
      start.await();
      try {
        return action.call();
      } catch (BusinessException exception) {
        return exception;
      } finally {
        SecurityContextHolder.clearContext();
      }
    };
  }

  private void setAuthenticatedGuardian() {
    setAuthenticatedUser(GUARDIAN_USER_ID);
  }

  private void setAuthenticatedUser(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }

  private void insertDetailResources(Long drawingSessionId) {
    jdbcTemplate.update(
        "INSERT INTO drawing_session_emotions "
            + "(drawing_session_id, emotion_code, selection_order) "
            + "VALUES (?, 'CALM', 1), (?, 'HAPPY', 0)",
        drawingSessionId,
        drawingSessionId);
    jdbcTemplate.update(
        "INSERT INTO drawing_assets "
            + "(id, drawing_session_id, asset_type, asset_version, storage_key, mime_type, "
            + "file_size_bytes, checksum_sha256, last_event_sequence, captured_at, created_at) "
            + "VALUES (20, ?, 'DRAFT', 1, 'private/draft-1.png', 'image/png', 1024, "
            + "REPEAT('a', 64), 1, '2026-07-23 01:01:00', '2026-07-23 01:01:00'), "
            + "(21, ?, 'DRAFT', 2, 'private/draft-2.png', 'image/png', 2048, "
            + "REPEAT('b', 64), 2, '2026-07-23 01:02:00', '2026-07-23 01:02:00')",
        drawingSessionId,
        drawingSessionId);
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(id, drawing_session_id, drawing_asset_id, analysis_type, analysis_task_type, "
            + "idempotency_key, analysis_status, trigger_reason, requested_at, started_at, "
            + "completed_at, created_at) "
            + "VALUES (30, ?, 21, 'INTERMEDIATE', 'OBJECT_DETECTION', "
            + "'detail-analysis-key', 'SUCCESS', 'INTERVAL', "
            + "'2026-07-23 01:03:00', '2026-07-23 01:03:00', "
            + "'2026-07-23 01:03:01', '2026-07-23 01:03:00')",
        drawingSessionId);
    jdbcTemplate.update(
        "INSERT INTO conversation_sessions "
            + "(id, drawing_session_id, conversation_status, difficulty_snapshot, "
            + "max_question_count, question_count, started_at) "
            + "VALUES (40, ?, 'CONVERSING', 'PRESCHOOL', 10, 0, '2026-07-23 01:04:00')",
        drawingSessionId);
    jdbcTemplate.update(
        "INSERT INTO reports "
            + "(id, drawing_session_id, analysis_id, report_version, report_status, "
            + "is_expert_review_recommended, limitations_text, pdf_status, created_at, updated_at) "
            + "VALUES (50, ?, 30, 1, 'GENERATING', FALSE, "
            + "'생성 중인 리포트입니다.', 'NONE', '2026-07-23 01:05:00', '2026-07-23 01:05:00')",
        drawingSessionId);
  }

  private CreateDrawingSessionRequest request(long childId) {
    return new CreateDrawingSessionRequest(
        childId,
        1L,
        DrawingInputMethod.CANVAS,
        OffsetDateTime.parse("2026-07-21T11:30:00+09:00"),
        new CanvasConfigurationRequest(1920, 1080, "#FFFFFF"));
  }

  private String canvasJson(long childId) {
    return """
        {
          "childId": %d,
          "drawingTypeId": 1,
          "inputMethod": "CANVAS",
          "clientStartedAt": "2026-07-21T11:30:00+09:00",
          "canvas": {"width": 1920, "height": 1080, "backgroundColor": "#FFFFFF"}
        }
        """
        .formatted(childId);
  }

  private String strokeBatchJson(long eventSequence) {
    return """
        {
          "batchSequence": 3,
          "firstEventSequence": %1$d,
          "lastEventSequence": %1$d,
          "clientCreatedAt": "2026-07-21T11:32:10.120+09:00",
          "events": [{
            "sequence": %1$d,
            "eventType": "STROKE",
            "tool": "PEN",
            "color": "#FFCC00",
            "width": 8.0,
            "points": [{"x":0.18,"y":0.42,"t":0},{"x":0.19,"y":0.43,"t":16}]
          }],
          "metrics": {
            "undoCountDelta": 1,
            "redoCountDelta": 0,
            "eraseCountDelta": 2,
            "pauseDurationMsDelta": 3200
          }
        }
        """
        .formatted(eventSequence);
  }

  private int sessionCount() {
    return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM drawing_sessions", Integer.class);
  }
}
