import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../domain/repositories/report_repository.dart';
import '../dto/report_dtos.dart';

final class RemoteReportRepository implements ReportRepository {
  const RemoteReportRepository(this._apiClient);
  final ApiClient _apiClient;
  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'children/$childId/reports',
      queryParameters: filter.toQueryParameters(),
    );
    return ApiPage.fromJson(response.data!, ReportSummaryDto.fromJson);
  }

  @override
  Future<ReportDetailDto> getReport(int reportId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'reports/$reportId',
    );
    return ReportDetailDto.fromJson(response.data!);
  }

  @override
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'analyses/$analysisId',
    );
    return AnalysisStatusDto.fromJson(response.data!);
  }

  @override
  Future<AnalysisAcceptedDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'analyses/$analysisId/retry',
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return AnalysisAcceptedDto.fromJson(response.data!);
  }
}
