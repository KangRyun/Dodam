package com.ssafy.b209.community.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.community.domain.PostFeed;
import com.ssafy.b209.community.domain.PostListSort.SortDirection;
import com.ssafy.b209.community.domain.PostListSort.SortField;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.dto.PostListQuery;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.repository.CommunityPostListPage;
import com.ssafy.b209.community.repository.CommunityPostListRepository;
import com.ssafy.b209.community.repository.CommunityPostListRow;
import com.ssafy.b209.community.repository.PostListSearchCriteria;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

@ExtendWith(MockitoExtension.class)
class CommunityPostListServiceTest {

  private static final long VIEWER_ID = 41L;

  @Mock private UserRepository userRepository;
  @Mock private CommunityPostListRepository communityPostListRepository;
  @Mock private User viewer;

  private CommunityPostListService service;

  @BeforeEach
  void setUp() {
    service =
        new CommunityPostListService(
            new CurrentAuthenticatedUserResolver(), userRepository, communityPostListRepository);
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(VIEWER_ID), null, List.of()));
    lenient().when(userRepository.findById(VIEWER_ID)).thenReturn(Optional.of(viewer));
    lenient().when(viewer.getRole()).thenReturn(UserRole.GUARDIAN);
  }

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void returnsContractFiltersCountsAndCurrentUserLike() {
    CommunityPostListRow row = row(false, UserRole.EXPERT, "보호자 닉네임", "전문가 표시명", 7L, 3L, true);
    given(communityPostListRepository.findPosts(org.mockito.ArgumentMatchers.any()))
        .willReturn(new CommunityPostListPage(List.of(row), 21));

    var response =
        service.getPosts(
            new PostListQuery(
                "EXPERT_COLUMN", " 그림 상담 ", "FOLLOWING", "EXPERT", "1", "10", "likeCount,desc"));

    ArgumentCaptor<PostListSearchCriteria> criteriaCaptor =
        ArgumentCaptor.forClass(PostListSearchCriteria.class);
    verify(communityPostListRepository).findPosts(criteriaCaptor.capture());
    PostListSearchCriteria criteria = criteriaCaptor.getValue();
    assertThat(criteria.postType()).isEqualTo(PostType.EXPERT_COLUMN);
    assertThat(criteria.keywordPattern()).isEqualTo("%그림 상담%");
    assertThat(criteria.feed()).isEqualTo(PostFeed.FOLLOWING);
    assertThat(criteria.authorRole()).isEqualTo(UserRole.EXPERT);
    assertThat(criteria.page()).isEqualTo(1);
    assertThat(criteria.size()).isEqualTo(10);
    assertThat(criteria.sort().field()).isEqualTo(SortField.LIKE_COUNT);
    assertThat(criteria.sort().direction()).isEqualTo(SortDirection.DESC);
    assertThat(criteria.viewerUserId()).isEqualTo(VIEWER_ID);
    assertThat(response.content()).hasSize(1);
    assertThat(response.content().getFirst().author().userId()).isEqualTo(20L);
    assertThat(response.content().getFirst().author().nickname()).isEqualTo("보호자 닉네임");
    assertThat(response.content().getFirst().likeCount()).isEqualTo(7L);
    assertThat(response.content().getFirst().commentCount()).isEqualTo(3L);
    assertThat(response.content().getFirst().likedByMe()).isTrue();
    assertThat(response.totalPages()).isEqualTo(3);
    assertThat(response.first()).isFalse();
    assertThat(response.hasNext()).isTrue();
  }

  @Test
  void masksEveryAuthorIdentifierForAnonymousPost() {
    given(communityPostListRepository.findPosts(org.mockito.ArgumentMatchers.any()))
        .willReturn(
            new CommunityPostListPage(
                List.of(row(true, UserRole.GUARDIAN, "실명", null, 0L, 0L, false)), 1));

    var response = service.getPosts(new PostListQuery(null, null, null, null, null, null, null));

    assertThat(response.content().getFirst().anonymous()).isTrue();
    assertThat(response.content().getFirst().author()).isNull();
  }

  @Test
  void rejectsInvalidPostTypePageSizeAndSort() {
    assertError(
        () -> service.getPosts(new PostListQuery("COLUMN", null, null, null, null, null, null)),
        CommunityErrorCode.VALIDATION_FAILED);
    assertError(
        () -> service.getPosts(new PostListQuery(null, null, null, null, "-1", null, null)),
        CommunityErrorCode.VALIDATION_FAILED);
    assertError(
        () -> service.getPosts(new PostListQuery(null, null, null, null, null, "101", null)),
        CommunityErrorCode.VALIDATION_FAILED);
    assertError(
        () ->
            service.getPosts(
                new PostListQuery(null, null, null, null, null, null, "updatedAt,desc")),
        CommunityErrorCode.VALIDATION_FAILED);
    assertError(
        () -> service.getPosts(new PostListQuery(null, null, "FRIENDS", null, null, null, null)),
        CommunityErrorCode.VALIDATION_FAILED);
    assertError(
        () -> service.getPosts(new PostListQuery(null, null, null, "ADMIN", null, null, null)),
        CommunityErrorCode.VALIDATION_FAILED);
  }

  @Test
  void rejectsKeywordLongerThanOneHundredCodePoints() {
    String keyword = "가".repeat(101);

    assertError(
        () -> service.getPosts(new PostListQuery(null, keyword, null, null, null, null, null)),
        CommunityErrorCode.VALIDATION_FAILED);
  }

  @Test
  void treatsBlankKeywordAsNoFilterAndEscapesLikeMetacharacters() {
    PostListSearchCriteria blank =
        service.toCriteria(new PostListQuery(null, "   ", null, null, null, null, null), VIEWER_ID);
    PostListSearchCriteria escaped =
        service.toCriteria(
            new PostListQuery(null, "50%_완료!", null, null, null, null, null), VIEWER_ID);

    assertThat(blank.keywordPattern()).isNull();
    assertThat(blank.feed()).isEqualTo(PostFeed.ALL);
    assertThat(escaped.keywordPattern()).isEqualTo("%50!%!_완료!!%");
  }

  @Test
  void rejectsMissingAuthenticatedPrincipal() {
    SecurityContextHolder.clearContext();

    assertError(
        () -> service.getPosts(new PostListQuery(null, null, null, null, null, null, null)),
        AuthErrorCode.AUTHENTICATION_REQUIRED);
  }

  @Test
  void returnsEmptyPageAsSuccessfulResponse() {
    given(communityPostListRepository.findPosts(org.mockito.ArgumentMatchers.any()))
        .willReturn(new CommunityPostListPage(List.of(), 0));

    var response = service.getPosts(new PostListQuery(null, null, null, null, null, null, null));

    assertThat(response.content()).isEmpty();
    assertThat(response.page()).isZero();
    assertThat(response.size()).isEqualTo(20);
    assertThat(response.totalPages()).isZero();
    assertThat(response.first()).isTrue();
    assertThat(response.last()).isTrue();
    assertThat(response.hasNext()).isFalse();
  }

  private CommunityPostListRow row(
      boolean anonymous,
      UserRole role,
      String nickname,
      String expertDisplayName,
      long likeCount,
      long commentCount,
      boolean likedByMe) {
    return new CommunityPostListRow(
        101L,
        PostType.EXPERT_COLUMN,
        "제목",
        "그림을 함께 보며 이야기하는 방법입니다.",
        anonymous,
        LocalDateTime.parse("2026-07-23T09:00:00"),
        LocalDateTime.parse("2026-07-23T10:00:00"),
        20L,
        nickname,
        likeCount,
        commentCount,
        likedByMe);
  }

  private void assertError(Runnable invocation, Object expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
