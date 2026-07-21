package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.request.CreateDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.CreateDrawingSessionResponse;
import com.ssafy.b209.drawing.service.DrawingSessionService;
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
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 그림 활동 세션 생성 HTTP API를 제공하는 Controller다.
 *
 * <p>요청 형식 검증과 공통 응답 조립만 담당하며, 아동·그림 유형 및 멱등성에 관한 업무 규칙은 {@link DrawingSessionService}에 위임한다.
 */
@Tag(name = "Drawing Sessions", description = "그림 활동 세션 API")
@RestController
@RequestMapping("/api/v1/drawing-sessions")
public class DrawingSessionController {

  private final DrawingSessionService drawingSessionService;

  /**
   * 그림 활동 세션 서비스를 사용하는 Controller를 생성한다.
   *
   * @param drawingSessionService 그림 활동 세션 생성 업무를 처리하는 서비스
   */
  public DrawingSessionController(DrawingSessionService drawingSessionService) {
    this.drawingSessionService = drawingSessionService;
  }

  /**
   * 새 그림 활동 세션을 생성하고 생성된 Resource 위치를 반환한다.
   *
   * @param idempotencyKey 요청 재시도를 식별하는 {@code Idempotency-Key} Header 값
   * @param request 생성할 그림 활동 세션 정보
   * @return HTTP 201, 생성된 세션의 Location Header와 공통 성공 응답
   */
  @Operation(summary = "그림 활동 세션 생성", description = "아동의 그림 활동 세션을 진행 중 상태로 생성합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "그림 활동 세션 생성 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 또는 Canvas 설정 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "아동 또는 그림 활동 유형을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "진행 중인 세션 또는 멱등 요청 충돌",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "서버 내부 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<CreateDrawingSessionResponse>> createDrawingSession(
      @Parameter(description = "요청 재시도 식별 키", required = true)
          @RequestHeader(value = "Idempotency-Key", required = false)
          String idempotencyKey,
      @Valid @RequestBody CreateDrawingSessionRequest request) {
    CreateDrawingSessionResponse response =
        drawingSessionService.createDrawingSession(idempotencyKey, request);
    URI location = URI.create("/api/v1/drawing-sessions/" + response.drawingSessionId());
    return ResponseEntity.created(location)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
