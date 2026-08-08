package com.ssafy.b209.referral.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import com.ssafy.b209.referral.dto.ReferralSummaryResponse;
import com.ssafy.b209.referral.service.ReferralSummaryQueryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 보호자가 전문가에게 가져갈 의뢰 요약을 조회하는 HTTP API다.
 *
 * <p><strong>진단도 소견도 아니다.</strong> 전문가가 판단하는 데 필요한 원자료를 모아 정리한 문서이며, 앱의 해석을 대신 주장하지 않는다.
 */
@Tag(name = "Referral Summary", description = "전문가 의뢰 요약 API")
@RestController
@RequestMapping("/api/v1/children/{childId}/referral-summary")
public class ReferralSummaryController {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ReferralSummaryQueryService queryService;

  /**
   * 의뢰 요약 Controller를 구성한다.
   *
   * @param currentUserResolver Access Token 사용자 식별 경계
   * @param queryService 의뢰 요약 조회 서비스
   */
  public ReferralSummaryController(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ReferralSummaryQueryService queryService) {
    this.currentUserResolver = currentUserResolver;
    this.queryService = queryService;
  }

  /**
   * 아이의 의뢰 요약을 조회한다.
   *
   * @param childId 대상 아동 식별자
   * @param sessions 가져올 최근 회차 수이며 없으면 기본값
   * @return 의뢰 요약
   */
  @Operation(
      summary = "의뢰 요약 조회",
      description =
          "최근 활동의 아이 발화·되풀이된 관찰·안전 신호·보호자가 기록해 둔 검사 결과를 모아 전문가 상담용으로 정리한다. "
              + "앱의 가설과 색·크기 해석은 담지 않으며, 무엇을 담지 않았는지도 함께 알려 준다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "접근 권한 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping
  public ResponseEntity<ApiResponse<ReferralSummaryResponse>> find(
      @PathVariable Long childId, @RequestParam(required = false) Integer sessions) {
    Long guardianUserId = currentUserResolver.requireUserId();
    return ResponseEntity.ok(
        ApiResponse.of(
            CommonSuccessCode.OK, queryService.summarize(guardianUserId, childId, sessions)));
  }
}
