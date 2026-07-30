import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
  'canvasState': MultipartFile.fromBytes(
    utf8.encode(
      jsonEncode({
        'lastEventSequence': canvasState.lastEventSequence,
        'clientSavedAt': canvasState.clientSavedAt,
      }),
    ),
    filename: 'canvas-state.json',
    contentType: DioMediaType.parse('application/json'),
  ),
});

FormData buildDrawingCompleteFormData(
  BinaryUploadDto? finalImage,
  DrawingCompleteMetadataDto metadata,
) => FormData.fromMap({
  if (finalImage != null)
    'finalImage': MultipartFile.fromBytes(
      finalImage.bytes,
      filename: 'drawing.png',
      contentType: DioMediaType.parse('image/png'),
    ),
  'metadata': MultipartFile.fromBytes(
    utf8.encode(jsonEncode(metadata.toJson())),
    filename: 'metadata.json',
    contentType: DioMediaType.parse('application/json'),
  ),
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

final class RemoteDrawingRepository
    implements
        DrawingUploadProgressRepository,
        HtpDrawingRepository,
        UploadedDrawingCompletionRepository,
        DrawingSessionDiscarder {
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
    return DrawingSessionDto.fromCreateJson(envelopeObject(response.data));
  }

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'htp-assessments',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': _idempotencyKey()}),
    );
    return HtpAssessmentDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<HtpAssessmentDto> getHtpAssessment(int assessmentId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'htp-assessments/$assessmentId',
    );
    return HtpAssessmentDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'htp-assessments/$assessmentId/steps/next',
      data: {'inputMethod': inputMethod},
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return HtpAssessmentDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    await _apiClient.put<void>(
      'htp-assessments/$assessmentId/reflection',
      data: request.toJson(),
    );
  }

  @override
  Future<void> completeHtpAssessment(
    int assessmentId, {
    required String idempotencyKey,
  }) async {
    await _apiClient.post<void>(
      'htp-assessments/$assessmentId/complete',
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
  }

  @override
  Future<DrawingSessionDto> getSession(int sessionId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'drawing-sessions/$sessionId',
    );
    return DrawingSessionDto.fromDetailJson(envelopeObject(response.data));
  }

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        'drawing-sessions/active',
        queryParameters: {'childId': childId},
      );
      return ActiveDrawingSessionDto.fromJson(envelopeObject(response.data));
    } on ApiResponseFailure catch (failure) {
      if (failure.error?.code == 'DRAWING_404_005') return null;
      rethrow;
    }
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
    return DraftSaveResponseDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        'drawing-sessions/$sessionId/draft',
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      return DraftRecoveryDto.fromJson(_payload(data));
    } on ApiResponseFailure catch (failure) {
      if (failure.error?.code == 'DRAWING_404_004') return null;
      rethrow;
    }
  }

  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) async {
    final path = _draftPreviewApiPath(previewUrl);
    final response = await _apiClient.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Draft preview response is empty.');
    }
    return Uint8List.fromList(bytes);
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
  Future<void> deleteSession(int sessionId) async {
    await _apiClient.delete<void>(
      'drawing-sessions/$sessionId',
      data: const {'confirmation': 'DELETE'},
    );
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
    return DrawingStageCompleteResponseDto.fromJson(
      envelopeObject(response.data),
    );
  }

  @override
  Future<DrawingStageCompleteResponseDto> completeUploadedDrawingStage(
    int sessionId, {
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/drawing-complete',
      data: buildDrawingCompleteFormData(null, metadata),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return DrawingStageCompleteResponseDto.fromJson(
      envelopeObject(response.data),
    );
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
  Future<DrawingCompletionResponseDto> completeActivity(
    int sessionId, {
    required CompleteActivityRequestDto request,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/complete',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    if (response.statusCode != 202) {
      throw StateError(
        'Unexpected Drawing Activity Complete status: ${response.statusCode}',
      );
    }
    return DrawingCompletionResponseDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    required UploadDrawingImageMetadataDto metadata,
    required String idempotencyKey,
    DrawingUploadProgressCallback? onProgress,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'drawing-sessions/$sessionId/upload',
      data: FormData.fromMap({
        'image': MultipartFile.fromBytes(
          image.bytes,
          filename: image.fileName,
          contentType: DioMediaType.parse(image.mimeType),
        ),
        'metadata': MultipartFile.fromBytes(
          utf8.encode(jsonEncode(metadata.toJson())),
          filename: 'metadata.json',
          contentType: DioMediaType.parse('application/json'),
        ),
      }),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      onSendProgress: onProgress,
    );
    return DrawingUploadResponseDto.fromJson(envelopeObject(response.data));
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

String _draftPreviewApiPath(String previewUrl) {
  final uri = Uri.tryParse(previewUrl);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(previewUrl, 'previewUrl');
  }
  final match = RegExp(
    r'^/api/v1/drawing-assets/([1-9][0-9]*)/file$',
  ).firstMatch(uri.path);
  if (match == null) {
    throw ArgumentError.value(previewUrl, 'previewUrl');
  }
  return 'drawing-assets/${match.group(1)}/file';
}
