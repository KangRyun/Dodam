import '../../../../core/network/api_page.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../data/dto/report_dtos.dart';

abstract interface class ReportRepository {
  // TODO(API): PDF and complaint APIs remain excluded while their proposal
  // status and backing schemas are unresolved.
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  });
  Future<ReportDetailDto> getReport(int reportId);
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId);
  Future<AnalysisAcceptedDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  });
}
