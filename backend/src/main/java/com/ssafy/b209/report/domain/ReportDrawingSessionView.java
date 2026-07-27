package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Duration;
import java.time.LocalDateTime;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code drawing_sessions} 한 행을 읽는 읽기 모델이다.
 *
 * <p>그림 활동 세션의 소유 아동, 유형, 입력 방식과 활동 시각만 스칼라로 읽어 리포트 조립에 사용한다.
 */
@Entity
@Table(name = "drawing_sessions")
public class ReportDrawingSessionView {

  @Id private Long id;

  @Column(name = "child_id", nullable = false)
  private Long childId;

  @Column(name = "drawing_type_id", nullable = false)
  private Long drawingTypeId;

  @Column(name = "input_method", nullable = false)
  private String inputMethod;

  @Column(name = "title")
  private String title;

  @Column(name = "expressed_emotion_text")
  private String expressedEmotionText;

  @Column(name = "started_at", nullable = false)
  private LocalDateTime startedAt;

  @Column(name = "completed_at")
  private LocalDateTime completedAt;

  protected ReportDrawingSessionView() {}

  /**
   * @return 그림 활동 세션 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 소유 아동 식별자
   */
  public Long getChildId() {
    return childId;
  }

  /**
   * @return 그림 활동 유형 식별자
   */
  public Long getDrawingTypeId() {
    return drawingTypeId;
  }

  /**
   * @return 입력 방식 코드
   */
  public String getInputMethod() {
    return inputMethod;
  }

  /**
   * @return 그림 제목이며 없으면 {@code null}
   */
  public String getTitle() {
    return title;
  }

  /**
   * @return 아동이 표현한 감정 내용이며 없으면 {@code null}
   */
  public String getExpressedEmotionText() {
    return expressedEmotionText;
  }

  /**
   * @return 그림 활동 시작 UTC 시각
   */
  public LocalDateTime getStartedAt() {
    return startedAt;
  }

  /**
   * @return 그림 활동 완료 UTC 시각이며 진행 중이면 {@code null}
   */
  public LocalDateTime getCompletedAt() {
    return completedAt;
  }

  /**
   * 시작·완료 시각으로 그림 활동 소요 시간을 계산한다.
   *
   * @return 밀리초 단위 소요 시간이며 완료되지 않았으면 {@code null}
   */
  public Long durationMs() {
    if (startedAt == null || completedAt == null) {
      return null;
    }
    long millis = Duration.between(startedAt, completedAt).toMillis();
    return millis < 0 ? null : millis;
  }
}
