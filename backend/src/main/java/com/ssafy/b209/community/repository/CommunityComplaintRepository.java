package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.CommunityComplaint;
import com.ssafy.b209.community.domain.ComplaintReasonCode;
import com.ssafy.b209.community.domain.ComplaintTargetType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 커뮤니티 통합 신고의 중복 확인과 저장을 담당한다. */
public interface CommunityComplaintRepository extends JpaRepository<CommunityComplaint, Long> {

  /**
   * 신고자·대상·사유가 모두 같은 기존 신고가 있는지 확인한다.
   *
   * @param reporterUserId 신고자 사용자 ID
   * @param targetType 신고 대상 유형
   * @param targetId 신고 대상 ID
   * @param reasonCode 신고 사유
   * @return 같은 신고가 있으면 {@code true}
   */
  @Query(
      """
      select (count(c) > 0) from CommunityComplaint c
      where c.reporterUserId = :reporterUserId
        and c.targetType = :targetType
        and c.reasonCode = :reasonCode
        and ((:targetType = com.ssafy.b209.community.domain.ComplaintTargetType.POST
                and c.targetPostId = :targetId)
          or (:targetType = com.ssafy.b209.community.domain.ComplaintTargetType.COMMENT
                and c.targetCommentId = :targetId)
          or (:targetType = com.ssafy.b209.community.domain.ComplaintTargetType.REPORT
                and c.targetReportId = :targetId))
      """)
  boolean existsDuplicate(
      @Param("reporterUserId") Long reporterUserId,
      @Param("targetType") ComplaintTargetType targetType,
      @Param("targetId") Long targetId,
      @Param("reasonCode") ComplaintReasonCode reasonCode);
}
