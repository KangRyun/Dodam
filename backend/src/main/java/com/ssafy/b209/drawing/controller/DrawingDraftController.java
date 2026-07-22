package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.request.SaveDrawingDraftRequest;
import com.ssafy.b209.drawing.dto.response.DrawingDraftResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.service.DrawingDraftService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.storage.image.StoreImageCommand;
import io.swagger.v3.oas.annotations.Operation;
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
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 진행 중인 그림 활동의 현재 초안 저장과 최신 초안 Metadata 조회 API를 제공한다.
 *
 * <p>Multipart 파일을 Storage 명령으로 변환하고 공통 응답을 조립한다. 저장 가능 상태, 버전 순서와 파일·DB 일관성은 {@link
 * DrawingDraftService}에 위임한다.
 */
@Tag(name = "Drawing Drafts", description = "진행 중 그림 활동의 초안 자동 저장 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-sessions/{drawingSessionId}/draft")
public class DrawingDraftController {

  private final DrawingDraftService drawingDraftService;

  /**
   * 그림 초안 Use Case를 사용하는 Controller를 생성한다.
   *
   * @param drawingDraftService 초안 저장과 조회를 처리하는 서비스
   */
  public DrawingDraftController(DrawingDraftService drawingDraftService) {
    this.drawingDraftService = drawingDraftService;
  }

  /**
   * 현재 캔버스 미리보기를 마지막 이벤트 순서와 함께 새 초안 버전으로 저장한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param preview 현재 캔버스의 JPEG 또는 PNG 미리보기
   * @param request 마지막 이벤트 순서와 클라이언트 저장 시각
   * @return HTTP 200 공통 성공 응답
   * @throws BusinessException 파일 Stream을 열 수 없거나 초안 저장 규칙을 충족하지 못한 경우
   */
  @Operation(
      summary = "진행 중 그림 초안 자동 저장",
      description =
          "IN_PROGRESS/DRAWING 세션의 비최종 초안을 저장합니다. 이전 이벤트 순서는 거부하며 AI 분석이나 세션 상태 변경을 실행하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "현재 초안 교체 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Multipart Part 또는 Canvas Metadata 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "그림 활동 세션을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "저장 불가 상태, 같은 순서 또는 이전 순서의 초안",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "413",
        description = "이미지 크기 제한 초과",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "파일 또는 Metadata 저장 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PutMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public ResponseEntity<ApiResponse<DrawingDraftResponse>> saveDraft(
      @PathVariable @Positive Long drawingSessionId,
      @RequestPart("preview") MultipartFile preview,
      @Valid @RequestPart("canvasState") SaveDrawingDraftRequest request) {
    try (InputStream inputStream = preview.getInputStream()) {
      StoreImageCommand command =
          new StoreImageCommand(
              inputStream,
              preview.getSize(),
              preview.getContentType(),
              preview.getOriginalFilename());
      return ResponseEntity.ok(
          ApiResponse.ok(drawingDraftService.save(drawingSessionId, command, request)));
    } catch (IOException exception) {
      throw new BusinessException(DrawingErrorCode.DRAWING_DRAFT_STORAGE_FAILED, exception);
    }
  }

  /**
   * 세션에 저장된 가장 최근 초안의 공개 가능한 Metadata를 조회한다.
   *
   * <p>이 API는 이미지 다운로드 API가 아니므로 이미지 Byte, 내부 Storage Key 또는 임의 URL을 반환하지 않는다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return HTTP 200과 최신 초안 Metadata
   * @throws BusinessException 세션 또는 저장된 초안을 찾을 수 없는 경우
   */
  @Operation(
      summary = "최신 그림 초안 조회",
      description = "가장 높은 초안 버전의 Metadata를 조회합니다. 이미지 파일 다운로드나 AI 분석은 실행하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "최신 초안 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "유효하지 않은 세션 식별자",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "그림 활동 세션 또는 저장된 초안을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping
  public ResponseEntity<ApiResponse<DrawingDraftResponse>> getLatestDraft(
      @PathVariable @Positive Long drawingSessionId) {
    return ResponseEntity.ok(ApiResponse.ok(drawingDraftService.getLatest(drawingSessionId)));
  }
}
