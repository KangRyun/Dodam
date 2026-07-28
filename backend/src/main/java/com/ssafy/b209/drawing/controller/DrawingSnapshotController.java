package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.request.UploadDrawingSnapshotRequest;
import com.ssafy.b209.drawing.dto.response.DrawingSessionAssetSummaryResponse;
import com.ssafy.b209.drawing.dto.response.UploadDrawingSnapshotResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.service.DrawingSessionQueryService;
import com.ssafy.b209.drawing.service.DrawingSnapshotService;
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
import java.util.List;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 그림 활동 세션의 이미지 스냅샷 Multipart 업로드 API를 제공한다.
 *
 * <p>HTTP Part를 Storage 명령으로 변환하고 공통 응답을 조립하며, 세션 상태·중복·저장 일관성 규칙은 {@link DrawingSnapshotService}에
 * 위임한다.
 */
@Tag(name = "Drawing Snapshots", description = "그림 활동 스냅샷 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-sessions/{drawingSessionId}/snapshots")
public class DrawingSnapshotController {

  private final DrawingSnapshotService drawingSnapshotService;
  private final DrawingSessionQueryService drawingSessionQueryService;

  /**
   * 스냅샷 업로드·조회 서비스를 사용하는 Controller를 생성한다.
   *
   * @param drawingSnapshotService 이미지와 Metadata 업로드를 처리하는 서비스
   * @param drawingSessionQueryService 그림 활동 읽기 전용 조회 서비스
   */
  public DrawingSnapshotController(
      DrawingSnapshotService drawingSnapshotService,
      DrawingSessionQueryService drawingSessionQueryService) {
    this.drawingSnapshotService = drawingSnapshotService;
    this.drawingSessionQueryService = drawingSessionQueryService;
  }

  /**
   * 그림 활동 세션의 그림 파일 스냅샷 목록을 최신순으로 조회한다.
   *
   * <p>조회만 수행하며 내부 저장 위치는 응답에 포함하지 않는다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return HTTP 200과 최신순 스냅샷 Metadata 목록 공통 응답
   */
  @Operation(
      summary = "그림 스냅샷 목록 조회",
      description = "연결 보호자가 그림 활동 세션의 스냅샷 Metadata를 최신순으로 조회합니다. 내부 저장 위치는 포함하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "그림 스냅샷 목록 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "그림 활동 세션 식별자 형식 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 그림 활동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping
  public ResponseEntity<ApiResponse<List<DrawingSessionAssetSummaryResponse>>> getDrawingSnapshots(
      @Parameter(description = "조회할 그림 활동 세션 식별자", required = true) @PathVariable @Positive
          Long drawingSessionId) {
    return ResponseEntity.ok(
        ApiResponse.ok(drawingSessionQueryService.getSnapshots(drawingSessionId)));
  }

  /**
   * 이미지 파일과 JSON Metadata를 저장하고 생성된 그림 파일의 위치를 반환한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param file 업로드할 JPEG 또는 PNG 이미지
   * @param request 스냅샷 유형, 버전과 캡처 시각
   * @return HTTP 201, 생성된 그림 파일의 Location Header와 공통 성공 응답
   * @throws BusinessException 파일 Stream을 열 수 없거나 업로드 규칙을 충족하지 못한 경우
   */
  @Operation(
      summary = "그림 스냅샷 업로드",
      description = "진행 중인 DRAWING 단계의 그림 활동 세션에 JPEG 또는 PNG 스냅샷을 저장합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "그림 스냅샷 저장 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Multipart Part 또는 Metadata 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "그림 활동 세션을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "업로드 불가 상태 또는 스냅샷 중복",
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
        description = "파일 또는 Metadata 저장 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public ResponseEntity<ApiResponse<UploadDrawingSnapshotResponse>> uploadDrawingSnapshot(
      @PathVariable @Positive Long drawingSessionId,
      @RequestPart(value = "file", required = false) MultipartFile file,
      @Valid @RequestPart(value = "metadata", required = false)
          UploadDrawingSnapshotRequest request) {
    if (file == null) {
      return createdResponse(
          drawingSessionId, drawingSnapshotService.upload(drawingSessionId, null, request));
    }
    try (InputStream inputStream = file.getInputStream()) {
      StoreImageCommand command =
          new StoreImageCommand(
              inputStream, file.getSize(), file.getContentType(), file.getOriginalFilename());
      return createdResponse(
          drawingSessionId, drawingSnapshotService.upload(drawingSessionId, command, request));
    } catch (IOException exception) {
      throw new BusinessException(DrawingErrorCode.DRAWING_SNAPSHOT_STORAGE_FAILED, exception);
    }
  }

  private ResponseEntity<ApiResponse<UploadDrawingSnapshotResponse>> createdResponse(
      Long drawingSessionId, UploadDrawingSnapshotResponse response) {
    URI location =
        URI.create(
            "/api/v1/drawing-sessions/"
                + drawingSessionId
                + "/snapshots/"
                + response.drawingAssetId());
    return ResponseEntity.created(location)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
