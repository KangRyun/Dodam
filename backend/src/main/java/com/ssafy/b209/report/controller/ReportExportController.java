package com.ssafy.b209.report.controller;

import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.report.dto.ReportExportResponse;
import com.ssafy.b209.report.dto.ReportPdfFile;
import com.ssafy.b209.report.service.ReportExportService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 보호자용 관찰 리포트 PDF 내보내기와 인증 파일 다운로드 API다. */
@Tag(name = "Reports", description = "관찰 리포트 조회·내보내기 API")
@RestController
@RequestMapping("/api/v1/reports/{reportId}/exports")
public class ReportExportController {

  private final GuardianUserResolver guardianResolver;
  private final ReportExportService reportExportService;

  /**
   * 리포트 내보내기 API 의존성을 생성한다.
   *
   * @param guardianResolver 인증 Header에서 보호자를 식별하는 경계
   * @param reportExportService 리포트 권한 검증과 PDF 생성을 담당하는 서비스
   */
  public ReportExportController(
      GuardianUserResolver guardianResolver, ReportExportService reportExportService) {
    this.guardianResolver = guardianResolver;
    this.reportExportService = reportExportService;
  }

  /**
   * 완료된 관찰 리포트의 PDF 내보내기를 접수한다.
   *
   * @param reportId 리포트 식별자
   * @param idempotencyKey 모바일 재시도를 구분하는 Idempotency-Key
   * @param authorization 운영 JWT Authorization Header
   * @param guardianUserId 개발·테스트 프로필 전용 보호자 식별 Header
   * @return HTTP 202와 상태 조회 위치
   */
  @Operation(summary = "관찰 리포트 PDF 내보내기 접수")
  @PostMapping
  public ResponseEntity<ApiResponse<ReportExportResponse>> requestExport(
      @PathVariable Long reportId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    ReportExportResponse response =
        reportExportService.requestExport(guardianId, reportId, idempotencyKey);
    URI location = URI.create("/api/v1/reports/" + reportId + "/exports/" + response.exportId());
    return ResponseEntity.accepted().location(location).body(ApiResponse.ok(response));
  }

  /**
   * 리포트 PDF 내보내기 상태와 다운로드 URI를 조회한다.
   *
   * @param reportId 리포트 식별자
   * @param exportId 내보내기 식별자
   * @param authorization 운영 JWT Authorization Header
   * @param guardianUserId 개발·테스트 프로필 전용 보호자 식별 Header
   * @return 내보내기 상태
   */
  @Operation(summary = "관찰 리포트 PDF 내보내기 상태 조회")
  @GetMapping("/{exportId}")
  public ResponseEntity<ApiResponse<ReportExportResponse>> getExport(
      @PathVariable Long reportId,
      @PathVariable Long exportId,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    return ResponseEntity.ok(
        ApiResponse.ok(reportExportService.getExport(guardianId, reportId, exportId)));
  }

  /**
   * 리포트 PDF를 인증된 응답으로 다운로드한다.
   *
   * @param reportId 리포트 식별자
   * @param exportId 내보내기 식별자
   * @param authorization 운영 JWT Authorization Header
   * @param guardianUserId 개발·테스트 프로필 전용 보호자 식별 Header
   * @return attachment Content-Disposition을 가진 PDF 바이트
   */
  @Operation(summary = "관찰 리포트 PDF 파일 다운로드")
  @GetMapping(value = "/{exportId}/file", produces = MediaType.APPLICATION_PDF_VALUE)
  public ResponseEntity<byte[]> download(
      @PathVariable Long reportId,
      @PathVariable Long exportId,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    ReportPdfFile file = reportExportService.download(guardianId, reportId, exportId);
    byte[] content = file.content();
    ContentDisposition disposition =
        ContentDisposition.attachment().filename(file.fileName(), StandardCharsets.UTF_8).build();
    return ResponseEntity.ok()
        .contentType(MediaType.APPLICATION_PDF)
        .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
        .contentLength(content.length)
        .body(content);
  }
}
