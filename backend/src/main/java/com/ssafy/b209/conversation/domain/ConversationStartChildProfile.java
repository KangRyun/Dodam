package com.ssafy.b209.conversation.domain;

import com.ssafy.b209.child.domain.QuestionDifficulty;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import org.hibernate.annotations.ColumnDefault;

/** 282번 시작 응답과 난이도 Snapshot에 필요한 아동 프로필 읽기 모델이다. */
@Entity
@Table(name = "children")
public class ConversationStartChildProfile {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Enumerated(EnumType.STRING)
  @Column(name = "question_difficulty", nullable = false)
  private QuestionDifficulty questionDifficulty;

  protected ConversationStartChildProfile() {}

  /**
   * @return DB v1.2와 API 계약에 정의된 질문 난이도
   */
  public QuestionDifficulty getQuestionDifficulty() {
    return questionDifficulty;
  }
}
