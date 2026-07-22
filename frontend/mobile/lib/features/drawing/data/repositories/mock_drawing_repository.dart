import '../../../../core/network/network.dart';
import '../../domain/repositories/drawing_repository.dart';
import '../dto/drawing_dtos.dart';

enum MockDraftScenario { found, absent, failure }

enum MockCompletionScenario { success, failure }

enum MockReflectionScenario { success, failure }

final class MockDrawingRepository implements DrawingRepository {
  const MockDrawingRepository({
    this.draftScenario = MockDraftScenario.found,
    this.completionScenario = MockCompletionScenario.success,
    this.reflectionScenario = MockReflectionScenario.success,
  });

  final MockDraftScenario draftScenario;
  final MockCompletionScenario completionScenario;
  final MockReflectionScenario reflectionScenario;
  static const _type = {
    'drawingTypeId': 5,
    'code': 'ART_DIARY',
    'name': '그림일기',
    'activityCategory': 'GENERAL',
    'selectableBy': 'GUARDIAN_OR_CHILD',
    'recommendedAgeMin': 4,
    'recommendedAgeMax': 12,
    'guideText': '오늘 있었던 일을 그림으로 그려 볼까?',
    'displayOrder': 1,
  };
  static const _asset = {
    'assetId': 120,
    'assetType': 'DRAFT',
    'assetVersion': 3,
    'fileUrl': 'https://storage.i15b209.p.ssafy.io/drawings/42/draft/v3.png',
    'mimeType': 'image/png',
    'fileSizeBytes': 384512,
    'widthPx': 1536,
    'heightPx': 1024,
    'checksumSha256': '9f2c1a7e0b4d',
    'expiresAt': '2026-07-28T09:41:10Z',
    'createdAt': '2026-07-21T09:41:10Z',
  };
  static const _session = {
    'drawingSessionId': 42,
    'childId': 3,
    'drawingType': {'drawingTypeId': 5, 'code': 'ART_DIARY', 'name': '그림일기'},
    'inputMethod': 'CANVAS',
    'title': '우리 가족 소풍',
    'sessionStatus': 'CONVERSING',
    'currentStage': 'CONVERSING',
    'selectedEmotions': null,
    'expressedEmotionText': null,
    'startedAt': '2026-07-21T09:30:00Z',
    'completedAt': null,
    'conversation': null,
    'latestAnalysis': null,
    'assets': [_asset],
  };

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    int? childId,
    String? ageGroup,
  }) async => ApiPage(
    content: [DrawingTypeDto.fromJson(_type)],
    page: 0,
    size: 100,
    totalElements: 1,
    totalPages: 1,
    hasNext: false,
  );
  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async => DrawingSessionDto.fromJson({
    ..._session,
    'sessionStatus': 'DRAWING',
    'currentStage': 'DRAWING',
    'guideText': _type['guideText'],
  });
  @override
  Future<DrawingSessionDto> getSession(int sessionId) async =>
      DrawingSessionDto.fromJson(_session);
  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async => StrokeBatchResponseDto.fromJson({
    'strokeBatchId': 501,
    'batchSequence': request.batchSequence,
    'eventCount': request.events.length,
    'receivedAt': '2026-07-21T09:41:03.542Z',
  });
  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState,
  ) async => DraftSaveResponseDto.fromJson({
    'drawingAssetId': 120,
    'assetVersion': 3,
    'lastEventSequence': canvasState.lastEventSequence,
    'savedAt': '2026-07-21T09:41:10Z',
    'expiresAt': '2026-07-28T09:41:10Z',
  });
  @override
  Future<DraftRecoveryDto> getDraft(int sessionId) async {
    switch (draftScenario) {
      case MockDraftScenario.absent:
        throw ApiResponseFailure(
          statusCode: 404,
          error: ApiError(
            timestamp: '2026-07-22T00:00:00Z',
            path: '/api/v1/drawing-sessions/$sessionId/draft',
            code: 'DRAWING_DRAFT_NOT_FOUND',
            message: 'Draft not found',
          ),
        );
      case MockDraftScenario.failure:
        throw const ApiTransportFailure(
          type: ApiTransportFailureType.connection,
        );
      case MockDraftScenario.found:
        return DraftRecoveryDto.fromJson({
          'previewUrl': _asset['fileUrl'],
          'canvasState': {
            'lastEventSequence': 1105,
            'toolState': null,
            'viewport': null,
            'clientSavedAt': '2026-07-21T09:41:10Z',
          },
          'assetVersion': 3,
        });
    }
  }

  @override
  Future<void> deleteDraft(int sessionId) async {}
  @override
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) async {
    if (completionScenario == MockCompletionScenario.failure) {
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    return DrawingStageCompleteResponseDto.fromJson({
      'drawingSessionId': 42,
      'finalAssetId': 140,
      'sessionStatus': 'IN_PROGRESS',
      'currentStage': 'ANALYZING',
      'analysis': {
        'analysisId': 700,
        'analysisType': 'INTERMEDIATE',
        'status': 'PENDING',
      },
      'nextAction': 'POLL_ANALYSIS',
    });
  }

  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    if (reflectionScenario == MockReflectionScenario.failure) {
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
  }

  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    String? objectCode,
  }) async => DrawingUploadResponseDto.fromJson({
    'drawingSessionId': 43,
    'objectCode': 'TREE',
    'originalAsset': {..._asset, 'assetId': 130, 'assetType': 'ORIGINAL'},
    'correctedAsset': {..._asset, 'assetId': 131, 'assetType': 'CORRECTED'},
  });
  @override
  Future<AnalysisAcceptedDto> requestAnalysis(
    int sessionId,
    RequestAnalysisDto request, {
    required String idempotencyKey,
  }) async => AnalysisAcceptedDto.fromJson(const {
    'analysisId': 15901,
    'drawingSessionId': 481,
    'analysisType': 'FINAL',
    'analysisStatus': 'PENDING',
    'requestedAt': '2026-07-21T09:41:12Z',
  });
}
