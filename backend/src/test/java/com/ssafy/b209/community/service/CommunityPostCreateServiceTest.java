package com.ssafy.b209.community.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
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
import com.ssafy.b209.community.dto.CreatePostRequest;
import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.repository.CommunityPostRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class CommunityPostCreateServiceTest {

  private static final long AUTHOR_ID = 41L;
  private static final long SAVED_ID = 500L;
  private static final Instant FIXED_INSTANT = Instant.parse("2026-07-24T00:00:00Z");

  @Mock private UserRepository userRepository;
  @Mock private CommunityPostRepository communityPostRepository;

  private CommunityPostCreateService service;

  @BeforeEach
  void setUp() {
    service =
        new CommunityPostCreateService(
            new CurrentAuthenticatedUserResolver(),
            userRepository,
            communityPostRepository,
            Clock.fixed(FIXED_INSTANT, ZoneOffset.UTC));
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(AUTHOR_ID), null, List.of()));
  }

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void persistsActiveVisiblePostAndReturnsDetailWithNewPostDefaults() {
    givenAuthor(UserRole.GUARDIAN, "작성자");
    givenSaveAssignsId();

    PostDetailResponse response =
        service.createPost(request(PostType.GUARDIAN_STORY, "제목", "본문", false));

    ArgumentCaptor<CommunityPost> captor = ArgumentCaptor.forClass(CommunityPost.class);
    verify(communityPostRepository).saveAndFlush(captor.capture());
    CommunityPost saved = captor.getValue();
    assertThat(saved.getAuthorUserId()).isEqualTo(AUTHOR_ID);
    assertThat(saved.getPostType()).isEqualTo(PostType.GUARDIAN_STORY);
    assertThat(saved.getPostStatus()).isEqualTo(PostStatus.ACTIVE);
    assertThat(saved.isVisible()).isTrue();
    assertThat(saved.isAnonymous()).isFalse();
    assertThat(saved.getCreatedAt().toInstant(ZoneOffset.UTC)).isEqualTo(FIXED_INSTANT);

    assertThat(response.postId()).isEqualTo(SAVED_ID);
    assertThat(response.title()).isEqualTo("제목");
    assertThat(response.content()).isEqualTo("본문");
    assertThat(response.author().userId()).isEqualTo(AUTHOR_ID);
    assertThat(response.author().nickname()).isEqualTo("작성자");
    assertThat(response.author().profileImageUrl()).isNull();
    assertThat(response.attachments()).isEmpty();
    assertThat(response.templateData()).isEmpty();
    assertThat(response.likeCount()).isZero();
    assertThat(response.commentCount()).isZero();
    assertThat(response.likedByMe()).isFalse();
    assertThat(response.editableByMe()).isTrue();
    assertThat(response.createdAt()).isEqualTo(FIXED_INSTANT);
  }

  @Test
  void masksAuthorWhenPostIsAnonymous() {
    givenAuthor(UserRole.GUARDIAN, "작성자");
    givenSaveAssignsId();

    PostDetailResponse response =
        service.createPost(request(PostType.EXPERT_QNA, "제목", "본문", true));

    assertThat(response.anonymous()).isTrue();
    assertThat(response.author()).isNull();
  }

  @Test
  void allowsGeneralTypesForAnyAuthenticatedRole() {
    for (UserRole role : UserRole.values()) {
      for (PostType type :
          List.of(PostType.GUARDIAN_STORY, PostType.ACTIVITY_REVIEW, PostType.EXPERT_QNA)) {
        Mockito.reset(userRepository, communityPostRepository);
        givenAuthor(role, "작성자");
        givenSaveAssignsId();

        assertThat(service.createPost(request(type, "제목", "본문", false)).postId())
            .isEqualTo(SAVED_ID);
      }
    }
  }

  @Test
  void allowsExpertResourceTypesOnlyForExpertOrAdmin() {
    for (PostType type :
        List.of(PostType.EXPERT_COLUMN, PostType.ART_RESOURCE, PostType.DRAWING_GUIDE)) {
      assertAllowed(UserRole.EXPERT, type);
      assertAllowed(UserRole.ADMIN, type);
      assertDenied(UserRole.GUARDIAN, type, CommunityErrorCode.POST_TYPE_NOT_ALLOWED);
    }
  }

  @Test
  void allowsNoticeOnlyForAdmin() {
    assertAllowed(UserRole.ADMIN, PostType.NOTICE);
    assertDenied(UserRole.EXPERT, PostType.NOTICE, CommunityErrorCode.POST_TYPE_NOT_ALLOWED);
    assertDenied(UserRole.GUARDIAN, PostType.NOTICE, CommunityErrorCode.POST_TYPE_NOT_ALLOWED);
  }

  @Test
  void deniesWhenRoleIsNotAssigned() {
    givenAuthor(null, null);

    assertError(
        () -> service.createPost(request(PostType.GUARDIAN_STORY, "제목", "본문", false)),
        CommunityErrorCode.POST_ACCESS_DENIED);
    verify(communityPostRepository, never()).saveAndFlush(any());
  }

  @Test
  void deniesWhenAuthenticatedUserRowIsMissing() {
    given(userRepository.findById(AUTHOR_ID)).willReturn(Optional.empty());

    assertError(
        () -> service.createPost(request(PostType.GUARDIAN_STORY, "제목", "본문", false)),
        AuthErrorCode.ACCESS_DENIED);
    verify(communityPostRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsMissingAuthenticatedPrincipal() {
    SecurityContextHolder.clearContext();

    assertError(
        () -> service.createPost(request(PostType.GUARDIAN_STORY, "제목", "본문", false)),
        AuthErrorCode.AUTHENTICATION_REQUIRED);
  }

  private void assertAllowed(UserRole role, PostType type) {
    Mockito.reset(userRepository, communityPostRepository);
    givenAuthor(role, "작성자");
    givenSaveAssignsId();

    assertThat(service.createPost(request(type, "제목", "본문", false)).postId()).isEqualTo(SAVED_ID);
  }

  private void assertDenied(UserRole role, PostType type, Object expectedCode) {
    Mockito.reset(userRepository, communityPostRepository);
    givenAuthor(role, "작성자");

    assertError(() -> service.createPost(request(type, "제목", "본문", false)), expectedCode);
    verify(communityPostRepository, never()).saveAndFlush(any());
  }

  private void givenAuthor(UserRole role, String nickname) {
    User author = Mockito.mock(User.class);
    given(author.getRole()).willReturn(role);
    Mockito.lenient().when(author.getId()).thenReturn(AUTHOR_ID);
    Mockito.lenient().when(author.getNickname()).thenReturn(nickname);
    given(userRepository.findById(AUTHOR_ID)).willReturn(Optional.of(author));
  }

  private void givenSaveAssignsId() {
    given(communityPostRepository.saveAndFlush(any(CommunityPost.class)))
        .willAnswer(
            invocation -> {
              CommunityPost post = invocation.getArgument(0);
              ReflectionTestUtils.setField(post, "id", SAVED_ID);
              return post;
            });
  }

  private CreatePostRequest request(
      PostType postType, String title, String content, boolean anonymous) {
    return new CreatePostRequest(postType, title, content, anonymous, null, null);
  }

  private void assertError(Runnable invocation, Object expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
