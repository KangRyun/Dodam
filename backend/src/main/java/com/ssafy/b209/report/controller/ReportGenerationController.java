package com.ssafy.b209.report.controller;

import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.report.dto.ReportGenerationStatusResponse;
import com.ssafy.b209.report.service.ReportGenerationService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Positive;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 관찰 리포트 생성 상태 조회와 실패한 생성 작업의 재접수 API를 제공한다.
 *
 * <p>보호자 인증 경계를 처리하고, 리포트 소유권 및 재시도 가능 여부 검증은 {@link ReportGenerationService}에 위임한다. 재생성 요청은 비동기
 * 작업을 접수하므로 호출자는 응답의 상태 조회 URI를 이용해 후속 상태를 확인해야 한다.
 */
@Tag(name = "Reports", description = "관찰 리포트 생성 상태 및 재생성 API")
@Validated
@RestController
@RequestMapping("/api/v1/reports")
public class ReportGenerationController {

  private final GuardianUserResolver guardianResolver;
  private final ReportGenerationService reportGenerationService;

  /**
   * 관찰 리포트 생성 API의 의존성을 구성한다.
   *
   * @param guardianResolver 인증 정보에서 보호자를 식별하는 경계
   * @param reportGenerationService 생성 상태 조회와 재생성을 처리하는 서비스
   */
  public ReportGenerationController(
      GuardianUserResolver guardianResolver, ReportGenerationService reportGenerationService) {
    this.guardianResolver = guardianResolver;
    this.reportGenerationService = reportGenerationService;
  }

  /**
   * 관찰 리포트의 현재 생성 상태와 재시도 가능 여부를 조회한다.
   *
   * @param reportId 조회할 관찰 리포트 식별자
   * @param authorization 운영 JWT가 전달되는 Authorization Header
   * @param guardianUserId 개발·테스트 환경에서만 사용하는 임시 보호자 Header
   * @return 관찰 리포트 생성 상태
   */
  @Operation(summary = "관찰 리포트 생성 상태 조회", description = "리포트 생성 상태와 실패 사유, 현재 재시도 가능 여부를 조회합니다.")
  @GetMapping("/{reportId}/generation-status")
  public ResponseEntity<ApiResponse<ReportGenerationStatusResponse>> getGenerationStatus(
      @PathVariable @Positive Long reportId,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    return ResponseEntity.ok(
        ApiResponse.ok(reportGenerationService.getStatus(guardianId, reportId)));
  }

  /**
   * 실패한 최신 관찰 리포트 생성을 새 버전으로 재접수한다.
   *
   * <p>같은 {@code Idempotency-Key}와 같은 리포트로 재호출하면 최초 접수 결과를 반환한다.
   *
   * @param reportId 재생성의 기준이 되는 실패 리포트 식별자
   * @param idempotencyKey 재시도 요청을 식별하는 {@code Idempotency-Key} Header 값
   * @param authorization 운영 JWT가 전달되는 Authorization Header
   * @param guardianUserId 개발·테스트 환경에서만 사용하는 임시 보호자 Header
   * @return 새로 접수된 관찰 리포트 생성 상태
   */
  @Operation(summary = "관찰 리포트 생성 재접수", description = "최신 실패 리포트를 기준으로 새 버전의 리포트 생성을 비동기로 접수합니다.")
  @PostMapping("/{reportId}/regenerate")
  public ResponseEntity<ApiResponse<ReportGenerationStatusResponse>> regenerate(
      @PathVariable @Positive Long reportId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    ReportGenerationStatusResponse response =
        reportGenerationService.regenerate(guardianId, reportId, idempotencyKey);
    URI statusLocation =
        URI.create("/api/v1/reports/" + response.reportId() + "/generation-status");
    return ResponseEntity.accepted().location(statusLocation).body(ApiResponse.ok(response));
  }
}
