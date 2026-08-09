package com.ssafy.b209.expert.controller;

import com.ssafy.b209.expert.dto.request.ReviewExpertVerificationRequest;
import com.ssafy.b209.expert.dto.response.ExpertVerificationResponse;
import com.ssafy.b209.expert.service.ExpertVerificationService;
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
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 관리자 전용 전문가 자격 승인·반려 API를 제공한다. */
@Tag(name = "Admin Expert Verification", description = "관리자 전문가 검증 API")
@Validated
@RestController
@RequestMapping("/api/v1/admin/experts")
public class AdminExpertVerificationController {

  private final ExpertVerificationService verificationService;

  /**
   * 관리자 전문가 검증 API를 구성한다.
   *
   * @param verificationService 전문가 검증 상태 처리 서비스
   */
  public AdminExpertVerificationController(ExpertVerificationService verificationService) {
    this.verificationService = verificationService;
  }

  /**
   * 전문가 프로필과 선택 자격의 승인 또는 반려 결과를 확정한다.
   *
   * @param expertId 전문가 프로필 ID
   * @param request 최종 검증 상태와 선택 자격·사유
   * @return 검토 후 프로필과 자격 상태
   */
  @Operation(summary = "전문가 자격 검증 처리")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "검증 처리 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "검증 상태·자격·사유 조합 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "관리자 권한 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "전문가 프로필 또는 선택 자격 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PatchMapping("/{expertId}/verification")
  public ResponseEntity<ApiResponse<ExpertVerificationResponse>> review(
      @PathVariable @Positive Long expertId,
      @Valid @RequestBody ReviewExpertVerificationRequest request) {
    return ResponseEntity.ok(ApiResponse.ok(verificationService.review(expertId, request)));
  }
}
