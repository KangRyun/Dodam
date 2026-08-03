package com.ssafy.b209.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/** 게시글·댓글·리포트 신고를 운영자 처리 전 상태로 보존하는 Entity다. */
@Entity
@Table(name = "complaints")
public class CommunityComplaint {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "reporter_user_id")
  private Long reporterUserId;

  @Enumerated(EnumType.STRING)
  @Column(name = "target_type", nullable = false, length = 20)
  private ComplaintTargetType targetType;

  @Column(name = "target_report_id")
  private Long targetReportId;

  @Column(name = "target_post_id")
  private Long targetPostId;

  @Column(name = "target_comment_id")
  private Long targetCommentId;

  @Enumerated(EnumType.STRING)
  @Column(name = "reason_code", nullable = false, length = 50)
  private ComplaintReasonCode reasonCode;

  @Column(name = "detail_text", columnDefinition = "TEXT")
  private String detailText;

  @Enumerated(EnumType.STRING)
  @Column(name = "complaint_status", nullable = false, length = 20)
  private ComplaintStatus status;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  /** JPA가 신고를 복원할 때 사용한다. */
  protected CommunityComplaint() {}

  private CommunityComplaint(
      Long reporterUserId,
      ComplaintTargetType targetType,
      Long targetId,
      ComplaintReasonCode reasonCode,
      String detailText,
      LocalDateTime now) {
    this.reporterUserId = Objects.requireNonNull(reporterUserId);
    this.targetType = Objects.requireNonNull(targetType);
    this.reasonCode = Objects.requireNonNull(reasonCode);
    this.detailText = detailText;
    this.status = ComplaintStatus.PENDING;
    this.createdAt = Objects.requireNonNull(now);
    this.updatedAt = now;
    switch (targetType) {
      case POST -> this.targetPostId = targetId;
      case COMMENT -> this.targetCommentId = targetId;
      case REPORT -> this.targetReportId = targetId;
    }
  }

  /**
   * 검증이 끝난 대상에 대한 대기 상태 신고를 생성한다.
   *
   * @param reporterUserId 신고자 사용자 ID
   * @param targetType 신고 대상 유형
   * @param targetId 신고 대상 ID
   * @param reasonCode 표준 신고 사유
   * @param detailText 선택 입력한 상세 설명
   * @param now 생성 시각
   * @return 저장 전 신고 Entity
   */
  public static CommunityComplaint create(
      Long reporterUserId,
      ComplaintTargetType targetType,
      Long targetId,
      ComplaintReasonCode reasonCode,
      String detailText,
      LocalDateTime now) {
    return new CommunityComplaint(
        reporterUserId, targetType, targetId, reasonCode, detailText, now);
  }

  /**
   * @return 저장 후 채번된 신고 ID
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 신고 대상 유형
   */
  public ComplaintTargetType getTargetType() {
    return targetType;
  }

  /**
   * @return 유형에 대응하는 신고 대상 ID
   */
  public Long getTargetId() {
    return switch (targetType) {
      case POST -> targetPostId;
      case COMMENT -> targetCommentId;
      case REPORT -> targetReportId;
    };
  }

  /**
   * @return 표준 신고 사유
   */
  public ComplaintReasonCode getReasonCode() {
    return reasonCode;
  }

  /**
   * @return 현재 신고 처리 상태
   */
  public ComplaintStatus getStatus() {
    return status;
  }

  /**
   * @return 신고 생성 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
}
