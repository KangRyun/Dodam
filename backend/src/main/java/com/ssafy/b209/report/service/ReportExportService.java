package com.ssafy.b209.report.service;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportExportResponse;
import com.ssafy.b209.report.dto.ReportPdfFile;
import com.ssafy.b209.report.exception.ReportExportErrorCode;
import org.springframework.stereotype.Service;

/**
 * 보호자 리포트의 내보내기 상태와 PDF 파일 생성을 조정한다.
 *
 * <p>현재 리포트 상세은 변경 불가능한 버전 단위 결과이므로 {@code reportId}를 안정적인 {@code exportId}로 재사용한다. 파일 URI를 호출할 때마다
 * 보호자 권한과 리포트 완료 상태를 다시 검증해 공유 가능한 고정 URL을 만들지 않는다.
 */
@Service
public class ReportExportService {

  private static final int IDEMPOTENCY_KEY_MIN_LENGTH = 8;
  private static final int IDEMPOTENCY_KEY_MAX_LENGTH = 100;

  private final ReportDetailQueryService reportDetailQueryService;
  private final ReportPdfRenderer reportPdfRenderer;

  /**
   * 리포트 내보내기 의존성을 생성한다.
   *
   * @param reportDetailQueryService 보호자 권한과 공개 필드를 검증하는 상세 조회 서비스
   * @param reportPdfRenderer 공개 리포트 DTO를 PDF로 렌더링하는 구성 요소
   */
  public ReportExportService(
      ReportDetailQueryService reportDetailQueryService, ReportPdfRenderer reportPdfRenderer) {
    this.reportDetailQueryService = reportDetailQueryService;
    this.reportPdfRenderer = reportPdfRenderer;
  }

  /**
   * 완료된 리포트의 PDF 내보내기를 멱등적으로 접수한다.
   *
   * @param guardianUserId 인증된 보호자 식별자
   * @param reportId 원본 리포트 식별자
   * @param idempotencyKey 모바일 재시도를 식별하는 Header 값
   * @return 즉시 사용할 수 있는 내보내기 상태와 인증 파일 URI
   * @throws BusinessException 권한이 없거나 리포트가 완료되지 않았거나 멱등성 키가 잘못된 경우
   */
  public ReportExportResponse requestExport(
      Long guardianUserId, Long reportId, String idempotencyKey) {
    validateIdempotencyKey(idempotencyKey);
    ReportDetailResponse report = completedReport(guardianUserId, reportId);
    return response(report.reportId());
  }

  /**
   * 기존 내보내기의 현재 상태와 파일 URI를 조회한다.
   *
   * @param guardianUserId 인증된 보호자 식별자
   * @param reportId 원본 리포트 식별자
   * @param exportId 내보내기 결과 식별자
   * @return 완료된 내보내기 상태
   * @throws BusinessException 식별자가 일치하지 않거나 접근할 수 없는 경우
   */
  public ReportExportResponse getExport(Long guardianUserId, Long reportId, Long exportId) {
    validateExportId(reportId, exportId);
    ReportDetailResponse report = completedReport(guardianUserId, reportId);
    return response(report.reportId());
  }

  /**
   * 보호자에게 공개 가능한 리포트 상세를 PDF 파일로 생성한다.
   *
   * @param guardianUserId 인증된 보호자 식별자
   * @param reportId 원본 리포트 식별자
   * @param exportId 내보내기 결과 식별자
   * @return 다운로드 파일명과 PDF 바이트
   * @throws BusinessException 식별자·권한·상태 검증 또는 PDF 생성에 실패한 경우
   */
  public ReportPdfFile download(Long guardianUserId, Long reportId, Long exportId) {
    validateExportId(reportId, exportId);
    ReportDetailResponse report = completedReport(guardianUserId, reportId);
    return new ReportPdfFile(
        "dodam-report-" + report.reportId() + ".pdf", reportPdfRenderer.render(report));
  }

  private ReportDetailResponse completedReport(Long guardianUserId, Long reportId) {
    ReportDetailResponse report = reportDetailQueryService.getReport(guardianUserId, reportId);
    if (!"COMPLETED".equals(report.reportStatus())) {
      throw new BusinessException(ReportExportErrorCode.REPORT_EXPORT_NOT_READY);
    }
    return report;
  }

  private ReportExportResponse response(Long reportId) {
    return new ReportExportResponse(
        reportId,
        reportId,
        "COMPLETED",
        "/api/v1/reports/" + reportId + "/exports/" + reportId + "/file");
  }

  private void validateExportId(Long reportId, Long exportId) {
    if (reportId == null || !reportId.equals(exportId)) {
      throw new BusinessException(ReportExportErrorCode.REPORT_EXPORT_NOT_FOUND);
    }
  }

  private void validateIdempotencyKey(String idempotencyKey) {
    if (idempotencyKey == null || idempotencyKey.isBlank()) {
      throw new BusinessException(ReportExportErrorCode.IDEMPOTENCY_KEY_REQUIRED);
    }
    int length = idempotencyKey.length();
    if (length < IDEMPOTENCY_KEY_MIN_LENGTH
        || length > IDEMPOTENCY_KEY_MAX_LENGTH
        || !idempotencyKey.matches("[A-Za-z0-9._:-]+")) {
      throw new BusinessException(ReportExportErrorCode.IDEMPOTENCY_KEY_INVALID);
    }
  }
}
