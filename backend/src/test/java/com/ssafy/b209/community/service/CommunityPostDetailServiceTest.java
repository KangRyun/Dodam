package com.ssafy.b209.community.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.community.repository.CommunityPostDetailRepository;
import com.ssafy.b209.community.repository.CommunityPostDetailRow;
import com.ssafy.b209.community.repository.CommunityPostTemplateFieldRow;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

@ExtendWith(MockitoExtension.class)
class CommunityPostDetailServiceTest {

  private static final long POST_ID = 101L;
  private static final long VIEWER_ID = 41L;

  @Mock private CommunityPostDetailRepository communityPostDetailRepository;
  @Mock private CommunityAttachmentService communityAttachmentService;

  private CommunityPostDetailService service;

  @BeforeEach
  void setUp() {
    service =
        new CommunityPostDetailService(
            new CurrentAuthenticatedUserResolver(),
            communityPostDetailRepository,
            communityAttachmentService);
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(VIEWER_ID), null, List.of()));
  }

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void returnsPublicPostWithOrderedTemplateDataAndCurrentUserAggregates() {
    given(communityPostDetailRepository.findPublicPost(POST_ID, VIEWER_ID))
        .willReturn(Optional.of(post(false, 20L, true)));
    given(communityPostDetailRepository.findTemplateFieldsByPostId(POST_ID))
        .willReturn(
            List.of(
                new CommunityPostTemplateFieldRow("mood", "STRING", "기쁜 날", 0),
                new CommunityPostTemplateFieldRow("count", "NUMBER", "0012", 1)));

    var response = service.getPost(POST_ID);

    assertThat(response.postId()).isEqualTo(POST_ID);
    assertThat(response.content()).isEqualTo("본문 전체");
    assertThat(response.author().userId()).isEqualTo(20L);
    assertThat(response.author().nickname()).isEqualTo("작성자");
    assertThat(response.author().profileImageUrl()).isEqualTo("https://example.test/profile.png");
    assertThat(response.attachments()).isEmpty();
    assertThat(response.templateData())
        .extracting(template -> template.fieldCode())
        .containsExactly("mood", "count");
    assertThat(response.templateData().get(1).value()).isEqualTo("0012");
    assertThat(response.likeCount()).isEqualTo(7L);
    assertThat(response.commentCount()).isEqualTo(3L);
    assertThat(response.likedByMe()).isTrue();
    assertThat(response.editableByMe()).isTrue();
    verify(communityPostDetailRepository).findTemplateFieldsByPostId(POST_ID);
  }

  @Test
  void masksAnonymousAuthorAndDoesNotExposeInternalStorageData() throws Exception {
    given(communityPostDetailRepository.findPublicPost(POST_ID, VIEWER_ID))
        .willReturn(Optional.of(post(true, VIEWER_ID, false)));
    given(communityPostDetailRepository.findTemplateFieldsByPostId(POST_ID)).willReturn(List.of());

    var response = service.getPost(POST_ID);
    String json =
        new ObjectMapper().registerModule(new JavaTimeModule()).writeValueAsString(response);

    assertThat(response.author()).isNull();
    assertThat(response.attachments()).isEmpty();
    assertThat(json).doesNotContain("작성자");
    assertThat(json).doesNotContain("profile.png");
    assertThat(json).doesNotContain("storageKey");
    assertThat(json).doesNotContain("local/");
    assertThat(json).doesNotContain("SELECT");
  }

  @Test
  void returnsPostNotFoundForMissingOrNonPublicPost() {
    given(communityPostDetailRepository.findPublicPost(POST_ID, VIEWER_ID))
        .willReturn(Optional.empty());

    assertError(() -> service.getPost(POST_ID), CommunityPostDetailErrorCode.POST_NOT_FOUND);
  }

  @Test
  void returnsNotEditableWhenAuthorDoesNotMatchOrPostIsAnonymous() {
    given(communityPostDetailRepository.findPublicPost(POST_ID, VIEWER_ID))
        .willReturn(Optional.of(post(false, 20L, false)));
    given(communityPostDetailRepository.findTemplateFieldsByPostId(POST_ID)).willReturn(List.of());

    assertThat(service.getPost(POST_ID).editableByMe()).isFalse();
  }

  @Test
  void rejectsMissingAuthenticatedPrincipal() {
    SecurityContextHolder.clearContext();

    assertError(() -> service.getPost(POST_ID), AuthErrorCode.AUTHENTICATION_REQUIRED);
  }

  private CommunityPostDetailRow post(boolean anonymous, long authorId, boolean editableByMe) {
    return new CommunityPostDetailRow(
        POST_ID,
        PostType.GUARDIAN_STORY,
        "제목",
        "본문 전체",
        anonymous,
        LocalDateTime.parse("2026-07-23T09:00:00"),
        LocalDateTime.parse("2026-07-23T10:00:00"),
        authorId,
        "작성자",
        "https://example.test/profile.png",
        7L,
        3L,
        true,
        editableByMe);
  }

  private void assertError(Runnable invocation, Object expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
