import 'dart:typed_data';

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
  Future<ReportGenerationStatusDto> getGenerationStatus(int reportId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'reports/$reportId/generation-status',
    );
    return ReportGenerationStatusDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<ReportGenerationStatusDto> regenerateReport(
    int reportId, {
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'reports/$reportId/regenerate',
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return ReportGenerationStatusDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<Uint8List> downloadImage(String imageUrl) async {
    final path = _reportImageApiPath(imageUrl);
    final response = await _apiClient.get<Uint8List>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? Uint8List(0);
  }

  @override
  Future<ReportExportDto> requestExport(
    int reportId, {
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'reports/$reportId/exports',
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return ReportExportDto.fromJson(envelopeObject(response.data));
  }

  /// 리포트 PDF를 내려받는다.
  ///
  /// `Accept`를 PDF로 덮어써야 한다. [ApiClient]가 모든 요청에 `Accept: application/json`을
  /// 붙이는데(`api_client.dart`), 이 응답은 JSON이 아니라 PDF다. 그대로 두면 서버가 콘텐츠 협상에서
  /// 요청을 거부하고, 그 실패가 컨트롤러 밖에서 나 `COMMON_500_001`(미분류 서버 오류)로 보인다 —
  /// PDF 저장·공유가 계속 실패한 원인이 이것이었다(S15P11B209-860).
  ///
  /// 그림·음성 파일 조회는 서버가 스트리밍으로 응답해 협상을 타지 않아 같은 헤더로도 동작한다. PDF만
  /// 깨진 이유다.
  @override
  Future<Uint8List> downloadExport(String downloadUrl) async {
    final path = _reportExportApiPath(downloadUrl);
    final response = await _apiClient.get<Uint8List>(
      path,
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {'Accept': 'application/pdf'},
      ),
    );
    return response.data ?? Uint8List(0);
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

String _reportExportApiPath(String downloadUrl) {
  final uri = Uri.tryParse(downloadUrl);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw ArgumentError.value(downloadUrl, 'downloadUrl');
  }
  if (!RegExp(
    r'^/api/v1/reports/[1-9][0-9]*/exports/[1-9][0-9]*/file$',
  ).hasMatch(uri.path)) {
    throw ArgumentError.value(downloadUrl, 'downloadUrl');
  }
  return uri.path.substring('/api/v1/'.length);
}

String _reportImageApiPath(String imageUrl) {
  final match = RegExp(
    r'^/api/v1/drawing-assets/([1-9][0-9]*)/file$',
  ).firstMatch(imageUrl);
  if (match == null) throw ArgumentError.value(imageUrl, 'imageUrl');
  return 'drawing-assets/${match.group(1)}/file';
}
