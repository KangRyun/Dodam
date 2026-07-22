package com.ssafy.b209.analysis.controller;

import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisResponse;
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
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 그림 활동 세션의 최종 스냅샷 분석 요청과 저장 API를 제공한다.
 *
 * <p>HTTP 입력 검증, 생성 리소스 Location과 공통 응답 조립만 담당하며 분석 상태와 AI 연동 규칙은 {@link DrawingAnalysisService}에
 * 위임한다.
 */
@Tag(name = "Drawing Analyses", description = "그림 분석 요청 및 결과 저장 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-sessions/{drawingSessionId}/analyses")
public class DrawingAnalysisController {

  private final DrawingAnalysisService drawingAnalysisService;

  /**
   * 그림 분석 Application Service를 사용하는 Controller를 생성한다.
   *
   * @param drawingAnalysisService 분석 실행과 결과 저장을 조율하는 서비스
   */
  public DrawingAnalysisController(DrawingAnalysisService drawingAnalysisService) {
    this.drawingAnalysisService = drawingAnalysisService;
  }

  /**
   * 세션의 최종 그림 분석을 실행하고 저장된 분석 리소스를 반환한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param request 분석 대상 그림 파일과 작업 유형
   * @return HTTP 201, 생성된 분석 Location과 공통 성공 응답
   * @throws BusinessException 대상·상태·중복 검증, Client 호출 또는 결과 저장에 실패한 경우
   */
  @Operation(
      summary = "그림 분석 요청 및 결과 저장",
      description = "세션의 최종 그림을 활성화된 DrawingAnalysisClient로 분석하고 객체 탐지 결과를 저장합니다.")
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
