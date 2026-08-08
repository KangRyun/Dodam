package com.ssafy.b209.referral.repository;

import java.time.LocalDate;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 의뢰 요약에 실을 원자료를 읽는다.
 *
 * <p>새 표를 만들지 않는다. 의뢰 요약은 <strong>이미 남아 있는 기록을 모아 정리한 것</strong>이지 새로운 판단이 아니다 — 별도 표에 저장해 두면 원본과
 * 요약이 어긋나고, 어긋난 요약이 병원으로 나간다.
 */
@Repository
public class JdbcReferralSummaryRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 의뢰 요약 원자료 조회 저장소를 구성한다.
   *
   * @param jdbcTemplate 리포트 하위 기록을 조회할 JDBC Template
   */
  public JdbcReferralSummaryRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 아이의 최근 활동 회차를 최신순으로 읽는다.
   *
   * <p>숨긴 리포트는 빼고 완료된 것만 본다 — 보호자가 숨긴 기록이 의뢰 문서로 되살아나면 안 된다.
   *
   * @param childId 아동 식별자
   * @param limit 가져올 회차 수
   * @return 최신순 회차 목록이며 없으면 빈 목록
   */
  public List<ReferralSessionRow> findRecentSessions(Long childId, int limit) {
    return jdbcTemplate.query(
        """
        select report.id                as report_id,
               type.code                as activity_type,
               date(session.started_at) as activity_date,
               insight.headline         as headline,
               insight.main_event       as main_event,
               insight.reality_status   as reality_status,
               insight.time_scope       as time_scope,
               insight.confirmed_voice_count as confirmed_voice_count,
               insight.option_answer_count   as option_answer_count,
               insight.skipped_count         as skipped_count,
               insight.stt_confirmation_count as stt_confirmation_count
          from reports report
          join drawing_sessions session on session.id = report.drawing_session_id
          join drawing_types type on type.id = session.drawing_type_id
          left join report_diary_insights insight on insight.report_id = report.id
         where session.child_id = ?
           and report.report_status = 'COMPLETED'
           and report.hidden_at is null
         order by session.started_at desc, report.id desc
         limit ?
        """,
        (rs, rowNum) ->
            new ReferralSessionRow(
                rs.getLong("report_id"),
                rs.getString("activity_type"),
                rs.getObject("activity_date", LocalDate.class),
                rs.getString("headline"),
                rs.getString("main_event"),
                rs.getString("reality_status"),
                rs.getString("time_scope"),
                rs.getInt("confirmed_voice_count"),
                rs.getInt("option_answer_count"),
                rs.getInt("skipped_count"),
                rs.getInt("stt_confirmation_count")),
        childId,
        limit);
  }

  /**
   * 그 회차들에서 아이가 한 말을 읽는다.
   *
   * @param reportIds 리포트 식별자 목록이며 비면 조회하지 않는다
   * @return 회차·노출 순서대로 정렬된 발화 목록
   */
  public List<ReferralChildVoiceRow> findChildVoices(List<Long> reportIds) {
    if (reportIds.isEmpty()) {
      return List.of();
    }
    String placeholders = String.join(",", reportIds.stream().map(id -> "?").toList());
    return jdbcTemplate.query(
        "select report_id, text, elicitation_type, answer_type, stt_needs_confirmation "
            + "from report_diary_child_voices "
            + "where report_id in ("
            + placeholders
            + ") order by report_id desc, display_order asc",
        (rs, rowNum) ->
            new ReferralChildVoiceRow(
                rs.getLong("report_id"),
                rs.getString("text"),
                rs.getString("elicitation_type"),
                rs.getString("answer_type"),
                rs.getBoolean("stt_needs_confirmation")),
        reportIds.toArray());
  }

  /**
   * 그 회차들의 관찰을 읽는다. 되풀이 판정은 호출부가 한다 — 몇 회부터 '반복'인지는 정책이지 SQL 이 아니다.
   *
   * @param reportIds 리포트 식별자 목록이며 비면 조회하지 않는다
   * @return 관찰 목록
   */
  public List<ReferralObservationRow> findObservations(List<Long> reportIds) {
    if (reportIds.isEmpty()) {
      return List.of();
    }
    String placeholders = String.join(",", reportIds.stream().map(id -> "?").toList());
    return jdbcTemplate.query(
        "select report_id, observation_code, title from report_diary_session_observations "
            + "where report_id in ("
            + placeholders
            + ") order by report_id desc, display_order asc",
        (rs, rowNum) ->
            new ReferralObservationRow(
                rs.getLong("report_id"), rs.getString("observation_code"), rs.getString("title")),
        reportIds.toArray());
  }

  /**
   * 그 회차들의 안전 신호를 읽는다.
   *
   * @param reportIds 리포트 식별자 목록이며 비면 조회하지 않는다
   * @return 안전 신호 목록
   */
  public List<ReferralSafetySignalRow> findSafetySignals(List<Long> reportIds) {
    if (reportIds.isEmpty()) {
      return List.of();
    }
    String placeholders = String.join(",", reportIds.stream().map(id -> "?").toList());
    return jdbcTemplate.query(
        "select report_id, reason_code, severity, title from report_crisis_alerts "
            + "where report_id in ("
            + placeholders
            + ") order by report_id desc",
        (rs, rowNum) ->
            new ReferralSafetySignalRow(
                rs.getLong("report_id"),
                rs.getString("reason_code"),
                rs.getString("severity"),
                rs.getString("title")),
        reportIds.toArray());
  }

  /**
   * 활동 한 회차의 원자료다.
   *
   * @param reportId 리포트 식별자
   * @param activityType 활동 유형 코드
   * @param activityDate 활동 날짜
   * @param headline 이야기 핵심
   * @param mainEvent 중심 사건
   * @param realityStatus 실제·상상 구분
   * @param timeScope 사건 시점
   * @param confirmedVoiceCount 음성으로 확정된 답변 수
   * @param optionAnswerCount 선택지에서 고른 답변 수
   * @param skippedCount 건너뛴 질문 수
   * @param sttConfirmationCount 음성 인식 확인이 필요한 답변 수
   */
  public record ReferralSessionRow(
      Long reportId,
      String activityType,
      LocalDate activityDate,
      String headline,
      String mainEvent,
      String realityStatus,
      String timeScope,
      int confirmedVoiceCount,
      int optionAnswerCount,
      int skippedCount,
      int sttConfirmationCount) {}

  /**
   * 아이가 한 말 한 줄이다.
   *
   * @param reportId 리포트 식별자
   * @param text 아이가 한 말 그대로
   * @param elicitationType 그 말을 끌어낸 질문 방식
   * @param answerType 답변 입력 방식
   * @param sttNeedsConfirmation 음성 인식 확인 필요 여부
   */
  public record ReferralChildVoiceRow(
      Long reportId,
      String text,
      String elicitationType,
      String answerType,
      boolean sttNeedsConfirmation) {}

  /**
   * 관찰 한 건이다.
   *
   * @param reportId 리포트 식별자
   * @param observationCode 관찰 코드
   * @param title 보호자에게 보이던 제목
   */
  public record ReferralObservationRow(Long reportId, String observationCode, String title) {}

  /**
   * 안전 신호 한 건이다.
   *
   * @param reportId 리포트 식별자
   * @param reasonCode 위기 사유 코드
   * @param severity 심각도
   * @param title 안내 제목
   */
  public record ReferralSafetySignalRow(
      Long reportId, String reasonCode, String severity, String title) {}
}
