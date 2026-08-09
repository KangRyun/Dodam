package com.ssafy.b209.community.controller;

import com.ssafy.b209.community.dto.CommunityAttachmentFileResource;
import com.ssafy.b209.community.dto.CommunityAttachmentUploadResponse;
import com.ssafy.b209.community.exception.CommunityAttachmentErrorCode;
import com.ssafy.b209.community.service.CommunityAttachmentFileQueryService;
import com.ssafy.b209.community.service.CommunityAttachmentUploadService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/** 커뮤니티 게시글 이미지의 사전 업로드와 인증 Proxy 조회 API를 제공한다. */
@RestController
@RequestMapping("/api/v1/community-files")
public class CommunityAttachmentController {

  private final CommunityAttachmentUploadService uploadService;
  private final CommunityAttachmentFileQueryService queryService;

  /**
   * 첨부 이미지 업로드와 인증 조회 유스케이스를 구성한다.
   *
   * @param uploadService 이미지 사전 업로드 서비스
   * @param queryService 권한 기반 이미지 조회 서비스
   */
  public CommunityAttachmentController(
      CommunityAttachmentUploadService uploadService,
      CommunityAttachmentFileQueryService queryService) {
    this.uploadService = uploadService;
    this.queryService = queryService;
  }

  /**
   * 게시글 작성·수정 전에 PNG 또는 JPEG 이미지를 최대 5 MiB까지 임시 저장한다.
   *
   * @param image 업로드할 첨부 이미지
   * @return HTTP 201과 게시글 요청에 사용할 파일 ID
   */
  @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public ResponseEntity<ApiResponse<CommunityAttachmentUploadResponse>> upload(
      @RequestPart(name = "image", required = false) MultipartFile image) {
    if (image == null) {
      return created(uploadService.upload(null));
    }
    try (InputStream inputStream = image.getInputStream()) {
      return created(
          uploadService.upload(
              new StoreImageCommand(
                  inputStream,
                  image.getSize(),
                  image.getContentType(),
                  image.getOriginalFilename())));
    } catch (IOException exception) {
      throw new BusinessException(CommunityAttachmentErrorCode.UPLOAD_FAILED, exception);
    }
  }

  /**
   * 소유한 임시 파일 또는 열람 가능한 공개 게시글의 첨부 이미지를 반환한다.
   *
   * @param fileId 외부 파일 ID
   * @return JWT 인증이 적용된 이미지 Stream
   */
  @GetMapping("/{fileId}/file")
  public ResponseEntity<StreamingResponseBody> getFile(@PathVariable String fileId) {
    CommunityAttachmentFileResource resource = queryService.getFile(fileId);
    StoredImageContent content = resource.content();
    StreamingResponseBody body =
        outputStream -> {
          try (StoredImageContent opened = content) {
            opened.inputStream().transferTo(outputStream);
          }
        };
    return ResponseEntity.ok()
        .cacheControl(CacheControl.noStore())
        .contentType(MediaType.parseMediaType(content.contentType()))
        .contentLength(content.size())
        .body(body);
  }

  private ResponseEntity<ApiResponse<CommunityAttachmentUploadResponse>> created(
      CommunityAttachmentUploadResponse response) {
    return ResponseEntity.created(URI.create("/api/v1/community-files/" + response.fileId()))
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
