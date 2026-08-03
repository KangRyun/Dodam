package com.ssafy.b209.expert.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import com.ssafy.b209.expert.dto.response.ExpertCredentialResponse;
import com.ssafy.b209.expert.service.ExpertCredentialUploadService;
import com.ssafy.b209.storage.credential.CredentialFileStorageProperties;
import java.time.Instant;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ExpertCredentialController.class)
@org.springframework.context.annotation.Import(
    com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class ExpertCredentialControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private ExpertCredentialUploadService uploadService;
  @MockitoBean private CredentialFileStorageProperties storageProperties;

  @Test
  void uploadsCredentialEvidence() throws Exception {
    given(storageProperties.maxSize()).willReturn(10_485_760L);
    MockMultipartFile file =
        new MockMultipartFile(
            "file", "license.pdf", MediaType.APPLICATION_PDF_VALUE, "%PDF-1.7\n".getBytes());
    MockMultipartFile metadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {
              "credentialType":"ART_THERAPIST",
              "credentialName":"미술심리상담사 1급",
              "issuer":"한국상담협회",
              "issuedAt":"2025-03-01",
              "credentialNumberMasked":"25-***-1234"
            }
            """
                .getBytes());
    given(uploadService.upload(any(), any()))
        .willReturn(
            new ExpertCredentialResponse(
                31L,
                "ART_THERAPIST",
                "미술심리상담사 1급",
                "한국상담협회",
                LocalDate.parse("2025-03-01"),
                "25-***-1234",
                ExpertVerificationStatus.PENDING,
                "license.pdf",
                MediaType.APPLICATION_PDF_VALUE,
                9L,
                Instant.parse("2026-08-03T00:00:00Z")));

    mockMvc
        .perform(multipart("/api/v1/experts/me/credentials").file(file).file(metadata))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/experts/me/credentials/31"))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.credentialId").value(31))
        .andExpect(jsonPath("$.data.credentialType").value("ART_THERAPIST"))
        .andExpect(jsonPath("$.data.storageKey").doesNotExist());
  }

  @Test
  void rejectsMissingFile() throws Exception {
    given(storageProperties.maxSize()).willReturn(10_485_760L);
    MockMultipartFile metadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {"credentialType":"ART_THERAPIST","credentialName":"자격명","issuer":"기관"}
            """
                .getBytes());

    mockMvc
        .perform(multipart("/api/v1/experts/me/credentials").file(metadata))
        .andExpect(status().isBadRequest());
  }
}
