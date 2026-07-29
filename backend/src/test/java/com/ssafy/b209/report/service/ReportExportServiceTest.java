package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportExportResponse;
import com.ssafy.b209.report.dto.ReportPdfFile;
import com.ssafy.b209.report.exception.ReportExportErrorCode;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ReportExportServiceTest {

  @Mock private ReportDetailQueryService reportDetailQueryService;
  @Mock private ReportPdfRenderer reportPdfRenderer;

  private ReportExportService service;

  @BeforeEach
  void setUp() {
    service = new ReportExportService(reportDetailQueryService, reportPdfRenderer);
  }

  @Test
  void returnsStableExportForCompletedReport() {
    when(reportDetailQueryService.getReport(10L, 500L)).thenReturn(report("COMPLETED"));

    ReportExportResponse response = service.requestExport(10L, 500L, "report-export-500");

    assertThat(response.exportId()).isEqualTo(500L);
    assertThat(response.status()).isEqualTo("COMPLETED");
    assertThat(response.downloadUrl()).endsWith("/reports/500/exports/500/file");
  }

  @Test
  void rejectsExportUntilReportIsCompleted() {
    when(reportDetailQueryService.getReport(10L, 500L)).thenReturn(report("GENERATING"));

    assertThatThrownBy(() -> service.requestExport(10L, 500L, "report-export-500"))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ReportExportErrorCode.REPORT_EXPORT_NOT_READY);
  }

  @Test
  void rejectsMismatchedExportIdBeforeReadingReport() {
    assertThatThrownBy(() -> service.getExport(10L, 500L, 501L))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ReportExportErrorCode.REPORT_EXPORT_NOT_FOUND);
  }

  @Test
  void rendersAuthenticatedCompletedReportForDownload() {
    ReportDetailResponse report = report("COMPLETED");
    when(reportDetailQueryService.getReport(10L, 500L)).thenReturn(report);
    when(reportPdfRenderer.render(report)).thenReturn("%PDF".getBytes());

    ReportPdfFile file = service.download(10L, 500L, 500L);

    assertThat(file.fileName()).isEqualTo("dodam-report-500.pdf");
    assertThat(file.content()).startsWith("%PDF".getBytes());
    verify(reportPdfRenderer).render(report);
  }

  private ReportDetailResponse report(String status) {
    return new ReportDetailResponse(
        500L,
        1,
        status,
        null,
        null,
        null,
        null,
        null,
        List.of(),
        List.of("이 리포트는 진단 자료가 아닙니다."),
        null,
        LocalDateTime.of(2026, 7, 29, 9, 0));
  }
}
