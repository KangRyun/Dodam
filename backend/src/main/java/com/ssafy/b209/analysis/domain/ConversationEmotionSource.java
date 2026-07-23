package com.ssafy.b209.analysis.domain;

/** 대화 요약에 기록하는 표현 감정의 출처를 나타낸다. */
public enum ConversationEmotionSource {
  /** 아동이 감정 카드에서 직접 선택한 감정이다. */
  SELECTED,
  /** 아동이 대화에서 말로 직접 표현한 감정이다. */
  STATED,
  /** 대화 맥락에서 보조적으로 유추한 감정이다. */
  INFERRED
}
