package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** v1.2 폴백 템플릿의 선택지 정의다. */
@Entity
@Table(name = "ai_question_template_options")
public class AiQuestionTemplateOption {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "question_template_id", nullable = false)
  private Long questionTemplateId;

  @Column(name = "option_key", nullable = false, length = 80)
  private String optionKey;

  @Column(name = "label", nullable = false, length = 200)
  private String label;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  protected AiQuestionTemplateOption() {}

  public String getOptionKey() {
    return optionKey;
  }

  public String getLabel() {
    return label;
  }
}
