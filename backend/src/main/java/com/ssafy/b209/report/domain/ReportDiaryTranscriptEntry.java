package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * 그림일기 리포트 생성 시점의 질문·답변 한 쌍을 보존하는 읽기 스냅샷이다.
 *
 * <p>음성 Storage Key나 인증 URL은 저장하지 않는다. 재생 가능 여부는 생성 당시의 비민감 상태만 남기고, 실제 URL과 현재 파일 존재 여부는 조회 시 원본
 * 메시지 ID를 통해 확인한다.
 */
@Entity
@Table(name = "report_diary_transcript_entries")
public class ReportDiaryTranscriptEntry {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "question_message_id")
  private Long questionMessageId;

  @Column(name = "answer_message_id")
  private Long answerMessageId;

  @Column(name = "question_text", nullable = false, columnDefinition = "TEXT")
  private String questionText;

  @Column(name = "answer_text", columnDefinition = "TEXT")
  private String answerText;

  @Column(name = "response_type", nullable = false, length = 20)
  private String responseType;

  @Column(name = "stt_status", length = 30)
  private String sttStatus;

  @Column(name = "audio_available_at_generation", nullable = false)
  private boolean audioAvailableAtGeneration;

  @Column(name = "audio_duration_ms")
  private Integer audioDurationMs;

  @Column(name = "elicitation_type", nullable = false, length = 30)
  private String elicitationType;

  @Column(name = "occurred_at")
  private LocalDateTime occurredAt;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryTranscriptEntry() {}

  private ReportDiaryTranscriptEntry(
      Report report,
      Long questionMessageId,
      Long answerMessageId,
      String questionText,
      String answerText,
      String responseType,
      String sttStatus,
      boolean audioAvailableAtGeneration,
      Integer audioDurationMs,
      String elicitationType,
      LocalDateTime occurredAt,
      int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.questionMessageId = questionMessageId;
    this.answerMessageId = answerMessageId;
    this.questionText = Objects.requireNonNull(questionText, "questionText must not be null");
    this.answerText = answerText;
    this.responseType = Objects.requireNonNull(responseType, "responseType must not be null");
    this.sttStatus = sttStatus;
    this.audioAvailableAtGeneration = audioAvailableAtGeneration;
    this.audioDurationMs = audioDurationMs;
    this.elicitationType =
        Objects.requireNonNull(elicitationType, "elicitationType must not be null");
    this.occurredAt = occurredAt;
    this.displayOrder = displayOrder;
  }

  /**
   * 리포트 생성 시점의 대화 한 쌍을 만든다.
   *
   * @param report 소속 리포트
   * @param questionMessageId 질문 메시지 식별자
   * @param answerMessageId 답변 메시지 식별자
   * @param questionText 질문 원문
   * @param answerText 답변 원문 또는 확정 STT이며 없으면 {@code null}
   * @param responseType VOICE·OPTION·TEXT·SKIPPED·CORRECTION 중 하나
   * @param sttStatus 음성 처리 상태이며 음성이 아니면 {@code null}
   * @param audioAvailableAtGeneration 생성 당시 원본 음성 참조 존재 여부
   * @param audioDurationMs 실제로 수집한 음성 길이이며 알 수 없으면 {@code null}
   * @param elicitationType 답변을 이끈 질문 방식
   * @param occurredAt 답변 생성 시각이며 과거 데이터는 {@code null}
   * @param displayOrder 대화 표시 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryTranscriptEntry create(
      Report report,
      Long questionMessageId,
      Long answerMessageId,
      String questionText,
      String answerText,
      String responseType,
      String sttStatus,
      boolean audioAvailableAtGeneration,
      Integer audioDurationMs,
      String elicitationType,
      LocalDateTime occurredAt,
      int displayOrder) {
    return new ReportDiaryTranscriptEntry(
        report,
        questionMessageId,
        answerMessageId,
        questionText,
        answerText,
        responseType,
        sttStatus,
        audioAvailableAtGeneration,
        audioDurationMs,
        elicitationType,
        occurredAt,
        displayOrder);
  }

  /**
   * @return 질문 메시지 식별자
   */
  public Long getQuestionMessageId() {
    return questionMessageId;
  }

  /**
   * @return 답변 메시지 식별자
   */
  public Long getAnswerMessageId() {
    return answerMessageId;
  }

  /**
   * @return 리포트 생성 시점 질문 원문
   */
  public String getQuestionText() {
    return questionText;
  }

  /**
   * @return 리포트 생성 시점 답변이며 없으면 {@code null}
   */
  public String getAnswerText() {
    return answerText;
  }

  /**
   * @return VOICE·OPTION·TEXT·SKIPPED·CORRECTION 중 하나
   */
  public String getResponseType() {
    return responseType;
  }

  /**
   * @return 음성 처리 상태이며 음성이 아니면 {@code null}
   */
  public String getSttStatus() {
    return sttStatus;
  }

  /**
   * @return 리포트 생성 당시 원본 음성 참조가 있었으면 {@code true}
   */
  public boolean isAudioAvailableAtGeneration() {
    return audioAvailableAtGeneration;
  }

  /**
   * @return 실제 수집한 음성 길이이며 알 수 없으면 {@code null}
   */
  public Integer getAudioDurationMs() {
    return audioDurationMs;
  }

  /**
   * @return 답변을 이끈 질문 방식
   */
  public String getElicitationType() {
    return elicitationType;
  }

  /**
   * @return 답변 생성 시각이며 과거 데이터는 {@code null}
   */
  public LocalDateTime getOccurredAt() {
    return occurredAt;
  }

  /**
   * @return 대화 표시 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
