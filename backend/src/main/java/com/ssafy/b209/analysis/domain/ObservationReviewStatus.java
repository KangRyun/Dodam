package com.ssafy.b209.analysis.domain;

/**
 * 관찰 결과의 전문가 검토 진행 상태를 나타낸다.
 *
 * <p>Mock 생성 단계에서는 항상 {@code AI_DRAFT}로만 저장하며, 전문가 검토 및 공개 전이는 별도 상담 워크플로 이슈에서 확장한다.
 */
public enum ObservationReviewStatus {
  /** AI가 생성했으며 전문가 검토를 거치지 않은 초안 상태다. */
  AI_DRAFT
}
