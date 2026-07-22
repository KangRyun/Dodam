package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** AI 호출 실패 시 사용할 v1.2 활성 질문 템플릿이다. */
@Entity
@Table(name = "ai_question_templates")
public class AiQuestionTemplate {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "template_type", nullable = false)
  private String templateType;

  @Column(name = "question_text", nullable = false)
  private String questionText;

  @Column(name = "is_active", nullable = false)
  private boolean active;

  protected AiQuestionTemplate() {}

  public Long getId() {
    return id;
  }

  public String getQuestionText() {
    return questionText;
  }
}
