package com.ssafy.b209.expert.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import com.ssafy.b209.expert.dto.request.ReviewExpertVerificationRequest;
import com.ssafy.b209.expert.dto.response.ExpertVerificationResponse;
import com.ssafy.b209.expert.service.ExpertVerificationService;
import com.ssafy.b209.global.exception.GlobalExceptionHandler;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class AdminExpertVerificationControllerTest {

  private final ExpertVerificationService service = Mockito.mock(ExpertVerificationService.class);
  private MockMvc mockMvc;

  @BeforeEach
  void setUp() {
    mockMvc =
        MockMvcBuilders.standaloneSetup(new AdminExpertVerificationController(service))
            .setControllerAdvice(new GlobalExceptionHandler())
            .build();
  }

  @Test
  void returnsApprovedProfileAndCredentialStatuses() throws Exception {
    given(service.review(eq(9L), any(ReviewExpertVerificationRequest.class)))
        .willReturn(
            new ExpertVerificationResponse(
                9L,
                ExpertVerificationStatus.VERIFIED,
                List.of(
                    new ExpertVerificationResponse.CredentialStatus(
                        31L, ExpertVerificationStatus.VERIFIED)),
                Instant.parse("2026-08-03T02:00:00Z")));

    mockMvc
        .perform(
            patch("/api/v1/admin/experts/{expertId}/verification", 9L)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "status":"VERIFIED",
                      "verifiedCredentialIds":[31],
                      "rejectionReason":null,
                      "internalNote":"증빙 확인 완료"
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.expertId").value(9))
        .andExpect(jsonPath("$.data.verificationStatus").value("VERIFIED"))
        .andExpect(jsonPath("$.data.credentials[0].credentialId").value(31));
  }

  @Test
  void rejectsMissingVerifiedCredentialIds() throws Exception {
    mockMvc
        .perform(
            patch("/api/v1/admin/experts/{expertId}/verification", 9L)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"status\":\"VERIFIED\"}"))
        .andExpect(status().isBadRequest());
  }
}
