package com.ssafy.b209.community.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.community.domain.CommunityPost;
import com.ssafy.b209.community.domain.PostStatus;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.dto.UpdatePostRequest;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.community.repository.CommunityPostRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class CommunityPostCommandServiceTest {

  private static final long AUTHOR_ID = 41L;
  private static final long OTHER_ID = 42L;
  private static final long POST_ID = 500L;
  private static final Instant FIXED_INSTANT = Instant.parse("2026-07-24T05:00:00Z");
  private static final LocalDateTime CREATED = LocalDateTime.parse("2026-07-23T00:00:00");

  @Mock private UserRepository userRepository;
  @Mock private CommunityPostRepository communityPostRepository;
  @Mock private CommunityAttachmentService communityAttachmentService;

  private CommunityPostCommandService service;

  @BeforeEach
  void setUp() {
    service =
        new CommunityPostCommandService(
            new CurrentAuthenticatedUserResolver(),
            userRepository,
            communityPostRepository,
            communityAttachmentService,
            Clock.fixed(FIXED_INSTANT, ZoneOffset.UTC));
    authenticateAs(AUTHOR_ID);
  }

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void updateReplacesFieldsAndReturnsDetailForAuthor() {
    CommunityPost post = postOwnedBy(AUTHOR_ID, PostType.GUARDIAN_STORY, false);
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.of(post));
    givenAuthor(AUTHOR_ID, UserRole.GUARDIAN, "작성자");

    PostDetailResponse response =
        service.updatePost(POST_ID, request(PostType.ACTIVITY_REVIEW, "새 제목", "새 본문", false));

    assertThat(post.getTitle()).isEqualTo("새 제목");
    assertThat(post.getContent()).isEqualTo("새 본문");
    assertThat(post.getPostType()).isEqualTo(PostType.ACTIVITY_REVIEW);
    assertThat(post.getUpdatedAt().toInstant(ZoneOffset.UTC)).isEqualTo(FIXED_INSTANT);
    assertThat(response.postId()).isEqualTo(POST_ID);
    assertThat(response.title()).isEqualTo("새 제목");
    assertThat(response.author().userId()).isEqualTo(AUTHOR_ID);
    assertThat(response.editableByMe()).isTrue();
    assertThat(response.updatedAt()).isEqualTo(FIXED_INSTANT);
    verify(communityAttachmentService).replace(AUTHOR_ID, POST_ID, null);
  }

  @Test
  void updateMasksAuthorWhenAnonymous() {
    CommunityPost post = postOwnedBy(AUTHOR_ID, PostType.GUARDIAN_STORY, false);
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.of(post));
    givenAuthor(AUTHOR_ID, UserRole.GUARDIAN, "작성자");

    PostDetailResponse response =
        service.updatePost(POST_ID, request(PostType.GUARDIAN_STORY, "제목", "본문", true));

    assertThat(response.anonymous()).isTrue();
    assertThat(response.author()).isNull();
  }

  @Test
  void updateReValidatesPermissionWhenPostTypeChangesToRestrictedType() {
    CommunityPost post = postOwnedBy(AUTHOR_ID, PostType.GUARDIAN_STORY, false);
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.of(post));
    givenAuthor(AUTHOR_ID, UserRole.GUARDIAN, "작성자");

    assertError(
        () -> service.updatePost(POST_ID, request(PostType.NOTICE, "제목", "본문", false)),
        CommunityErrorCode.POST_TYPE_NOT_ALLOWED);
    assertThat(post.getPostType()).isEqualTo(PostType.GUARDIAN_STORY);
  }

  @Test
  void updateSkipsPermissionReCheckWhenPostTypeUnchanged() {
    CommunityPost post = postOwnedBy(AUTHOR_ID, PostType.NOTICE, false);
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.of(post));
    givenAuthor(AUTHOR_ID, UserRole.GUARDIAN, "작성자");

    PostDetailResponse response =
        service.updatePost(POST_ID, request(PostType.NOTICE, "고친 공지", "본문", false));

    assertThat(response.title()).isEqualTo("고친 공지");
    assertThat(response.postType()).isEqualTo(PostType.NOTICE);
  }

  @Test
  void updateRejectsWhenRequesterIsNotAuthor() {
    CommunityPost post = postOwnedBy(OTHER_ID, PostType.GUARDIAN_STORY, false);
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.of(post));

    assertError(
        () -> service.updatePost(POST_ID, request(PostType.GUARDIAN_STORY, "제목", "본문", false)),
        CommunityErrorCode.POST_ACCESS_DENIED);
    Mockito.verify(userRepository, Mockito.never()).findById(Mockito.anyLong());
  }

  @Test
  void updateReturnsNotFoundWhenPostIsMissingOrDeleted() {
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.empty());

    assertError(
        () -> service.updatePost(POST_ID, request(PostType.GUARDIAN_STORY, "제목", "본문", false)),
        CommunityPostDetailErrorCode.POST_NOT_FOUND);
  }

  @Test
  void updateRejectsMissingAuthenticatedPrincipal() {
    SecurityContextHolder.clearContext();

    assertError(
        () -> service.updatePost(POST_ID, request(PostType.GUARDIAN_STORY, "제목", "본문", false)),
        AuthErrorCode.AUTHENTICATION_REQUIRED);
  }

  @Test
  void deleteSoftDeletesPostForAuthor() {
    CommunityPost post = postOwnedBy(AUTHOR_ID, PostType.GUARDIAN_STORY, false);
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.of(post));
    givenAuthor(AUTHOR_ID, UserRole.GUARDIAN, "작성자");

    service.deletePost(POST_ID);

    assertThat(post.getPostStatus()).isEqualTo(PostStatus.DELETED);
    assertThat(post.getDeletedAt().toInstant(ZoneOffset.UTC)).isEqualTo(FIXED_INSTANT);
    verify(communityAttachmentService).deleteByPostId(POST_ID);
  }

  @Test
  void deleteSoftDeletesPostForAdminWhoIsNotAuthor() {
    authenticateAs(OTHER_ID);
    CommunityPost post = postOwnedBy(AUTHOR_ID, PostType.GUARDIAN_STORY, false);
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.of(post));
    givenAuthor(OTHER_ID, UserRole.ADMIN, "관리자");

    service.deletePost(POST_ID);

    assertThat(post.getPostStatus()).isEqualTo(PostStatus.DELETED);
  }

  @Test
  void deleteRejectsNonAuthorNonAdmin() {
    authenticateAs(OTHER_ID);
    CommunityPost post = postOwnedBy(AUTHOR_ID, PostType.GUARDIAN_STORY, false);
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.of(post));
    givenAuthor(OTHER_ID, UserRole.GUARDIAN, "다른 사용자");

    assertError(() -> service.deletePost(POST_ID), CommunityErrorCode.POST_ACCESS_DENIED);
    assertThat(post.getPostStatus()).isEqualTo(PostStatus.ACTIVE);
  }

  @Test
  void deleteReturnsNotFoundWhenPostIsMissingOrDeleted() {
    given(communityPostRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.empty());

    assertError(() -> service.deletePost(POST_ID), CommunityPostDetailErrorCode.POST_NOT_FOUND);
  }

  private void authenticateAs(long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }

  private CommunityPost postOwnedBy(long authorId, PostType postType, boolean anonymous) {
    CommunityPost post = CommunityPost.create(authorId, postType, "제목", "본문", anonymous, CREATED);
    ReflectionTestUtils.setField(post, "id", POST_ID);
    return post;
  }

  private void givenAuthor(long userId, UserRole role, String nickname) {
    User user = Mockito.mock(User.class);
    given(user.getRole()).willReturn(role);
    Mockito.lenient().when(user.getId()).thenReturn(userId);
    Mockito.lenient().when(user.getNickname()).thenReturn(nickname);
    given(userRepository.findById(userId)).willReturn(Optional.of(user));
  }

  private UpdatePostRequest request(
      PostType postType, String title, String content, boolean anonymous) {
    return new UpdatePostRequest(postType, title, content, anonymous, null, null);
  }

  private void assertError(Runnable invocation, Object expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
