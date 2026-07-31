package com.ssafy.b209.child.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.child.dto.response.ChildProfileImageUploadResponse;
import com.ssafy.b209.child.service.ChildProfileImageUploadService;
import com.ssafy.b209.storage.image.StoreImageCommand;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ChildProfileImageController.class)
@org.springframework.context.annotation.Import(
    com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class ChildProfileImageControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private ChildProfileImageUploadService service;

  @Test
  void uploadsAChildProfileImage() throws Exception {
    MockMultipartFile image =
        new MockMultipartFile("image", "profile.png", MediaType.IMAGE_PNG_VALUE, new byte[] {1});
    given(service.upload(any(StoreImageCommand.class)))
        .willReturn(
            new ChildProfileImageUploadResponse(
                "d20f42a9-6a55-4c91-b4b0-b6c79b8bd121",
                MediaType.IMAGE_PNG_VALUE,
                1024,
                320,
                320,
                Instant.parse("2026-08-01T00:00:00Z")));

    mockMvc
        .perform(multipart("/api/v1/child-profile-images").file(image))
        .andExpect(status().isCreated())
        .andExpect(
            header()
                .string(
                    "Location",
                    "/api/v1/child-profile-images/d20f42a9-6a55-4c91-b4b0-b6c79b8bd121"))
        .andExpect(
            jsonPath("$.data.profileImageFileId").value("d20f42a9-6a55-4c91-b4b0-b6c79b8bd121"))
        .andExpect(jsonPath("$.data.contentType").value("image/png"))
        .andExpect(jsonPath("$.data.fileSizeBytes").value(1024))
        .andExpect(jsonPath("$.data.widthPx").value(320))
        .andExpect(jsonPath("$.data.heightPx").value(320))
        .andExpect(jsonPath("$.data.storageKey").doesNotExist());
  }
}
