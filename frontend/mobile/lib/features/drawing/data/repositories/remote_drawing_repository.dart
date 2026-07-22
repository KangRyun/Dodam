import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/repositories/drawing_repository.dart';
import '../dto/drawing_dtos.dart';

FormData buildDraftFormData(BinaryUploadDto image, {int? lastEventSequence}) =>
    FormData.fromMap({
      'image': MultipartFile.fromBytes(
        image.bytes,
        filename: image.fileName,
        contentType: DioMediaType.parse(image.mimeType),
      ),
      if (lastEventSequence != null)
        'lastEventSequence': lastEventSequence.toString(),
    });

final class RemoteDrawingRepository implements DrawingRepository {
  const RemoteDrawingRepository(this._apiClient);
  final ApiClient _apiClient;

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    int? childId,
    String? ageGroup,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'drawing-types',
      queryParameters: {'childId': ?childId, 'ageGroup': ?ageGroup},
    );
    return ApiPage.fromJson(response.data!, DrawingTypeDto.fromJson);
  }

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions',
      data: request.toJson(),
    );
    return DrawingSessionDto.fromJson(response.data!);
  }

  @override
  Future<DrawingSessionDto> getSession(int sessionId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'drawing-sessions/$sessionId',
    );
    return DrawingSessionDto.fromJson(response.data!);
  }

  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/strokes',
      data: request.toJson(),
    );
    return StrokeBatchResponseDto.fromJson(response.data!);
  }

  @override
  Future<DrawingAssetDto> saveDraft(
    int sessionId,
    BinaryUploadDto image, {
    int? lastEventSequence,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/draft',
      data: buildDraftFormData(image, lastEventSequence: lastEventSequence),
    );
    return DrawingAssetDto.fromJson(response.data!);
  }

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/draft',
    );
    final data = response.data;
    if (data == null || data.isEmpty) return null;
    return DraftRecoveryDto.fromJson(data);
  }

  @override
  Future<void> deleteDraft(int sessionId) async {
    await _apiClient.delete<void>('drawing-sessions/$sessionId/draft');
  }

  @override
  Future<CompleteDrawingResponseDto> completeDrawing(
    int sessionId, {
    BinaryUploadDto? image,
    int? lastEventSequence,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/complete',
      data: FormData.fromMap({
        if (image != null)
          'image': MultipartFile.fromBytes(
            image.bytes,
            filename: image.fileName,
            contentType: DioMediaType.parse(image.mimeType),
          ),
        if (lastEventSequence != null)
          'lastEventSequence': lastEventSequence.toString(),
      }),
    );
    return CompleteDrawingResponseDto.fromJson(response.data!);
  }

  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    String? objectCode,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/upload',
      data: FormData.fromMap({
        'image': MultipartFile.fromBytes(
          image.bytes,
          filename: image.fileName,
          contentType: DioMediaType.parse(image.mimeType),
        ),
        'objectCode': ?objectCode,
      }),
    );
    return DrawingUploadResponseDto.fromJson(response.data!);
  }

  @override
  Future<AnalysisAcceptedDto> requestAnalysis(
    int sessionId,
    RequestAnalysisDto request, {
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/analysis',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return AnalysisAcceptedDto.fromJson(response.data!);
  }
}
