package com.ssafy.b209.community.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.community.dto.CommunityAttachmentFileResource;
import com.ssafy.b209.community.dto.CommunityAttachmentUploadResponse;
import com.ssafy.b209.community.service.CommunityAttachmentFileQueryService;
import com.ssafy.b209.community.service.CommunityAttachmentUploadService;
import com.ssafy.b209.global.exception.GlobalExceptionHandler;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.ByteArrayInputStream;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class CommunityAttachmentControllerTest {

  private final CommunityAttachmentUploadService uploadService =
      Mockito.mock(CommunityAttachmentUploadService.class);
  private final CommunityAttachmentFileQueryService queryService =
      Mockito.mock(CommunityAttachmentFileQueryService.class);
  private final MockMvc mockMvc =
      MockMvcBuilders.standaloneSetup(
              new CommunityAttachmentController(uploadService, queryService))
          .setControllerAdvice(new GlobalExceptionHandler())
          .build();

  @Test
  void uploadsImageAndReturnsFileReference() throws Exception {
    given(uploadService.upload(any(StoreImageCommand.class)))
        .willReturn(
            new CommunityAttachmentUploadResponse(
                "70e956a0-42b7-4d83-a79f-4d73e80a6acc",
                "image/png",
                1024,
                640,
                480,
                Instant.parse("2026-08-04T00:00:00Z")));
    MockMultipartFile image =
        new MockMultipartFile("image", "drawing.png", MediaType.IMAGE_PNG_VALUE, new byte[] {1});

    mockMvc
        .perform(multipart("/api/v1/community-files").file(image))
        .andExpect(status().isCreated())
        .andExpect(
            header()
                .string("Location", "/api/v1/community-files/70e956a0-42b7-4d83-a79f-4d73e80a6acc"))
        .andExpect(jsonPath("$.data.fileId").value("70e956a0-42b7-4d83-a79f-4d73e80a6acc"))
        .andExpect(jsonPath("$.data.widthPx").value(640));
  }

  @Test
  void preventsCachingAuthenticatedAttachedImage() throws Exception {
    given(queryService.getFile("file-id"))
        .willReturn(
            new CommunityAttachmentFileResource(
                new StoredImageContent(
                    new ByteArrayInputStream(new byte[] {1}), MediaType.IMAGE_PNG_VALUE, 1),
                true));

    mockMvc
        .perform(get("/api/v1/community-files/file-id/file"))
        .andExpect(status().isOk())
        .andExpect(header().string("Cache-Control", "no-store"));
  }
}
