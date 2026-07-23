package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.request.SaveDrawingReflectionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingReflectionResponse;
import com.ssafy.b209.drawing.service.DrawingReflectionService;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 그림 활동을 돌아보며 작성한 제목과 아동의 감정 표현을 저장하는 API를 제공한다.
 *
 * <p>요청 형식 검증과 공통 응답 조립만 담당하며, 소유 관계와 상태 전이 검증은 {@link DrawingReflectionService}에 위임한다.
 */
@Tag(name = "Drawing Reflections", description = "그림 활동 제목과 감정 표현 저장 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-sessions/{drawingSessionId}/reflection")
public class DrawingReflectionController {

  private final DrawingReflectionService drawingReflectionService;

  /**
   * 그림 활동 감정 저장 Use Case를 사용하는 Controller를 생성한다.
   *
   * @param drawingReflectionService 제목과 감정 표현 저장을 처리하는 서비스
   */
  public DrawingReflectionController(DrawingReflectionService drawingReflectionService) {
    this.drawingReflectionService = drawingReflectionService;
  }

  /**
   * 그림 활동의 제목과 감정 표현을 현재 요청 값으로 교체한다.
   *
   * @param drawingSessionId 저장 대상 그림 활동 세션 식별자
   * @param request 제목, 감정 선택, 직접 표현과 건너뛰기 여부
   * @return HTTP 200과 REFLECTION 단계의 저장 결과
   */
  @Operation(
      summary = "그림 활동 감정·제목 저장",
      description =
          "아동이 직접 선택한 감정과 표현을 저장하고 세션을 REFLECTION 단계로 변경합니다. " + "UNKNOWN은 다른 감정과 함께 선택할 수 없습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "감정 표현 저장 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "제목 길이 또는 감정 선택 조합 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 그림 활동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "감정 표현 저장을 허용하지 않는 세션 상태",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PutMapping
  public ResponseEntity<ApiResponse<DrawingReflectionResponse>> saveReflection(
      @PathVariable @Positive Long drawingSessionId,
      @Valid @RequestBody SaveDrawingReflectionRequest request) {
    return ResponseEntity.ok(
        ApiResponse.ok(drawingReflectionService.save(drawingSessionId, request)));
  }
}
