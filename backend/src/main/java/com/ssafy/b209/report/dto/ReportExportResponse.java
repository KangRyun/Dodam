package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 보호자용 관찰 리포트 PDF 내보내기 상태다.
 *
 * @param reportId 원본 리포트 식별자
 * @param exportId 내보내기 결과 식별자
 * @param status 내보내기 상태
 * @param downloadUrl 인증된 PDF 파일 조회 URI
 */
@Schema(description = "관찰 리포트 PDF 내보내기 상태")
public record ReportExportResponse(
    Long reportId, Long exportId, String status, String downloadUrl) {}
