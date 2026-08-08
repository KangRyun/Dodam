package com.ssafy.b209.referral.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.referral.dto.ReferralSummaryResponse;
import com.ssafy.b209.referral.exception.ReferralSummaryErrorCode;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralChildVoiceRow;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralObservationRow;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralSafetySignalRow;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralSessionRow;
import com.ssafy.b209.report.repository.ReportChildViewRepository;
import com.ssafy.b209.screening.dto.response.ScreeningSummaryResponse;
import com.ssafy.b209.screening.service.ScreeningRecordQueryService;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

/**
 * 의뢰 요약이 지켜야 하는 것을 고정한다.
 *
 * <p>이 문서는 <strong>가정 밖으로 나간다.</strong> 그래서 막는 실패가 다르다 — 한 번을 반복으로 부르는 것, 고른 답을 아이가 한 말로 세는 것, 앱의
 * 해석을 소견처럼 싣는 것, 그리고 진료에 필요 없는 신원 정보가 따라 나가는 것.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class ReferralSummaryQueryServiceTest {

  private static final Long GUARDIAN_ID = 7L;
  private static final Long CHILD_ID = 42L;

  @Mock private GuardianResourceAccessRepository guardianAccessRepository;
  @Mock private JdbcReferralSummaryRepository referralRepository;
  @Mock private ReportChildViewRepository childRepository;
  @Mock private ScreeningRecordQueryService screeningRecordQueryService;

  private ReferralSummaryQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new ReferralSummaryQueryService(
            guardianAccessRepository,
            referralRepository,
            childRepository,
            screeningRecordQueryService,
            Clock.fixed(Instant.parse("2026-08-08T09:00:00Z"), ZoneOffset.UTC));
    when(guardianAccessRepository.hasChildAccess(GUARDIAN_ID, CHILD_ID)).thenReturn(true);
    when(childRepository.findById(anyLong())).thenReturn(Optional.empty());
    when(screeningRecordQueryService.summarize(anyLong()))
        .thenReturn(
            new ScreeningSummaryResponse("NOT_OFFERED", "이 앱은 표준화 선별검사를 제공하지 않아요.", List.of()));
    when(referralRepository.findRecentSessions(anyLong(), anyInt())).thenReturn(sessions());
    when(referralRepository.findChildVoices(anyList())).thenReturn(voices());
    when(referralRepository.findObservations(anyList())).thenReturn(observations());
    when(referralRepository.findSafetySignals(anyList())).thenReturn(List.of());
  }

  @Test
  @DisplayName("두 회차 이상 되풀이된 것만 반복이라고 부른다")
  void onlyMultiSessionObservationsCountAsRepeated() {
    // 한 번뿐인 관찰을 반복으로 부르면 한 번의 활동이 그 자리에서 아이의 성향이 된다.
    ReferralSummaryResponse summary = service.summarize(GUARDIAN_ID, CHILD_ID, null);

    assertThat(summary.repeatedObservations()).hasSize(1);
    assertThat(summary.repeatedObservations().getFirst().observationCode())
        .isEqualTo("SHARES_ACHIEVEMENT");
    assertThat(summary.repeatedObservations().getFirst().occurrenceCount()).isEqualTo(2);
    assertThat(summary.repeatedObservations())
        .as("한 회차에만 나온 관찰은 반복이 아니다")
        .noneMatch(item -> item.observationCode().equals("QUIET_START"));
  }

  @Test
  @DisplayName("고른 답을 아이가 자기 말로 한 것으로 세지 않는다")
  void chosenAnswersAreNotSpontaneous() {
    ReferralSummaryResponse summary = service.summarize(GUARDIAN_ID, CHILD_ID, null);

    List<ReferralSummaryResponse.ChildVoiceResponse> voices =
        summary.sessions().getFirst().childVoices();
    assertThat(voices)
        .filteredOn(voice -> voice.elicitationType().equals("MULTIPLE_CHOICE"))
        .allMatch(voice -> !voice.spontaneous());
    assertThat(voices)
        .filteredOn(voice -> voice.elicitationType().equals("OPEN_INVITATION"))
        .allMatch(ReferralSummaryResponse.ChildVoiceResponse::spontaneous);
  }

  @Test
  @DisplayName("학교 이름과 아파트 동호수는 가려서 내보낸다")
  void redactsSchoolAndAddress() {
    // 앱 안에서 보호자만 보던 발화가 병원으로 옮겨 간다. 진료에 필요 없는 것은 빼고 보낸다.
    ReferralSummaryResponse summary = service.summarize(GUARDIAN_ID, CHILD_ID, null);

    String joined =
        summary.sessions().stream()
            .flatMap(session -> session.childVoices().stream())
            .map(ReferralSummaryResponse.ChildVoiceResponse::text)
            .reduce("", (left, right) -> left + " " + right);
    assertThat(joined).doesNotContain("햇살초등학교").doesNotContain("101동 902호");
    assertThat(joined).contains("○○초등학교").contains("○○동 ○○호");
    // 사람 이름은 가리지 않는다 — 친구인지 동생인지 코드로는 알 수 없다.
    assertThat(joined).contains("민준이");
  }

  @Test
  @DisplayName("무엇을 담지 않았는지 함께 알려 준다")
  void statesWhatIsExcluded() {
    // 빠진 것을 모르면 전문가는 없는 것을 '문제 없음'으로 읽는다.
    ReferralSummaryResponse summary = service.summarize(GUARDIAN_ID, CHILD_ID, null);

    assertThat(summary.notIncluded()).isNotEmpty();
    assertThat(String.join(" ", summary.notIncluded()))
        .contains("가설")
        .contains("색·크기")
        .contains("검사 문항")
        .contains("음성 재생 링크");
    assertThat(summary.reviewNotice()).contains("친구 이름");
  }

  @Test
  @DisplayName("진단이나 소견이 아니라고 문서가 스스로 말한다")
  void purposeSaysItIsNotADiagnosis() {
    ReferralSummaryResponse summary = service.summarize(GUARDIAN_ID, CHILD_ID, null);

    assertThat(summary.purpose()).contains("진단이나 소견이 아니며");
  }

  @Test
  @DisplayName("회차 수는 범위 안으로 맞춘다")
  void limitIsClamped() {
    service.summarize(GUARDIAN_ID, CHILD_ID, 999);
    service.summarize(GUARDIAN_ID, CHILD_ID, 0);
    // 길면 아무도 끝까지 읽지 않는다.
    org.mockito.Mockito.verify(referralRepository)
        .findRecentSessions(CHILD_ID, ReferralSummaryQueryService.MAX_SESSION_LIMIT);
    org.mockito.Mockito.verify(referralRepository).findRecentSessions(CHILD_ID, 1);
  }

  @Test
  @DisplayName("연결되지 않은 보호자는 볼 수 없다")
  void rejectsUnrelatedGuardian() {
    when(guardianAccessRepository.hasChildAccess(anyLong(), anyLong())).thenReturn(false);

    assertThatThrownBy(() -> service.summarize(GUARDIAN_ID, CHILD_ID, null))
        .isInstanceOf(BusinessException.class)
        .hasMessage(ReferralSummaryErrorCode.REFERRAL_ACCESS_DENIED.getMessage());
  }

  @Test
  @DisplayName("안전 신호에는 앱이 무엇을 했는지 함께 적는다")
  void safetySignalCarriesHandling() {
    when(referralRepository.findSafetySignals(anyList()))
        .thenReturn(
            List.of(
                new ReferralSafetySignalRow(101L, "SELF_HARM_RISK", "HIGH", "지금 바로 도움을 받을 수 있어요")));

    ReferralSummaryResponse summary = service.summarize(GUARDIAN_ID, CHILD_ID, null);

    // 처리 내역이 없으면 전문가는 방치됐는지 알 수 없다.
    assertThat(summary.safetySignals()).hasSize(1);
    assertThat(summary.safetySignals().getFirst().handling()).contains("앱이 보호자에게 안내를 보여 주었어요");
    assertThat(summary.safetySignals().getFirst().occurredOn()).isEqualTo(LocalDate.of(2026, 8, 6));
  }

  private static List<ReferralSessionRow> sessions() {
    return List.of(
        new ReferralSessionRow(
            101L,
            "ART_DIARY",
            LocalDate.of(2026, 8, 6),
            "수학시험에서 100점을 받은 날",
            "수학시험에서 100점을 받음",
            "REAL",
            "TODAY",
            2,
            1,
            0,
            0),
        new ReferralSessionRow(
            100L,
            "ART_DIARY",
            LocalDate.of(2026, 8, 2),
            "친구랑 그네를 탄 날",
            "놀이터에서 그네를 탐",
            "REAL",
            "RECENT",
            1,
            2,
            1,
            1));
  }

  private static List<ReferralChildVoiceRow> voices() {
    return List.of(
        new ReferralChildVoiceRow(
            101L, "기분이 좋아서 엄마한테 자랑했어", "OPEN_INVITATION", "VOICE_ANSWER", false),
        new ReferralChildVoiceRow(101L, "기뻐", "MULTIPLE_CHOICE", "OPTION_ANSWER", false),
        new ReferralChildVoiceRow(
            100L, "햇살초등학교 앞 놀이터에서 민준이랑 놀았어", "OPEN_INVITATION", "VOICE_ANSWER", false),
        new ReferralChildVoiceRow(
            100L, "우리집 101동 902호로 같이 갔어", "CUED_INVITATION", "VOICE_ANSWER", true));
  }

  private static List<ReferralObservationRow> observations() {
    return List.of(
        new ReferralObservationRow(101L, "SHARES_ACHIEVEMENT", "성취한 경험을 먼저 이야기했어요"),
        new ReferralObservationRow(100L, "SHARES_ACHIEVEMENT", "성취한 경험을 먼저 이야기했어요"),
        new ReferralObservationRow(101L, "QUIET_START", "이야기를 천천히 시작했어요"));
  }
}
