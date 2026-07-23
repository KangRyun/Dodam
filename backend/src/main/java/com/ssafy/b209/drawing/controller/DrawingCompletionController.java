package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.request.CompleteDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingCompletionResponse;
import com.ssafy.b209.drawing.service.DrawingCompletionService;
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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 그림 활동의 최종 분석과 선택적 리포트 생성을 접수하는 API를 제공한다.
 *
 * <p>HTTP 계약과 공통 응답 조립만 담당하며, 권한·멱등성·상태 검증과 Transaction 처리는 {@link DrawingCompletionService}에 위임한다.
 */
@Tag(name = "Drawing Completions", description = "그림 활동 완료 후속 처리 접수 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-sessions/{drawingSessionId}/complete")
public class DrawingCompletionController {

  private final DrawingCompletionService service;

  /**
   * 그림 활동 완료 접수 Use Case를 사용하는 Controller를 생성한다.
   *
   * @param service 완료 접수와 상태 전이를 처리하는 서비스
   */
  public DrawingCompletionController(DrawingCompletionService service) {
    this.service = service;
  }

  /**
   * 최종 분석과 선택적 리포트 생성을 비동기 후속 작업으로 접수한다.
   *
   * @param drawingSessionId 완료 접수 대상 그림 활동 세션 식별자
   * @param idempotencyKey 재시도를 식별하는 {@code Idempotency-Key} Header 값
   * @param request 대화 생략과 리포트 생성 요청 여부
   * @return HTTP 202와 분석·리포트의 접수 상태
   */
  @Operation(
      summary = "그림 활동 완료 접수",
      description =
          "최종 그림과 감정 돌아보기 상태를 검증하고 최종 분석 및 선택적 리포트 생성을 접수합니다. " + "응답은 생성 완료가 아닌 비동기 처리 대기 상태입니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "202",
        description = "완료 후속 처리 접수 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "필수 Header 또는 요청 값 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 그림 활동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "완료 사전 조건, 멱등성 또는 동시 요청 충돌",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<DrawingCompletionResponse>> complete(
      @PathVariable @Positive Long drawingSessionId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @Valid @RequestBody CompleteDrawingSessionRequest request) {
    return ResponseEntity.accepted()
        .body(ApiResponse.ok(service.complete(drawingSessionId, idempotencyKey, request)));
  }
}
