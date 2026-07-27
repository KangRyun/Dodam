package com.ssafy.b209.report.controller;

import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.service.ReportDetailQueryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 보호자가 관찰 리포트 상세를 조회하는 공개 HTTP API다.
 *
 * <p>운영에서는 JWT를 검증하는 {@link GuardianUserResolver}가 보호자를 식별하며, 개발·테스트 프로필의 임시 Header 경계는 운영 인증을 대체하지
 * 않는다. 응답은 보호자 안전 규칙에 따라 AI 추정 감정·위험도·전문가 전용 관찰 특징을 포함하지 않는다.
 */
@Tag(name = "Reports", description = "관찰 리포트 조회 API")
@RestController
@RequestMapping("/api/v1/reports")
public class ReportDetailController {

  private final GuardianUserResolver guardianResolver;
  private final ReportDetailQueryService reportDetailQueryService;

  /**
   * Controller 의존성을 생성한다.
   *
   * @param guardianResolver JWT 전환 전 개발용 보호자 식별 경계
   * @param reportDetailQueryService 소유권 검증·리포트 조립 읽기 서비스
   */
  public ReportDetailController(
      GuardianUserResolver guardianResolver, ReportDetailQueryService reportDetailQueryService) {
    this.guardianResolver = guardianResolver;
    this.reportDetailQueryService = reportDetailQueryService;
  }

  /**
   * 보호자용 관찰 리포트 상세를 조회한다.
   *
   * @param reportId 리포트 식별자
   * @param authorization 운영 JWT 검증기 또는 개발·테스트 임시 경계가 해석할 Authorization Header
   * @param guardianUserId 개발·테스트에서만 사용하는 임시 보호자 Header
   * @return HTTP 200과 공통 성공 응답으로 감싼 리포트 상세
   * @throws BusinessException 인증·권한 검증에 실패하거나 리포트를 찾을 수 없는 경우
   */
  @Operation(summary = "관찰 리포트 상세 조회", description = "연결 보호자가 아동의 관찰 리포트 상세를 조회합니다.")
  @GetMapping("/{reportId}")
  public ResponseEntity<ApiResponse<ReportDetailResponse>> getReport(
      @PathVariable Long reportId,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    ReportDetailResponse response = reportDetailQueryService.getReport(guardianId, reportId);
    return ResponseEntity.ok(ApiResponse.ok(response));
  }
}
