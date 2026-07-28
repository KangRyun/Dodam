package com.ssafy.b209.drawing.htp.controller;

import com.ssafy.b209.drawing.dto.request.SaveDrawingReflectionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingReflectionResponse;
import com.ssafy.b209.drawing.htp.dto.HtpAssessmentResponse;
import com.ssafy.b209.drawing.htp.dto.HtpCompletionResponse;
import com.ssafy.b209.drawing.htp.dto.StartHtpAssessmentRequest;
import com.ssafy.b209.drawing.htp.service.HtpAssessmentService;
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
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * HTP 활동 묶음의 시작·현재 단계 조회·다음 단계·포기 HTTP API를 제공한다.
 *
 * <p>단계별 그림 저장과 대화는 응답의 {@code drawingSessionId}를 사용해 기존 API를 호출하며, 클라이언트가 HTP 주제를 다시 지정하지 않는다.
 */
@Tag(name = "HTP Assessments", description = "HTP 3단계 그림 활동 API")
@Validated
@RestController
@RequestMapping("/api/v1/htp-assessments")
public class HtpAssessmentController {

  private final HtpAssessmentService htpAssessmentService;

  /**
   * HTP 활동 Application Service를 사용하는 Controller를 생성한다.
   *
   * @param htpAssessmentService HTP 묶음과 단계 전이를 처리하는 서비스
   */
  public HtpAssessmentController(HtpAssessmentService htpAssessmentService) {
    this.htpAssessmentService = htpAssessmentService;
  }

  /**
   * HTP 묶음과 HOUSE 그림 세션을 생성한다.
   *
   * @param idempotencyKey 시작 요청을 식별하는 멱등 키
   * @param request 아동과 그림 입력 방식
   * @return HTTP 201과 생성된 HTP 활동
   */
  @Operation(summary = "HTP 활동 시작", description = "HOUSE, TREE, PERSON 순서 중 첫 HOUSE 그림 세션을 생성합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "HTP 활동 생성 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "진행 중 활동 존재 또는 HTP 유형 미준비",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<HtpAssessmentResponse>> start(
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @Valid @RequestBody StartHtpAssessmentRequest request) {
    HtpAssessmentResponse response = htpAssessmentService.start(idempotencyKey, request);
    URI location = URI.create("/api/v1/htp-assessments/" + response.htpAssessmentId());
    return ResponseEntity.created(location)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }

  /**
   * HTP 묶음과 현재 그림 단계를 조회한다.
   *
   * @param assessmentId HTP 활동 식별자
   * @return HTTP 200과 현재 단계
   */
  @Operation(summary = "HTP 진행 상태 조회", description = "서버에 저장된 현재 주제와 그림 세션 식별자를 반환합니다.")
  @GetMapping("/{assessmentId}")
  public ResponseEntity<ApiResponse<HtpAssessmentResponse>> get(
      @PathVariable @Positive Long assessmentId) {
    return ResponseEntity.ok(ApiResponse.ok(htpAssessmentService.get(assessmentId)));
  }

  /**
   * 현재 단계의 대화 완료를 확인하고 다음 주제 세션을 생성한다.
   *
   * @param assessmentId HTP 활동 식별자
   * @param idempotencyKey 단계 변경 요청을 식별하는 멱등 키
   * @return HTTP 200과 다음 단계 또는 세 단계 완료 상태
   */
  @Operation(summary = "HTP 다음 단계", description = "현재 대화가 끝난 경우 현재 세션을 완료하고 다음 주제 세션을 생성합니다.")
  @PostMapping("/{assessmentId}/steps/next")
  public ResponseEntity<ApiResponse<HtpAssessmentResponse>> nextStep(
      @PathVariable @Positive Long assessmentId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey) {
    return ResponseEntity.ok(
        ApiResponse.ok(htpAssessmentService.nextStep(assessmentId, idempotencyKey)));
  }

  /**
   * 세 HTP 그림 단계의 저장·분석·대화 완료를 검증하고 단일 리포트 생성을 접수한다.
   *
   * @param assessmentId HTP 활동 묶음 식별자
   * @param idempotencyKey 완료 요청을 식별하는 멱등 키
   * @return HTTP 202와 종합 리포트 작업 식별자
   */
  @Operation(
      summary = "HTP 종합 완료",
      description = "HOUSE, TREE, PERSON 결과가 모두 준비된 경우 HTP 리포트 하나의 생성을 접수합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "202",
        description = "HTP 단일 리포트 생성 접수"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "세 단계 결과 미완료 또는 처리 상태 충돌",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping("/{assessmentId}/complete")
  public ResponseEntity<ApiResponse<HtpCompletionResponse>> complete(
      @PathVariable @Positive Long assessmentId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey) {
    return ResponseEntity.accepted()
        .body(ApiResponse.ok(htpAssessmentService.complete(assessmentId, idempotencyKey)));
  }

  /**
   * PERSON 단계의 감정을 HTP 활동 단위 Reflection으로 저장한다.
   *
   * @param assessmentId HTP 활동 묶음 식별자
   * @param request 선택 감정과 건너뛰기 여부
   * @return 저장된 Reflection 결과
   */
  @Operation(summary = "HTP 활동 감정 저장", description = "세 그림을 마친 PERSON 단계에서 활동 전체의 감정을 한 번 저장합니다.")
  @PutMapping("/{assessmentId}/reflection")
  public ResponseEntity<ApiResponse<DrawingReflectionResponse>> saveReflection(
      @PathVariable @Positive Long assessmentId,
      @Valid @RequestBody SaveDrawingReflectionRequest request) {
    return ResponseEntity.ok(
        ApiResponse.ok(htpAssessmentService.saveReflection(assessmentId, request)));
  }

  /**
   * HTP 활동과 현재 미완료 그림 세션을 포기 처리한다.
   *
   * @param assessmentId HTP 활동 식별자
   * @param idempotencyKey 포기 요청을 식별하는 멱등 키
   * @return HTTP 200과 포기 상태
   */
  @Operation(summary = "HTP 활동 포기", description = "진행 중 HTP 묶음을 포기하고 활성 그림 세션을 종료합니다.")
  @PostMapping("/{assessmentId}/abandon")
  public ResponseEntity<ApiResponse<HtpAssessmentResponse>> abandon(
      @PathVariable @Positive Long assessmentId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey) {
    return ResponseEntity.ok(
        ApiResponse.ok(htpAssessmentService.abandon(assessmentId, idempotencyKey)));
  }
}
