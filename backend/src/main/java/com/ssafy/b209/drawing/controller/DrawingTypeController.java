package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.domain.DrawingActivityCategory;
import com.ssafy.b209.drawing.dto.response.DrawingTypePageResponse;
import com.ssafy.b209.drawing.service.DrawingTypeQueryService;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Positive;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 아동에게 노출할 그림 활동 유형 조회 HTTP API를 제공한다.
 *
 * <p>Query 형식 검증과 공통 응답 조립만 담당하며 인증·권한·아동 상태 검증은 {@link DrawingTypeQueryService}에 위임한다.
 */
@Tag(name = "Drawing Types", description = "그림 활동 유형 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-types")
public class DrawingTypeController {

  private final DrawingTypeQueryService drawingTypeQueryService;

  /**
   * 그림 유형 조회 서비스를 사용하는 Controller를 생성한다.
   *
   * @param drawingTypeQueryService 아동별 그림 유형 조회 업무를 처리하는 서비스
   */
  public DrawingTypeController(DrawingTypeQueryService drawingTypeQueryService) {
    this.drawingTypeQueryService = drawingTypeQueryService;
  }

  /**
   * 연결 아동과 요청 조건에 맞는 그림 활동 유형을 조회한다.
   *
   * @param childId 그림 유형을 조회할 연결 아동 식별자
   * @param category 조회할 활동 분류, 전체 분류이면 {@code null}
   * @param activeOnly 활성 유형만 포함할지 여부
   * @return HTTP 200과 공통 응답으로 감싼 그림 유형 목록
   */
  @Operation(
      summary = "그림 활동 유형 조회",
      description =
          "연결 아동의 권한을 확인하고 활동 분류와 활성 조건에 맞는 그림 유형을 기본 노출 순서로 조회합니다. "
              + "권장 연령은 참고 Metadata이며 조회 결과를 제한하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "그림 활동 유형 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "아동 식별자 또는 활동 분류 형식 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 아동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping
  public ResponseEntity<ApiResponse<DrawingTypePageResponse>> getDrawingTypes(
      @Parameter(description = "조회할 연결 아동 식별자", required = true) @RequestParam @Positive
          Long childId,
      @Parameter(description = "활동 분류") @RequestParam(required = false)
          DrawingActivityCategory category,
      @Parameter(description = "활성 유형만 조회할지 여부") @RequestParam(defaultValue = "true")
          boolean activeOnly) {
    return ResponseEntity.ok(
        ApiResponse.ok(drawingTypeQueryService.getDrawingTypes(childId, category, activeOnly)));
  }
}
