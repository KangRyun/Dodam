import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/repositories/drawing_repository.dart';
import '../dto/drawing_dtos.dart';

FormData buildDraftFormData(
  BinaryUploadDto preview,
  DraftCanvasStateDto canvasState,
) => FormData.fromMap({
  'preview': MultipartFile.fromBytes(
    preview.bytes,
    filename: preview.fileName,
    contentType: DioMediaType.parse(preview.mimeType),
  ),
  'canvasState': jsonEncode(canvasState.toJson()),
});

FormData buildDrawingCompleteFormData(
  BinaryUploadDto finalImage,
  DrawingCompleteMetadataDto metadata,
) => FormData.fromMap({
  'finalImage': MultipartFile.fromBytes(
    finalImage.bytes,
    filename: finalImage.fileName,
    contentType: DioMediaType.parse(finalImage.mimeType),
  ),
  'metadata': jsonEncode(metadata.toJson()),
});

String _idempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final class RemoteDrawingRepository implements DrawingRepository {
  const RemoteDrawingRepository(this._apiClient);
  final ApiClient _apiClient;

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'drawing-types',
      queryParameters: {
        'childId': childId,
        'category': ?category,
        'activeOnly': activeOnly,
      },
    );
    return ApiPage.fromJson(
      envelopeObject(response.data),
      DrawingTypeDto.fromJson,
    );
  }

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': _idempotencyKey()}),
    );
    return DrawingSessionDto.fromJson(envelopeObject(response.data));
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
      'drawing-sessions/$sessionId/stroke-batches',
      data: request.toJson(),
    );
    return StrokeBatchResponseDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState,
  ) async {
    final response = await _apiClient.put<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/draft',
      data: buildDraftFormData(preview, canvasState),
    );
    return DraftSaveResponseDto.fromJson(_payload(response.data!));
  }

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/draft',
    );
    final data = response.data;
    if (data == null || data.isEmpty) return null;
    return DraftRecoveryDto.fromJson(_payload(data));
  }

  Map<String, dynamic> _payload(Map<String, dynamic> body) =>
      body['data'] is Map
      ? Map<String, dynamic>.from(body['data']! as Map)
      : body;

  @override
  Future<void> deleteDraft(int sessionId) async {
    await _apiClient.delete<void>('drawing-sessions/$sessionId/draft');
  }

  @override
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/drawing-complete',
      data: buildDrawingCompleteFormData(finalImage, metadata),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    final body = response.data!;
    final payload = body['data'] is Map
        ? Map<String, dynamic>.from(body['data']! as Map)
        : body;
    return DrawingStageCompleteResponseDto.fromJson(payload);
  }

  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    await _apiClient.put<void>(
      'drawing-sessions/$sessionId/reflection',
      data: request.toJson(),
    );
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
  Future<ObjectDetectionResponseDto> requestObjectDetection(
    int sessionId,
    ObjectDetectionRequestDto request,
  ) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/analyses',
      data: request.toJson(),
    );
    return ObjectDetectionResponseDto.fromJson(_payload(response.data!));
  }
}
