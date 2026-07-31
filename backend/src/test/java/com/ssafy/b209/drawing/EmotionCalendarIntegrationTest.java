package com.ssafy.b209.drawing;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 월간 감정 달력 조회를 실 MySQL로 관통 검증하는 통합 테스트다.
 *
 * <p>단위 테스트는 조회 결과를 테스트 대역으로 주입하므로 조인·정렬·범위 조건이 실제 MySQL에서 같게 동작하는지는 증명하지 못한다. 이 클래스는 KST 월 경계 환산,
 * 세션과 감정의 조인으로 활동 수가 부풀지 않는지, 삭제·중단 활동과 다른 아동의 활동이 빠지는지를 실제 Query로 확인한다.
 *
 * <p>인증은 다른 단면 통합 테스트와 같이 검증된 {@link AuthenticatedUser} Principal을 SecurityContext에 넣어 재현하고, 조회 대상
 * 데이터는 jdbc로 구성한다.
 */
@AutoConfigureMockMvc
class EmotionCalendarIntegrationTest extends IntegrationTestSupport {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long OTHER_GUARDIAN_USER_ID = 42L;
  private static final long CHILD_ID = 1L;
  private static final long OTHER_CHILD_ID = 2L;

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    authenticate(GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) VALUES "
            + "(?, 'GUARDIAN', 'calendar-guardian', 'ACTIVE'), "
            + "(?, 'GUARDIAN', 'other-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID,
        OTHER_GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, '별이', '2019-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE'), "
            + "(?, '남의아이', '2019-05-06', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
        CHILD_ID,
        OTHER_CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations (guardian_user_id, child_id, relationship_type) "
            + "VALUES (?, ?, 'MOTHER'), (?, ?, 'MOTHER')",
        GUARDIAN_USER_ID,
        CHILD_ID,
        OTHER_GUARDIAN_USER_ID,
        OTHER_CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, is_active, display_order) "
            + "VALUES (1, 'HOUSE', '집', 'GENERAL', 'BOTH', TRUE, 1)");

    // 저장 값은 UTC 벽시계이며 괄호 안이 KST 기준 시각이다.
    insertSession(10, CHILD_ID, "2026-06-30 15:30:00", "IN_PROGRESS", null); // KST 07-01 00:30
    insertSession(11, CHILD_ID, "2026-07-31 14:30:00", "COMPLETED", null); // KST 07-31 23:30
    insertSession(12, CHILD_ID, "2026-06-30 14:30:00", "COMPLETED", null); // KST 06-30 23:30
    insertSession(13, CHILD_ID, "2026-07-31 15:30:00", "COMPLETED", null); // KST 08-01 00:30
    insertSession(14, CHILD_ID, "2026-07-10 01:00:00", "ABANDONED", null); // KST 07-10 10:00
    insertSession(15, CHILD_ID, "2026-07-11 01:00:00", "COMPLETED", "2026-07-11 02:00:00");
    insertSession(16, CHILD_ID, "2026-07-05 02:00:00", "COMPLETED", null); // KST 07-05 11:00
    insertSession(17, CHILD_ID, "2026-07-05 08:00:00", "COMPLETED", null); // KST 07-05 17:00
    insertSession(18, OTHER_CHILD_ID, "2026-07-05 03:00:00", "COMPLETED", null);

    insertEmotion(10, "HAPPY", 0);
    insertEmotion(10, "CALM", 1);
    insertEmotion(11, "SAD", 0);
    insertEmotion(12, "ANGRY", 0);
    insertEmotion(13, "ANGRY", 0);
    insertEmotion(14, "ANGRY", 0);
    insertEmotion(15, "ANGRY", 0);
    insertEmotion(16, "HAPPY", 0);
    insertEmotion(17, "UNKNOWN", 0);
    insertEmotion(18, "SCARED", 0);

    insertAnalysis(300, 16);
    insertReport(400, 16, 300, 1, "COMPLETED");
    insertReport(401, 16, 300, 2, "GENERATING");
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void aggregatesTheMonthByKoreanCalendarDaysWithoutInflatingActivityCounts() throws Exception {
    mockMvc
        .perform(monthlyCalendar(CHILD_ID, 2026, 7))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.year").value(2026))
        .andExpect(jsonPath("$.data.month").value(7))
        .andExpect(jsonPath("$.data.days.length()").value(3))
        // KST 07-01 00:30 활동은 UTC로는 6월 30일이지만 달력에서는 7월 1일이다.
        .andExpect(jsonPath("$.data.days[0].date").value("2026-07-01"))
        .andExpect(jsonPath("$.data.days[0].representativeEmotion").value("HAPPY"))
        .andExpect(jsonPath("$.data.days[0].emotions[0]").value("HAPPY"))
        .andExpect(jsonPath("$.data.days[0].emotions[1]").value("CALM"))
        // 감정이 2건이어도 활동 수는 1이어야 한다(조인 곱셈 방어).
        .andExpect(jsonPath("$.data.days[0].activityCount").value(1))
        .andExpect(jsonPath("$.data.days[0].completedReportCount").value(0))
        .andExpect(jsonPath("$.data.days[1].date").value("2026-07-05"))
        .andExpect(jsonPath("$.data.days[1].representativeEmotion").value("UNKNOWN"))
        .andExpect(jsonPath("$.data.days[1].emotions[0]").value("HAPPY"))
        .andExpect(jsonPath("$.data.days[1].emotions[1]").value("UNKNOWN"))
        .andExpect(jsonPath("$.data.days[1].activityCount").value(2))
        .andExpect(jsonPath("$.data.days[1].completedReportCount").value(1))
        // KST 07-31 23:30 활동은 UTC로도 7월이며 같은 달에 남아야 한다.
        .andExpect(jsonPath("$.data.days[2].date").value("2026-07-31"))
        .andExpect(jsonPath("$.data.days[2].representativeEmotion").value("SAD"))
        .andExpect(jsonPath("$.data.days[2].activityCount").value(1))
        .andExpect(jsonPath("$.data.summary.activityCount").value(4))
        .andExpect(jsonPath("$.data.summary.topEmotion").value("HAPPY"))
        .andExpect(jsonPath("$.data.summary.completedReportCount").value(1));
  }

  @Test
  void movesTheKoreanBoundaryActivitiesIntoTheirOwnMonths() throws Exception {
    mockMvc
        .perform(monthlyCalendar(CHILD_ID, 2026, 6))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.days.length()").value(1))
        .andExpect(jsonPath("$.data.days[0].date").value("2026-06-30"))
        .andExpect(jsonPath("$.data.summary.activityCount").value(1));

    mockMvc
        .perform(monthlyCalendar(CHILD_ID, 2026, 8))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.days.length()").value(1))
        .andExpect(jsonPath("$.data.days[0].date").value("2026-08-01"))
        .andExpect(jsonPath("$.data.summary.activityCount").value(1));
  }

  @Test
  void returnsAnEmptyCalendarForAMonthWithoutActivity() throws Exception {
    mockMvc
        .perform(monthlyCalendar(CHILD_ID, 2026, 5))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.days").isEmpty())
        .andExpect(jsonPath("$.data.summary.activityCount").value(0))
        .andExpect(jsonPath("$.data.summary.topEmotion").doesNotExist())
        .andExpect(jsonPath("$.data.summary.completedReportCount").value(0));
  }

  @Test
  void hidesTheCalendarOfAChildTheGuardianIsNotConnectedTo() throws Exception {
    for (long childId : List.of(OTHER_CHILD_ID, 999L)) {
      mockMvc
          .perform(monthlyCalendar(childId, 2026, 7))
          .andExpect(status().isNotFound())
          .andExpect(jsonPath("$.code").value("CHILD_404_001"));
    }
  }

  @Test
  void rejectsAMonthOutsideTheAllowedRange() throws Exception {
    mockMvc
        .perform(monthlyCalendar(CHILD_ID, 2026, 13))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsAnUnauthenticatedRequest() throws Exception {
    SecurityContextHolder.clearContext();

    mockMvc
        .perform(monthlyCalendar(CHILD_ID, 2026, 7))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  private MockHttpServletRequestBuilder monthlyCalendar(long childId, int year, int month) {
    return get("/api/v1/children/{childId}/emotions/calendar", childId)
        .param("year", String.valueOf(year))
        .param("month", String.valueOf(month));
  }

  private void insertSession(
      long id, long childId, String startedAt, String status, String deletedAt) {
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, deleted_at, idempotency_key) "
            + "VALUES (?, ?, 1, 'CANVAS', ?, 'COMPLETED', ?, ?, ?)",
        id,
        childId,
        status,
        startedAt,
        deletedAt,
        "calendar-key-" + id);
  }

  private void insertEmotion(long sessionId, String emotionCode, int selectionOrder) {
    jdbcTemplate.update(
        "INSERT INTO drawing_session_emotions "
            + "(drawing_session_id, emotion_code, selection_order) VALUES (?, ?, ?)",
        sessionId,
        emotionCode,
        selectionOrder);
  }

  private void insertAnalysis(long id, long drawingSessionId) {
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(id, drawing_session_id, analysis_type, idempotency_key, analysis_status, "
            + "requested_at) VALUES (?, ?, 'FINAL', ?, 'SUCCESS', '2026-07-05 02:30:00')",
        id,
        drawingSessionId,
        "calendar-analysis-" + id);
  }

  private void insertReport(
      long id, long drawingSessionId, long analysisId, int version, String status) {
    jdbcTemplate.update(
        "INSERT INTO reports "
            + "(id, drawing_session_id, analysis_id, report_version, report_status, "
            + "limitations_text) VALUES (?, ?, ?, ?, ?, '참고용 자료입니다.')",
        id,
        drawingSessionId,
        analysisId,
        version,
        status);
  }

  private void authenticate(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
