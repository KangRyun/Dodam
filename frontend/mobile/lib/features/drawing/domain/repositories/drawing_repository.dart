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
    required UploadDrawingImageMetadataDto metadata,
    required String idempotencyKey,
  });
  Future<ObjectDetectionResponseDto> requestObjectDetection(
    int sessionId,
    ObjectDetectionRequestDto request,
  );
}

abstract interface class UploadedDrawingCompletionRepository {
  Future<DrawingStageCompleteResponseDto> completeUploadedDrawingStage(
    int sessionId, {
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  });
}

abstract interface class HtpDrawingRepository {
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  );
  Future<HtpAssessmentDto> getHtpAssessment(int assessmentId);
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
  });
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  );
  Future<void> completeHtpAssessment(int assessmentId);
}

/// 진행 중인 활동을 폐기하고 새 활동을 시작할 때 사용하는 선택 계약.
abstract interface class DrawingSessionDiscarder {
  Future<void> deleteSession(int sessionId);
}
