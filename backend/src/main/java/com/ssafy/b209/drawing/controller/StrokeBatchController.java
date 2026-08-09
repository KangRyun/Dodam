package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.request.SaveStrokeBatchRequest;
import com.ssafy.b209.drawing.dto.response.StrokeBatchResponse;
import com.ssafy.b209.drawing.service.StrokeBatchSaveResult;
import com.ssafy.b209.drawing.service.StrokeBatchService;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 진행 중인 Canvas 그림 활동의 Stroke·편집 행동 배치를 저장하는 HTTP API를 제공한다. */
@Tag(name = "Drawing Strokes", description = "캔버스 그림 과정 데이터 저장 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-sessions/{drawingSessionId}/stroke-batches")
public class StrokeBatchController {

  private final StrokeBatchService strokeBatchService;

  /**
   * Stroke 배치 저장 Controller를 구성한다.
   *
   * @param strokeBatchService 접근·상태·멱등 규칙을 처리하는 Service
   */
  public StrokeBatchController(StrokeBatchService strokeBatchService) {
    this.strokeBatchService = strokeBatchService;
  }

  /**
   * 최대 500개의 순서화된 Canvas 이벤트를 하나의 배치로 저장한다.
   *
   * @param drawingSessionId 그림 활동 식별자
   * @param request 이벤트와 행동 지표
   * @return 신규 저장이면 HTTP 201, 같은 payload 재전송이면 HTTP 200
   */
  @Operation(
      summary = "Stroke 행동 배치 저장",
      description =
          "IN_PROGRESS/DRAWING 상태의 Canvas 세션에 정규화 좌표와 편집 지표를 저장합니다. 같은 배치 순번과 payload 재전송은 기존 결과를 반환합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "새 배치 저장 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "동일 배치 재전송"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "이벤트 순서·좌표·지표 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "저장 불가 상태 또는 같은 순번의 다른 payload",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "413",
        description = "압축 전 JSON 1 MiB 또는 좌표 20,000개 제한 초과",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<StrokeBatchResponse>> save(
      @PathVariable @Positive Long drawingSessionId,
      @Valid @RequestBody SaveStrokeBatchRequest request) {
    StrokeBatchSaveResult result = strokeBatchService.save(drawingSessionId, request);
    if (!result.created()) {
      return ResponseEntity.ok(ApiResponse.ok(result.response()));
    }
    return ResponseEntity.status(HttpStatus.CREATED)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, result.response()));
  }
}
