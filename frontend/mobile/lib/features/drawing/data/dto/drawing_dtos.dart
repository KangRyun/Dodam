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
    guideText: json['guideText'] as String,
    displayOrder: json['displayOrder'] as int,
  );
  final int drawingTypeId;
  final String code, name, activityCategory, selectableBy, guideText;
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
    this.selectionActor,
  });
  final int childId, drawingTypeId;
  final String inputMethod;
  final String? selectionActor;
  Map<String, dynamic> toJson() => {
    'childId': childId,
    'drawingTypeId': drawingTypeId,
    'inputMethod': inputMethod,
    if (selectionActor != null) 'selectionActor': selectionActor,
  };
}

final class DrawingAssetDto {
  const DrawingAssetDto({
    required this.assetId,
    required this.assetType,
    required this.assetVersion,
    required this.fileUrl,
    required this.mimeType,
    required this.widthPx,
    required this.heightPx,
    this.fileSizeBytes,
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
        widthPx: json['widthPx'] as int,
        heightPx: json['heightPx'] as int,
        fileSizeBytes: json['fileSizeBytes'] as int?,
        checksumSha256: json['checksumSha256'] as String?,
        expiresAt: json['expiresAt'] as String?,
        createdAt: json['createdAt'] as String?,
        drawingSessionId: json['drawingSessionId'] as int?,
      );
  final int assetId, assetVersion, widthPx, heightPx;
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
  });
  factory DrawingSessionDto.fromJson(Map<String, dynamic> json) =>
      DrawingSessionDto(
        drawingSessionId: json['drawingSessionId'] as int,
        childId: json['childId'] as int,
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
        assets: (json['assets'] as List? ?? const [])
            .map((item) => DrawingAssetDto.fromJson(_map(item)))
            .toList(growable: false),
        guideText: json['guideText'] as String?,
      );
  final int drawingSessionId, childId;
  final DrawingTypeSummaryDto drawingType;
  final String inputMethod, sessionStatus, currentStage, startedAt;
  final String? title, expressedEmotionText, completedAt, guideText;
  final List<String>? selectedEmotions;
  final Map<String, dynamic>? conversation, latestAnalysis;
  final List<DrawingAssetDto> assets;
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

final class StrokeBatchRequestDto {
  const StrokeBatchRequestDto({
    required this.batchSequence,
    required this.firstEventSequence,
    required this.lastEventSequence,
    required this.clientCreatedAt,
    required this.events,
  });
  final int batchSequence, firstEventSequence, lastEventSequence;
  final String clientCreatedAt;
  final List<StrokeEventDto> events;
  Map<String, dynamic> toJson() => {
    'batchSequence': batchSequence,
    'firstEventSequence': firstEventSequence,
    'lastEventSequence': lastEventSequence,
    'eventCount': events.length,
    'clientCreatedAt': clientCreatedAt,
    'events': events.map((event) => event.toJson()).toList(growable: false),
  };
}

final class StrokeBatchResponseDto {
  const StrokeBatchResponseDto({
    required this.strokeBatchId,
    required this.batchSequence,
    required this.eventCount,
    required this.receivedAt,
  });
  factory StrokeBatchResponseDto.fromJson(Map<String, dynamic> json) =>
      StrokeBatchResponseDto(
        strokeBatchId: json['strokeBatchId'] as int,
        batchSequence: json['batchSequence'] as int,
        eventCount: json['eventCount'] as int,
        receivedAt: json['receivedAt'] as String,
      );
  final int strokeBatchId, batchSequence, eventCount;
  final String receivedAt;
}

final class DraftRecoveryDto {
  const DraftRecoveryDto({
    required this.drawingSessionId,
    required this.sessionStatus,
    required this.currentStage,
    required this.drawingType,
    required this.draftAsset,
    required this.lastBatchSequence,
    required this.lastEventSequence,
  });
  factory DraftRecoveryDto.fromJson(Map<String, dynamic> json) {
    final sync = _map(json['strokeSync']);
    final draft = _map(json['draftAsset']);
    return DraftRecoveryDto(
      drawingSessionId: json['drawingSessionId'] as int,
      sessionStatus: json['sessionStatus'] as String,
      currentStage: json['currentStage'] as String,
      drawingType: DrawingTypeSummaryDto.fromJson(_map(json['drawingType'])),
      draftAsset: DrawingAssetDto.fromJson({...draft, 'assetType': 'DRAFT'}),
      lastBatchSequence: sync['lastBatchSequence'] as int?,
      lastEventSequence: sync['lastEventSequence'] as int?,
    );
  }
  final int drawingSessionId;
  final String sessionStatus, currentStage;
  final DrawingTypeSummaryDto drawingType;
  final DrawingAssetDto draftAsset;
  final int? lastBatchSequence, lastEventSequence;
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

final class DrawingUploadResponseDto {
  const DrawingUploadResponseDto({
    required this.drawingSessionId,
    required this.objectCode,
    required this.originalAsset,
    required this.correctedAsset,
  });
  factory DrawingUploadResponseDto.fromJson(Map<String, dynamic> json) =>
      DrawingUploadResponseDto(
        drawingSessionId: json['drawingSessionId'] as int,
        objectCode: json['objectCode'] as String?,
        originalAsset: DrawingAssetDto.fromJson(_map(json['originalAsset'])),
        correctedAsset: DrawingAssetDto.fromJson(_map(json['correctedAsset'])),
      );
  final int drawingSessionId;
  final String? objectCode;
  final DrawingAssetDto originalAsset, correctedAsset;
}

final class RequestAnalysisDto {
  const RequestAnalysisDto({this.triggerReason, this.inputChecksumSha256});
  final String? triggerReason, inputChecksumSha256;
  Map<String, dynamic> toJson() => {
    if (triggerReason != null) 'triggerReason': triggerReason,
    if (inputChecksumSha256 != null) 'inputChecksumSha256': inputChecksumSha256,
  };
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
