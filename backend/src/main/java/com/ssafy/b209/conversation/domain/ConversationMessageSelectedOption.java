package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** v1.2 conversation_message_selected_options의 아동 선택 응답 저장 모델이다. */
@Entity
@Table(name = "conversation_message_selected_options")
public class ConversationMessageSelectedOption {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "answer_message_id", nullable = false)
  private Long answerMessageId;

  @Column(name = "question_message_id", nullable = false)
  private Long questionMessageId;

  @Column(name = "message_option_id", nullable = false)
  private Long messageOptionId;

  @Column(name = "label_snapshot", nullable = false, length = 200)
  private String labelSnapshot;

  @Column(name = "selection_order", nullable = false, columnDefinition = "SMALLINT")
  private short selectionOrder;

  protected ConversationMessageSelectedOption() {}

  /**
   * 하나의 선택 응답 행을 생성한다.
   *
   * @param answerMessageId 저장된 OPTION_ANSWER 메시지 ID
   * @param questionMessageId 답변이 연결된 QUESTION 메시지 ID
   * @param messageOptionId 선택된 질문 선택지 Snapshot 행 ID
   * @param labelSnapshot 선택 당시 화면에 노출된 문구
   * @param selectionOrder 요청 배열 순서 기반의 선택 순번
   * @return 영속화 전 선택 응답
   */
  public static ConversationMessageSelectedOption of(
      Long answerMessageId,
      Long questionMessageId,
      Long messageOptionId,
      String labelSnapshot,
      short selectionOrder) {
    ConversationMessageSelectedOption selected = new ConversationMessageSelectedOption();
    selected.answerMessageId = answerMessageId;
    selected.questionMessageId = questionMessageId;
    selected.messageOptionId = messageOptionId;
    selected.labelSnapshot = labelSnapshot;
    selected.selectionOrder = selectionOrder;
    return selected;
  }

  public Long getId() {
    return id;
  }

  public Long getAnswerMessageId() {
    return answerMessageId;
  }

  public Long getQuestionMessageId() {
    return questionMessageId;
  }

  public Long getMessageOptionId() {
    return messageOptionId;
  }

  public String getLabelSnapshot() {
    return labelSnapshot;
  }

  public short getSelectionOrder() {
    return selectionOrder;
  }
}
