package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code drawing_session_emotions} 한 행을 읽는 읽기 모델이다.
 *
 * <p>아동이 직접 선택한 감정 코드와 선택 순서만 읽는다.
 */
@Entity
@Table(name = "drawing_session_emotions")
public class ReportDrawingEmotionView {

  @Id private Long id;

  @Column(name = "drawing_session_id", nullable = false)
  private Long drawingSessionId;

  @Column(name = "emotion_code", nullable = false)
  private String emotionCode;

  @Column(name = "selection_order", nullable = false)
  private short selectionOrder;

  protected ReportDrawingEmotionView() {}

  /**
   * @return 선택 감정 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 소유 그림 활동 세션 식별자
   */
  public Long getDrawingSessionId() {
    return drawingSessionId;
  }

  /**
   * @return 아동이 선택한 감정 코드
   */
  public String getEmotionCode() {
    return emotionCode;
  }

  /**
   * @return 아동이 선택한 순서
   */
  public short getSelectionOrder() {
    return selectionOrder;
  }
}
