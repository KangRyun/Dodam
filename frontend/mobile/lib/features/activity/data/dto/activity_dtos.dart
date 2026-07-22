import '../../../../core/network/api_page.dart';

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

final class ActivityFilterDto {
  const ActivityFilterDto({
    this.from,
    this.to,
    this.drawingType,
    this.status,
    this.page = 0,
    this.size = 20,
  });
  final String? from, to, drawingType, status;
  final int page, size;
  Map<String, dynamic> toQueryParameters() => {
    if (from != null) 'from': from,
    if (to != null) 'to': to,
    if (drawingType != null) 'drawingType': drawingType,
    if (status != null) 'status': status,
    'page': page,
    'size': size,
  };
}

final class ActivityDrawingTypeDto {
  const ActivityDrawingTypeDto({required this.code, required this.name});
  factory ActivityDrawingTypeDto.fromJson(Map<String, dynamic> json) =>
      ActivityDrawingTypeDto(
        code: json['code'] as String,
        name: json['name'] as String,
      );
  final String code, name;
}

final class ActivityReportSummaryDto {
  const ActivityReportSummaryDto({
    required this.reportId,
    required this.reportStatus,
    this.reportVersion,
  });
  factory ActivityReportSummaryDto.fromJson(Map<String, dynamic> json) =>
      ActivityReportSummaryDto(
        reportId: json['reportId'] as int,
        reportStatus: json['reportStatus'] as String,
        reportVersion: json['reportVersion'] as int?,
      );
  final int reportId;
  final String reportStatus;
  final int? reportVersion;
}

final class ActivitySummaryDto {
  const ActivitySummaryDto({
    required this.activityId,
    required this.title,
    required this.drawingType,
    required this.inputMethod,
    required this.sessionStatus,
    required this.selectedEmotions,
    required this.thumbnailUrl,
    required this.analysisStatus,
    required this.report,
    required this.startedAt,
    required this.completedAt,
  });
  factory ActivitySummaryDto.fromJson(Map<String, dynamic> json) =>
      ActivitySummaryDto(
        activityId: json['activityId'] as int,
        title: json['title'] as String?,
        drawingType: ActivityDrawingTypeDto.fromJson(_map(json['drawingType'])),
        inputMethod: json['inputMethod'] as String,
        sessionStatus: json['sessionStatus'] as String,
        selectedEmotions: List<String>.from(json['selectedEmotions'] as List),
        thumbnailUrl: json['thumbnailUrl'] as String?,
        analysisStatus: json['analysisStatus'] as String?,
        report: json['report'] == null
            ? null
            : ActivityReportSummaryDto.fromJson(_map(json['report'])),
        startedAt: json['startedAt'] as String,
        completedAt: json['completedAt'] as String?,
      );
  final int activityId;
  final String? title, thumbnailUrl, analysisStatus, completedAt;
  final ActivityDrawingTypeDto drawingType;
  final String inputMethod, sessionStatus, startedAt;
  final List<String> selectedEmotions;
  final ActivityReportSummaryDto? report;
}

final class ActivityAssetDto {
  const ActivityAssetDto({
    required this.assetId,
    required this.assetType,
    required this.assetVersion,
    required this.fileUrl,
    required this.mimeType,
    required this.widthPx,
    required this.heightPx,
  });
  factory ActivityAssetDto.fromJson(Map<String, dynamic> json) =>
      ActivityAssetDto(
        assetId: json['assetId'] as int,
        assetType: json['assetType'] as String,
        assetVersion: json['assetVersion'] as int,
        fileUrl: json['fileUrl'] as String,
        mimeType: json['mimeType'] as String,
        widthPx: json['widthPx'] as int,
        heightPx: json['heightPx'] as int,
      );
  final int assetId, assetVersion, widthPx, heightPx;
  final String assetType, fileUrl, mimeType;
}

final class ActivityConversationSummaryDto {
  const ActivityConversationSummaryDto({
    required this.conversationSessionId,
    required this.conversationStatus,
    required this.questionCount,
    required this.completedAt,
  });
  factory ActivityConversationSummaryDto.fromJson(Map<String, dynamic> json) =>
      ActivityConversationSummaryDto(
        conversationSessionId: json['conversationSessionId'] as int,
        conversationStatus: json['conversationStatus'] as String,
        questionCount: json['questionCount'] as int,
        completedAt: json['completedAt'] as String?,
      );
  final int conversationSessionId, questionCount;
  final String conversationStatus;
  final String? completedAt;
}

final class ActivityAnalysisSummaryDto {
  const ActivityAnalysisSummaryDto({
    required this.analysisId,
    required this.analysisStatus,
    required this.completedAt,
  });
  factory ActivityAnalysisSummaryDto.fromJson(Map<String, dynamic> json) =>
      ActivityAnalysisSummaryDto(
        analysisId: json['analysisId'] as int,
        analysisStatus: json['analysisStatus'] as String,
        completedAt: json['completedAt'] as String?,
      );
  final int analysisId;
  final String analysisStatus;
  final String? completedAt;
}

final class ActivityDetailDto {
  const ActivityDetailDto({
    required this.activityId,
    required this.childId,
    required this.title,
    required this.drawingType,
    required this.inputMethod,
    required this.sessionStatus,
    required this.currentStage,
    required this.selectedEmotions,
    required this.expressedEmotionText,
    required this.startedAt,
    required this.completedAt,
    required this.assets,
    required this.conversation,
    required this.analysis,
    required this.report,
  });
  factory ActivityDetailDto.fromJson(Map<String, dynamic> json) =>
      ActivityDetailDto(
        activityId: json['activityId'] as int,
        childId: json['childId'] as int,
        title: json['title'] as String?,
        drawingType: ActivityDrawingTypeDto.fromJson(_map(json['drawingType'])),
        inputMethod: json['inputMethod'] as String,
        sessionStatus: json['sessionStatus'] as String,
        currentStage: json['currentStage'] as String,
        selectedEmotions: List<String>.from(json['selectedEmotions'] as List),
        expressedEmotionText: json['expressedEmotionText'] as String?,
        startedAt: json['startedAt'] as String,
        completedAt: json['completedAt'] as String?,
        assets: (json['assets'] as List)
            .map((item) => ActivityAssetDto.fromJson(_map(item)))
            .toList(growable: false),
        conversation: json['conversation'] == null
            ? null
            : ActivityConversationSummaryDto.fromJson(
                _map(json['conversation']),
              ),
        analysis: json['analysis'] == null
            ? null
            : ActivityAnalysisSummaryDto.fromJson(_map(json['analysis'])),
        report: json['report'] == null
            ? null
            : ActivityReportSummaryDto.fromJson(_map(json['report'])),
      );
  final int activityId, childId;
  final String? title, expressedEmotionText, completedAt;
  final ActivityDrawingTypeDto drawingType;
  final String inputMethod, sessionStatus, currentStage, startedAt;
  final List<String> selectedEmotions;
  final List<ActivityAssetDto> assets;
  final ActivityConversationSummaryDto? conversation;
  final ActivityAnalysisSummaryDto? analysis;
  final ActivityReportSummaryDto? report;
}

typedef ActivityPage = ApiPage<ActivitySummaryDto>;
