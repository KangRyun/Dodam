package com.ssafy.b209.analysis.controller;

import com.ssafy.b209.analysis.dto.AnalysisStatusResponse;
import com.ssafy.b209.analysis.service.DrawingAnalysisQueryService;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Positive;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 분석 식별자를 기준으로 진행·완료·실패 상태를 폴링하는 정본 공개 API를 제공한다.
 *
 * <p>세션 하위 분석 조회 API는 기존 그림 화면과의 호환을 위해 유지하고, 리포트 등 세션 식별자를 보유하지 않은 Client는 이 API를 사용한다.
 */
@Tag(name = "Analyses", description = "분석 상태 및 결과 조회 API")
@Validated
@RestController
@RequestMapping("/api/v1/analyses")
public class AnalysisStatusController {

  private final DrawingAnalysisQueryService drawingAnalysisQueryService;

  /**
   * 저장된 분석 조회 서비스를 주입받는다.
   *
   * @param drawingAnalysisQueryService 분석 접근 권한과 결과 정합성을 검증하는 서비스
   */
  public AnalysisStatusController(DrawingAnalysisQueryService drawingAnalysisQueryService) {
    this.drawingAnalysisQueryService = drawingAnalysisQueryService;
  }

  /**
   * 분석 식별자로 현재 상태와 보호자에게 공개 가능한 결과를 조회한다.
   *
   * @param analysisId 분석 실행 식별자
   * @return HTTP 200과 분석 상태 공통 응답
   */
  @Operation(
      summary = "분석 진행 상태 및 결과 조회",
      description =
          "PENDING, PROCESSING, PARTIAL_SUCCESS, SUCCESS, FAILED 상태를 조회합니다. "
              + "FAILED도 정상적인 폴링 결과이므로 HTTP 200으로 반환합니다.")
  @GetMapping("/{analysisId}")
  public ResponseEntity<ApiResponse<AnalysisStatusResponse>> getAnalysisStatus(
      @PathVariable @Positive Long analysisId) {
    return ResponseEntity.ok(
        ApiResponse.ok(drawingAnalysisQueryService.getAnalysisStatus(analysisId)));
  }
}
