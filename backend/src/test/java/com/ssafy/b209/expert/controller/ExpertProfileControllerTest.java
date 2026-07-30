package com.ssafy.b209.expert.controller;

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
import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import com.ssafy.b209.expert.dto.request.CreateExpertProfileRequest;
import com.ssafy.b209.expert.dto.response.ExpertProfileResponse;
import com.ssafy.b209.expert.service.ExpertProfileCreationService;
import com.ssafy.b209.global.exception.GlobalExceptionHandler;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class ExpertProfileControllerTest {

  private final JwtAccessTokenDecoder decoder = Mockito.mock(JwtAccessTokenDecoder.class);
  private final ExpertProfileCreationService creationService =
      Mockito.mock(ExpertProfileCreationService.class);
  private MockMvc mockMvc;

  @BeforeEach
  void setUp() {
    mockMvc =
        MockMvcBuilders.standaloneSetup(new ExpertProfileController(creationService))
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
            post("/api/v1/experts/me/profile")
                .contentType(MediaType.APPLICATION_JSON)
                .content(validRequest()))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  @Test
  void returnsCreatedProfileAndLocation() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(57L));
    given(creationService.create(any(CreateExpertProfileRequest.class)))
        .willReturn(
            new ExpertProfileResponse(
                574L,
                "마음숲 상담사",
                null,
                "마음숲 센터",
                "상담사",
                6,
                List.of("CHILD_ART"),
                4,
                12,
                "소개",
                true,
                ExpertVerificationStatus.PENDING,
                "대전",
                0,
                false));

    mockMvc
        .perform(
            post("/api/v1/experts/me/profile")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content(validRequest()))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/experts/574"))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.expertId").value(574))
        .andExpect(jsonPath("$.data.verificationStatus").value("PENDING"));
  }

  @Test
  void rejectsIncompleteTargetAgeRange() throws Exception {
    given(decoder.decode("valid-token")).willReturn(new AuthenticatedUser(57L));
    String invalid = validRequest().replace("\"targetAgeMax\": 12,", "");

    mockMvc
        .perform(
            post("/api/v1/experts/me/profile")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content(invalid))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  private String validRequest() {
    return """
        {
          "displayName": "마음숲 상담사",
          "careerYears": 6,
          "specialties": ["CHILD_ART"],
          "targetAgeMin": 4,
          "targetAgeMax": 12,
          "consultationAvailable": true
        }
        """;
  }
}
