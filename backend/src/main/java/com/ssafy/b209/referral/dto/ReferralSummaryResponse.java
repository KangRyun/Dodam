package com.ssafy.b209.referral.dto;

import com.ssafy.b209.screening.dto.response.ScreeningSummaryResponse;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * 전문가에게 전달할 의뢰 요약이다.
 *
 * <p><strong>이 문서는 진단도 소견도 아니다.</strong> 전문가가 판단하는 데 필요한 <strong>원자료</strong>를 모아 정리한 것이며, 앱의 해석을
 * 대신 주장하지 않는다. 해석을 앞세우면 전문가의 판단이 그 방향으로 끌려간다(앵커링) — 그래서 아이가 실제로 한 말과, 그 말이 어떤 질문에서 나왔는지를 먼저 싣는다.
 *
 * <p>전부 <strong>결정론적으로 조립</strong>한다. LLM 은 이 문서를 만들지 않는다 — 맡기면 없는 진단명과 색·크기 상징이 곧바로 섞인다.
 *
 * @param childDisplayName 아이 표시명(별명)이며 없으면 {@code null}. 실명·생년월일은 담지 않는다
 * @param generatedAt 요약을 만든 시각
 * @param purpose 이 문서가 무엇인지 알리는 고정 문구
 * @param sessions 최근 활동 회차이며 최신순이다
 * @param repeatedObservations <strong>두 회차 이상</strong>에서 되풀이된 관찰이다. 한 번뿐인 것은 여기 오지 않는다
 * @param safetySignals 안전 신호와 앱이 취한 처리 내역
 * @param screening 보호자가 기록해 둔 검사 결과이며 앱이 실시하거나 채점한 것이 아니다
 * @param answerComposition 답변이 무엇으로 이루어졌는지. 고른 답을 자발 발화로 세지 않기 위한 구분이다
 * @param voiceRecordingAvailable 아이 음성 원본이 앱에 남아 있으면 {@code true}. <strong>재생 링크는 담지 않는다</strong>
 * @param notIncluded 이 요약에 <strong>담지 않은 것</strong>이다. 무엇이 빠졌는지 알아야 전문가가 빈 곳을 오해하지 않는다
 * @param reviewNotice 보호자가 공유 전에 확인할 것
 */
public record ReferralSummaryResponse(
    String childDisplayName,
    LocalDateTime generatedAt,
    String purpose,
    List<ReferralSessionResponse> sessions,
    List<RepeatedObservationResponse> repeatedObservations,
    List<SafetySignalResponse> safetySignals,
    ScreeningSummaryResponse screening,
    AnswerCompositionResponse answerComposition,
    boolean voiceRecordingAvailable,
    List<String> notIncluded,
    String reviewNotice) {

  /** 목록은 빈 목록으로 정규화한다. */
  public ReferralSummaryResponse {
    sessions = sessions == null ? List.of() : List.copyOf(sessions);
    repeatedObservations =
        repeatedObservations == null ? List.of() : List.copyOf(repeatedObservations);
    safetySignals = safetySignals == null ? List.of() : List.copyOf(safetySignals);
    notIncluded = notIncluded == null ? List.of() : List.copyOf(notIncluded);
  }

  /**
   * 활동 한 회차다.
   *
   * @param reportId 리포트 식별자
   * @param activityType 활동 유형 코드이며 알 수 없으면 {@code null}
   * @param activityDate 활동 날짜
   * @param headline 그 회차 이야기의 핵심이며 없으면 {@code null}
   * @param mainEvent 중심 사건이며 분명하지 않으면 {@code null}
   * @param realityStatus 실제·상상 구분이다. <strong>아이가 말한 경우에만</strong> {@code UNKNOWN} 밖의 값이 온다
   * @param timeScope 사건 시점이며 아이가 말하지 않았으면 {@code UNKNOWN}이다. 활동 날짜는 사건 날짜의 근거가 아니다
   * @param childVoices 아이가 실제로 한 말
   */
  public record ReferralSessionResponse(
      Long reportId,
      String activityType,
      LocalDate activityDate,
      String headline,
      String mainEvent,
      String realityStatus,
      String timeScope,
      List<ChildVoiceResponse> childVoices) {

    /** 목록은 빈 목록으로 정규화한다. */
    public ReferralSessionResponse {
      childVoices = childVoices == null ? List.of() : List.copyOf(childVoices);
    }
  }

  /**
   * 아이가 한 말 한 줄이다.
   *
   * @param text 아이가 한 말이며 학교·주소 형태는 가려져 있다
   * @param elicitationType 그 말을 끌어낸 질문 방식
   * @param spontaneous 아이가 자기 말로 만든 문장이면 {@code true}. <strong>선택지에서 고른 답은 거짓</strong>이다
   * @param sttNeedsConfirmation 음성 인식 확인이 필요한 답이면 {@code true}. 인용 근거로 쓰지 않는다
   */
  public record ChildVoiceResponse(
      String text, String elicitationType, boolean spontaneous, boolean sttNeedsConfirmation) {}

  /**
   * 두 회차 이상에서 되풀이된 관찰이다.
   *
   * <p><strong>한 번뿐인 것은 반복이 아니다.</strong> 1회를 패턴으로 부르면 그 순간 한 번의 활동이 아이의 성향이 된다.
   *
   * @param observationCode 관찰 코드
   * @param title 보호자에게 보이던 제목
   * @param occurrenceCount 되풀이된 회차 수
   * @param firstSeenOn 처음 확인된 날
   * @param lastSeenOn 마지막으로 확인된 날
   */
  public record RepeatedObservationResponse(
      String observationCode,
      String title,
      int occurrenceCount,
      LocalDate firstSeenOn,
      LocalDate lastSeenOn) {}

  /**
   * 안전 신호와 처리 내역이다.
   *
   * @param reasonCode 위기 사유 코드
   * @param severity 심각도
   * @param occurredOn 확인된 날
   * @param handling 앱이 취한 처리
   */
  public record SafetySignalResponse(
      String reasonCode, String severity, LocalDate occurredOn, String handling) {}

  /**
   * 답변이 무엇으로 이루어졌는지 알려 준다.
   *
   * <p>고른 답을 자발 발화로 세면 아이가 실제보다 많이 말한 것처럼 보인다. 전문가가 근거의 무게를 가늠하려면 이 구분이 필요하다.
   *
   * @param spokenAnswerCount 아이가 자기 말로 답한 수
   * @param optionAnswerCount 선택지에서 고른 수
   * @param skippedCount 건너뛴 수
   * @param sttUnconfirmedCount 음성 인식 확인이 필요한 수
   */
  public record AnswerCompositionResponse(
      int spokenAnswerCount, int optionAnswerCount, int skippedCount, int sttUnconfirmedCount) {}
}
