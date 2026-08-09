package com.ssafy.b209.analysis.controller;

import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.RetryDrawingAnalysisRequest;
import com.ssafy.b209.analysis.service.DrawingAnalysisService;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 실패한 그림 분석 식별자를 기준으로 새 분석 실행을 생성하는 HTTP API를 제공한다.
 *
 * <p>재시도 상태 검증과 AI 호출은 {@link DrawingAnalysisService}에 위임하며 원본 분석 행은 변경하지 않는다.
 */
@Tag(name = "Drawing Analyses", description = "그림 분석 요청, 결과 저장 및 상태 조회 API")
@Validated
@RestController
@RequestMapping("/api/v1/analyses")
public class DrawingAnalysisRetryController {

  private final DrawingAnalysisService drawingAnalysisService;

  /**
   * 그림 분석 재시도 Controller를 생성한다.
   *
   * @param drawingAnalysisService 실패 분석 재시도를 조율하는 Service
   */
  public DrawingAnalysisRetryController(DrawingAnalysisService drawingAnalysisService) {
    this.drawingAnalysisService = drawingAnalysisService;
  }

  /**
   * 실패한 분석을 원본으로 연결한 새 분석 실행을 생성한다.
   *
   * @param analysisId 실패한 원본 분석 식별자
   * @param request 재시도 사유와 입력 선택 정책
   * @param idempotencyKey 같은 재시도 요청의 중복 실행을 방지하는 식별자
   * @return HTTP 201, 생성된 분석 Location과 공통 성공 응답
   */
  @Operation(
      summary = "실패한 그림 분석 재요청",
      description =
          "FAILED 분석만 재시도하며 새 분석 행에 원본 분석 ID를 기록합니다. "
              + "useLatestInputs가 true이면 같은 세션과 자산 유형의 최신 그림을 사용합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "그림 분석 재시도 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Path Variable 또는 요청 Body 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 원본 분석을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "FAILED 상태가 아니거나 선택된 입력에 활성 분석이 존재함",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "502",
        description = "AI Client 호출 또는 응답 계약 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping("/{analysisId}/retry")
  public ResponseEntity<ApiResponse<CreateDrawingAnalysisResponse>> retryAnalysis(
      @PathVariable @Positive Long analysisId,
      @Valid @RequestBody RetryDrawingAnalysisRequest request,
      @Parameter(description = "재시도 요청을 식별하는 멱등 Key", required = true)
          @RequestHeader(value = "Idempotency-Key", required = false)
          String idempotencyKey) {
    CreateDrawingAnalysisResponse response =
        drawingAnalysisService.retryAnalysis(analysisId, request, idempotencyKey);
    URI location =
        URI.create(
            "/api/v1/drawing-sessions/"
                + response.drawingSessionId()
                + "/analyses/"
                + response.drawingAnalysisId());
    return ResponseEntity.created(location)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
