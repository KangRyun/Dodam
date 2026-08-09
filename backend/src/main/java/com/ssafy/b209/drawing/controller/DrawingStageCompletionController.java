package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.request.CompleteDrawingStageRequest;
import com.ssafy.b209.drawing.dto.response.CompleteDrawingStageResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.service.DrawingStageCompletionService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 그림 편집 종료 시 최종 이미지와 완료 Metadata를 받는 그림 단계 완료 API를 제공한다.
 *
 * <p>Multipart Part를 Storage 명령으로 변환하고 공통 응답을 조립한다. FINAL 저장, 분석 실행, 멱등성과 상태 전이 규칙은 {@link
 * DrawingStageCompletionService}에 위임한다.
 */
@Tag(name = "Drawing Sessions", description = "그림 활동 세션 API")
@Validated
@RestController
public class DrawingStageCompletionController {

  private final DrawingStageCompletionService drawingStageCompletionService;

  /**
   * 그림 단계 완료 Use Case를 처리하는 서비스를 주입받는다.
   *
   * @param drawingStageCompletionService 최종 그림 저장과 분석을 조율하는 서비스
   */
  public DrawingStageCompletionController(
      DrawingStageCompletionService drawingStageCompletionService) {
    this.drawingStageCompletionService = drawingStageCompletionService;
  }

  /**
   * 최종 그림을 저장하고 대화 준비용 분석을 확정한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param idempotencyKey 완료 요청을 식별하는 Header 값
   * @param finalImage 최초 완료 요청에서 저장할 PNG 또는 JPEG 이미지
   * @param request 완료 시각과 그림 작성 시간 Metadata
   * @return HTTP 200과 그림 단계 완료 결과 공통 응답
   * @throws BusinessException 파일 Stream을 열 수 없거나 완료 규칙을 충족하지 못한 경우
   */
  @Operation(summary = "그림 단계 완료", description = "최종 그림을 저장하고 객체 탐지를 수행한 뒤 감정 선택이 가능한 단계로 전환합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "그림 단계 완료 또는 동일 요청 결과 재조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Idempotency-Key, Multipart Part 또는 Metadata 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 그림 활동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "완료 불가 상태, FINAL 중복 또는 멱등 요청 충돌",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "413",
        description = "이미지 크기 제한 초과",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "422",
        description = "IMAGE_DIMENSION_INVALID(STORAGE_422_001): 이미지 픽셀 크기 범위 위반",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "최종 그림 또는 분석 상태 저장 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping(
      value = "/api/v1/drawing-sessions/{drawingSessionId}/drawing-complete",
      consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public ResponseEntity<ApiResponse<CompleteDrawingStageResponse>> completeDrawingStage(
      @Parameter(description = "그림 활동 세션 식별자", required = true) @PathVariable @Positive
          Long drawingSessionId,
      @Parameter(description = "완료 요청을 식별하는 멱등 Key", required = true)
          @RequestHeader(value = "Idempotency-Key", required = false)
          String idempotencyKey,
      @RequestPart(value = "finalImage", required = false) MultipartFile finalImage,
      @Valid @RequestPart("metadata") CompleteDrawingStageRequest request) {
    if (finalImage == null) {
      return ok(
          drawingStageCompletionService.complete(drawingSessionId, idempotencyKey, null, request));
    }
    try (InputStream inputStream = finalImage.getInputStream()) {
      StoreImageCommand command =
          new StoreImageCommand(
              inputStream,
              finalImage.getSize(),
              finalImage.getContentType(),
              finalImage.getOriginalFilename());
      return ok(
          drawingStageCompletionService.complete(
              drawingSessionId, idempotencyKey, command, request));
    } catch (IOException exception) {
      throw new BusinessException(DrawingErrorCode.DRAWING_SNAPSHOT_STORAGE_FAILED, exception);
    }
  }

  private ResponseEntity<ApiResponse<CompleteDrawingStageResponse>> ok(
      CompleteDrawingStageResponse response) {
    return ResponseEntity.ok(ApiResponse.ok(response));
  }
}
