package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.request.CreateDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.request.DeleteDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.ActiveDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.CreateDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionDetailResponse;
import com.ssafy.b209.drawing.service.DrawingSessionDeletionService;
import com.ssafy.b209.drawing.service.DrawingSessionQueryService;
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
import jakarta.validation.constraints.Positive;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 그림 활동 세션 생성과 진행 중 세션 조회 HTTP API를 제공하는 Controller다.
 *
 * <p>요청 형식 검증과 공통 응답 조립만 담당한다. 생성 규칙은 {@link DrawingSessionService}, 재개 정보 조회 규칙은 {@link
 * DrawingSessionQueryService}에 위임한다.
 */
@Tag(name = "Drawing Sessions", description = "그림 활동 세션 API")
@Validated
@RestController
@RequestMapping("/api/v1/drawing-sessions")
public class DrawingSessionController {

  private final DrawingSessionService drawingSessionService;
  private final DrawingSessionQueryService drawingSessionQueryService;
  private final DrawingSessionDeletionService drawingSessionDeletionService;

  /**
   * 그림 활동 세션 생성·조회 서비스를 사용하는 Controller를 생성한다.
   *
   * @param drawingSessionService 그림 활동 세션 생성 업무를 처리하는 서비스
   * @param drawingSessionQueryService 진행 중 그림 활동 조회 업무를 처리하는 서비스
   * @param drawingSessionDeletionService 그림 활동 취소·삭제 업무를 처리하는 서비스
   */
  public DrawingSessionController(
      DrawingSessionService drawingSessionService,
      DrawingSessionQueryService drawingSessionQueryService,
      DrawingSessionDeletionService drawingSessionDeletionService) {
    this.drawingSessionService = drawingSessionService;
    this.drawingSessionQueryService = drawingSessionQueryService;
    this.drawingSessionDeletionService = drawingSessionDeletionService;
  }

  /**
   * 아동의 진행 중 그림 활동 세션과 최신 자동 저장 초안을 조회한다.
   *
   * <p>초안이 없는 세션도 조회에 성공하며 응답의 {@code latestDraft}가 {@code null}이 된다. 이 요청은 세션 상태를 변경하지 않는다.
   *
   * @param childId 진행 중인 그림 활동을 조회할 아동 식별자
   * @return HTTP 200과 재개에 필요한 세션·최신 초안 정보
   */
  @Operation(
      summary = "진행 중 그림 활동 조회",
      description =
          "아동의 현재 진행 중 Session과 최신 초안 Metadata를 조회합니다. 최신 초안이 없을 수 있습니다. "
              + "조회만으로 세션 상태를 변경하지 않습니다. 조회만으로 AI 분석을 실행하지 않습니다. "
              + "이미지 파일 다운로드 API가 아닙니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "진행 중 그림 활동 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "아동 식별자 형식 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "진행 중인 그림 활동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "진행 중 세션 데이터 중복 또는 서버 내부 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/active")
  public ResponseEntity<ApiResponse<ActiveDrawingSessionResponse>> getActiveDrawingSession(
      @Parameter(description = "조회할 아동 식별자", required = true) @RequestParam @Positive
          Long childId) {
    return ResponseEntity.ok(
        ApiResponse.ok(drawingSessionQueryService.getActiveDrawingSession(childId)));
  }

  /**
   * 보호자가 접근할 수 있는 그림 활동의 현재 상태와 최신 연관 리소스를 조회한다.
   *
   * <p>조회만 수행하며 그림 파일 원본, 내부 저장 위치, 아동 생년월일은 응답에 포함하지 않는다.
   *
   * @param drawingSessionId 조회할 그림 활동 세션 식별자
   * @return HTTP 200과 그림 활동 상세 정보
   */
  @Operation(
      summary = "그림 활동 상세 조회",
      description =
          "연결 보호자가 그림 활동 상태와 최신 그림·분석·대화·리포트 Metadata를 조회합니다. "
              + "조회 과정에서 세션 상태를 변경하거나 AI 분석을 실행하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "그림 활동 상세 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "그림 활동 세션 식별자 형식 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 그림 활동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/{drawingSessionId}")
  public ResponseEntity<ApiResponse<DrawingSessionDetailResponse>> getDrawingSessionDetail(
      @Parameter(description = "조회할 그림 활동 세션 식별자", required = true) @PathVariable @Positive
          Long drawingSessionId) {
    return ResponseEntity.ok(
        ApiResponse.ok(drawingSessionQueryService.getDrawingSessionDetail(drawingSessionId)));
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

  /**
   * 연결 보호자의 그림 활동을 삭제 상태로 전환하고 파일 삭제를 예약한다.
   *
   * @param drawingSessionId 삭제할 그림 활동 세션 식별자
   * @param request 명시적 삭제 확인 값
   * @return 본문이 없는 HTTP 204 응답
   */
  @Operation(
      summary = "그림 활동 취소·삭제",
      description = "confirmation이 DELETE인 연결 보호자의 그림 활동을 Soft Delete하고 연관 파일의 비동기 삭제를 예약합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "204",
        description = "그림 활동 삭제 접수 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "세션 식별자 또는 삭제 확인 값 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 그림 활동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @DeleteMapping("/{drawingSessionId}")
  public ResponseEntity<Void> deleteDrawingSession(
      @Parameter(description = "삭제할 그림 활동 세션 식별자", required = true) @PathVariable @Positive
          Long drawingSessionId,
      @Valid @RequestBody DeleteDrawingSessionRequest request) {
    drawingSessionDeletionService.delete(drawingSessionId, request);
    return ResponseEntity.noContent().build();
  }
}
