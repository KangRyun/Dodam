package com.ssafy.b209.notification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.notification.push.PushMessage;
import com.ssafy.b209.notification.push.PushSendOutcome;
import com.ssafy.b209.notification.push.PushSender;
import com.ssafy.b209.notification.service.AnalysisCompletedNotificationService;
import com.ssafy.b209.notification.service.CreatedNotification;
import com.ssafy.b209.notification.service.RetentionNoticeNotificationService;
import com.ssafy.b209.notification.service.TermsChangeNotificationService;
import com.ssafy.b209.report.service.AnalysisCompletedEvent;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 커밋 이후 부수효과로 실행되는 알림 생성·발송이 실 MySQL에 실제로 남는지 관통 검증한다 (S15P11B209-749).
 *
 * <p>기존 {@code AnalysisCompletedPushListenerTest}는 생성 서비스를 Mock으로 대체해 통과했다. 그래서 "커밋 후 단계에서는 저장이 아예
 * 일어나지 않는다"는 결함을 잡지 못했다. 이 클래스는 리포트 완료 Transaction이 커밋된 다음 단계를 실제 Transaction 동기화로 재현하고, 알림 행·생성된
 * 식별자 ·전송 상태를 DB에서 직접 확인한다.
 *
 * <p>커밋 후 단계에서는 이미 커밋된 Transaction 자원이 아직 Thread에 남아 있어, 전파 수준이 {@code REQUIRED}이면 새 Transaction이
 * 시작되지 않고 그 자원에 참여한다. 그 상태의 {@code save()}는 IDENTITY 채번을 미루므로 식별자가 비고 INSERT도 실행되지 않는다. 여기서 검증하는
 * 계약은 "커밋 후 단계의 알림 저장은 독립 Transaction에서 커밋된다"는 것이다.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
@TestPropertySource(
    properties =
        "app.push.device-token.encryption-key=MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=")
class AnalysisCompletedNotificationIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long SECOND_GUARDIAN_USER_ID = 42L;
  private static final Long CHILD_ID = 1L;
  private static final Long DELETED_CHILD_ID = 2L;
  private static final long DRAWING_SESSION_ID = 10L;
  private static final long DELETED_CHILD_SESSION_ID = 11L;
  private static final long ANALYSIS_ID = 30L;
  private static final long DELETED_CHILD_ANALYSIS_ID = 31L;
  private static final long REPORT_ID = 50L;
  private static final long DELETED_CHILD_REPORT_ID = 51L;
  private static final String DEVICE_ID = "installation-uuid";
  private static final String TERM_CODE = "SERVICE_TOS";

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_analysis_notification")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private ApplicationEventPublisher eventPublisher;
  @Autowired private PlatformTransactionManager transactionManager;
  @Autowired private AnalysisCompletedNotificationService analysisCompletedNotificationService;
  @Autowired private RetentionNoticeNotificationService retentionNoticeNotificationService;
  @Autowired private TermsChangeNotificationService termsChangeNotificationService;

  @MockitoBean private PushSender pushSender;

  @BeforeEach
  void setUp() {
    authenticate(GUARDIAN_USER_ID);
    jdbcTemplate.update("DELETE FROM notification_attributes");
    jdbcTemplate.update("DELETE FROM notifications");
    jdbcTemplate.update("DELETE FROM notification_device_tokens");
    jdbcTemplate.update("DELETE FROM consent_records");
    jdbcTemplate.update("DELETE FROM reports");
    jdbcTemplate.update("DELETE FROM analyses");
    jdbcTemplate.update("DELETE FROM drawing_sessions");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) VALUES "
            + "(?, 'GUARDIAN', 'first-guardian', 'ACTIVE'), "
            + "(?, 'GUARDIAN', 'second-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID,
        SECOND_GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status, "
            + "deleted_at) VALUES "
            + "(?, '별이', '2020-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE', NULL), "
            + "(?, '지운아이', '2019-05-06', 'PRESCHOOL', 'NOT_STARTED', 'DELETED', "
            + "'2026-07-01 00:00:00')",
        CHILD_ID,
        DELETED_CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations (guardian_user_id, child_id, relationship_type) "
            + "VALUES (?, ?, 'MOTHER'), (?, ?, 'FATHER'), (?, ?, 'MOTHER')",
        GUARDIAN_USER_ID,
        CHILD_ID,
        SECOND_GUARDIAN_USER_ID,
        CHILD_ID,
        GUARDIAN_USER_ID,
        DELETED_CHILD_ID);
    Long drawingTypeId =
        jdbcTemplate.queryForObject("SELECT MIN(id) FROM drawing_types", Long.class);
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at) VALUES "
            + "(?, ?, ?, 'CANVAS', 'COMPLETED', 'COMPLETED', '2026-07-20 01:00:00'), "
            + "(?, ?, ?, 'CANVAS', 'COMPLETED', 'COMPLETED', '2026-07-20 02:00:00')",
        DRAWING_SESSION_ID,
        CHILD_ID,
        drawingTypeId,
        DELETED_CHILD_SESSION_ID,
        DELETED_CHILD_ID,
        drawingTypeId);
    insertAnalysis(ANALYSIS_ID, DRAWING_SESSION_ID);
    insertAnalysis(DELETED_CHILD_ANALYSIS_ID, DELETED_CHILD_SESSION_ID);
    insertReport(REPORT_ID, DRAWING_SESSION_ID, ANALYSIS_ID);
    insertReport(DELETED_CHILD_REPORT_ID, DELETED_CHILD_SESSION_ID, DELETED_CHILD_ANALYSIS_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  // ------------------------------------------------------- 749 커밋 후 알림 저장

  @Test
  void persistsNotificationWithGeneratedIdForEveryGuardianAfterCommit() {
    AtomicReference<List<CreatedNotification>> created = new AtomicReference<>();
    AtomicReference<RuntimeException> failure = new AtomicReference<>();

    runAfterCommit(
        () -> {
          try {
            created.set(analysisCompletedNotificationService.createAnalysisCompleted(REPORT_ID));
          } catch (RuntimeException exception) {
            failure.set(exception);
          }
        });

    // 생성 단계에서 예외가 나면 발송이 통째로 건너뛰어져 알림함도 푸시도 남지 않는다.
    assertThat(failure.get()).isNull();
    List<Map<String, Object>> rows = notificationRows();
    // 커밋되지 않는 Transaction에 참여하면 INSERT 자체가 유실돼 이 목록이 빈다.
    assertThat(rows).hasSize(2);
    assertThat(created.get()).hasSize(2);
    assertThat(created.get())
        .allSatisfy(notification -> assertThat(notification.notificationId()).isPositive());
    assertThat(created.get().stream().map(CreatedNotification::notificationId).toList())
        .containsExactlyInAnyOrderElementsOf(
            rows.stream().map(row -> (Long) row.get("id")).toList());
    assertThat(rows)
        .allSatisfy(
            row -> {
              assertThat(row.get("notification_type")).isEqualTo("ANALYSIS_COMPLETED");
              assertThat(row.get("title")).isEqualTo("분석이 완료됐어요");
              assertThat(row.get("content")).isEqualTo("리포트를 확인해 보세요");
              assertThat(row.get("related_report_id")).isEqualTo(REPORT_ID);
              assertThat(row.get("delivery_status")).isEqualTo("PENDING");
            });
    assertThat(rows.stream().map(row -> row.get("recipient_user_id")).toList())
        .containsExactlyInAnyOrder(GUARDIAN_USER_ID, SECOND_GUARDIAN_USER_ID);
  }

  @Test
  void persistsNotificationThroughTheRealListenerWhenReportCompletionCommits() {
    publishAnalysisCompletedInTransaction(REPORT_ID);

    assertThat(notificationRows()).hasSize(2);
  }

  @Test
  void savesNothingWhenTheReportHasNoActiveGuardian() {
    publishAnalysisCompletedInTransaction(DELETED_CHILD_REPORT_ID);

    assertThat(notificationRows()).isEmpty();
  }

  @Test
  void dispatchesPushWithThePersistedIdAndRecordsDeliveryAfterCommit() throws Exception {
    given(pushSender.isEnabled()).willReturn(true);
    List<PushMessage> sent = capturePushMessages();
    registerDeviceToken();

    publishAnalysisCompletedInTransaction(REPORT_ID);

    Map<String, Object> ownRow = notificationRow(GUARDIAN_USER_ID);
    // 발송 결과 반영도 커밋 후 단계에서 실행되므로 같은 함정에 빠지면 PENDING으로 남는다.
    assertThat(ownRow.get("delivery_status")).isEqualTo("SENT");
    assertThat(ownRow.get("sent_at")).isNotNull();
    assertThat(sent).hasSize(1);
    assertThat(sent.get(0).data())
        .containsEntry("notificationId", String.valueOf(ownRow.get("id")))
        .containsEntry("type", "ANALYSIS_COMPLETED")
        .containsEntry("relatedResourceType", "REPORT")
        .containsEntry("relatedResourceId", String.valueOf(REPORT_ID));
    // 기기가 없는 보호자는 발송을 시도하지 않으므로 알림함 원본만 남는다.
    assertThat(notificationRow(SECOND_GUARDIAN_USER_ID).get("delivery_status"))
        .isEqualTo("PENDING");
  }

  // ------------------------------------------------------- 557 동일 패턴 회귀

  @Test
  void persistsRetentionNoticeWithGeneratedIdAfterCommit() {
    AtomicReference<List<CreatedNotification>> created = new AtomicReference<>();
    AtomicReference<RuntimeException> failure = new AtomicReference<>();

    runAfterCommit(
        () -> {
          try {
            created.set(
                retentionNoticeNotificationService.createRetentionNotices(
                    List.of(GUARDIAN_USER_ID, SECOND_GUARDIAN_USER_ID)));
          } catch (RuntimeException exception) {
            failure.set(exception);
          }
        });

    assertThat(failure.get()).isNull();
    assertThat(notificationRows()).hasSize(2);
    assertThat(created.get())
        .allSatisfy(notification -> assertThat(notification.notificationId()).isPositive());
  }

  @Test
  void persistsConsentUpdatedNoticeWithGeneratedIdAfterCommit() {
    agreeToTerm(GUARDIAN_USER_ID);
    AtomicReference<List<CreatedNotification>> created = new AtomicReference<>();
    AtomicReference<RuntimeException> failure = new AtomicReference<>();

    runAfterCommit(
        () -> {
          try {
            created.set(termsChangeNotificationService.createConsentUpdated(TERM_CODE));
          } catch (RuntimeException exception) {
            failure.set(exception);
          }
        });

    assertThat(failure.get()).isNull();
    assertThat(notificationRows()).hasSize(1);
    assertThat(created.get())
        .singleElement()
        .satisfies(notification -> assertThat(notification.notificationId()).isPositive());
  }

  // ------------------------------------------------------- helpers

  /** 리포트 완료 Transaction과 같은 방식으로, 커밋된 뒤 실행되는 단계에서 주어진 작업을 수행한다. */
  private void runAfterCommit(Runnable action) {
    new TransactionTemplate(transactionManager)
        .executeWithoutResult(
            status ->
                TransactionSynchronizationManager.registerSynchronization(
                    new TransactionSynchronization() {
                      @Override
                      public void afterCommit() {
                        action.run();
                      }
                    }));
  }

  /** 완료 Transaction 안에서 이벤트를 발행해 실제 Listener를 커밋 후 단계로 태운다. */
  private void publishAnalysisCompletedInTransaction(long reportId) {
    new TransactionTemplate(transactionManager)
        .executeWithoutResult(
            status -> eventPublisher.publishEvent(new AnalysisCompletedEvent(reportId)));
  }

  private List<PushMessage> capturePushMessages() {
    List<PushMessage> sent = new ArrayList<>();
    given(pushSender.send(any(PushMessage.class)))
        .willAnswer(
            invocation -> {
              sent.add(invocation.getArgument(0));
              return PushSendOutcome.SENT;
            });
    return sent;
  }

  private void registerDeviceToken() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/notifications/device-tokens")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "deviceId": "%s",
                      "platform": "ANDROID",
                      "pushToken": "fcm-token-1",
                      "appVersion": "1.0.0"
                    }
                    """
                        .formatted(DEVICE_ID)))
        .andExpect(status().isOk());
  }

  private void agreeToTerm(Long userId) {
    Long termId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM consent_terms WHERE term_code = ? AND version = 'v1'",
            Long.class,
            TERM_CODE);
    jdbcTemplate.update(
        "INSERT INTO consent_records "
            + "(consent_term_id, actor_user_id, subject_child_id, subject_reference_hash, action) "
            + "VALUES (?, ?, NULL, REPEAT('a', 64), 'AGREE')",
        termId,
        userId);
  }

  private void insertAnalysis(long id, long drawingSessionId) {
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(id, drawing_session_id, analysis_type, analysis_task_type, idempotency_key, "
            + "analysis_status, requested_at, completed_at) "
            + "VALUES (?, ?, 'FINAL', 'ACTIVITY_REPORT', ?, 'SUCCESS', "
            + "'2026-07-20 03:00:00', '2026-07-20 03:10:00')",
        id,
        drawingSessionId,
        "analysis-key-" + id);
  }

  private void insertReport(long id, long drawingSessionId, long analysisId) {
    jdbcTemplate.update(
        "INSERT INTO reports "
            + "(id, drawing_session_id, analysis_id, report_version, report_status, "
            + "is_expert_review_recommended, limitations_text) "
            + "VALUES (?, ?, ?, 1, 'COMPLETED', FALSE, '참고용 자료입니다.')",
        id,
        drawingSessionId,
        analysisId);
  }

  private List<Map<String, Object>> notificationRows() {
    return jdbcTemplate.queryForList(
        "SELECT id, recipient_user_id, notification_type, title, content, related_report_id, "
            + "delivery_status, sent_at FROM notifications ORDER BY id");
  }

  private Map<String, Object> notificationRow(Long recipientUserId) {
    return jdbcTemplate.queryForMap(
        "SELECT id, delivery_status, sent_at FROM notifications WHERE recipient_user_id = ?",
        recipientUserId);
  }

  private void authenticate(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
