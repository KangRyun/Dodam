package com.ssafy.b209.report.domain;

/** 보호자 가이드의 유형이다. 유형마다 화면 섹션이 나뉘며 없는 유형은 섹션이 숨는다(계약 §7). */
public enum ReportParentGuideType {
  /** 그림으로 대화해 보세요. */
  DRAWING_CONVERSATION,
  /** 일상에서 이렇게 도와주세요. */
  DAILY_PARENTING,
  /** 가정에서 살펴봐 주세요. */
  HOME_OBSERVATION,
  /**
   * 도움이 필요할 때 — 상시 노출되는 일반 상담 안내다.
   *
   * <p>위기 대응 안내(crisisAlert)와 다르다. 위기 문구·신고·긴급 연락처를 여기에 담지 않는다(계약 §4-4).
   */
  PROFESSIONAL_SUPPORT
}
