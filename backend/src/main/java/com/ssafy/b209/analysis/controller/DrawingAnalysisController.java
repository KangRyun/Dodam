package com.ssafy.b209.analysis.controller;

import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisDetailResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisHistoryResponse;
import com.ssafy.b209.analysis.service.DrawingAnalysisQueryService;
import com.ssafy.b209.analysis.service.DrawingAnalysisService;
import com.ssafy.b209.global.exception.BusinessException;
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
import java.net.URI;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 그림 활동 세션의 자동 저장·최종 그림 객체 탐지 요청과 저장 결과 조회 API를 제공한다.
 *
 * <p>HTTP 입력 검증, 생성 리소스 Location과 공통 응답 조립만 담당하며 실행 규칙은 {@link DrawingAnalysisService}, 조회 규칙은
 * {@link DrawingAnalysisQueryService}에 위임한다.
 */
@Tag(name = "Drawing Analyses", description = "그림 분석 요청, 결과 저장 및 상태 조회 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-sessions/{drawingSessionId}/analyses")
public class DrawingAnalysisController {

  private final DrawingAnalysisService drawingAnalysisService;
  private final DrawingAnalysisQueryService drawingAnalysisQueryService;

  /**
   * 그림 분석 Application Service를 사용하는 Controller를 생성한다.
   *
   * @param drawingAnalysisService 분석 실행과 결과 저장을 조율하는 서비스
   * @param drawingAnalysisQueryService 저장된 분석 상태와 결과를 조회하는 서비스
   */
  public DrawingAnalysisController(
      DrawingAnalysisService drawingAnalysisService,
      DrawingAnalysisQueryService drawingAnalysisQueryService) {
    this.drawingAnalysisService = drawingAnalysisService;
    this.drawingAnalysisQueryService = drawingAnalysisQueryService;
  }

  /**
   * 세션에 속한 그림 분석 이력을 요청 시각 역순으로 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return HTTP 200과 요청 시각 역순의 분석 이력 목록 공통 응답
   */
  @Operation(
      summary = "활동별 그림 분석 이력 조회",
      description = "연결 보호자가 그림 활동 세션의 분석 이력을 요청 시각 역순으로 조회합니다. 객체 탐지 결과는 상세 조회에서 제공합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "분석 이력 조회 성공"),
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
  public ResponseEntity<ApiResponse<List<DrawingAnalysisHistoryResponse>>> getAnalyses(
      @PathVariable @Positive Long drawingSessionId) {
    return ResponseEntity.ok(
        ApiResponse.ok(drawingAnalysisQueryService.getDrawingAnalyses(drawingSessionId)));
  }

  /**
   * 분석 요청 식별자로 저장된 진행 상태와 객체 탐지 결과를 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param drawingAnalysisId 분석 실행 식별자
   * @return HTTP 200과 상태별 분석 상세 공통 응답
   * @throws BusinessException 분석을 찾을 수 없거나 저장 상태가 모순되는 경우
   */
  @Operation(
      summary = "그림 분석 진행 상태 및 결과 조회",
      description =
          "분석 요청 ID로 PENDING, PROCESSING, SUCCEEDED, FAILED 상태를 Polling합니다. "
              + "FAILED도 정상 조회이므로 HTTP 200으로 반환하며, 성공 시 저장된 Detection을 제공합니다. "
              + "조회 과정에서 AI 서버를 다시 호출하거나 분석을 재시도하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "분석 진행 상태 또는 저장 결과 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Path Variable 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "요청한 Session에서 분석을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "분석 상태와 저장 결과가 일치하지 않음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/{drawingAnalysisId}")
  public ResponseEntity<ApiResponse<DrawingAnalysisDetailResponse>> getAnalysis(
      @PathVariable @Positive Long drawingSessionId,
      @PathVariable @Positive Long drawingAnalysisId) {
    DrawingAnalysisDetailResponse response =
        drawingAnalysisQueryService.getDrawingAnalysis(drawingSessionId, drawingAnalysisId);
    return ResponseEntity.ok(ApiResponse.of(CommonSuccessCode.OK, response));
  }

  /**
   * 세션의 DRAFT 또는 FINAL 그림 객체 탐지를 실행하고 저장된 분석 리소스를 반환한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param request 분석 대상 그림 파일과 작업 유형
   * @return HTTP 201, 생성된 분석 Location과 공통 성공 응답
   * @throws BusinessException 대상·상태·중복 검증, Client 호출 또는 결과 저장에 실패한 경우
   */
  @Operation(
      summary = "그림 분석 요청 및 결과 저장",
      description =
          "세션의 DRAFT 자동 저장 그림 또는 FINAL 그림을 DrawingAnalysisClient로 분석하고 객체 탐지 결과를 저장합니다. "
              + "DRAFT는 INTERMEDIATE 분석으로, FINAL은 FINAL 분석으로 기록합니다. "
              + "자동 저장 후 3초 debounce는 Client가 담당합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "그림 분석 및 결과 저장 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Path Variable 또는 요청 Body 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "그림 활동 세션 또는 분석 대상 그림을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "분석 불가 상태 또는 진행·성공 분석 중복",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "502",
        description = "AI Client 호출 또는 응답 계약 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "분석 결과 저장 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<CreateDrawingAnalysisResponse>> createAnalysis(
      @PathVariable @Positive Long drawingSessionId,
      @Valid @RequestBody CreateDrawingAnalysisRequest request) {
    CreateDrawingAnalysisResponse response =
        drawingAnalysisService.requestAnalysis(drawingSessionId, request);
    URI location =
        URI.create(
            "/api/v1/drawing-sessions/"
                + drawingSessionId
                + "/analyses/"
                + response.drawingAnalysisId());
    return ResponseEntity.created(location)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
