package com.ssafy.b209.community.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.filter.AccessTokenAuthenticationFilter;
import com.ssafy.b209.auth.filter.AuthFilterProperties;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.auth.token.JwtAccessTokenDecoder;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.dto.PostDetailAuthorResponse;
import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.dto.UpdatePostRequest;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.community.service.CommunityPostCommandService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.exception.GlobalExceptionHandler;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class CommunityPostCommandControllerTest {

  private static final String BODY =
      "{\"postType\":\"GUARDIAN_STORY\",\"title\":\"제목\",\"content\":\"본문\"}";

  private final JwtAccessTokenDecoder decoder = Mockito.mock(JwtAccessTokenDecoder.class);
  private final CommunityPostCommandService communityPostCommandService =
      Mockito.mock(CommunityPostCommandService.class);

  private MockMvc mockMvc;

  @BeforeEach
  void setUp() {
    mockMvc =
        MockMvcBuilders.standaloneSetup(
                new CommunityPostCommandController(communityPostCommandService))
            .setControllerAdvice(new GlobalExceptionHandler())
            .addFilters(
                new AccessTokenAuthenticationFilter(
                    decoder, new ObjectMapper(), new AuthFilterProperties(false)))
            .build();
  }

  @Test
  void updateRejectsRequestWithoutAccessToken() throws Exception {
    mockMvc
        .perform(patch("/api/v1/posts/500").contentType(MediaType.APPLICATION_JSON).content(BODY))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  @Test
  void updateReturnsOkWithUpdatedDetail() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    given(communityPostCommandService.updatePost(eq(500L), any(UpdatePostRequest.class)))
        .willReturn(
            new PostDetailResponse(
                500L,
                PostType.GUARDIAN_STORY,
                "제목",
                "본문",
                new PostDetailAuthorResponse(41L, "작성자", null),
                false,
                List.of(),
                List.of(),
                0L,
                0L,
                false,
                true,
                Instant.parse("2026-07-24T00:00:00Z"),
                Instant.parse("2026-07-24T05:00:00Z")));

    mockMvc
        .perform(
            patch("/api/v1/posts/500")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content(BODY))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.postId").value(500))
        .andExpect(jsonPath("$.data.editableByMe").value(true));
  }

  @Test
  void updateRejectsBlankTitleWithBadRequest() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));

    mockMvc
        .perform(
            patch("/api/v1/posts/500")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"postType\":\"GUARDIAN_STORY\",\"title\":\"\",\"content\":\"본문\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void updateReturnsForbiddenWhenNotAuthor() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    given(communityPostCommandService.updatePost(eq(500L), any(UpdatePostRequest.class)))
        .willThrow(new BusinessException(CommunityErrorCode.POST_ACCESS_DENIED));

    mockMvc
        .perform(
            patch("/api/v1/posts/500")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content(BODY))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("POST_ACCESS_DENIED"));
  }

  @Test
  void updateReturnsNotFoundWhenPostMissing() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    given(communityPostCommandService.updatePost(eq(500L), any(UpdatePostRequest.class)))
        .willThrow(new BusinessException(CommunityPostDetailErrorCode.POST_NOT_FOUND));

    mockMvc
        .perform(
            patch("/api/v1/posts/500")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content(BODY))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("POST_NOT_FOUND"));
  }

  @Test
  void deleteRejectsRequestWithoutAccessToken() throws Exception {
    mockMvc
        .perform(delete("/api/v1/posts/500"))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  @Test
  void deleteReturnsNoContent() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));

    mockMvc
        .perform(delete("/api/v1/posts/500").header("Authorization", "Bearer valid-token"))
        .andExpect(status().isNoContent());
  }

  @Test
  void deleteReturnsForbiddenWhenNotAuthorNorAdmin() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    willThrow(new BusinessException(CommunityErrorCode.POST_ACCESS_DENIED))
        .given(communityPostCommandService)
        .deletePost(500L);

    mockMvc
        .perform(delete("/api/v1/posts/500").header("Authorization", "Bearer valid-token"))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("POST_ACCESS_DENIED"));
  }

  @Test
  void deleteReturnsNotFoundWhenPostMissing() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    willThrow(new BusinessException(CommunityPostDetailErrorCode.POST_NOT_FOUND))
        .given(communityPostCommandService)
        .deletePost(500L);

    mockMvc
        .perform(delete("/api/v1/posts/500").header("Authorization", "Bearer valid-token"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("POST_NOT_FOUND"));
  }
}
