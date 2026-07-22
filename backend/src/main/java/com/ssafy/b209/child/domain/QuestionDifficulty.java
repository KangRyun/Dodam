package com.ssafy.b209.child.domain;

/**
 * 아동 프로필과 대화 세션에 저장하는 질문 난이도다.
 *
 * <p>DB v1.2 {@code children.question_difficulty} 및 최종 API 명세의 허용값과 이름을 일치시킨다.
 */
public enum QuestionDifficulty {
  PRESCHOOL,
  LOWER_ELEMENTARY,
  UPPER_ELEMENTARY,
  SUPPORT
}
