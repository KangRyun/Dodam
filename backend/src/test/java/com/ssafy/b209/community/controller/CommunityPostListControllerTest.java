package com.ssafy.b209.community.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.filter.AccessTokenAuthenticationFilter;
import com.ssafy.b209.auth.filter.AuthFilterProperties;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.auth.token.JwtAccessTokenDecoder;
import com.ssafy.b209.community.dto.PostListPageResponse;
import com.ssafy.b209.community.dto.PostListQuery;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.service.CommunityPostListService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.exception.GlobalExceptionHandler;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class CommunityPostListControllerTest {

  private final JwtAccessTokenDecoder decoder = Mockito.mock(JwtAccessTokenDecoder.class);
  private final CommunityPostListService communityPostListService =
      Mockito.mock(CommunityPostListService.class);

  private MockMvc mockMvc;

  @BeforeEach
  void setUp() {
    mockMvc =
        MockMvcBuilders.standaloneSetup(new CommunityPostListController(communityPostListService))
            .setControllerAdvice(new GlobalExceptionHandler())
            .addFilters(
                new AccessTokenAuthenticationFilter(
                    decoder, new ObjectMapper(), new AuthFilterProperties(false)))
            .build();
  }

  @Test
  void rejectsRequestWithoutAccessToken() throws Exception {
    mockMvc
        .perform(get("/api/v1/posts"))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  @Test
  void returnsCommonPageResponseForAuthenticatedRequest() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    given(communityPostListService.getPosts(Mockito.any()))
        .willReturn(new PostListPageResponse(List.of(), 0, 20, 0, 0, true, true, false));

    mockMvc
        .perform(
            get("/api/v1/posts")
                .header("Authorization", "Bearer valid-token")
                .param("type", "EXPERT_COLUMN")
                .param("keyword", "그림 상담")
                .param("feed", "FOLLOWING")
                .param("authorRole", "EXPERT")
                .param("sort", "likeCount,asc"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.content").isEmpty());

    ArgumentCaptor<PostListQuery> queryCaptor = ArgumentCaptor.forClass(PostListQuery.class);
    Mockito.verify(communityPostListService).getPosts(queryCaptor.capture());
    assertThat(queryCaptor.getValue().type()).isEqualTo("EXPERT_COLUMN");
    assertThat(queryCaptor.getValue().keyword()).isEqualTo("그림 상담");
    assertThat(queryCaptor.getValue().feed()).isEqualTo("FOLLOWING");
    assertThat(queryCaptor.getValue().authorRole()).isEqualTo("EXPERT");
    assertThat(queryCaptor.getValue().sort()).isEqualTo("likeCount,asc");
  }

  @Test
  void returnsValidationFailedForInvalidQuery() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    given(communityPostListService.getPosts(Mockito.any()))
        .willThrow(new BusinessException(CommunityErrorCode.VALIDATION_FAILED));

    mockMvc
        .perform(
            get("/api/v1/posts")
                .header("Authorization", "Bearer valid-token")
                .param("sort", "unknown,desc"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"))
        .andExpect(jsonPath("$.message", containsString("요청 값")));
  }
}
