import 'dart:convert';

import '../../../../core/network/api_page.dart';

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

final class BinaryUploadDto {
  const BinaryUploadDto({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });
  final List<int> bytes;
  final String fileName, mimeType;
}

final class DrawingTypeDto {
  const DrawingTypeDto({
    required this.drawingTypeId,
    required this.code,
    required this.name,
    required this.activityCategory,
    required this.selectableBy,
    required this.recommendedAgeMin,
    required this.recommendedAgeMax,
    required this.guideText,
    required this.displayOrder,
  });
  factory DrawingTypeDto.fromJson(Map<String, dynamic> json) => DrawingTypeDto(
    drawingTypeId: json['drawingTypeId'] as int,
    code: json['code'] as String,
    name: json['name'] as String,
    activityCategory: json['activityCategory'] as String,
    selectableBy: json['selectableBy'] as String,
    recommendedAgeMin: json['recommendedAgeMin'] as int?,
    recommendedAgeMax: json['recommendedAgeMax'] as int?,
    guideText: json['guideText'] as String?,
    displayOrder: json['displayOrder'] as int,
  );
  final int drawingTypeId;
  final String code, name, activityCategory, selectableBy;
  final String? guideText;
  final int? recommendedAgeMin, recommendedAgeMax;
  final int displayOrder;
}

final class DrawingTypeSummaryDto {
  const DrawingTypeSummaryDto({
    required this.drawingTypeId,
    required this.code,
    required this.name,
  });
  factory DrawingTypeSummaryDto.fromJson(Map<String, dynamic> json) =>
      DrawingTypeSummaryDto(
        drawingTypeId: json['drawingTypeId'] as int? ?? 0,
        code: json['code'] as String,
        name: json['name'] as String,
      );
  final int drawingTypeId;
  final String code, name;
}

final class CreateDrawingSessionRequestDto {
  const CreateDrawingSessionRequestDto({
    required this.childId,
    required this.drawingTypeId,
    required this.inputMethod,
    required this.clientStartedAt,
    this.selectionActor,
    this.canvasWidth,
    this.canvasHeight,
    this.canvasBackgroundColor,
    this.replaceActive = false,
  });
  final int childId, drawingTypeId;
  final String inputMethod;
  final String clientStartedAt;
  final String? selectionActor;
  final int? canvasWidth, canvasHeight;
  final String? canvasBackgroundColor;
  final bool replaceActive;
  Map<String, dynamic> toJson() => {
    'childId': childId,
    'drawingTypeId': drawingTypeId,
    'inputMethod': inputMethod,
    'clientStartedAt': clientStartedAt,
    if (selectionActor != null) 'selectionActor': selectionActor,
    if (replaceActive) 'replaceActive': true,
    if (canvasWidth != null &&
        canvasHeight != null &&
        canvasBackgroundColor != null)
      'canvas': {
        'width': canvasWidth,
        'height': canvasHeight,
        'backgroundColor': canvasBackgroundColor,
      },
  };
}

final class DrawingAssetDto {
  const DrawingAssetDto({
    required this.assetId,
    required this.assetType,
    required this.assetVersion,
    required this.fileUrl,
    required this.mimeType,
    this.fileSizeBytes,
    this.widthPx,
    this.heightPx,
    this.checksumSha256,
    this.expiresAt,
    this.createdAt,
    this.drawingSessionId,
  });
  factory DrawingAssetDto.fromJson(Map<String, dynamic> json) =>
      DrawingAssetDto(
        assetId: json['assetId'] as int,
        assetType: json['assetType'] as String,
        assetVersion: json['assetVersion'] as int,
        fileUrl: json['fileUrl'] as String,
        mimeType: json['mimeType'] as String,
        widthPx: json['widthPx'] as int?,
        heightPx: json['heightPx'] as int?,
        fileSizeBytes: json['fileSizeBytes'] as int?,
        checksumSha256: json['checksumSha256'] as String?,
        expiresAt: json['expiresAt'] as String?,
        createdAt: json['createdAt'] as String?,
        drawingSessionId: json['drawingSessionId'] as int?,
      );
  final int assetId, assetVersion;
  final int? widthPx, heightPx;
  final String assetType, fileUrl, mimeType;
  final int? fileSizeBytes;
  final int? drawingSessionId;
  final String? checksumSha256, expiresAt, createdAt;
}

final class DrawingSessionDto {
  const DrawingSessionDto({
    required this.drawingSessionId,
    required this.childId,
    required this.drawingType,
    required this.inputMethod,
    required this.title,
    required this.sessionStatus,
    required this.currentStage,
    required this.selectedEmotions,
    required this.expressedEmotionText,
    required this.startedAt,
    required this.completedAt,
    required this.conversation,
    required this.latestAnalysis,
    required this.assets,
    this.guideText,
    this.conversationId,
    this.reportId,
  });
  factory DrawingSessionDto.fromCreateJson(Map<String, dynamic> json) =>
      DrawingSessionDto._fromJson(json, childId: json['childId'] as int);

  factory DrawingSessionDto.fromDetailJson(Map<String, dynamic> json) =>
      DrawingSessionDto._fromJson(
        json,
        childId: _map(json['child'])['childId'] as int,
      );

  static DrawingSessionDto _fromJson(
    Map<String, dynamic> json, {
    required int childId,
  }) => DrawingSessionDto(
    drawingSessionId: json['drawingSessionId'] as int,
    childId: childId,
    drawingType: DrawingTypeSummaryDto.fromJson(_map(json['drawingType'])),
    inputMethod: json['inputMethod'] as String,
    title: json['title'] as String?,
    sessionStatus: json['sessionStatus'] as String,
    currentStage: json['currentStage'] as String,
    selectedEmotions: (json['selectedEmotions'] as List?)?.cast<String>(),
    expressedEmotionText: json['expressedEmotionText'] as String?,
    startedAt: json['startedAt'] as String,
    completedAt: json['completedAt'] as String?,
    conversation: json['conversation'] == null
        ? null
        : _map(json['conversation']),
    latestAnalysis: json['latestAnalysis'] == null
        ? null
        : _map(json['latestAnalysis']),
    conversationId: json['conversationId'] as int?,
    reportId: json['reportId'] as int?,
    assets: (json['assets'] as List? ?? const [])
        .map((item) => DrawingAssetDto.fromJson(_map(item)))
        .toList(growable: false),
    guideText: json['guideText'] as String?,
  );
  final int drawingSessionId, childId;
  final DrawingTypeSummaryDto drawingType;
  final String inputMethod, sessionStatus, currentStage, startedAt;
  final String? title, expressedEmotionText, completedAt, guideText;
  final int? conversationId, reportId;
  final List<String>? selectedEmotions;
  final Map<String, dynamic>? conversation, latestAnalysis;
  final List<DrawingAssetDto> assets;
}

final class ActiveDrawingSessionDto {
  const ActiveDrawingSessionDto({
    required this.drawingSessionId,
    required this.childId,
    required this.drawingType,
    required this.inputMethod,
    required this.sessionStatus,
    required this.currentStage,
    required this.startedAt,
    required this.latestDraft,
    this.activityContext = const DrawingActivityContextDto.general(),
  });

  factory ActiveDrawingSessionDto.fromJson(Map<String, dynamic> json) =>
      ActiveDrawingSessionDto(
        drawingSessionId: json['drawingSessionId'] as int,
        childId: json['childId'] as int,
        drawingType: DrawingTypeSummaryDto.fromJson(_map(json['drawingType'])),
        inputMethod: json['inputMethod'] as String,
        sessionStatus: json['sessionStatus'] as String,
        currentStage: json['currentStage'] as String,
        startedAt: json['startedAt'] as String,
        latestDraft: json['latestDraft'] == null
            ? null
            : ActiveDrawingDraftDto.fromJson(_map(json['latestDraft'])),
        activityContext: json['activityContext'] == null
            ? const DrawingActivityContextDto.general()
            : DrawingActivityContextDto.fromJson(_map(json['activityContext'])),
      );

  final int drawingSessionId, childId;
  final DrawingTypeSummaryDto drawingType;
  final String inputMethod, sessionStatus, currentStage, startedAt;
  final ActiveDrawingDraftDto? latestDraft;
  final DrawingActivityContextDto activityContext;
}

final class DrawingActivityContextDto {
  const DrawingActivityContextDto({
    required this.activityKind,
    this.htpAssessmentId,
    this.htpStatus,
    this.stepOrder,
    this.drawingSubject,
  });

  const DrawingActivityContextDto.general()
    : activityKind = 'GENERAL',
      htpAssessmentId = null,
      htpStatus = null,
      stepOrder = null,
      drawingSubject = null;

  factory DrawingActivityContextDto.fromJson(Map<String, dynamic> json) =>
      DrawingActivityContextDto(
        activityKind: json['activityKind'] as String,
        htpAssessmentId: json['htpAssessmentId'] as int?,
        htpStatus: json['htpStatus'] as String?,
        stepOrder: json['stepOrder'] as int?,
        drawingSubject: json['drawingSubject'] as String?,
      );

  final String activityKind;
  final int? htpAssessmentId, stepOrder;
  final String? htpStatus, drawingSubject;

  bool get isHtp => activityKind == 'HTP' && htpAssessmentId != null;
}

final class StartHtpAssessmentRequestDto {
  const StartHtpAssessmentRequestDto({
    required this.childId,
    required this.inputMethod,
    required this.clientStartedAt,
    this.replaceActive = false,
  });

  final int childId;
  final String inputMethod, clientStartedAt;
  final bool replaceActive;

  Map<String, dynamic> toJson() => {
    'childId': childId,
    'inputMethod': inputMethod,
    'clientStartedAt': clientStartedAt,
    'replaceActive': replaceActive,
  };
}

final class HtpAssessmentStepDto {
  const HtpAssessmentStepDto({
    required this.stepOrder,
    required this.drawingSubject,
    required this.drawingSessionId,
    required this.sessionStatus,
    required this.currentStage,
  });

  factory HtpAssessmentStepDto.fromJson(Map<String, dynamic> json) =>
      HtpAssessmentStepDto(
        stepOrder: json['stepOrder'] as int,
        drawingSubject: json['drawingSubject'] as String,
        drawingSessionId: json['drawingSessionId'] as int,
        sessionStatus: json['sessionStatus'] as String,
        currentStage: json['currentStage'] as String,
      );

  final int stepOrder, drawingSessionId;
  final String drawingSubject, sessionStatus, currentStage;
}

final class HtpAssessmentDto {
  const HtpAssessmentDto({
    required this.htpAssessmentId,
    required this.status,
    required this.expiresAt,
    required this.currentStep,
    required this.allStepsCompleted,
  });

  factory HtpAssessmentDto.fromJson(Map<String, dynamic> json) =>
      HtpAssessmentDto(
        htpAssessmentId: json['htpAssessmentId'] as int,
        status: json['status'] as String,
        expiresAt: json['expiresAt'] as String,
        currentStep: HtpAssessmentStepDto.fromJson(_map(json['currentStep'])),
        allStepsCompleted: json['allStepsCompleted'] as bool,
      );

  final int htpAssessmentId;
  final String status, expiresAt;
  final HtpAssessmentStepDto currentStep;
  final bool allStepsCompleted;
}

final class ActiveDrawingDraftDto {
  const ActiveDrawingDraftDto({
    required this.drawingAssetId,
    required this.assetVersion,
    required this.lastEventSequence,
    required this.savedAt,
  });

  factory ActiveDrawingDraftDto.fromJson(Map<String, dynamic> json) =>
      ActiveDrawingDraftDto(
        drawingAssetId: json['drawingAssetId'] as int,
        assetVersion: json['assetVersion'] as int,
        lastEventSequence: json['lastEventSequence'] as int?,
        savedAt: json['savedAt'] as String,
      );

  final int drawingAssetId, assetVersion;
  final int? lastEventSequence;
  final String savedAt;
}

final class StrokeEventDto {
  const StrokeEventDto({
    required this.seq,
    required this.t,
    required this.type,
    this.x,
    this.y,
    this.tool,
    this.color,
    this.thickness,
    this.pressure,
  });
  final int seq, t;
  final String type;
  final double? x, y, thickness, pressure;
  final String? tool, color;
  Map<String, dynamic> toJson() => {
    'seq': seq,
    't': t,
    'type': type,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    if (tool != null) 'tool': tool,
    if (color != null) 'color': color,
    if (thickness != null) 'thickness': thickness,
    if (pressure != null) 'pressure': pressure,
  };
}

final class StrokePointDto {
  const StrokePointDto({
    required this.x,
    required this.y,
    required this.t,
    this.pressure,
  });

  final double x, y;
  final int t;
  final double? pressure;

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    't': t,
    if (pressure != null) 'pressure': pressure,
  };
}

final class StrokeBatchEventDto {
  const StrokeBatchEventDto({
    required this.sequence,
    required this.eventType,
    required this.points,
    this.tool,
    this.color,
    this.width,
  });

  final int sequence;
  final String eventType;
  final String? tool, color;
  final double? width;
  final List<StrokePointDto> points;

  Map<String, dynamic> toJson() => {
    'sequence': sequence,
    'eventType': eventType,
    if (tool != null) 'tool': tool,
    if (color != null) 'color': color,
    if (width != null) 'width': width,
    'points': points.map((point) => point.toJson()).toList(growable: false),
  };
}

final class StrokeMetricsDto {
  const StrokeMetricsDto({
    required this.undoCountDelta,
    this.redoCountDelta = 0,
    this.eraseCountDelta = 0,
    this.pauseDurationMsDelta = 0,
  });

  final int undoCountDelta, redoCountDelta, eraseCountDelta;
  final int pauseDurationMsDelta;

  Map<String, dynamic> toJson() => {
    'undoCountDelta': undoCountDelta,
    'redoCountDelta': redoCountDelta,
    'eraseCountDelta': eraseCountDelta,
    'pauseDurationMsDelta': pauseDurationMsDelta,
  };
}

final class StrokeBatchRequestDto {
  const StrokeBatchRequestDto({
    required this.batchSequence,
    required this.firstEventSequence,
    required this.lastEventSequence,
    required this.clientCreatedAt,
    required this.events,
    required this.metrics,
  });
  final int batchSequence, firstEventSequence, lastEventSequence;
  final String clientCreatedAt;
  final List<StrokeBatchEventDto> events;
  final StrokeMetricsDto metrics;

  Map<String, dynamic> toJson() => {
    'batchSequence': batchSequence,
    'firstEventSequence': firstEventSequence,
    'lastEventSequence': lastEventSequence,
    'clientCreatedAt': clientCreatedAt,
    'events': events.map((event) => event.toJson()).toList(growable: false),
    'metrics': metrics.toJson(),
  };
}

final class StrokeBatchResponseDto {
  const StrokeBatchResponseDto({
    required this.batchId,
    required this.batchSequence,
    required this.acceptedEventCount,
    required this.lastEventSequence,
    required this.receivedAt,
  });
  factory StrokeBatchResponseDto.fromJson(Map<String, dynamic> json) =>
      StrokeBatchResponseDto(
        batchId: json['batchId'] as int,
        batchSequence: json['batchSequence'] as int,
        acceptedEventCount: json['acceptedEventCount'] as int,
        lastEventSequence: json['lastEventSequence'] as int,
        receivedAt: json['receivedAt'] as String,
      );
  final int batchId, batchSequence, acceptedEventCount, lastEventSequence;
  final String receivedAt;
}

final class DraftCanvasStateDto {
  const DraftCanvasStateDto({
    required this.lastEventSequence,
    required this.toolState,
    required this.viewport,
    required this.clientSavedAt,
  });

  factory DraftCanvasStateDto.fromJson(Map<String, dynamic> json) =>
      DraftCanvasStateDto(
        lastEventSequence: json['lastEventSequence'] as int?,
        toolState: json['toolState'] == null ? null : _map(json['toolState']),
        viewport: json['viewport'] == null ? null : _map(json['viewport']),
        clientSavedAt: json['clientSavedAt'] as String?,
      );

  final int? lastEventSequence;
  final Map<String, dynamic>? toolState;
  final Map<String, dynamic>? viewport;
  final String? clientSavedAt;

  Map<String, dynamic> toJson() => {
    'lastEventSequence': lastEventSequence,
    'toolState': toolState,
    'viewport': viewport,
    'clientSavedAt': clientSavedAt,
  };
}

final class DraftSaveResponseDto {
  const DraftSaveResponseDto({
    required this.drawingAssetId,
    required this.assetVersion,
    required this.lastEventSequence,
    required this.savedAt,
    required this.expiresAt,
    this.widthPx,
    this.heightPx,
  });

  factory DraftSaveResponseDto.fromJson(Map<String, dynamic> json) =>
      DraftSaveResponseDto(
        drawingAssetId: json['drawingAssetId'] as int,
        assetVersion: json['assetVersion'] as int,
        lastEventSequence: json['lastEventSequence'] as int?,
        savedAt: json['savedAt'] as String,
        expiresAt: json['expiresAt'] as String?,
        widthPx: json['widthPx'] as int?,
        heightPx: json['heightPx'] as int?,
      );

  final int drawingAssetId, assetVersion;
  final int? lastEventSequence;
  final int? widthPx, heightPx;
  final String savedAt;
  final String? expiresAt;
}

final class DraftRecoveryDto {
  const DraftRecoveryDto({
    required this.previewUrl,
    required this.canvasState,
    required this.assetVersion,
  });

  factory DraftRecoveryDto.fromJson(Map<String, dynamic> json) {
    final rawCanvasState = json['canvasState'];
    final canvasState = rawCanvasState is String
        ? jsonDecode(rawCanvasState) as Map<String, dynamic>
        : _map(rawCanvasState);
    return DraftRecoveryDto(
      previewUrl: json['previewUrl'] as String,
      canvasState: DraftCanvasStateDto.fromJson(canvasState),
      assetVersion: json['assetVersion'] as int,
    );
  }

  final String previewUrl;
  final DraftCanvasStateDto canvasState;
  final int assetVersion;
}

final class DrawingCompleteMetadataDto {
  const DrawingCompleteMetadataDto({
    required this.drawingDurationMs,
    required this.clientCompletedAt,
    this.sourceAssetId,
    this.lastEventSequence,
  });

  final int drawingDurationMs;
  final String clientCompletedAt;
  final int? sourceAssetId, lastEventSequence;

  Map<String, dynamic> toJson() => {
    if (sourceAssetId != null) 'sourceAssetId': sourceAssetId,
    if (lastEventSequence != null) 'lastEventSequence': lastEventSequence,
    'drawingDurationMs': drawingDurationMs,
    'clientCompletedAt': clientCompletedAt,
  };
}

final class UploadDrawingImageMetadataDto {
  const UploadDrawingImageMetadataDto({
    required this.clientCapturedAt,
    required this.rotationDegrees,
    required this.cropApplied,
  });

  final String? clientCapturedAt;
  final int rotationDegrees;
  final bool cropApplied;

  Map<String, dynamic> toJson() => {
    if (clientCapturedAt != null) 'clientCapturedAt': clientCapturedAt,
    'rotationDegrees': rotationDegrees,
    'cropApplied': cropApplied,
  };
}

final class DrawingStageAnalysisDto {
  const DrawingStageAnalysisDto({
    required this.analysisId,
    required this.analysisType,
    required this.status,
  });

  factory DrawingStageAnalysisDto.fromJson(Map<String, dynamic> json) =>
      DrawingStageAnalysisDto(
        analysisId: json['analysisId'] as int,
        analysisType: json['analysisType'] as String,
        status: json['status'] as String,
      );

  final int analysisId;
  final String analysisType, status;
}

final class DrawingStageCompleteResponseDto {
  const DrawingStageCompleteResponseDto({
    required this.drawingSessionId,
    required this.finalAssetId,
    required this.sessionStatus,
    required this.currentStage,
    required this.analysis,
    required this.nextAction,
  });

  factory DrawingStageCompleteResponseDto.fromJson(Map<String, dynamic> json) =>
      DrawingStageCompleteResponseDto(
        drawingSessionId: json['drawingSessionId'] as int,
        finalAssetId: json['finalAssetId'] as int,
        sessionStatus: json['sessionStatus'] as String,
        currentStage: json['currentStage'] as String,
        analysis: DrawingStageAnalysisDto.fromJson(_map(json['analysis'])),
        nextAction: json['nextAction'] as String,
      );

  final int drawingSessionId, finalAssetId;
  final String sessionStatus, currentStage, nextAction;
  final DrawingStageAnalysisDto analysis;
}

enum DrawingEmotionType {
  happy('HAPPY'),
  sad('SAD'),
  angry('ANGRY'),
  scared('SCARED'),
  calm('CALM'),
  unknown('UNKNOWN');

  const DrawingEmotionType(this.apiValue);
  final String apiValue;
}

final class SaveDrawingReflectionRequestDto {
  const SaveDrawingReflectionRequestDto({
    required this.title,
    required this.selectedEmotions,
    required this.expressedEmotionText,
    required this.skipped,
  });

  final String? title;
  final List<DrawingEmotionType> selectedEmotions;
  final String? expressedEmotionText;
  final bool skipped;

  Map<String, dynamic> toJson() => {
    'title': title,
    'selectedEmotions': selectedEmotions
        .map((emotion) => emotion.apiValue)
        .toList(growable: false),
    'expressedEmotionText': expressedEmotionText,
    'skipped': skipped,
  };
}

final class CompleteActivityRequestDto {
  const CompleteActivityRequestDto({
    required this.conversationSkipped,
    this.requestReport = true,
  });

  final bool conversationSkipped, requestReport;

  Map<String, dynamic> toJson() => {
    'conversationSkipped': conversationSkipped,
    'requestReport': requestReport,
  };
}

final class DrawingCompletionResponseDto {
  const DrawingCompletionResponseDto({
    required this.drawingSessionId,
    required this.sessionStatus,
    required this.currentStage,
    required this.analysisId,
    required this.analysisStatus,
    required this.reportId,
    required this.reportStatus,
  });

  factory DrawingCompletionResponseDto.fromJson(Map<String, dynamic> json) =>
      DrawingCompletionResponseDto(
        drawingSessionId: json['drawingSessionId'] as int,
        sessionStatus: json['sessionStatus'] as String,
        currentStage: json['currentStage'] as String,
        analysisId: json['analysisId'] as int,
        analysisStatus: json['analysisStatus'] as String,
        reportId: json['reportId'] as int?,
        reportStatus: json['reportStatus'] as String?,
      );

  final int drawingSessionId, analysisId;
  final int? reportId;
  final String sessionStatus, currentStage, analysisStatus;
  final String? reportStatus;
}

final class DrawingUploadResponseDto {
  const DrawingUploadResponseDto({
    required this.drawingSessionId,
    required this.drawingAssetId,
    required this.assetType,
    required this.drawingSubject,
    required this.currentStage,
    required this.previewUrl,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.widthPx,
    required this.heightPx,
    required this.capturedAt,
    required this.uploadedAt,
    required this.qualityWarnings,
  });
  factory DrawingUploadResponseDto.fromJson(Map<String, dynamic> json) =>
      DrawingUploadResponseDto(
        drawingSessionId: json['drawingSessionId'] as int,
        drawingAssetId: json['drawingAssetId'] as int,
        assetType: json['assetType'] as String,
        drawingSubject: json['drawingSubject'] as String,
        currentStage: json['currentStage'] as String,
        previewUrl: json['previewUrl'] as String,
        mimeType: json['mimeType'] as String,
        fileSizeBytes: json['fileSizeBytes'] as int,
        widthPx: json['widthPx'] as int,
        heightPx: json['heightPx'] as int,
        capturedAt: json['capturedAt'] as String,
        uploadedAt: json['uploadedAt'] as String,
        qualityWarnings: (json['qualityWarnings'] as List<dynamic>)
            .cast<String>(),
      );
  final int drawingSessionId, drawingAssetId, fileSizeBytes, widthPx, heightPx;
  final String assetType,
      drawingSubject,
      currentStage,
      previewUrl,
      mimeType,
      capturedAt,
      uploadedAt;
  final List<String> qualityWarnings;
}

final class ObjectDetectionRequestDto {
  const ObjectDetectionRequestDto({required this.drawingAssetId});

  final int drawingAssetId;

  Map<String, dynamic> toJson() => {
    'drawingAssetId': drawingAssetId,
    'analysisType': 'OBJECT_DETECTION',
  };
}

final class DrawingBoundingBoxDto {
  const DrawingBoundingBoxDto({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory DrawingBoundingBoxDto.fromJson(Map<String, dynamic> json) =>
      DrawingBoundingBoxDto(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );

  final double x, y, width, height;
}

final class DrawingDetectionDto {
  const DrawingDetectionDto({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  factory DrawingDetectionDto.fromJson(Map<String, dynamic> json) =>
      DrawingDetectionDto(
        label: json['label'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        boundingBox: DrawingBoundingBoxDto.fromJson(_map(json['boundingBox'])),
      );

  final String label;
  final double confidence;
  final DrawingBoundingBoxDto boundingBox;
}

final class DrawingAnalysisModelDto {
  const DrawingAnalysisModelDto({required this.name, required this.version});

  factory DrawingAnalysisModelDto.fromJson(Map<String, dynamic> json) =>
      DrawingAnalysisModelDto(
        name: json['name'] as String,
        version: json['version'] as String,
      );

  final String name, version;
}

final class ObjectDetectionResponseDto {
  const ObjectDetectionResponseDto({
    required this.drawingAnalysisId,
    required this.drawingSessionId,
    required this.drawingAssetId,
    required this.requestId,
    required this.analysisType,
    required this.status,
    required this.model,
    required this.detections,
    required this.requestedAt,
    required this.processedAt,
  });

  factory ObjectDetectionResponseDto.fromJson(Map<String, dynamic> json) =>
      ObjectDetectionResponseDto(
        drawingAnalysisId: json['drawingAnalysisId'] as int,
        drawingSessionId: json['drawingSessionId'] as int,
        drawingAssetId: json['drawingAssetId'] as int,
        requestId: json['requestId'] as String,
        analysisType: json['analysisType'] as String,
        status: json['status'] as String,
        model: DrawingAnalysisModelDto.fromJson(_map(json['model'])),
        detections: (json['detections'] as List? ?? const [])
            .map((item) => DrawingDetectionDto.fromJson(_map(item)))
            .toList(growable: false),
        requestedAt: json['requestedAt'] as String,
        processedAt: json['processedAt'] as String,
      );

  final int drawingAnalysisId, drawingSessionId, drawingAssetId;
  final String requestId, analysisType, status, requestedAt, processedAt;
  final DrawingAnalysisModelDto model;
  final List<DrawingDetectionDto> detections;
}

final class AnalysisAcceptedDto {
  const AnalysisAcceptedDto({
    required this.analysisId,
    this.drawingSessionId,
    this.retryOfAnalysisId,
    required this.analysisType,
    required this.analysisStatus,
    required this.requestedAt,
  });
  factory AnalysisAcceptedDto.fromJson(Map<String, dynamic> json) =>
      AnalysisAcceptedDto(
        analysisId: json['analysisId'] as int,
        drawingSessionId: json['drawingSessionId'] as int?,
        retryOfAnalysisId: json['retryOfAnalysisId'] as int?,
        analysisType: json['analysisType'] as String,
        analysisStatus: json['analysisStatus'] as String,
        requestedAt: json['requestedAt'] as String,
      );
  final int analysisId;
  final int? drawingSessionId, retryOfAnalysisId;
  final String analysisType, analysisStatus, requestedAt;
}

typedef DrawingTypePage = ApiPage<DrawingTypeDto>;
