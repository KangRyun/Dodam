package com.ssafy.b209.consent.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import com.ssafy.b209.consent.dto.request.CreateConsentRequest;
import com.ssafy.b209.consent.dto.response.ConsentRegistrationResponse;
import com.ssafy.b209.consent.dto.response.ConsentTermResponse;
import com.ssafy.b209.consent.service.ConsentRegistrationService;
import com.ssafy.b209.consent.service.ConsentTermQueryService;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ConsentController.class)
class ConsentControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private CurrentAuthenticatedUserResolver currentUserResolver;
  @MockitoBean private ConsentRegistrationService registrationService;
  @MockitoBean private ConsentTermQueryService termQueryService;

  @Test
  void returnsActiveTermsForTheAuthenticatedUser() throws Exception {
    when(currentUserResolver.requireUserId()).thenReturn(41L);
    when(termQueryService.getActiveTerms(null, null))
        .thenReturn(
            List.of(
                new ConsentTermResponse(
                    1L,
                    "SERVICE_TOS",
                    ConsentTargetScope.USER,
                    true,
                    "v1",
                    "서비스 이용약관",
                    "https://example.com/tos",
                    Instant.parse("2026-07-20T00:00:00Z"))));

    mockMvc
        .perform(get("/api/v1/consents/terms"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data[0].termId").value(1))
        .andExpect(jsonPath("$.data[0].termCode").value("SERVICE_TOS"))
        .andExpect(jsonPath("$.data[0].targetScope").value("USER"))
        .andExpect(jsonPath("$.data[0].required").value(true));
  }

  @Test
  void registersConsentHistoryWithAuthenticatedActorAndRequestEvidence() throws Exception {
    when(currentUserResolver.requireUserId()).thenReturn(41L);
    when(registrationService.register(
            eq(41L), any(CreateConsentRequest.class), any(), eq("app/1.0")))
        .thenReturn(
            new ConsentRegistrationResponse(null, 2, true, LocalDateTime.of(2026, 7, 23, 0, 0)));

    mockMvc
        .perform(
            post("/api/v1/consents")
                .contentType(MediaType.APPLICATION_JSON)
                .header("User-Agent", "app/1.0")
                .content(
                    """
                    {
                      "agreements": [
                        {"termId": 1, "action": "AGREE"},
                        {"termId": 2, "action": "AGREE"}
                      ]
                    }
                    """))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.recordedCount").value(2))
        .andExpect(jsonPath("$.data.requiredConsentsSatisfied").value(true));

    verify(registrationService)
        .register(eq(41L), any(CreateConsentRequest.class), any(), eq("app/1.0"));
  }

  @Test
  void validatesAgreementListAndTermFields() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/consents")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {"agreements":[{"termId":0,"action":null}]}
                    """))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.success").value(false));
  }
}
