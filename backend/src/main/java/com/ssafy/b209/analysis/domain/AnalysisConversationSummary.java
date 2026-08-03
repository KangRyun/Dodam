package com.ssafy.b209.analysis.domain;

import com.ssafy.b209.conversation.domain.ConversationSession;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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
 * 최종 분석에 연결된 대화 세션의 요약과 객관적 집계 수치를 저장한다.
 *
 * <p>질문·응답·건너뜀·음성 인식 실패 수는 실제 대화 메시지 집계값이며, 요약 문구는 관찰 보조 표현으로만 작성한다.
 */
@Entity
@Table(name = "analysis_conversation_summaries")
public class AnalysisConversationSummary {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  @Column(name = "conversation_summary_id")
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "analysis_id", nullable = false)
  private DrawingAnalysis analysis;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "conversation_session_id")
  private ConversationSession conversationSession;

  @Column(name = "summary_text", columnDefinition = "TEXT")
  private String summaryText;

  @Column(name = "main_topic", length = 100)
  private String mainTopic;

  @Column(name = "expressed_emotion", length = 50)
  private String expressedEmotion;

  @Enumerated(EnumType.STRING)
  @Column(name = "emotion_source", length = 30)
  private ConversationEmotionSource emotionSource;

  @Column(name = "question_count")
  private Integer questionCount;

  @Column(name = "response_count")
  private Integer responseCount;

  @Column(name = "skipped_question_count")
  private Integer skippedQuestionCount;

  @Column(name = "unrecognized_speech_count")
  private Integer unrecognizedSpeechCount;

  @Column(name = "representative_utterance", columnDefinition = "TEXT")
  private String representativeUtterance;

  @Column(name = "summary_model_version", length = 255)
  private String summaryModelVersion;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected AnalysisConversationSummary() {}

  private AnalysisConversationSummary(
      DrawingAnalysis analysis,
      ConversationSession conversationSession,
      String summaryText,
      String mainTopic,
      String expressedEmotion,
      ConversationEmotionSource emotionSource,
      int questionCount,
      int responseCount,
      int skippedQuestionCount,
      int unrecognizedSpeechCount,
      String representativeUtterance,
      String summaryModelVersion,
      LocalDateTime createdAt) {
    this.analysis = Objects.requireNonNull(analysis, "analysis must not be null");
    this.conversationSession = conversationSession;
    this.summaryText = summaryText;
    this.mainTopic = mainTopic;
    this.expressedEmotion = expressedEmotion;
    this.emotionSource = emotionSource;
    this.questionCount = requireNonNegative(questionCount, "questionCount");
    this.responseCount = requireNonNegative(responseCount, "responseCount");
    this.skippedQuestionCount = requireNonNegative(skippedQuestionCount, "skippedQuestionCount");
    this.unrecognizedSpeechCount =
        requireNonNegative(unrecognizedSpeechCount, "unrecognizedSpeechCount");
    this.representativeUtterance = representativeUtterance;
    this.summaryModelVersion = summaryModelVersion;
    this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
    this.updatedAt = createdAt;
  }

  /**
   * 실제 대화 집계와 관찰 요약을 담은 대화 요약을 생성한다.
   *
   * @param analysis 요약이 속한 최종 분석
   * @param conversationSession 요약 대상 대화 세션이며 대화를 생략했으면 {@code null}
   * @param summaryText 관찰 보조 표현으로 작성한 대화 요약
   * @param mainTopic 대화의 주요 주제
   * @param expressedEmotion 대화에서 표현된 감정
   * @param emotionSource 표현 감정의 출처
   * @param questionCount 실제 제시한 질문 수
   * @param responseCount 실제 응답한 답변 수
   * @param skippedQuestionCount 건너뛴 질문 수
   * @param unrecognizedSpeechCount 음성 인식에 실패한 답변 수
   * @param representativeUtterance 대표 발화이며 없으면 {@code null}
   * @param summaryModelVersion 요약을 생성한 Model 버전
   * @param createdAt 서버가 요약을 저장한 UTC 시각
   * @return 저장 가능한 대화 요약
   * @throws IllegalArgumentException 집계 수치가 음수인 경우
   */
  public static AnalysisConversationSummary create(
      DrawingAnalysis analysis,
      ConversationSession conversationSession,
      String summaryText,
      String mainTopic,
      String expressedEmotion,
      ConversationEmotionSource emotionSource,
      int questionCount,
      int responseCount,
      int skippedQuestionCount,
      int unrecognizedSpeechCount,
      String representativeUtterance,
      String summaryModelVersion,
      LocalDateTime createdAt) {
    return new AnalysisConversationSummary(
        analysis,
        conversationSession,
        summaryText,
        mainTopic,
        expressedEmotion,
        emotionSource,
        questionCount,
        responseCount,
        skippedQuestionCount,
        unrecognizedSpeechCount,
        representativeUtterance,
        summaryModelVersion,
        createdAt);
  }

  /**
   * @return 대화 요약 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 요약이 속한 최종 분석
   */
  public DrawingAnalysis getAnalysis() {
    return analysis;
  }

  /**
   * @return 요약 대상 대화 세션이며 대화를 생략했으면 {@code null}
   */
  public ConversationSession getConversationSession() {
    return conversationSession;
  }

  /**
   * @return 관찰 보조 표현으로 작성한 대화 요약
   */
  public String getSummaryText() {
    return summaryText;
  }

  /**
   * @return 대화의 주요 주제
   */
  public String getMainTopic() {
    return mainTopic;
  }

  /**
   * @return 대화에서 표현된 감정
   */
  public String getExpressedEmotion() {
    return expressedEmotion;
  }

  /**
   * @return 표현 감정의 출처
   */
  public ConversationEmotionSource getEmotionSource() {
    return emotionSource;
  }

  /**
   * @return 실제 제시한 질문 수
   */
  public Integer getQuestionCount() {
    return questionCount;
  }

  /**
   * @return 실제 응답한 답변 수
   */
  public Integer getResponseCount() {
    return responseCount;
  }

  /**
   * @return 건너뛴 질문 수
   */
  public Integer getSkippedQuestionCount() {
    return skippedQuestionCount;
  }

  /**
   * @return 음성 인식에 실패한 답변 수
   */
  public Integer getUnrecognizedSpeechCount() {
    return unrecognizedSpeechCount;
  }

  /**
   * @return 대표 발화이며 없으면 {@code null}
   */
  public String getRepresentativeUtterance() {
    return representativeUtterance;
  }

  /**
   * @return 요약을 생성한 Model 버전
   */
  public String getSummaryModelVersion() {
    return summaryModelVersion;
  }

  /**
   * @return 서버가 요약을 저장한 UTC 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  private static int requireNonNegative(int value, String name) {
    if (value < 0) {
      throw new IllegalArgumentException(name + " must not be negative");
    }
    return value;
  }
}
