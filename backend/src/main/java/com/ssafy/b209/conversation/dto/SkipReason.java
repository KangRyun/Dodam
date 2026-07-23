package com.ssafy.b209.conversation.dto;

/** 아동이 현재 AI 질문을 건너뛴 사유다. 무응답 존중 원칙에 따라 아동 요청만 허용한다. */
public enum SkipReason {
  /** 아동이 답변 대신 건너뛰기 또는 계속 그리기를 선택한 경우다. */
  CHILD_REQUEST
}
