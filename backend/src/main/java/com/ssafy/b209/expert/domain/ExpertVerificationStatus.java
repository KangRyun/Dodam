package com.ssafy.b209.expert.domain;

/** 전문가 프로필과 자격 정보의 운영 검증 상태다. */
public enum ExpertVerificationStatus {
  /** 최초 등록 후 관리자 검토를 기다리는 상태다. */
  PENDING,
  /** 관리자 검증을 통과한 상태다. */
  VERIFIED,
  /** 관리자 검증에서 반려된 상태다. */
  REJECTED,
  /** 검증 후 주요 정보가 바뀌어 재검토가 필요한 상태다. */
  REVIEW_REQUIRED
}
