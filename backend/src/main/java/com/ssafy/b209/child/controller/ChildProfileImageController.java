package com.ssafy.b209.child.controller;

import com.ssafy.b209.child.dto.response.ChildProfileImageUploadResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.service.ChildProfileImageUploadService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import com.ssafy.b209.storage.image.StoreImageCommand;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 아동 등록·수정 전에 사용할 프로필 이미지를 업로드하는 REST API를 제공한다.
 *
 * <p>원본 Storage Key는 노출하지 않고 후속 아동 API에 전달할 {@code profileImageFileId}만 반환한다.
 */
@Tag(name = "Child Profile Image", description = "아동 프로필 이미지 사전 업로드 API")
@Validated
@RestController
@RequestMapping("/api/v1/child-profile-images")
public class ChildProfileImageController {

  private final ChildProfileImageUploadService service;

  /**
   * 프로필 이미지 업로드 서비스를 사용하는 Controller를 생성한다.
   *
   * @param service 이미지 검증·저장 서비스
   */
  public ChildProfileImageController(ChildProfileImageUploadService service) {
    this.service = service;
  }

  /**
   * PNG 또는 JPEG 이미지를 최대 5 MiB까지 임시 저장한다.
   *
   * @param image 업로드할 프로필 이미지
   * @return HTTP 201과 아동 등록·수정에 사용할 파일 식별자
   * @throws BusinessException 파일 Stream을 읽을 수 없거나 업로드 정책을 위반한 경우
   */
  @Operation(
      summary = "아동 프로필 이미지 업로드",
      description = "PNG 또는 JPEG를 검증해 임시 저장하고 24시간 동안 유효한 profileImageFileId를 발급합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "프로필 이미지 업로드 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "파일 누락 또는 유효하지 않은 이미지",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "413",
        description = "5 MiB 크기 제한 초과",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "415",
        description = "PNG/JPEG 외 형식",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public ResponseEntity<ApiResponse<ChildProfileImageUploadResponse>> upload(
      @RequestPart(name = "image", required = false) MultipartFile image) {
    if (image == null) {
      return created(service.upload(null));
    }
    try (InputStream inputStream = image.getInputStream()) {
      ChildProfileImageUploadResponse response =
          service.upload(
              new StoreImageCommand(
                  inputStream,
                  image.getSize(),
                  image.getContentType(),
                  image.getOriginalFilename()));
      return created(response);
    } catch (IOException exception) {
      throw new BusinessException(ChildErrorCode.CHILD_PROFILE_IMAGE_UPLOAD_FAILED, exception);
    }
  }

  private ResponseEntity<ApiResponse<ChildProfileImageUploadResponse>> created(
      ChildProfileImageUploadResponse response) {
    URI location = URI.create("/api/v1/child-profile-images/" + response.profileImageFileId());
    return ResponseEntity.created(location)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
