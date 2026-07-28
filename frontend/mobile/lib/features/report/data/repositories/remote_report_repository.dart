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
    return ApiPage.fromJson(
      envelopeObject(response.data),
      ReportSummaryDto.fromJson,
    );
  }

  /// REPORT-02 `GET /reports/{reportId}`.
  ///
  /// 성공 응답은 공통 봉투 `{success, code, message, data}`로 오므로
  /// `data`를 벗겨 DTO에 넘긴다. 401/403/404는 [ApiClient]가
  /// [ApiResponseFailure]로 변환해 그대로 올려보낸다.
  @override
  Future<ReportDetailDto> getReport(int reportId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'reports/$reportId',
    );
    return ReportDetailDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'analyses/$analysisId',
    );
    return AnalysisStatusDto.fromJson(envelopeObject(response.data));
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
    return AnalysisAcceptedDto.fromJson(envelopeObject(response.data));
  }
}
