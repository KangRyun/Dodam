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

/// 업로드 요청이 전송한 바이트 수와 전체 바이트 수를 전달하는 callback이다.
typedef DrawingUploadProgressCallback = void Function(int sent, int total);

/// 사진 업로드의 실제 전송 진행률을 제공하는 [DrawingRepository] capability다.
///
/// Mock처럼 진행률을 제공하지 않는 구현은 기존 [DrawingRepository]만 구현할 수
/// 있으며, 화면은 이 capability가 없을 때 기존 로딩 상태를 유지한다.
abstract interface class DrawingUploadProgressRepository
    implements DrawingRepository {
  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    required UploadDrawingImageMetadataDto metadata,
    required String idempotencyKey,
    DrawingUploadProgressCallback? onProgress,
  });
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
    required String idempotencyKey,
  });
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  );
  Future<void> completeHtpAssessment(
    int assessmentId, {
    required String idempotencyKey,
  });
}

/// 진행 중인 활동을 폐기하고 새 활동을 시작할 때 사용하는 선택 계약.
abstract interface class DrawingSessionDiscarder {
  Future<void> deleteSession(int sessionId);
}
