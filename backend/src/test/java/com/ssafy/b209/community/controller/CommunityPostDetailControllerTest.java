package com.ssafy.b209.community.controller;

import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.filter.AccessTokenAuthenticationFilter;
import com.ssafy.b209.auth.filter.AuthFilterProperties;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.auth.token.JwtAccessTokenDecoder;
import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.community.service.CommunityPostDetailService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.exception.GlobalExceptionHandler;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class CommunityPostDetailControllerTest {

  private final JwtAccessTokenDecoder decoder = Mockito.mock(JwtAccessTokenDecoder.class);
  private final CommunityPostDetailService communityPostDetailService =
      Mockito.mock(CommunityPostDetailService.class);

  private MockMvc mockMvc;

  @BeforeEach
  void setUp() {
    mockMvc =
        MockMvcBuilders.standaloneSetup(
                new CommunityPostDetailController(communityPostDetailService))
            .setControllerAdvice(new GlobalExceptionHandler())
            .addFilters(
                new AccessTokenAuthenticationFilter(
                    decoder, new ObjectMapper(), new AuthFilterProperties(false)))
            .build();
  }

  @Test
  void rejectsRequestWithoutAccessToken() throws Exception {
    mockMvc
        .perform(get("/api/v1/posts/101"))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  @Test
  void returnsEmptyAttachmentsForAuthenticatedRequest() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    given(communityPostDetailService.getPost(101L))
        .willReturn(
            new PostDetailResponse(
                101L,
                null,
                "제목",
                "본문",
                null,
                true,
                List.of(),
                List.of(),
                0L,
                0L,
                false,
                false,
                Instant.parse("2026-07-23T09:00:00Z"),
                Instant.parse("2026-07-23T09:00:00Z")));

    mockMvc
        .perform(get("/api/v1/posts/101").header("Authorization", "Bearer valid-token"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.attachments").isEmpty())
        .andExpect(jsonPath("$.data.author").doesNotExist());
  }

  @Test
  void returnsPostNotFoundForNonPublicPost() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    given(communityPostDetailService.getPost(101L))
        .willThrow(new BusinessException(CommunityPostDetailErrorCode.POST_NOT_FOUND));

    mockMvc
        .perform(get("/api/v1/posts/101").header("Authorization", "Bearer valid-token"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("POST_NOT_FOUND"));
  }
}
