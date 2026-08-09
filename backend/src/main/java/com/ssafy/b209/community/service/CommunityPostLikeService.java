package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.domain.CommunityPost;
import com.ssafy.b209.community.domain.CommunityPostLike;
import com.ssafy.b209.community.domain.PostStatus;
import com.ssafy.b209.community.dto.PostLikeCommandResult;
import com.ssafy.b209.community.dto.PostLikeResponse;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.community.repository.CommunityPostLikeRepository;
import com.ssafy.b209.community.repository.CommunityPostRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증 사용자의 게시글 좋아요 등록·취소를 상태 기반 멱등 연산으로 처리한다.
 *
 * <p>대상 게시글을 쓰기 잠금으로 직렬화해 같은 게시글에 대한 중복 요청과 동시 요청이 유일 제약 오류로 노출되지 않게 한다.
 */
@Service
public class CommunityPostLikeService {

  private final CurrentAuthenticatedUserResolver userResolver;
  private final UserRepository userRepository;
  private final CommunityPostRepository postRepository;
  private final CommunityPostLikeRepository likeRepository;
  private final Clock clock;

  /** 좋아요 처리에 필요한 인증·게시글·좋아요 저장소를 주입한다. */
  @Autowired
  public CommunityPostLikeService(
      CurrentAuthenticatedUserResolver userResolver,
      UserRepository userRepository,
      CommunityPostRepository postRepository,
      CommunityPostLikeRepository likeRepository) {
    this(userResolver, userRepository, postRepository, likeRepository, Clock.systemUTC());
  }

  CommunityPostLikeService(
      CurrentAuthenticatedUserResolver userResolver,
      UserRepository userRepository,
      CommunityPostRepository postRepository,
      CommunityPostLikeRepository likeRepository,
      Clock clock) {
    this.userResolver = userResolver;
    this.userRepository = userRepository;
    this.postRepository = postRepository;
    this.likeRepository = likeRepository;
    this.clock = clock;
  }

  /**
   * 공개 게시글에 현재 사용자의 좋아요가 없으면 생성하고, 이미 있으면 현재 상태를 그대로 반환한다.
   *
   * @param postId 대상 게시글 ID
   * @return 좋아요 상태와 신규 생성 여부
   * @throws BusinessException 대상이 공개 게시글이 아니거나 사용자 역할이 보호자·전문가가 아닌 경우
   */
  @Transactional
  public PostLikeCommandResult likePost(Long postId) {
    Long userId = requireAllowedUserId();
    CommunityPost post = requirePublicPost(postId);
    boolean created =
        likeRepository
            .findByPostIdAndUserId(post.getId(), userId)
            .map(ignored -> false)
            .orElseGet(
                () -> {
                  likeRepository.saveAndFlush(
                      CommunityPostLike.create(post.getId(), userId, now()));
                  return true;
                });
    long likeCount = likeRepository.countByPostId(post.getId());
    return new PostLikeCommandResult(new PostLikeResponse(post.getId(), true, likeCount), created);
  }

  /**
   * 현재 사용자의 좋아요가 있으면 삭제하고, 없으면 변경 없이 성공 처리한다.
   *
   * @param postId 대상 게시글 ID
   * @throws BusinessException 대상이 공개 게시글이 아니거나 사용자 역할이 보호자·전문가가 아닌 경우
   */
  @Transactional
  public void unlikePost(Long postId) {
    Long userId = requireAllowedUserId();
    CommunityPost post = requirePublicPost(postId);
    likeRepository
        .findByPostIdAndUserId(post.getId(), userId)
        .ifPresent(
            like -> {
              likeRepository.delete(like);
              likeRepository.flush();
            });
  }

  private Long requireAllowedUserId() {
    Long userId = userResolver.requireUserId();
    User user =
        userRepository
            .findById(userId)
            .orElseThrow(() -> new BusinessException(AuthErrorCode.ACCESS_DENIED));
    if (user.getRole() != UserRole.GUARDIAN && user.getRole() != UserRole.EXPERT) {
      throw new BusinessException(AuthErrorCode.ACCESS_DENIED);
    }
    return userId;
  }

  private CommunityPost requirePublicPost(Long postId) {
    return postRepository
        .findNotDeletedByIdForUpdate(postId)
        .filter(post -> post.getPostStatus() == PostStatus.ACTIVE && post.isVisible())
        .orElseThrow(() -> new BusinessException(CommunityPostDetailErrorCode.POST_NOT_FOUND));
  }

  private LocalDateTime now() {
    return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
  }
}
