import '../../data/dto/drawing_dtos.dart';
import '../../../../core/network/api_page.dart';

abstract interface class DrawingRepository {
  // TODO(API): Add emotion/final-completion orchestration only after the
  // /emotions versus /analysis state-transition contract is resolved.
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    int? childId,
    String? ageGroup,
  });
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  );
  Future<DrawingSessionDto> getSession(int sessionId);
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  );
  Future<DrawingAssetDto> saveDraft(
    int sessionId,
    BinaryUploadDto image, {
    int? lastEventSequence,
  });
  Future<DraftRecoveryDto?> getDraft(int sessionId);
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
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    String? objectCode,
  });
  Future<AnalysisAcceptedDto> requestAnalysis(
    int sessionId,
    RequestAnalysisDto request, {
    required String idempotencyKey,
  });
}
