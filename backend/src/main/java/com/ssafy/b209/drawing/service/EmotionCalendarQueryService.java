package com.ssafy.b209.drawing.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.dto.response.EmotionCalendarDayResponse;
import com.ssafy.b209.drawing.dto.response.EmotionCalendarResponse;
import com.ssafy.b209.drawing.dto.response.EmotionCalendarSummaryResponse;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.EmotionCalendarRowProjection;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 연결 보호자가 아동의 월간 감정 달력을 조회하는 읽기 전용 서비스다.
 *
 * <p>활동과 아동 선택 감정을 한 Query로 읽어 서비스에서 일자별·월별로 집계한다. 세션 하나에 감정이 여러 건이면 조회 결과가 감정 수만큼 늘어나므로 세션 식별자로 먼저
 * 모은 뒤 집계해 활동 수와 리포트 수가 부풀지 않게 한다.
 *
 * <p>일자와 월 경계는 {@link #CALENDAR_ZONE}으로 해석한다. 활동 시작 시각은 UTC 기준 벽시계 값으로 저장되므로 조회 범위는 달력 기준 월 경계를
 * UTC로 변환해 전달하고, 응답 일자는 저장 값을 다시 달력 기준 시간대로 환산해 계산한다. 활동 기록 목록 조회가 UTC 경계로 날짜를 해석하는 것과 달리 달력은 사용자가
 * 보는 날짜와 칸이 어긋나지 않아야 하므로 기준을 다르게 둔다.
 *
 * <p>아동이 직접 선택한 감정만 집계하며 AI 추정 감정과 위험도, 전문가 전용 정보는 조회 대상에서 제외한다.
 */
@Service
@Transactional(readOnly = true)
public class EmotionCalendarQueryService {

  /** 달력의 일자와 월 경계를 해석하는 기준 시간대다. */
  private static final ZoneId CALENDAR_ZONE = ZoneId.of("Asia/Seoul");

  private final DrawingSessionRepository drawingSessionRepository;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;

  /**
   * 감정 달력 집계에 사용할 저장소와 인증·권한 경계를 구성한다.
   *
   * @param drawingSessionRepository 활동과 선택 감정을 함께 조회하는 저장소
   * @param currentUserResolver Access Token에서 현재 보호자 ID를 제공하는 Resolver
   * @param accessValidator 보호자와 아동의 연결 관계를 검증하는 Validator
   */
  public EmotionCalendarQueryService(
      DrawingSessionRepository drawingSessionRepository,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
  }

  /**
   * 연결 보호자 권한을 검증하고 아동의 한 달 감정 달력을 집계한다.
   *
   * <p>조회 과정에서 상태를 변경하거나 외부 시스템을 호출하지 않으며, 해당 달에 활동이 없으면 빈 일자 목록과 값이 비어 있는 요약을 반환한다.
   *
   * @param childId 조회 대상 아동 식별자
   * @param month 조회할 연·월
   * @return 활동이 있는 날의 감정 요약과 한 달 요약
   */
  public EmotionCalendarResponse getMonthlyCalendar(Long childId, YearMonth month) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireChildAccess(guardianUserId, childId);

    LocalDateTime fromInclusive = toStoredWallClock(month.atDay(1).atStartOfDay(CALENDAR_ZONE));
    LocalDateTime toExclusive =
        toStoredWallClock(month.plusMonths(1).atDay(1).atStartOfDay(CALENDAR_ZONE));

    List<EmotionCalendarRowProjection> rows =
        drawingSessionRepository.findEmotionCalendarRows(childId, fromInclusive, toExclusive);

    Map<Long, SessionAggregate> sessions = groupBySession(rows);
    Map<LocalDate, DayAggregate> days = groupByCalendarDate(sessions.values());

    return new EmotionCalendarResponse(
        month.getYear(), month.getMonthValue(), toDayResponses(days), toSummary(sessions.values()));
  }

  /**
   * 감정 수만큼 늘어난 조회 행을 세션 단위로 모아 조인으로 생긴 중복을 제거한다.
   *
   * <p>반환 순서는 조회 정렬과 같은 시작 시각 오름차순이며, 세션 안의 감정은 아동이 선택한 순서를 유지한다.
   */
  private Map<Long, SessionAggregate> groupBySession(List<EmotionCalendarRowProjection> rows) {
    Map<Long, SessionAggregate> sessions = new LinkedHashMap<>();
    for (EmotionCalendarRowProjection row : rows) {
      SessionAggregate session =
          sessions.computeIfAbsent(
              row.getDrawingSessionId(),
              key -> new SessionAggregate(row.getStartedAt(), row.getCompletedReportCount()));
      String emotionCode = row.getEmotionCode();
      if (emotionCode != null) {
        session.emotions.add(DrawingEmotionCode.valueOf(emotionCode));
      }
    }
    return sessions;
  }

  /** 세션 집계를 달력 기준 일자로 모으며, 대표 감정은 그날 마지막 활동의 첫 선택 감정으로 정한다. */
  private Map<LocalDate, DayAggregate> groupByCalendarDate(Iterable<SessionAggregate> sessions) {
    Map<LocalDate, DayAggregate> days = new TreeMap<>();
    for (SessionAggregate session : sessions) {
      DayAggregate day =
          days.computeIfAbsent(toCalendarDate(session.startedAt), key -> new DayAggregate());
      day.activityCount++;
      day.completedReportCount += session.completedReportCount;
      day.emotions.addAll(session.emotions);
      // 세션은 시작 시각 오름차순으로 처리되므로 마지막으로 덮어쓴 값이 그날 가장 늦은 활동의 대표 감정이 된다.
      day.representativeEmotion =
          session.emotions.isEmpty() ? null : session.emotions.iterator().next();
    }
    return days;
  }

  private List<EmotionCalendarDayResponse> toDayResponses(Map<LocalDate, DayAggregate> days) {
    List<EmotionCalendarDayResponse> responses = new ArrayList<>(days.size());
    for (Map.Entry<LocalDate, DayAggregate> entry : days.entrySet()) {
      DayAggregate day = entry.getValue();
      responses.add(
          new EmotionCalendarDayResponse(
              entry.getKey(),
              day.representativeEmotion,
              List.copyOf(day.emotions),
              day.activityCount,
              day.completedReportCount));
    }
    return responses;
  }

  private EmotionCalendarSummaryResponse toSummary(Iterable<SessionAggregate> sessions) {
    Map<DrawingEmotionCode, Long> emotionCounts = new EnumMap<>(DrawingEmotionCode.class);
    long activityCount = 0;
    long completedReportCount = 0;
    for (SessionAggregate session : sessions) {
      activityCount++;
      completedReportCount += session.completedReportCount;
      for (DrawingEmotionCode emotion : session.emotions) {
        emotionCounts.merge(emotion, 1L, Long::sum);
      }
    }
    return new EmotionCalendarSummaryResponse(
        activityCount, topEmotion(emotionCounts), completedReportCount);
  }

  /** 선택 수가 가장 많은 감정을 고르고, 수가 같으면 감정 코드 이름의 사전순으로 앞서는 값을 선택해 결과를 결정적으로 만든다. */
  private DrawingEmotionCode topEmotion(Map<DrawingEmotionCode, Long> emotionCounts) {
    return emotionCounts.entrySet().stream()
        .sorted(
            Comparator.comparingLong(
                    (Map.Entry<DrawingEmotionCode, Long> entry) -> entry.getValue())
                .reversed()
                .thenComparing(entry -> entry.getKey().name()))
        .map(Map.Entry::getKey)
        .findFirst()
        .orElse(null);
  }

  /** 달력 기준 시간대의 경계 시각을 저장 형식인 UTC 기준 벽시계 값으로 변환한다. */
  private LocalDateTime toStoredWallClock(ZonedDateTime calendarBoundary) {
    return LocalDateTime.ofInstant(calendarBoundary.toInstant(), ZoneOffset.UTC);
  }

  /** UTC 기준으로 저장된 활동 시작 시각을 달력 기준 시간대의 일자로 환산한다. */
  private LocalDate toCalendarDate(LocalDateTime storedStartedAt) {
    return storedStartedAt.toInstant(ZoneOffset.UTC).atZone(CALENDAR_ZONE).toLocalDate();
  }

  /** 조인으로 늘어난 행을 세션 단위로 되돌린 중간 집계다. */
  private static final class SessionAggregate {

    private final LocalDateTime startedAt;
    private final long completedReportCount;
    private final Set<DrawingEmotionCode> emotions = new LinkedHashSet<>();

    private SessionAggregate(LocalDateTime startedAt, long completedReportCount) {
      this.startedAt = startedAt;
      this.completedReportCount = completedReportCount;
    }
  }

  /** 달력 하루 칸에 필요한 값을 누적하는 중간 집계다. */
  private static final class DayAggregate {

    private final Set<DrawingEmotionCode> emotions = new LinkedHashSet<>();
    private DrawingEmotionCode representativeEmotion;
    private long activityCount;
    private long completedReportCount;
  }
}
