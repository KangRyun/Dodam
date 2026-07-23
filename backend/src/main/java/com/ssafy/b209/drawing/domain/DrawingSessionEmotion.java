package com.ssafy.b209.drawing.domain;

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
import java.util.Objects;

/** 그림 활동을 돌아보며 아동이 직접 선택한 감정과 선택 순서를 저장한다. */
@Entity
@Table(name = "drawing_session_emotions")
public class DrawingSessionEmotion {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_session_id", nullable = false)
  private DrawingSession drawingSession;

  @Enumerated(EnumType.STRING)
  @Column(name = "emotion_code", nullable = false, length = 20)
  private DrawingEmotionCode emotionCode;

  @Column(name = "selection_order", nullable = false)
  private short selectionOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected DrawingSessionEmotion() {}

  private DrawingSessionEmotion(
      DrawingSession drawingSession, DrawingEmotionCode emotionCode, int selectionOrder) {
    this.drawingSession = Objects.requireNonNull(drawingSession);
    this.emotionCode = Objects.requireNonNull(emotionCode);
    if (selectionOrder < 0 || selectionOrder > Short.MAX_VALUE) {
      throw new IllegalArgumentException("selectionOrder must fit a non-negative SMALLINT");
    }
    this.selectionOrder = (short) selectionOrder;
  }

  /**
   * 요청에 포함된 선택 순서를 유지하는 감정 Entity를 생성한다.
   *
   * @param drawingSession 감정을 선택한 그림 활동 세션
   * @param emotionCode 아동이 선택한 감정 코드
   * @param selectionOrder 요청 배열에서의 0부터 시작하는 선택 순서
   * @return 저장 가능한 그림 활동 감정
   */
  public static DrawingSessionEmotion create(
      DrawingSession drawingSession, DrawingEmotionCode emotionCode, int selectionOrder) {
    return new DrawingSessionEmotion(drawingSession, emotionCode, selectionOrder);
  }

  /**
   * 감정을 선택한 그림 활동 세션을 반환한다.
   *
   * @return 감정이 속한 그림 활동 세션
   */
  public DrawingSession getDrawingSession() {
    return drawingSession;
  }

  /**
   * 선택된 감정 코드를 반환한다.
   *
   * @return 선택 감정 코드
   */
  public DrawingEmotionCode getEmotionCode() {
    return emotionCode;
  }

  /**
   * 요청에서 감정이 선택된 순서를 반환한다.
   *
   * @return 0부터 시작하는 선택 순서
   */
  public int getSelectionOrder() {
    return selectionOrder;
  }
}
