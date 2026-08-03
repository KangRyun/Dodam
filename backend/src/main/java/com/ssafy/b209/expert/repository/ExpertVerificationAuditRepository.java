package com.ssafy.b209.expert.repository;

import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import java.time.LocalDateTime;
import java.util.List;

/** 관리자 전문가 검토의 사유와 선택 자격을 감사 가능한 이력으로 저장한다. */
public interface ExpertVerificationAuditRepository {

  /**
   * 검토 이력과 공통 감사 로그를 동일 Transaction 안에 기록한다.
   *
   * @param reviewerUserId 검토 관리자 사용자 ID
   * @param expertId 전문가 프로필 ID
   * @param status 승인 또는 반려 결과
   * @param verifiedCredentialIds 승인 자격 ID 목록
   * @param rejectionReason 반려 사유
   * @param internalNote 내부 메모
   * @param reviewedAt 검토 완료 시각
   */
  void saveReview(
      Long reviewerUserId,
      Long expertId,
      ExpertVerificationStatus status,
      List<Long> verifiedCredentialIds,
      String rejectionReason,
      String internalNote,
      LocalDateTime reviewedAt);
}
