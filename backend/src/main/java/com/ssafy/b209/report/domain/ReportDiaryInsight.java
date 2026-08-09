package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.MapsId;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import java.util.Objects;

/**
 * 그림일기 V2 구조화 결과의 머리 부분이다 — 핵심 이야기와 데이터 구성.
 *
 * <p>리포트 하나에 최대 하나다. <strong>행이 없는 것이 정상</strong>이다: HTP 리포트이거나, 그림일기지만 근거가 부족해 AI 가 구조화를 포기한 경우다.
 * 빈 껍데기를 만들지 않는 것이 이 구조의 계약이라, 화면은 행의 유무로 V2 를 열지 말지 가른다.
 *
 * <p>흐름·발화·관찰·질문은 각자 자식 테이블에 있고 이 Entity 는 들고 있지 않다. 조회는 리포트 단위로 한 번에 모으는 View 가 맡는다.
 */
@Entity
@Table(name = "report_diary_insights")
public class ReportDiaryInsight {

  /** 리포트 식별자를 그대로 PK 로 쓴다(1:1). */
  @Id
  @Column(name = "report_id")
  private Long reportId;

  @MapsId
  @OneToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "headline", length = 200)
  private String headline;

  @Column(name = "summary", columnDefinition = "TEXT")
  private String summary;

  /** 실제/상상 구분이다. 아이가 말한 경우에만 {@code UNKNOWN} 밖의 값이 온다 — 서버가 아이 원문에서 정하며 모델이 짐작하지 않는다. */
  @Column(name = "reality_status", nullable = false, length = 20)
  private String realityStatus;

  /** 사건 시점이다. 아이가 말하지 않았으면 {@code UNKNOWN} 이다. 활동한 날짜는 사건 날짜의 근거가 아니다. */
  @Column(name = "time_scope", nullable = false, length = 20)
  private String timeScope;

  @Column(name = "main_event", length = 300)
  private String mainEvent;

  @Column(name = "listening_tip", columnDefinition = "TEXT")
  private String listeningTip;

  @Column(name = "confirmed_voice_count", nullable = false, columnDefinition = "SMALLINT")
  private int confirmedVoiceCount;

  @Column(name = "option_answer_count", nullable = false, columnDefinition = "SMALLINT")
  private int optionAnswerCount;

  @Column(name = "skipped_count", nullable = false, columnDefinition = "SMALLINT")
  private int skippedCount;

  @Column(name = "stt_confirmation_count", nullable = false, columnDefinition = "SMALLINT")
  private int sttConfirmationCount;

  @Column(name = "evidence_count", nullable = false, columnDefinition = "SMALLINT")
  private int evidenceCount;

  @Column(name = "vision_summary_available", nullable = false)
  private boolean visionSummaryAvailable;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryInsight() {}

  private ReportDiaryInsight(
      Report report,
      String headline,
      String summary,
      String realityStatus,
      String timeScope,
      String mainEvent,
      String listeningTip,
      int confirmedVoiceCount,
      int optionAnswerCount,
      int skippedCount,
      int sttConfirmationCount,
      int evidenceCount,
      boolean visionSummaryAvailable) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.headline = headline;
    this.summary = summary;
    this.realityStatus = normalizeCode(realityStatus);
    this.timeScope = normalizeCode(timeScope);
    this.mainEvent = mainEvent;
    this.listeningTip = listeningTip;
    this.confirmedVoiceCount = confirmedVoiceCount;
    this.optionAnswerCount = optionAnswerCount;
    this.skippedCount = skippedCount;
    this.sttConfirmationCount = sttConfirmationCount;
    this.evidenceCount = evidenceCount;
    this.visionSummaryAvailable = visionSummaryAvailable;
  }

  /**
   * 구조화 결과의 머리 부분을 만든다.
   *
   * @param report 소속 리포트
   * @param headline 핵심 이야기 제목이며 없으면 {@code null}
   * @param summary 이야기 요약이며 없으면 {@code null}
   * @param realityStatus 실제/상상 구분이며 비어 있으면 {@code UNKNOWN} 으로 둔다
   * @param timeScope 사건 시점이며 비어 있으면 {@code UNKNOWN} 으로 둔다
   * @param mainEvent 중심 사건이며 없으면 {@code null}
   * @param listeningTip 듣는 태도 한 문장이며 없으면 {@code null}
   * @param confirmedVoiceCount 음성으로 확정된 답변 수
   * @param optionAnswerCount 선택지에서 고른 답변 수
   * @param skippedCount 건너뛴 질문 수
   * @param sttConfirmationCount 음성 인식 확인이 필요한 답변 수
   * @param evidenceCount 사용된 근거 수
   * @param visionSummaryAvailable 그림 관찰 서술 존재 여부
   * @return 저장 대기 Entity
   */
  public static ReportDiaryInsight create(
      Report report,
      String headline,
      String summary,
      String realityStatus,
      String timeScope,
      String mainEvent,
      String listeningTip,
      int confirmedVoiceCount,
      int optionAnswerCount,
      int skippedCount,
      int sttConfirmationCount,
      int evidenceCount,
      boolean visionSummaryAvailable) {
    return new ReportDiaryInsight(
        report,
        headline,
        summary,
        realityStatus,
        timeScope,
        mainEvent,
        listeningTip,
        confirmedVoiceCount,
        optionAnswerCount,
        skippedCount,
        sttConfirmationCount,
        evidenceCount,
        visionSummaryAvailable);
  }

  /** 값이 비면 {@code UNKNOWN} 으로 둔다 — '모른다'가 이 두 축의 정상 상태다. */
  private static String normalizeCode(String value) {
    return value == null || value.isBlank() ? "UNKNOWN" : value;
  }

  /**
   * @return 리포트 식별자
   */
  public Long getReportId() {
    return reportId;
  }

  /**
   * @return 핵심 이야기 제목이며 없으면 {@code null}
   */
  public String getHeadline() {
    return headline;
  }

  /**
   * @return 이야기 요약이며 없으면 {@code null}
   */
  public String getSummary() {
    return summary;
  }

  /**
   * @return 실제/상상 구분
   */
  public String getRealityStatus() {
    return realityStatus;
  }

  /**
   * @return 사건 시점
   */
  public String getTimeScope() {
    return timeScope;
  }

  /**
   * @return 중심 사건이며 없으면 {@code null}
   */
  public String getMainEvent() {
    return mainEvent;
  }

  /**
   * @return 듣는 태도 한 문장이며 없으면 {@code null}
   */
  public String getListeningTip() {
    return listeningTip;
  }

  /**
   * @return 음성으로 확정된 답변 수
   */
  public int getConfirmedVoiceCount() {
    return confirmedVoiceCount;
  }

  /**
   * @return 선택지에서 고른 답변 수
   */
  public int getOptionAnswerCount() {
    return optionAnswerCount;
  }

  /**
   * @return 건너뛴 질문 수
   */
  public int getSkippedCount() {
    return skippedCount;
  }

  /**
   * @return 음성 인식 확인이 필요한 답변 수
   */
  public int getSttConfirmationCount() {
    return sttConfirmationCount;
  }

  /**
   * @return 사용된 근거 수
   */
  public int getEvidenceCount() {
    return evidenceCount;
  }

  /**
   * @return 그림 관찰 서술 존재 여부
   */
  public boolean isVisionSummaryAvailable() {
    return visionSummaryAvailable;
  }
}
