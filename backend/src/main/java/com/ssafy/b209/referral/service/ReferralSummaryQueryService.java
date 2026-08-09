package com.ssafy.b209.referral.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.referral.ReferralTextRedactor;
import com.ssafy.b209.referral.dto.ReferralSummaryResponse;
import com.ssafy.b209.referral.dto.ReferralSummaryResponse.AnswerCompositionResponse;
import com.ssafy.b209.referral.dto.ReferralSummaryResponse.ChildVoiceResponse;
import com.ssafy.b209.referral.dto.ReferralSummaryResponse.ReferralSessionResponse;
import com.ssafy.b209.referral.dto.ReferralSummaryResponse.RepeatedObservationResponse;
import com.ssafy.b209.referral.dto.ReferralSummaryResponse.SafetySignalResponse;
import com.ssafy.b209.referral.exception.ReferralSummaryErrorCode;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralChildVoiceRow;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralObservationRow;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralSafetySignalRow;
import com.ssafy.b209.referral.repository.JdbcReferralSummaryRepository.ReferralSessionRow;
import com.ssafy.b209.report.domain.ReportChildView;
import com.ssafy.b209.report.repository.ReportChildViewRepository;
import com.ssafy.b209.screening.service.ScreeningRecordQueryService;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 전문가에게 전달할 의뢰 요약을 만든다.
 *
 * <p><strong>전부 결정론적으로 조립한다.</strong> LLM 은 이 문서를 만들지 않는다 — 맡기면 없는 진단명과 색·크기 상징이 곧바로 섞이고, 그것이 병원으로
 * 나간다.
 *
 * <p>담는 것과 담지 않는 것을 코드가 정한다.
 *
 * <ul>
 *   <li>담는다 — 최근 회차의 핵심 사건, 아이가 실제로 한 말과 <strong>그 말을 끌어낸 질문 방식</strong>, 두 회차 이상 되풀이된 관찰, 안전 신호와
 *       처리 내역, 보호자가 기록해 둔 검사 결과, 답변 구성
 *   <li>담지 않는다 — 앱의 가설·경향 해석, 색·크기 기반 상징, 라이선스 검사 문항, 음성 재생 링크, 아이 실명·생년월일
 * </ul>
 *
 * <p>해석을 앞세우지 않는 이유가 있다. 전문가가 먼저 읽는 것이 앱의 가설이면 판단이 그 방향으로 끌려간다 — 그래서 아이가 한 말이 맨 앞이고, 앱이 본 것은 '두 번
 * 이상 되풀이된 것'만 뒤에 붙는다.
 */
@Service
public class ReferralSummaryQueryService {

  /** 최근 회차 기본 개수다. 3~5회가 임상적으로 의미 있는 최소 관찰 구간이다. */
  public static final int DEFAULT_SESSION_LIMIT = 5;

  /** 가져올 수 있는 최대 회차다. 많을수록 좋은 문서가 아니다 — 길면 아무도 끝까지 읽지 않는다. */
  public static final int MAX_SESSION_LIMIT = 10;

  /** '반복'이라고 부를 수 있는 최소 회차다. <strong>한 번은 반복이 아니다.</strong> */
  private static final int REPEAT_THRESHOLD = 2;

  /** 아이가 자기 말로 만든 문장으로 세는 질문 방식이다. 고른 답·예아니오는 여기 없다. */
  private static final Set<String> SPONTANEOUS =
      Set.of("OPEN_INVITATION", "CUED_INVITATION", "CORRECTION");

  private static final String PURPOSE =
      "아이가 그림 활동에서 실제로 한 말과 앱이 관찰한 기록을 모은 자료입니다. " + "진단이나 소견이 아니며, 판단은 전문가가 합니다.";

  private static final String REVIEW_NOTICE =
      "공유하기 전에 아이 말 속에 친구 이름처럼 알릴 필요 없는 정보가 있는지 확인해 주세요. "
          + "학교·유치원 이름과 아파트 동호수는 자동으로 가려 두었지만, 사람 이름은 가리지 않았어요.";

  private static final List<String> NOT_INCLUDED =
      List.of(
          "앱이 세운 가설과 경향 해석 — 이번 활동에서 확인된 사실만 담았어요.",
          "색·크기·위치로 마음을 읽는 해석 — 근거가 없어 담지 않아요.",
          "표준화 검사 문항과 점수 — 앱은 검사를 실시하거나 채점하지 않아요.",
          "아이 음성 재생 링크 — 원본은 앱 안에서만 들을 수 있어요.",
          "아이 실명·생년월일·주소 — 표시명만 담아요.",
          "보호자가 직접 적은 우려 — 아직 앱에 그 자리가 없어요. 상담에서 말씀해 주세요.");

  private final GuardianResourceAccessRepository guardianAccessRepository;
  private final JdbcReferralSummaryRepository referralRepository;
  private final ReportChildViewRepository childRepository;
  private final ScreeningRecordQueryService screeningRecordQueryService;
  private final Clock clock;

  /**
   * 의뢰 요약 조회 서비스를 구성한다.
   *
   * @param guardianAccessRepository 보호자-아동 접근 확인 경계
   * @param referralRepository 의뢰 요약 원자료 조회 경계
   * @param childRepository 표시명 조회 경계이며 별명만 읽는다
   * @param screeningRecordQueryService 보호자가 기록해 둔 검사 결과 조회 경계
   * @param clock 생성 시각을 제공하는 시계
   */
  public ReferralSummaryQueryService(
      GuardianResourceAccessRepository guardianAccessRepository,
      JdbcReferralSummaryRepository referralRepository,
      ReportChildViewRepository childRepository,
      ScreeningRecordQueryService screeningRecordQueryService,
      Clock clock) {
    this.guardianAccessRepository = guardianAccessRepository;
    this.referralRepository = referralRepository;
    this.childRepository = childRepository;
    this.screeningRecordQueryService = screeningRecordQueryService;
    this.clock = clock;
  }

  /**
   * 아이의 의뢰 요약을 만든다.
   *
   * @param guardianUserId 인증된 보호자 사용자 식별자
   * @param childId 아동 식별자
   * @param requestedLimit 가져올 회차 수이며 {@code null}이면 기본값
   * @return 의뢰 요약
   */
  @Transactional(readOnly = true)
  public ReferralSummaryResponse summarize(
      Long guardianUserId, Long childId, Integer requestedLimit) {
    if (!guardianAccessRepository.hasChildAccess(guardianUserId, childId)) {
      throw new BusinessException(ReferralSummaryErrorCode.REFERRAL_ACCESS_DENIED);
    }
    int limit = normalizeLimit(requestedLimit);
    List<ReferralSessionRow> sessionRows = referralRepository.findRecentSessions(childId, limit);
    List<Long> reportIds = sessionRows.stream().map(ReferralSessionRow::reportId).toList();
    Map<Long, LocalDate> dateByReport = new LinkedHashMap<>();
    sessionRows.forEach(row -> dateByReport.put(row.reportId(), row.activityDate()));

    Map<Long, List<ChildVoiceResponse>> voices = groupVoices(reportIds);
    return new ReferralSummaryResponse(
        childRepository.findById(childId).map(ReportChildView::displayName).orElse(null),
        LocalDateTime.now(clock),
        PURPOSE,
        sessionRows.stream()
            .map(
                row ->
                    new ReferralSessionResponse(
                        row.reportId(),
                        row.activityType(),
                        row.activityDate(),
                        row.headline(),
                        row.mainEvent(),
                        row.realityStatus(),
                        row.timeScope(),
                        voices.getOrDefault(row.reportId(), List.of())))
            .toList(),
        buildRepeatedObservations(reportIds, dateByReport),
        buildSafetySignals(reportIds, dateByReport),
        screeningRecordQueryService.summarize(childId),
        buildAnswerComposition(sessionRows),
        sessionRows.stream().anyMatch(row -> row.confirmedVoiceCount() > 0),
        NOT_INCLUDED,
        REVIEW_NOTICE);
  }

  private static int normalizeLimit(Integer requestedLimit) {
    if (requestedLimit == null) {
      return DEFAULT_SESSION_LIMIT;
    }
    return Math.clamp(requestedLimit, 1, MAX_SESSION_LIMIT);
  }

  private Map<Long, List<ChildVoiceResponse>> groupVoices(List<Long> reportIds) {
    Map<Long, List<ChildVoiceResponse>> grouped = new LinkedHashMap<>();
    for (ReferralChildVoiceRow row : referralRepository.findChildVoices(reportIds)) {
      grouped
          .computeIfAbsent(row.reportId(), key -> new ArrayList<>())
          .add(
              new ChildVoiceResponse(
                  // 가정 밖으로 나가는 문서라 학교·주소 형태를 가린다.
                  ReferralTextRedactor.redact(row.text()),
                  row.elicitationType(),
                  SPONTANEOUS.contains(row.elicitationType()),
                  row.sttNeedsConfirmation()));
    }
    return grouped;
  }

  /**
   * 두 회차 이상에서 되풀이된 관찰만 남긴다.
   *
   * <p>한 번뿐인 관찰을 '반복'으로 부르면 한 번의 활동이 그 자리에서 아이의 성향이 된다. 전문가가 여러 날짜의 반복을 볼 수 있게 하는 것이 이 자리의 목적이지, 앱의
   * 관찰을 늘어놓는 자리가 아니다.
   */
  private List<RepeatedObservationResponse> buildRepeatedObservations(
      List<Long> reportIds, Map<Long, LocalDate> dateByReport) {
    Map<String, List<ReferralObservationRow>> byCode = new LinkedHashMap<>();
    for (ReferralObservationRow row : referralRepository.findObservations(reportIds)) {
      byCode.computeIfAbsent(row.observationCode(), key -> new ArrayList<>()).add(row);
    }
    List<RepeatedObservationResponse> repeated = new ArrayList<>();
    byCode.forEach(
        (code, rows) -> {
          // 한 회차에 같은 코드가 두 번 나와도 '두 회차'가 아니다 — 리포트 단위로 센다.
          List<LocalDate> dates =
              rows.stream()
                  .map(row -> dateByReport.get(row.reportId()))
                  .filter(date -> date != null)
                  .distinct()
                  .sorted()
                  .toList();
          if (dates.size() >= REPEAT_THRESHOLD) {
            repeated.add(
                new RepeatedObservationResponse(
                    code,
                    rows.get(0).title(),
                    dates.size(),
                    dates.get(0),
                    dates.get(dates.size() - 1)));
          }
        });
    return repeated;
  }

  private List<SafetySignalResponse> buildSafetySignals(
      List<Long> reportIds, Map<Long, LocalDate> dateByReport) {
    List<SafetySignalResponse> signals = new ArrayList<>();
    for (ReferralSafetySignalRow row : referralRepository.findSafetySignals(reportIds)) {
      signals.add(
          new SafetySignalResponse(
              row.reasonCode(),
              row.severity(),
              dateByReport.get(row.reportId()),
              // 앱이 무엇을 했는지 그대로 적는다. 처리 내역이 없으면 전문가는 방치됐는지 알 수 없다.
              "앱이 보호자에게 안내를 보여 주었어요: " + row.title()));
    }
    return signals;
  }

  private AnswerCompositionResponse buildAnswerComposition(List<ReferralSessionRow> rows) {
    return new AnswerCompositionResponse(
        rows.stream().mapToInt(ReferralSessionRow::confirmedVoiceCount).sum(),
        rows.stream().mapToInt(ReferralSessionRow::optionAnswerCount).sum(),
        rows.stream().mapToInt(ReferralSessionRow::skippedCount).sum(),
        rows.stream().mapToInt(ReferralSessionRow::sttConfirmationCount).sum());
  }
}
