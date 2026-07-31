package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.dto.response.EmotionCalendarDayResponse;
import com.ssafy.b209.drawing.dto.response.EmotionCalendarResponse;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.EmotionCalendarRowProjection;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class EmotionCalendarQueryServiceTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long CHILD_ID = 3L;
  private static final YearMonth JULY_2026 = YearMonth.of(2026, 7);

  /** KST 2026-07-01 00:00은 UTC 2026-06-30 15:00이다. */
  private static final LocalDateTime UTC_MONTH_START = LocalDateTime.of(2026, 6, 30, 15, 0);

  /** KST 2026-08-01 00:00은 UTC 2026-07-31 15:00이다. */
  private static final LocalDateTime UTC_MONTH_END_EXCLUSIVE = LocalDateTime.of(2026, 7, 31, 15, 0);

  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private EmotionCalendarQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new EmotionCalendarQueryService(
            drawingSessionRepository, currentUserResolver, accessValidator);
  }

  @Test
  void readsTheKoreanMonthRangeConvertedToStoredUtcBounds() {
    authenticate();
    givenRows(List.of());

    service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    verify(drawingSessionRepository)
        .findEmotionCalendarRows(CHILD_ID, UTC_MONTH_START, UTC_MONTH_END_EXCLUSIVE);
  }

  @Test
  void placesAnActivityJustAfterKoreanMidnightOnTheFirstDayOfTheMonth() {
    authenticate();
    // KST 2026-07-01 00:30 = UTC 2026-06-30 15:30. UTC 경계로 묶으면 6월 30일로 새는 값이다.
    givenRows(List.of(row(1L, LocalDateTime.of(2026, 6, 30, 15, 30), "HAPPY", 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.days())
        .extracting(EmotionCalendarDayResponse::date)
        .containsExactly(LocalDate.of(2026, 7, 1));
  }

  @Test
  void keepsAnActivityLateOnTheLastKoreanDayInTheSameMonth() {
    authenticate();
    // KST 2026-07-31 23:30 = UTC 2026-07-31 14:30.
    givenRows(List.of(row(1L, LocalDateTime.of(2026, 7, 31, 14, 30), "CALM", 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.days())
        .extracting(EmotionCalendarDayResponse::date)
        .containsExactly(LocalDate.of(2026, 7, 31));
    assertThat(response.summary().activityCount()).isEqualTo(1);
  }

  @Test
  void doesNotInflateActivityCountWhenAnActivityHasSeveralEmotions() {
    authenticate();
    LocalDateTime startedAt = LocalDateTime.of(2026, 7, 3, 1, 0);
    givenRows(
        List.of(
            row(1L, startedAt, "HAPPY", 1),
            row(1L, startedAt, "CALM", 1),
            row(1L, startedAt, "SAD", 1)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.days()).hasSize(1);
    assertThat(response.days().get(0).activityCount()).isEqualTo(1);
    assertThat(response.days().get(0).completedReportCount()).isEqualTo(1);
    assertThat(response.summary().activityCount()).isEqualTo(1);
    assertThat(response.summary().completedReportCount()).isEqualTo(1);
  }

  @Test
  void usesTheFirstEmotionOfTheLatestActivityAsTheRepresentativeEmotion() {
    authenticate();
    LocalDateTime earlier = LocalDateTime.of(2026, 7, 3, 1, 0);
    LocalDateTime later = LocalDateTime.of(2026, 7, 3, 5, 0);
    givenRows(
        List.of(
            row(1L, earlier, "SAD", 0),
            row(1L, earlier, "ANGRY", 0),
            row(2L, later, "HAPPY", 0),
            row(2L, later, "CALM", 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    EmotionCalendarDayResponse day = response.days().get(0);
    assertThat(day.representativeEmotion()).isEqualTo(DrawingEmotionCode.HAPPY);
    assertThat(day.activityCount()).isEqualTo(2);
    assertThat(day.emotions())
        .containsExactly(
            DrawingEmotionCode.SAD,
            DrawingEmotionCode.ANGRY,
            DrawingEmotionCode.HAPPY,
            DrawingEmotionCode.CALM);
  }

  @Test
  void returnsNoRepresentativeEmotionWhenTheLatestActivityRecordedNone() {
    authenticate();
    givenRows(
        List.of(
            row(1L, LocalDateTime.of(2026, 7, 3, 1, 0), "SAD", 0),
            row(2L, LocalDateTime.of(2026, 7, 3, 5, 0), null, 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    EmotionCalendarDayResponse day = response.days().get(0);
    assertThat(day.representativeEmotion()).isNull();
    assertThat(day.activityCount()).isEqualTo(2);
    assertThat(day.emotions()).containsExactly(DrawingEmotionCode.SAD);
  }

  @Test
  void removesDuplicateEmotionsWithinADay() {
    authenticate();
    givenRows(
        List.of(
            row(1L, LocalDateTime.of(2026, 7, 3, 1, 0), "HAPPY", 0),
            row(2L, LocalDateTime.of(2026, 7, 3, 5, 0), "HAPPY", 0),
            row(2L, LocalDateTime.of(2026, 7, 3, 5, 0), "CALM", 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.days().get(0).emotions())
        .containsExactly(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM);
  }

  @Test
  void skipsDaysWithoutActivityAndOrdersDaysAscending() {
    authenticate();
    givenRows(
        List.of(
            row(1L, LocalDateTime.of(2026, 7, 2, 1, 0), "HAPPY", 0),
            row(2L, LocalDateTime.of(2026, 7, 9, 1, 0), "CALM", 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.days())
        .extracting(EmotionCalendarDayResponse::date)
        .containsExactly(LocalDate.of(2026, 7, 2), LocalDate.of(2026, 7, 9));
  }

  @Test
  void picksTheMostSelectedEmotionOfTheMonthAsTopEmotion() {
    authenticate();
    givenRows(
        List.of(
            row(1L, LocalDateTime.of(2026, 7, 2, 1, 0), "SAD", 0),
            row(2L, LocalDateTime.of(2026, 7, 3, 1, 0), "HAPPY", 0),
            row(3L, LocalDateTime.of(2026, 7, 4, 1, 0), "HAPPY", 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.summary().topEmotion()).isEqualTo(DrawingEmotionCode.HAPPY);
  }

  @Test
  void breaksTopEmotionTiesByEmotionCodeName() {
    authenticate();
    givenRows(
        List.of(
            row(1L, LocalDateTime.of(2026, 7, 2, 1, 0), "SCARED", 0),
            row(2L, LocalDateTime.of(2026, 7, 3, 1, 0), "CALM", 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.summary().topEmotion()).isEqualTo(DrawingEmotionCode.CALM);
  }

  @Test
  void countsUnknownAsASelectedEmotion() {
    authenticate();
    givenRows(
        List.of(
            row(1L, LocalDateTime.of(2026, 7, 2, 1, 0), "UNKNOWN", 0),
            row(2L, LocalDateTime.of(2026, 7, 3, 1, 0), "UNKNOWN", 0),
            row(3L, LocalDateTime.of(2026, 7, 4, 1, 0), "HAPPY", 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.days().get(0).representativeEmotion())
        .isEqualTo(DrawingEmotionCode.UNKNOWN);
    assertThat(response.days().get(0).emotions()).containsExactly(DrawingEmotionCode.UNKNOWN);
    assertThat(response.summary().topEmotion()).isEqualTo(DrawingEmotionCode.UNKNOWN);
  }

  @Test
  void sumsCompletedReportCountOncePerActivity() {
    authenticate();
    givenRows(
        List.of(
            row(1L, LocalDateTime.of(2026, 7, 2, 1, 0), "HAPPY", 2),
            row(1L, LocalDateTime.of(2026, 7, 2, 1, 0), "CALM", 2),
            row(2L, LocalDateTime.of(2026, 7, 5, 1, 0), null, 0)));

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.days().get(0).completedReportCount()).isEqualTo(2);
    assertThat(response.days().get(1).completedReportCount()).isZero();
    assertThat(response.summary().completedReportCount()).isEqualTo(2);
  }

  @Test
  void returnsAnEmptyCalendarWhenTheMonthHasNoActivity() {
    authenticate();
    givenRows(List.of());

    EmotionCalendarResponse response = service.getMonthlyCalendar(CHILD_ID, JULY_2026);

    assertThat(response.year()).isEqualTo(2026);
    assertThat(response.month()).isEqualTo(7);
    assertThat(response.days()).isEmpty();
    assertThat(response.summary().activityCount()).isZero();
    assertThat(response.summary().completedReportCount()).isZero();
    assertThat(response.summary().topEmotion()).isNull();
  }

  @Test
  void doesNotReadActivitiesWhenTheGuardianIsNotConnectedToTheChild() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(new BusinessException(ChildErrorCode.CHILD_NOT_FOUND))
        .given(accessValidator)
        .requireChildAccess(GUARDIAN_USER_ID, CHILD_ID);

    assertThatThrownBy(() -> service.getMonthlyCalendar(CHILD_ID, JULY_2026))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(drawingSessionRepository);
  }

  private void authenticate() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
  }

  private void givenRows(List<EmotionCalendarRowProjection> rows) {
    given(
            drawingSessionRepository.findEmotionCalendarRows(
                any(), any(LocalDateTime.class), any(LocalDateTime.class)))
        .willReturn(rows);
  }

  private EmotionCalendarRowProjection row(
      Long sessionId, LocalDateTime startedAt, String emotionCode, long completedReportCount) {
    return new Row(sessionId, startedAt, emotionCode, completedReportCount);
  }

  /** 조회 결과 한 행을 그대로 재현하는 Projection 구현이다. */
  private record Row(
      Long sessionId, LocalDateTime startedAt, String emotionCode, long completedReportCount)
      implements EmotionCalendarRowProjection {

    @Override
    public Long getDrawingSessionId() {
      return sessionId;
    }

    @Override
    public LocalDateTime getStartedAt() {
      return startedAt;
    }

    @Override
    public String getEmotionCode() {
      return emotionCode;
    }

    @Override
    public long getCompletedReportCount() {
      return completedReportCount;
    }
  }
}
