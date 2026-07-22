package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** 282번 시작 응답과 난이도 Snapshot에 필요한 아동 프로필 읽기 모델이다. */
@Entity
@Table(name = "children")
public class ConversationStartChildProfile {

  @Id private Long id;

  @Column(name = "question_difficulty", nullable = false)
  private String questionDifficulty;

  protected ConversationStartChildProfile() {}

  /**
   * @return DB v1.2에 정의된 질문 난이도
   */
  public String getQuestionDifficulty() {
    return questionDifficulty;
  }
}
