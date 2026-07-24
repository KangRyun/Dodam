package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.domain.CommunityPost;
import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.dto.UpdatePostRequest;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.community.repository.CommunityPostRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Objects;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증된 사용자의 커뮤니티 게시글 수정·삭제 유스케이스를 조율한다.
 *
 * <p>수정은 작성자 본인만 허용하며 유형을 바꾸는 경우 유형별 작성 권한을 다시 검증한다. 삭제는 작성자 본인 또는 관리자만 허용하고 Soft Delete로 처리한다. 두
 * 유스케이스 모두 비관적 쓰기 잠금으로 대상 게시글을 조회하고, 삭제됐거나 없는 게시글은 조회되지 않는 게시글로 간주한다.
 */
@Service
public class CommunityPostCommandService {

  private final CurrentAuthenticatedUserResolver currentAuthenticatedUserResolver;
  private final UserRepository userRepository;
  private final CommunityPostRepository communityPostRepository;
  private final Clock clock;

  /**
   * 게시글 수정·삭제에 필요한 협력 객체를 주입한다.
   *
   * @param currentAuthenticatedUserResolver 검증된 Access JWT 사용자 확인 도구
   * @param userRepository 요청자 역할 확인 저장소
   * @param communityPostRepository 게시글 잠금 조회·상태 저장 저장소
   */
  @Autowired
  public CommunityPostCommandService(
      CurrentAuthenticatedUserResolver currentAuthenticatedUserResolver,
      UserRepository userRepository,
      CommunityPostRepository communityPostRepository) {
    this(
        currentAuthenticatedUserResolver,
        userRepository,
        communityPostRepository,
        Clock.systemUTC());
  }

  CommunityPostCommandService(
      CurrentAuthenticatedUserResolver currentAuthenticatedUserResolver,
      UserRepository userRepository,
      CommunityPostRepository communityPostRepository,
      Clock clock) {
    this.currentAuthenticatedUserResolver = currentAuthenticatedUserResolver;
    this.userRepository = userRepository;
    this.communityPostRepository = communityPostRepository;
    this.clock = clock;
  }

  /**
   * 작성자 본인의 게시글을 새 값으로 교체하고 상세 형태의 응답으로 반환한다.
   *
   * <p>유형을 바꾸는 경우에만 새 유형에 대한 작성 권한을 다시 검증한다.
   *
   * @param postId 수정할 게시글 식별자
   * @param request 교체할 게시글 정보
   * @return 수정된 게시글의 상세 응답
   * @throws BusinessException 인증 사용자가 없거나, 게시글이 없거나, 작성자 본인이 아니거나, 바꾸려는 유형을 작성할 권한이 없는 경우
   */
  @Transactional
  public PostDetailResponse updatePost(Long postId, UpdatePostRequest request) {
    Long currentUserId = currentAuthenticatedUserResolver.requireUserId();
    CommunityPost post =
        communityPostRepository
            .findNotDeletedByIdForUpdate(postId)
            .orElseThrow(() -> new BusinessException(CommunityPostDetailErrorCode.POST_NOT_FOUND));
    if (!Objects.equals(post.getAuthorUserId(), currentUserId)) {
      throw new BusinessException(CommunityErrorCode.POST_ACCESS_DENIED);
    }
    User author =
        userRepository
            .findById(currentUserId)
            .orElseThrow(() -> new BusinessException(AuthErrorCode.ACCESS_DENIED));
    UserRole role = author.getRole();
    if (role == null) {
      throw new BusinessException(CommunityErrorCode.POST_ACCESS_DENIED);
    }
    if (post.getPostType() != request.postType()) {
      CommunityPostWritePermission.verify(request.postType(), role);
    }

    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    post.update(request.postType(), request.title(), request.content(), request.anonymous(), now);
    return CommunityPostResponseMapper.toDetailResponse(post, author);
  }

  /**
   * 작성자 본인 또는 관리자의 요청으로 게시글을 Soft Delete한다.
   *
   * @param postId 삭제할 게시글 식별자
   * @throws BusinessException 인증 사용자가 없거나, 게시글이 없거나, 작성자 본인도 관리자도 아닌 경우
   */
  @Transactional
  public void deletePost(Long postId) {
    Long currentUserId = currentAuthenticatedUserResolver.requireUserId();
    CommunityPost post =
        communityPostRepository
            .findNotDeletedByIdForUpdate(postId)
            .orElseThrow(() -> new BusinessException(CommunityPostDetailErrorCode.POST_NOT_FOUND));
    User user =
        userRepository
            .findById(currentUserId)
            .orElseThrow(() -> new BusinessException(AuthErrorCode.ACCESS_DENIED));
    boolean author = Objects.equals(post.getAuthorUserId(), currentUserId);
    boolean admin = user.getRole() == UserRole.ADMIN;
    if (!author && !admin) {
      throw new BusinessException(CommunityErrorCode.POST_ACCESS_DENIED);
    }

    post.softDelete(LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC));
  }
}
