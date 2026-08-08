package com.ssafy.b209.referral.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.referral.dto.ReferralSummaryResponse;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralChildVoiceRow;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralObservationRow;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralSessionRow;
import com.ssafy.b209.report.repository.ReportChildViewRepository;
import com.ssafy.b209.screening.dto.response.ScreeningRecordResponse;
import com.ssafy.b209.screening.dto.response.ScreeningRecordResponse.DomainResultResponse;
import com.ssafy.b209.screening.dto.response.ScreeningSummaryResponse;
import com.ssafy.b209.screening.service.ScreeningRecordQueryService;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

/**
 * 의뢰 요약 실물을 한 번 찍어 본다.
 *
 * <p>계약이 지켜지는지는 {@link ReferralSummaryQueryServiceTest} 가 본다. 이 테스트는 <strong>사람이 읽어 보기 위한
 * 것</strong>이다 — 필드 단위로는 다 맞는데 모아 놓으면 읽히지 않는 문서가 되는 일이 흔해서, 실제 조합을 눈으로 확인할 자리를 남긴다.
 *
 * <p>결과는 {@code build/referral-summary-example.json} 에 남는다.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class ReferralSummaryExampleTest {

  @Mock private GuardianResourceAccessRepository guardianAccessRepository;
  @Mock private JdbcReferralSummaryRepository referralRepository;
  @Mock private ReportChildViewRepository childRepository;
  @Mock private ScreeningRecordQueryService screeningRecordQueryService;

  @Test
  @DisplayName("의뢰 요약 실물을 찍어 build 에 남긴다")
  void writesExample() throws Exception {
    when(guardianAccessRepository.hasChildAccess(anyLong(), anyLong())).thenReturn(true);
    when(childRepository.findById(anyLong())).thenReturn(Optional.empty());
    when(screeningRecordQueryService.summarize(anyLong())).thenReturn(screening());
    when(referralRepository.findRecentSessions(anyLong(), anyInt())).thenReturn(sessions());
    when(referralRepository.findChildVoices(anyList())).thenReturn(voices());
    when(referralRepository.findObservations(anyList())).thenReturn(observations());
    when(referralRepository.findSafetySignals(anyList())).thenReturn(List.of());

    ReferralSummaryResponse summary =
        new ReferralSummaryQueryService(
                guardianAccessRepository,
                referralRepository,
                childRepository,
                screeningRecordQueryService,
                Clock.fixed(Instant.parse("2026-08-08T09:00:00Z"), ZoneOffset.UTC))
            .summarize(7L, 42L, null);

    ObjectMapper mapper = new ObjectMapper().registerModule(new JavaTimeModule());
    mapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    String json = mapper.writerWithDefaultPrettyPrinter().writeValueAsString(summary);
    Path output = Path.of("build", "referral-summary-example.json");
    Files.createDirectories(output.getParent());
    Files.writeString(output, json, StandardCharsets.UTF_8);

    assertThat(json).isNotBlank();
    assertThat(summary.sessions()).hasSize(3);
  }

  private static ScreeningSummaryResponse screening() {
    return new ScreeningSummaryResponse(
        "EXTERNAL_RESULT_AVAILABLE",
        "보호자가 직접 입력한 검사 기록이에요. 앱이 확인하거나 채점한 결과가 아니며, 그림일기 관찰과는 별개예요.",
        List.of(
            new ScreeningRecordResponse(
                1L,
                "K_DST",
                "한국 영유아 발달선별검사 K-DST",
                null,
                "GUARDIAN",
                LocalDate.of(2026, 5, 20),
                "GUARDIAN_REPORTED",
                "영유아건강검진",
                false,
                "FOLLOW_UP_RECOMMENDED",
                "심화평가권고",
                "SCREENING_NOT_DIAGNOSIS",
                "공식 검진 기관",
                "공식 발달선별 결과이며 진단은 아닙니다. 결과에 따라 정밀평가가 필요할 수 있습니다.",
                List.of(new DomainResultResponse("언어", "심화평가권고")),
                "SCHEDULE_FURTHER_EVALUATION",
                "공식 선별 결과에 따라 소아청소년과 또는 발달 관련 전문가와 추가 평가를 상의해 보세요.",
                List.of("소아청소년과", "발달클리닉"))));
  }

  private static List<ReferralSessionRow> sessions() {
    return List.of(
        new ReferralSessionRow(
            103L,
            "ART_DIARY",
            LocalDate.of(2026, 8, 6),
            "동생이 내 블록을 무너뜨린 날",
            "동생이 블록탑을 무너뜨림",
            "REAL",
            "TODAY",
            3,
            1,
            0,
            0),
        new ReferralSessionRow(
            102L,
            "ART_DIARY",
            LocalDate.of(2026, 8, 3),
            "혼자 그네를 오래 탄 날",
            "놀이터에서 혼자 그네를 탐",
            "REAL",
            "RECENT",
            1,
            3,
            2,
            1),
        new ReferralSessionRow(
            101L,
            "ART_DIARY",
            LocalDate.of(2026, 7, 30),
            "동생이랑 다투고 방에 들어간 날",
            "동생과 다툼",
            "REAL",
            "PAST",
            2,
            2,
            1,
            0));
  }

  private static List<ReferralChildVoiceRow> voices() {
    return List.of(
        new ReferralChildVoiceRow(
            103L, "동생이 내 블록 무너뜨려서 진짜 화났어", "OPEN_INVITATION", "VOICE_ANSWER", false),
        new ReferralChildVoiceRow(
            103L, "엄마한테 말했는데 동생만 안아줬어", "CUED_INVITATION", "VOICE_ANSWER", false),
        new ReferralChildVoiceRow(103L, "속상해", "MULTIPLE_CHOICE", "OPTION_ANSWER", false),
        new ReferralChildVoiceRow(
            102L, "그냥 혼자 탔어. 햇살초등학교 애들은 저쪽에 있었어", "OPEN_INVITATION", "VOICE_ANSWER", true),
        new ReferralChildVoiceRow(102L, "응", "YES_NO", "OPTION_ANSWER", false),
        new ReferralChildVoiceRow(
            101L, "동생이 먼저 그랬는데 나만 혼났어", "OPEN_INVITATION", "VOICE_ANSWER", false),
        new ReferralChildVoiceRow(101L, "방에 들어가서 문 닫았어", "CUED_INVITATION", "VOICE_ANSWER", false));
  }

  private static List<ReferralObservationRow> observations() {
    return List.of(
        new ReferralObservationRow(103L, "SIBLING_CONFLICT_STORY", "동생과 있었던 일을 자기 말로 이야기했어요"),
        new ReferralObservationRow(101L, "SIBLING_CONFLICT_STORY", "동생과 있었던 일을 자기 말로 이야기했어요"),
        new ReferralObservationRow(103L, "UNFAIRNESS_EXPRESSED", "억울했던 마음을 말로 표현했어요"),
        new ReferralObservationRow(101L, "UNFAIRNESS_EXPRESSED", "억울했던 마음을 말로 표현했어요"),
        new ReferralObservationRow(102L, "SOLO_PLAY_STORY", "혼자 논 이야기를 했어요"));
  }
}
