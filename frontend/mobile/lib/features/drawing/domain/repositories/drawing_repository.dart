import 'dart:typed_data';

import '../../data/dto/drawing_dtos.dart';
import '../../../../core/network/api_page.dart';

abstract interface class DrawingRepository {
  // TODO(API): Add emotion/final-completion orchestration only after the
  // /emotions versus /analysis state-transition contract is resolved.
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  });
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  );
  Future<DrawingSessionDto> getSession(int sessionId);
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId);
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  );
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState,
  );
  Future<DraftRecoveryDto?> getDraft(int sessionId);
  Future<Uint8List> downloadDraftPreview(String previewUrl);
  Future<void> deleteDraft(int sessionId);
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  });
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  );
  Future<DrawingCompletionResponseDto> completeActivity(
    int sessionId, {
    required CompleteActivityRequestDto request,
    required String idempotencyKey,
  });
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    String? objectCode,
  });
  Future<ObjectDetectionResponseDto> requestObjectDetection(
    int sessionId,
    ObjectDetectionRequestDto request,
  );
}
