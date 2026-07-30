import 'dart:typed_data';

import '../../../../core/network/api_page.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../data/dto/report_dtos.dart';

abstract interface class ReportRepository {
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  });
  Future<ReportDetailDto> getReport(int reportId);
  Future<ReportExportDto> requestExport(
    int reportId, {
    required String idempotencyKey,
  });
  Future<Uint8List> downloadExport(String downloadUrl);
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId);
  Future<AnalysisAcceptedDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  });
}
