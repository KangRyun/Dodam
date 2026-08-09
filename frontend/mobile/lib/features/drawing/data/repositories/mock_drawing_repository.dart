import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/network/network.dart';
import '../../domain/repositories/drawing_repository.dart';
import '../dto/drawing_dtos.dart';

enum MockDraftScenario { found, absent, failure }

enum MockCompletionScenario { success, failure }

enum MockReflectionScenario { success, failure }

final class MockDrawingRepository
    implements
        DrawingRepository,
        HtpDrawingRepository,
        UploadedDrawingCompletionRepository,
        DrawingSessionDiscarder {
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
    'selectableBy': 'BOTH',
    'recommendedAgeMin': 4,
    'recommendedAgeMax': 12,
    'guideText': '오늘 있었던 일을 그림으로 그려 볼까?',
    'displayOrder': 1,
  };
  static const _htpType = {
    'drawingTypeId': 6,
    'code': 'HTP',
    'name': '집·나무·사람 그림',
    'activityCategory': 'ASSESSMENT',
    'selectableBy': 'GUARDIAN',
    'recommendedAgeMin': 4,
    'recommendedAgeMax': 12,
    'guideText': '집, 나무, 사람을 차례로 그려 볼까요?',
    'displayOrder': 2,
  };
  static const _asset = {
    'assetId': 120,
    'assetType': 'DRAFT',
    'assetVersion': 3,
    'fileUrl': '/api/v1/drawing-assets/120/file',
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
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async => ApiPage(
    content: [
      DrawingTypeDto.fromJson(_type),
      DrawingTypeDto.fromJson(_htpType),
    ],
    page: 0,
    size: 2,
    totalElements: 2,
    totalPages: 1,
    hasNext: false,
  );
  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async => DrawingSessionDto.fromCreateJson({
    ..._session,
    'sessionStatus': 'DRAWING',
    'currentStage': 'DRAWING',
    'guideText': _type['guideText'],
  });

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) async => HtpAssessmentDto.fromJson(_htpAssessment);

  @override
  Future<HtpAssessmentDto> getHtpAssessment(int assessmentId) async =>
      HtpAssessmentDto.fromJson(_htpAssessment);

  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async => HtpAssessmentDto.fromJson({
    ..._htpAssessment,
    'currentStep': {
      'stepOrder': 2,
      'drawingSubject': 'TREE',
      'drawingSessionId': 43,
      'sessionStatus': 'IN_PROGRESS',
      'currentStage': 'DRAWING',
    },
  });

  @override
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  ) async {}

  @override
  Future<void> completeHtpAssessment(
    int assessmentId, {
    required String idempotencyKey,
  }) async {}
  @override
  Future<DrawingSessionDto> getSession(int sessionId) async =>
      DrawingSessionDto.fromDetailJson({
        ..._session,
        'child': {'childId': _session['childId'], 'nickname': '도담'},
      });
  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;
  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async => StrokeBatchResponseDto.fromJson({
    'batchId': 501,
    'batchSequence': request.batchSequence,
    'acceptedEventCount': request.events.length,
    'lastEventSequence': request.lastEventSequence,
    'receivedAt': '2026-07-21T09:41:03.542Z',
  });
  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState, {
    required String idempotencyKey,
  }) async => DraftSaveResponseDto.fromJson({
    'drawingAssetId': 120,
    'assetVersion': 3,
    'lastEventSequence': canvasState.lastEventSequence,
    'savedAt': '2026-07-21T09:41:10Z',
    'expiresAt': '2026-07-28T09:41:10Z',
  });
  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async {
    switch (draftScenario) {
      case MockDraftScenario.absent:
        return null;
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
  Future<Uint8List> downloadDraftPreview(String previewUrl) async =>
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1Pe'
        'AAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
      );

  @override
  Future<void> deleteDraft(int sessionId) async {}

  @override
  Future<void> deleteSession(int sessionId) async {}
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
      'currentStage': 'CONVERSING',
      'analysis': {
        'analysisId': 700,
        'analysisType': 'OBJECT_DETECTION',
        'status': 'SUCCEEDED',
      },
      'nextAction': 'SELECT_EMOTION',
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
  Future<DrawingCompletionResponseDto> completeActivity(
    int sessionId, {
    required CompleteActivityRequestDto request,
    required String idempotencyKey,
  }) async => DrawingCompletionResponseDto.fromJson({
    'drawingSessionId': sessionId,
    'sessionStatus': 'IN_PROGRESS',
    'currentStage': 'REPORTING',
    'analysisId': 701,
    'analysisStatus': 'PENDING',
    'reportId': 501,
    'reportStatus': 'GENERATING',
  });

  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    required UploadDrawingImageMetadataDto metadata,
    required String idempotencyKey,
  }) async => DrawingUploadResponseDto.fromJson({
    'drawingSessionId': sessionId,
    'drawingAssetId': 130,
    'assetType': 'UPLOADED',
    'drawingSubject': 'HOUSE',
    'currentStage': 'DRAWING',
    'previewUrl': '/api/v1/drawing-assets/130/file',
    'mimeType': image.mimeType,
    'fileSizeBytes': image.bytes.length,
    'widthPx': 1200,
    'heightPx': 800,
    'capturedAt': '2026-07-29T01:00:00Z',
    'uploadedAt': '2026-07-29T01:00:01Z',
    'qualityWarnings': const <String>[],
  });

  @override
  Future<DrawingStageCompleteResponseDto> completeUploadedDrawingStage(
    int sessionId, {
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) async => DrawingStageCompleteResponseDto.fromJson({
    'drawingSessionId': sessionId,
    'finalAssetId': metadata.sourceAssetId,
    'sessionStatus': 'IN_PROGRESS',
    'currentStage': 'CONVERSING',
    'analysis': {
      'analysisId': 15901,
      'analysisType': 'OBJECT_DETECTION',
      'status': 'SUCCEEDED',
    },
    'nextAction': 'SELECT_EMOTION',
  });
  @override
  Future<ObjectDetectionResponseDto> requestObjectDetection(
    int sessionId,
    ObjectDetectionRequestDto request,
  ) async => ObjectDetectionResponseDto.fromJson({
    'drawingAnalysisId': 15901,
    'drawingSessionId': sessionId,
    'drawingAssetId': request.drawingAssetId,
    'requestId': '550e8400-e29b-41d4-a716-446655440000',
    'analysisType': 'OBJECT_DETECTION',
    'status': 'SUCCEEDED',
    'model': {'name': 'dodam-detector', 'version': '1.0'},
    'detections': const [
      {
        'label': 'HOUSE',
        'confidence': 0.94,
        'boundingBox': {'x': 120.0, 'y': 80.0, 'width': 320.0, 'height': 280.0},
      },
    ],
    'requestedAt': '2026-07-21T09:41:12Z',
    'processedAt': '2026-07-21T09:41:13Z',
  });

  static const _htpAssessment = {
    'htpAssessmentId': 7,
    'status': 'IN_PROGRESS',
    'expiresAt': '2026-07-30T09:30:00Z',
    'currentStep': {
      'stepOrder': 1,
      'drawingSubject': 'HOUSE',
      'drawingSessionId': 42,
      'sessionStatus': 'IN_PROGRESS',
      'currentStage': 'DRAWING',
    },
    'allStepsCompleted': false,
  };
}
