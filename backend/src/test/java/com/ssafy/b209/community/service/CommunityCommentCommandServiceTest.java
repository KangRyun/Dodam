package com.ssafy.b209.community.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.community.domain.CommentStatus;
import com.ssafy.b209.community.domain.CommunityComment;
import com.ssafy.b209.community.domain.CommunityPost;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.dto.CommentResponse;
import com.ssafy.b209.community.dto.CreateCommentRequest;
import com.ssafy.b209.community.dto.UpdateCommentRequest;
import com.ssafy.b209.community.exception.CommunityCommentErrorCode;
import com.ssafy.b209.community.repository.CommunityCommentRepository;
import com.ssafy.b209.community.repository.CommunityPostRepository;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
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
class CommunityCommentCommandServiceTest {

  private static final long AUTHOR_ID = 41L;
  private static final long OTHER_ID = 42L;
  private static final long POST_ID = 100L;
  private static final long COMMENT_ID = 500L;
  private static final Instant NOW = Instant.parse("2026-08-03T00:00:00Z");

  @Mock private UserRepository userRepository;
  @Mock private CommunityPostRepository postRepository;
  @Mock private CommunityCommentRepository commentRepository;
  @Mock private ExpertProfileRepository expertProfileRepository;

  private CommunityCommentCommandService service;

  @BeforeEach
  void setUp() {
    service =
        new CommunityCommentCommandService(
            new CurrentAuthenticatedUserResolver(),
            userRepository,
            postRepository,
            commentRepository,
            expertProfileRepository,
            Clock.fixed(NOW, ZoneOffset.UTC));
    authenticate(AUTHOR_ID);
  }

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void createsCommentForPublicPost() {
    given(postRepository.findNotDeletedByIdForUpdate(POST_ID))
        .willReturn(Optional.of(publicPost()));
    User author = user(UserRole.GUARDIAN);
    given(userRepository.findById(AUTHOR_ID)).willReturn(Optional.of(author));
    given(commentRepository.saveAndFlush(Mockito.any()))
        .willAnswer(
            invocation -> {
              CommunityComment comment = invocation.getArgument(0);
              ReflectionTestUtils.setField(comment, "id", COMMENT_ID);
              return comment;
            });

    CommentResponse response =
        service.createComment(POST_ID, new CreateCommentRequest("댓글입니다.", true));

    assertThat(response.commentId()).isEqualTo(COMMENT_ID);
    assertThat(response.postId()).isEqualTo(POST_ID);
    assertThat(response.author()).isNull();
    assertThat(response.anonymous()).isTrue();
    assertThat(response.editableByMe()).isTrue();
  }

  @Test
  void updateRejectsNonAuthor() {
    authenticate(OTHER_ID);
    given(commentRepository.findNotDeletedByIdForUpdate(COMMENT_ID))
        .willReturn(Optional.of(commentOwnedBy(AUTHOR_ID)));

    assertError(
        () -> service.updateComment(COMMENT_ID, new UpdateCommentRequest("가로채기")),
        CommunityCommentErrorCode.COMMENT_ACCESS_DENIED);
  }

  @Test
  void adminCanSoftDeleteAnotherUsersComment() {
    authenticate(OTHER_ID);
    CommunityComment comment = commentOwnedBy(AUTHOR_ID);
    given(commentRepository.findNotDeletedByIdForUpdate(COMMENT_ID))
        .willReturn(Optional.of(comment));
    User admin = user(UserRole.ADMIN);
    given(userRepository.findById(OTHER_ID)).willReturn(Optional.of(admin));

    service.deleteComment(COMMENT_ID);

    assertThat(comment.getCommentStatus()).isEqualTo(CommentStatus.DELETED);
    assertThat(comment.getDeletedAt().toInstant(ZoneOffset.UTC)).isEqualTo(NOW);
  }

  private CommunityPost publicPost() {
    CommunityPost post =
        CommunityPost.create(
            OTHER_ID,
            PostType.EXPERT_COLUMN,
            "제목",
            "본문",
            false,
            LocalDateTime.parse("2026-08-01T00:00:00"));
    ReflectionTestUtils.setField(post, "id", POST_ID);
    return post;
  }

  private CommunityComment commentOwnedBy(long userId) {
    CommunityComment comment =
        CommunityComment.create(
            POST_ID, userId, "원문", false, LocalDateTime.parse("2026-08-01T00:00:00"));
    ReflectionTestUtils.setField(comment, "id", COMMENT_ID);
    return comment;
  }

  private User user(UserRole role) {
    User user = Mockito.mock(User.class);
    given(user.getRole()).willReturn(role);
    Mockito.lenient().when(user.getId()).thenReturn(AUTHOR_ID);
    Mockito.lenient().when(user.getNickname()).thenReturn("작성자");
    return user;
  }

  private void authenticate(long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }

  private void assertError(Runnable invocation, Object expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
