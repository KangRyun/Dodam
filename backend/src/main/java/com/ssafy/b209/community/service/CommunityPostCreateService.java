package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.domain.CommunityPost;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.dto.CreatePostRequest;
import com.ssafy.b209.community.dto.PostDetailAuthorResponse;
import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.repository.CommunityPostRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증된 사용자의 커뮤니티 게시글 작성 유스케이스를 조율한다.
 *
 * <p>게시글 유형별 작성 권한을 역할로 검증한 뒤 활성·공개 상태로 단일 저장하고, 생성 결과를 상세 조회와 동일한 형태의 응답으로 반환한다. 첨부와 Template 저장
 * 구조는 이 범위에 없으므로 응답의 {@code attachments}와 {@code templateData}는 항상 빈 목록이다.
 */
@Service
public class CommunityPostCreateService {

  private final CurrentAuthenticatedUserResolver currentAuthenticatedUserResolver;
  private final UserRepository userRepository;
  private final CommunityPostRepository communityPostRepository;
  private final Clock clock;

  /**
   * 게시글 작성에 필요한 협력 객체를 주입한다.
   *
   * @param currentAuthenticatedUserResolver 검증된 Access JWT 사용자 확인 도구
   * @param userRepository 작성자 역할 확인 저장소
   * @param communityPostRepository 게시글 저장소
   */
  public CommunityPostCreateService(
      CurrentAuthenticatedUserResolver currentAuthenticatedUserResolver,
      UserRepository userRepository,
      CommunityPostRepository communityPostRepository) {
    this(
        currentAuthenticatedUserResolver,
        userRepository,
        communityPostRepository,
        Clock.systemUTC());
  }

  CommunityPostCreateService(
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
   * 게시글을 활성·공개 상태로 생성하고 상세 형태의 응답으로 반환한다.
   *
   * @param request 작성할 게시글 정보
   * @return 생성된 게시글의 상세 응답
   * @throws BusinessException 인증 사용자가 없거나, 역할이 없거나, 해당 유형을 작성할 권한이 없는 경우
   */
  @Transactional
  public PostDetailResponse createPost(CreatePostRequest request) {
    Long authorUserId = currentAuthenticatedUserResolver.requireUserId();
    User author =
        userRepository
            .findById(authorUserId)
            .orElseThrow(() -> new BusinessException(AuthErrorCode.ACCESS_DENIED));
    UserRole role = author.getRole();
    if (role == null) {
      throw new BusinessException(CommunityErrorCode.POST_ACCESS_DENIED);
    }
    verifyCreatePermission(request.postType(), role);

    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    CommunityPost saved =
        communityPostRepository.saveAndFlush(
            CommunityPost.create(
                authorUserId,
                request.postType(),
                request.title(),
                request.content(),
                request.anonymous(),
                now));
    return toResponse(saved, author);
  }

  private void verifyCreatePermission(PostType postType, UserRole role) {
    boolean allowed =
        switch (postType) {
          case NOTICE -> role == UserRole.ADMIN;
          case EXPERT_COLUMN, ART_RESOURCE, DRAWING_GUIDE ->
              role == UserRole.EXPERT || role == UserRole.ADMIN;
          case GUARDIAN_STORY, ACTIVITY_REVIEW, EXPERT_QNA -> true;
        };
    if (!allowed) {
      throw new BusinessException(CommunityErrorCode.POST_TYPE_NOT_ALLOWED);
    }
  }

  /**
   * 저장된 게시글을 상세 조회와 동일한 형태의 응답으로 변환한다.
   *
   * <p>신규 게시글이므로 집계는 0, 좋아요 여부는 {@code false}, 수정 가능 여부는 {@code true}로 고정한다. 작성자 프로필 이미지는 이 시점에
   * 조회하지 않으므로 {@code null}이며 상세 조회 API가 완전한 값을 제공한다.
   *
   * @param post 저장된 게시글 Entity
   * @param author 작성자 사용자
   * @return 생성 결과 상세 응답
   */
  private PostDetailResponse toResponse(CommunityPost post, User author) {
    PostDetailAuthorResponse authorResponse =
        post.isAnonymous()
            ? null
            : new PostDetailAuthorResponse(author.getId(), author.getNickname(), null);
    return new PostDetailResponse(
        post.getId(),
        post.getPostType(),
        post.getTitle(),
        post.getContent(),
        authorResponse,
        post.isAnonymous(),
        List.of(),
        List.of(),
        0L,
        0L,
        false,
        true,
        post.getCreatedAt().toInstant(ZoneOffset.UTC),
        post.getUpdatedAt().toInstant(ZoneOffset.UTC));
  }
}
