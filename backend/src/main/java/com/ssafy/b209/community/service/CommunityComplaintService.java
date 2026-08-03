package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.domain.CommentStatus;
import com.ssafy.b209.community.domain.CommunityComplaint;
import com.ssafy.b209.community.domain.PostStatus;
import com.ssafy.b209.community.dto.ComplaintCreateRequest;
import com.ssafy.b209.community.dto.ComplaintResponse;
import com.ssafy.b209.community.exception.CommunityCommentErrorCode;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.community.exception.CommunitySafetyErrorCode;
import com.ssafy.b209.community.repository.CommunityCommentRepository;
import com.ssafy.b209.community.repository.CommunityComplaintRepository;
import com.ssafy.b209.community.repository.CommunityPostRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.service.ReportDetailQueryService;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 신고 대상의 공개·접근 가능 여부를 확인하고 중복 없는 통합 신고를 접수한다. */
@Service
public class CommunityComplaintService {

  private final CurrentAuthenticatedUserResolver userResolver;
  private final CommunityComplaintRepository complaintRepository;
  private final CommunityPostRepository postRepository;
  private final CommunityCommentRepository commentRepository;
  private final ReportDetailQueryService reportDetailQueryService;
  private final Clock clock;

  /** 신고 처리에 필요한 인증, 대상 조회, 저장소와 서버 시계를 주입한다. */
  public CommunityComplaintService(
      CurrentAuthenticatedUserResolver userResolver,
      CommunityComplaintRepository complaintRepository,
      CommunityPostRepository postRepository,
      CommunityCommentRepository commentRepository,
      ReportDetailQueryService reportDetailQueryService,
      Clock clock) {
    this.userResolver = userResolver;
    this.complaintRepository = complaintRepository;
    this.postRepository = postRepository;
    this.commentRepository = commentRepository;
    this.reportDetailQueryService = reportDetailQueryService;
    this.clock = clock;
  }

  /**
   * 현재 사용자의 신고를 대기 상태로 한 번만 접수한다.
   *
   * @param request 대상과 사유가 포함된 신고 요청
   * @return 생성된 신고의 공개 정보
   * @throws BusinessException 대상이 없거나 접근할 수 없거나 동일 신고가 이미 있는 경우
   */
  @Transactional
  public ComplaintResponse createComplaint(ComplaintCreateRequest request) {
    Long reporterUserId = userResolver.requireUserId();
    requireAvailableTarget(reporterUserId, request);
    if (complaintRepository.existsDuplicate(
        reporterUserId, request.targetType(), request.targetId(), request.reasonCode())) {
      throw new BusinessException(CommunitySafetyErrorCode.COMPLAINT_ALREADY_EXISTS);
    }

    CommunityComplaint complaint =
        CommunityComplaint.create(
            reporterUserId,
            request.targetType(),
            request.targetId(),
            request.reasonCode(),
            normalizeDescription(request.description()),
            LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC));
    try {
      complaintRepository.saveAndFlush(complaint);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(CommunitySafetyErrorCode.COMPLAINT_ALREADY_EXISTS);
    }
    return new ComplaintResponse(
        complaint.getId(),
        complaint.getTargetType(),
        complaint.getTargetId(),
        complaint.getReasonCode(),
        complaint.getStatus(),
        complaint.getCreatedAt().toInstant(ZoneOffset.UTC));
  }

  private void requireAvailableTarget(Long reporterUserId, ComplaintCreateRequest request) {
    switch (request.targetType()) {
      case POST ->
          postRepository
              .findNotDeletedByIdForUpdate(request.targetId())
              .filter(post -> post.getPostStatus() == PostStatus.ACTIVE && post.isVisible())
              .orElseThrow(
                  () -> new BusinessException(CommunityPostDetailErrorCode.POST_NOT_FOUND));
      case COMMENT ->
          commentRepository
              .findNotDeletedByIdForUpdate(request.targetId())
              .filter(
                  comment ->
                      comment.getCommentStatus() == CommentStatus.ACTIVE && comment.isVisible())
              .orElseThrow(
                  () -> new BusinessException(CommunityCommentErrorCode.COMMENT_NOT_FOUND));
      case REPORT -> reportDetailQueryService.getReport(reporterUserId, request.targetId());
    }
  }

  private String normalizeDescription(String description) {
    return description == null || description.isBlank() ? null : description.trim();
  }
}
