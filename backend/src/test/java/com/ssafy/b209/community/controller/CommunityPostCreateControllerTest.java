package com.ssafy.b209.community.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.filter.AccessTokenAuthenticationFilter;
import com.ssafy.b209.auth.filter.AuthFilterProperties;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.auth.token.JwtAccessTokenDecoder;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.dto.CreatePostRequest;
import com.ssafy.b209.community.dto.PostDetailAuthorResponse;
import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.service.CommunityPostCreateService;
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

class CommunityPostCreateControllerTest {

  private final JwtAccessTokenDecoder decoder = Mockito.mock(JwtAccessTokenDecoder.class);
  private final CommunityPostCreateService communityPostCreateService =
      Mockito.mock(CommunityPostCreateService.class);

  private MockMvc mockMvc;

  @BeforeEach
  void setUp() {
    mockMvc =
        MockMvcBuilders.standaloneSetup(
                new CommunityPostCreateController(communityPostCreateService))
            .setControllerAdvice(new GlobalExceptionHandler())
            .addFilters(
                new AccessTokenAuthenticationFilter(
                    decoder, new ObjectMapper(), new AuthFilterProperties(false)))
            .build();
  }

  @Test
  void rejectsRequestWithoutAccessToken() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/posts")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"postType\":\"GUARDIAN_STORY\",\"title\":\"제목\",\"content\":\"본문\"}"))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  @Test
  void createsPostAndReturnsCreatedWithLocation() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    given(communityPostCreateService.createPost(any(CreatePostRequest.class)))
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
                Instant.parse("2026-07-24T00:00:00Z")));

    mockMvc
        .perform(
            post("/api/v1/posts")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"postType\":\"GUARDIAN_STORY\",\"title\":\"제목\",\"content\":\"본문\"}"))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/posts/500"))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.postId").value(500))
        .andExpect(jsonPath("$.data.editableByMe").value(true))
        .andExpect(jsonPath("$.data.attachments").isEmpty());
  }

  @Test
  void rejectsBlankTitleWithBadRequest() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));

    mockMvc
        .perform(
            post("/api/v1/posts")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"postType\":\"GUARDIAN_STORY\",\"title\":\"\",\"content\":\"본문\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsUnsupportedAttachmentType() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));

    mockMvc
        .perform(
            post("/api/v1/posts")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "postType":"GUARDIAN_STORY",
                      "title":"제목",
                      "content":"본문",
                      "attachments":[{"fileId":"file-id","type":"AUDIO"}]
                    }
                    """))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_003"));
  }

  @Test
  void returnsForbiddenWhenPostTypeNotAllowed() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(41L));
    given(communityPostCreateService.createPost(any(CreatePostRequest.class)))
        .willThrow(new BusinessException(CommunityErrorCode.POST_TYPE_NOT_ALLOWED));

    mockMvc
        .perform(
            post("/api/v1/posts")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"postType\":\"NOTICE\",\"title\":\"제목\",\"content\":\"본문\"}"))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("POST_TYPE_NOT_ALLOWED"));
  }
}
