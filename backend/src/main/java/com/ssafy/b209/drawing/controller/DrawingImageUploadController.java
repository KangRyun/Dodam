package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.request.UploadDrawingImageRequest;
import com.ssafy.b209.drawing.dto.response.UploadDrawingImageResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.service.DrawingImageUploadService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import com.ssafy.b209.storage.image.StoreImageCommand;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * HTP의 사진으로 시작하기 기능에 사용하는 전용 Multipart 업로드 API를 제공한다.
 *
 * <p>일반 Canvas 스냅샷의 {@code /snapshots} 계약과 분리하며, 저장 가능 여부와 HTP 주제 판정은 {@link
 * DrawingImageUploadService}에 위임한다.
 */
@Tag(name = "Drawing Image Upload", description = "HTP 사진으로 시작하기 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-sessions/{drawingSessionId}/upload")
public class DrawingImageUploadController {

  private final DrawingImageUploadService service;

  /**
   * HTP 원본 이미지 저장 서비스를 사용하는 Controller를 생성한다.
   *
   * @param service 업로드 검증·저장 서비스
   */
  public DrawingImageUploadController(DrawingImageUploadService service) {
    this.service = service;
  }

  /**
   * JPEG 또는 PNG 한 장을 HTP 현재 주제의 원본 Asset으로 저장한다.
   *
   * @param drawingSessionId HTP 단계 그림 세션 식별자
   * @param idempotencyKey 업로드 요청을 식별하는 멱등 키
   * @param image 업로드할 JPEG 또는 PNG
   * @param request 촬영 시각과 회전·자르기 Metadata
   * @return HTTP 201과 완료 요청에 사용할 {@code drawingAssetId}
   * @throws BusinessException 파일 Stream을 열 수 없거나 저장 규칙을 충족하지 못한 경우
   */
  @Operation(
      summary = "HTP 원본 이미지 업로드",
      description = "UPLOAD 방식으로 시작한 HTP HOUSE·TREE·PERSON 단계에 JPEG 또는 PNG 한 장을 저장합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "원본 이미지 저장 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "파일·Metadata 오류 또는 지원하지 않는 활동",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "업로드 불가 상태, 중복 또는 멱등 충돌",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "413",
        description = "10 MiB 파일 크기 제한 초과",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "422",
        description = "320~8192px 이미지 차원 제한 위반",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public ResponseEntity<ApiResponse<UploadDrawingImageResponse>> upload(
      @Parameter(description = "HTP 단계 그림 세션 식별자", required = true) @PathVariable @Positive
          Long drawingSessionId,
      @RequestHeader(name = "Idempotency-Key", required = false) String idempotencyKey,
      @RequestPart(name = "image", required = false) MultipartFile image,
      @Valid @RequestPart(name = "metadata", required = false) UploadDrawingImageRequest request) {
    if (image == null) {
      return created(service.upload(drawingSessionId, idempotencyKey, null, request));
    }
    try (InputStream inputStream = image.getInputStream()) {
      StoreImageCommand command =
          new StoreImageCommand(
              inputStream, image.getSize(), image.getContentType(), image.getOriginalFilename());
      return created(service.upload(drawingSessionId, idempotencyKey, command, request));
    } catch (IOException exception) {
      throw new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_FAILED, exception);
    }
  }

  private ResponseEntity<ApiResponse<UploadDrawingImageResponse>> created(
      UploadDrawingImageResponse response) {
    URI location = URI.create(response.previewUrl());
    return ResponseEntity.created(location)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
