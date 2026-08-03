package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.domain.CommunityComment;
import com.ssafy.b209.community.domain.CommunityPost;
import com.ssafy.b209.community.domain.PostStatus;
import com.ssafy.b209.community.dto.CommentAuthorResponse;
import com.ssafy.b209.community.dto.CommentResponse;
import com.ssafy.b209.community.dto.CreateCommentRequest;
import com.ssafy.b209.community.dto.UpdateCommentRequest;
import com.ssafy.b209.community.exception.CommunityCommentErrorCode;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.community.repository.CommunityCommentRepository;
import com.ssafy.b209.community.repository.CommunityPostRepository;
import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Objects;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 인증 사용자의 댓글 작성·수정·삭제 유스케이스를 수행한다. */
@Service
public class CommunityCommentCommandService {

  private final CurrentAuthenticatedUserResolver userResolver;
  private final UserRepository userRepository;
  private final CommunityPostRepository postRepository;
  private final CommunityCommentRepository commentRepository;
  private final ExpertProfileRepository expertProfileRepository;
  private final Clock clock;

  /**
   * 댓글 쓰기 작업에 필요한 저장소와 인증 사용자 확인 도구를 주입한다.
   *
   * @param userResolver 인증 사용자 확인 도구
   * @param userRepository 사용자 역할·공개 프로필 저장소
   * @param postRepository 댓글 대상 게시글 저장소
   * @param commentRepository 댓글 저장소
   * @param expertProfileRepository 전문가 검증 상태 저장소
   */
  @Autowired
  public CommunityCommentCommandService(
      CurrentAuthenticatedUserResolver userResolver,
      UserRepository userRepository,
      CommunityPostRepository postRepository,
      CommunityCommentRepository commentRepository,
      ExpertProfileRepository expertProfileRepository) {
    this(
        userResolver,
        userRepository,
        postRepository,
        commentRepository,
        expertProfileRepository,
        Clock.systemUTC());
  }

  CommunityCommentCommandService(
      CurrentAuthenticatedUserResolver userResolver,
      UserRepository userRepository,
      CommunityPostRepository postRepository,
      CommunityCommentRepository commentRepository,
      ExpertProfileRepository expertProfileRepository,
      Clock clock) {
    this.userResolver = userResolver;
    this.userRepository = userRepository;
    this.postRepository = postRepository;
    this.commentRepository = commentRepository;
    this.expertProfileRepository = expertProfileRepository;
    this.clock = clock;
  }

  /**
   * 공개 게시글에 댓글을 작성한다.
   *
   * @param postId 대상 게시글 ID
   * @param request 댓글 본문과 익명 여부
   * @return 생성된 댓글의 공개 응답
   * @throws BusinessException 인증 사용자 또는 공개 게시글을 확인할 수 없는 경우
   */
  @Transactional
  public CommentResponse createComment(Long postId, CreateCommentRequest request) {
    Long userId = userResolver.requireUserId();
    CommunityPost post =
        postRepository
            .findNotDeletedByIdForUpdate(postId)
            .filter(p -> p.getPostStatus() == PostStatus.ACTIVE && p.isVisible())
            .orElseThrow(() -> new BusinessException(CommunityPostDetailErrorCode.POST_NOT_FOUND));
    User author = requireUser(userId);
    verifyWritePermission(post, author);
    LocalDateTime now = now();
    CommunityComment comment =
        CommunityComment.create(post.getId(), userId, request.content(), request.anonymous(), now);
    commentRepository.saveAndFlush(comment);
    return toResponse(comment, author, userId);
  }

  /**
   * 작성자 본인의 댓글 본문을 수정한다.
   *
   * @param commentId 수정할 댓글 ID
   * @param request 교체할 본문
   * @return 수정된 댓글의 공개 응답
   * @throws BusinessException 댓글이 없거나 요청자가 작성자가 아닌 경우
   */
  @Transactional
  public CommentResponse updateComment(Long commentId, UpdateCommentRequest request) {
    Long userId = userResolver.requireUserId();
    CommunityComment comment = requireComment(commentId);
    if (!Objects.equals(comment.getAuthorUserId(), userId)) {
      throw new BusinessException(CommunityCommentErrorCode.COMMENT_ACCESS_DENIED);
    }
    User author = requireUser(userId);
    comment.updateContent(request.content(), now());
    return toResponse(comment, author, userId);
  }

  /**
   * 작성자 본인 또는 관리자의 댓글을 Soft Delete한다.
   *
   * @param commentId 삭제할 댓글 ID
   * @throws BusinessException 댓글이 없거나 삭제 권한이 없는 경우
   */
  @Transactional
  public void deleteComment(Long commentId) {
    Long userId = userResolver.requireUserId();
    CommunityComment comment = requireComment(commentId);
    User user = requireUser(userId);
    if (!Objects.equals(comment.getAuthorUserId(), userId) && user.getRole() != UserRole.ADMIN) {
      throw new BusinessException(CommunityCommentErrorCode.COMMENT_ACCESS_DENIED);
    }
    comment.softDelete(now());
  }

  private CommunityComment requireComment(Long commentId) {
    return commentRepository
        .findNotDeletedByIdForUpdate(commentId)
        .orElseThrow(() -> new BusinessException(CommunityCommentErrorCode.COMMENT_NOT_FOUND));
  }

  private User requireUser(Long userId) {
    return userRepository
        .findById(userId)
        .filter(user -> user.getRole() != null)
        .orElseThrow(() -> new BusinessException(AuthErrorCode.ACCESS_DENIED));
  }

  private LocalDateTime now() {
    return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
  }

  private CommentResponse toResponse(CommunityComment comment, User author, Long viewerId) {
    CommentAuthorResponse publicAuthor =
        comment.isAnonymous()
            ? null
            : new CommentAuthorResponse(
                author.getId(),
                author.getNickname(),
                author.getRole(),
                author.getProfileImageUrl());
    return new CommentResponse(
        comment.getId(),
        comment.getPostId(),
        publicAuthor,
        comment.isAnonymous(),
        comment.getContent(),
        isVerifiedExpert(author),
        false,
        Objects.equals(comment.getAuthorUserId(), viewerId) || author.getRole() == UserRole.ADMIN,
        comment.getCreatedAt().toInstant(ZoneOffset.UTC),
        comment.getUpdatedAt().toInstant(ZoneOffset.UTC));
  }

  private boolean isVerifiedExpert(User author) {
    return author.getRole() == UserRole.EXPERT
        && expertProfileRepository
            .findDetailByUserId(author.getId())
            .filter(profile -> profile.getVerificationStatus() == ExpertVerificationStatus.VERIFIED)
            .isPresent();
  }

  private void verifyWritePermission(CommunityPost post, User author) {
    boolean expertOnly =
        switch (post.getPostType()) {
          case GUARDIAN_STORY, ACTIVITY_REVIEW, EXPERT_QNA -> true;
          default -> false;
        };
    if (expertOnly && author.getRole() != UserRole.ADMIN && !isVerifiedExpert(author)) {
      throw new BusinessException(CommunityCommentErrorCode.COMMENT_WRITE_NOT_ALLOWED);
    }
  }
}
