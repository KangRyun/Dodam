import '../../../../core/network/api_page.dart';
import '../../../drawing/data/dto/drawing_dtos.dart' show AnalysisAcceptedDto;

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

final class ReportFilterDto {
  const ReportFilterDto({this.from, this.to, this.page = 0, this.size = 20});
  final String? from, to;
  final int page, size;
  Map<String, dynamic> toQueryParameters() => {
    if (from != null) 'from': from,
    if (to != null) 'to': to,
    'page': page,
    'size': size,
  };
}

final class ReportSummaryDto {
  const ReportSummaryDto({
    required this.reportId,
    required this.drawingSessionId,
    required this.reportVersion,
    required this.reportStatus,
    required this.title,
    required this.drawingType,
    required this.inputMethod,
    required this.selectedEmotions,
    required this.thumbnailUrl,
    required this.isExpertReviewRecommended,
    required this.createdAt,
  });
  factory ReportSummaryDto.fromJson(Map<String, dynamic> json) =>
      ReportSummaryDto(
        reportId: json['reportId'] as int,
        drawingSessionId: json['drawingSessionId'] as int,
        reportVersion: json['reportVersion'] as int,
        reportStatus: json['reportStatus'] as String,
        title: json['title'] as String?,
        drawingType: _map(json['drawingType']),
        inputMethod: json['inputMethod'] as String,
        selectedEmotions: List<String>.from(json['selectedEmotions'] as List),
        thumbnailUrl: json['thumbnailUrl'] as String?,
        isExpertReviewRecommended: json['isExpertReviewRecommended'] as bool,
        createdAt: json['createdAt'] as String,
      );
  final int reportId, drawingSessionId, reportVersion;
  final String reportStatus, inputMethod, createdAt;
  final String? title, thumbnailUrl;
  final Map<String, dynamic> drawingType;
  final List<String> selectedEmotions;
  final bool isExpertReviewRecommended;
}

final class ReportActivitySummaryDto {
  const ReportActivitySummaryDto({
    required this.title,
    required this.drawingType,
    required this.inputMethod,
    required this.startedAt,
    required this.completedAt,
    required this.durationMinutes,
    required this.selectedEmotions,
  });
  factory ReportActivitySummaryDto.fromJson(Map<String, dynamic> json) =>
      ReportActivitySummaryDto(
        title: json['title'] as String?,
        drawingType: _map(json['drawingType']),
        inputMethod: json['inputMethod'] as String,
        startedAt: json['startedAt'] as String,
        completedAt: json['completedAt'] as String,
        durationMinutes: json['durationMinutes'] as int,
        selectedEmotions: List<String>.from(json['selectedEmotions'] as List),
      );
  final String? title;
  final Map<String, dynamic> drawingType;
  final String inputMethod, startedAt, completedAt;
  final int durationMinutes;
  final List<String> selectedEmotions;
}

final class ObservedFeatureDto {
  const ObservedFeatureDto({
    required this.label,
    required this.description,
    required this.evidenceRef,
  });
  factory ObservedFeatureDto.fromJson(Map<String, dynamic> json) =>
      ObservedFeatureDto(
        label: json['label'] as String,
        description: json['description'] as String,
        evidenceRef: json['evidenceRef'] as String,
      );
  final String label, description, evidenceRef;
}

final class KeyConversationDto {
  const KeyConversationDto({
    required this.question,
    required this.answer,
    required this.answerType,
  });
  factory KeyConversationDto.fromJson(Map<String, dynamic> json) =>
      KeyConversationDto(
        question: json['question'] as String,
        answer: json['answer'] as String,
        answerType: json['answerType'] as String,
      );
  final String question, answer, answerType;
}

final class ReportEvidenceDto {
  const ReportEvidenceDto({
    required this.drawingRefs,
    required this.conversationRefs,
  });
  factory ReportEvidenceDto.fromJson(Map<String, dynamic> json) =>
      ReportEvidenceDto(
        drawingRefs: List<String>.from(json['drawingRefs'] as List),
        conversationRefs: List<int>.from(json['conversationRefs'] as List),
      );
  final List<String> drawingRefs;
  final List<int> conversationRefs;
}

final class ReportFollowUpDto {
  const ReportFollowUpDto({
    required this.attentionPoints,
    required this.guidance,
  });
  factory ReportFollowUpDto.fromJson(Map<String, dynamic> json) =>
      ReportFollowUpDto(
        attentionPoints: List<String>.from(json['attentionPoints'] as List),
        guidance: json['guidance'] as String,
      );
  final List<String> attentionPoints;
  final String guidance;
}

/// DTO follows the current public API example. JSON section schema is pending final team agreement.
final class ReportDetailDto {
  const ReportDetailDto({
    required this.reportId,
    required this.drawingSessionId,
    required this.analysisId,
    required this.reportVersion,
    required this.reportStatus,
    required this.activitySummary,
    required this.drawingImageUrl,
    required this.observedFeatures,
    required this.keyConversations,
    required this.evidence,
    required this.followUp,
    required this.guardianQuestions,
    required this.isExpertReviewRecommended,
    required this.limitationsText,
    required this.modelVersion,
    required this.createdAt,
  });
  factory ReportDetailDto.fromJson(Map<String, dynamic> json) =>
      ReportDetailDto(
        reportId: json['reportId'] as int,
        drawingSessionId: json['drawingSessionId'] as int,
        analysisId: json['analysisId'] as int,
        reportVersion: json['reportVersion'] as int,
        reportStatus: json['reportStatus'] as String,
        activitySummary: json['activitySummary'] == null
            ? null
            : ReportActivitySummaryDto.fromJson(_map(json['activitySummary'])),
        drawingImageUrl: json['drawingImageUrl'] as String?,
        observedFeatures: (json['observedFeatures'] as List?)
            ?.map((item) => ObservedFeatureDto.fromJson(_map(item)))
            .toList(growable: false),
        keyConversations: (json['keyConversations'] as List?)
            ?.map((item) => KeyConversationDto.fromJson(_map(item)))
            .toList(growable: false),
        evidence: json['evidence'] == null
            ? null
            : ReportEvidenceDto.fromJson(_map(json['evidence'])),
        followUp: json['followUp'] == null
            ? null
            : ReportFollowUpDto.fromJson(_map(json['followUp'])),
        guardianQuestions: (json['guardianQuestions'] as List?)?.cast<String>(),
        isExpertReviewRecommended: json['isExpertReviewRecommended'] as bool?,
        limitationsText: json['limitationsText'] as String,
        modelVersion: json['modelVersion'] as String?,
        createdAt: json['createdAt'] as String,
      );
  final int reportId, drawingSessionId, analysisId, reportVersion;
  final String reportStatus, limitationsText, createdAt;
  final ReportActivitySummaryDto? activitySummary;
  final String? drawingImageUrl, modelVersion;
  final List<ObservedFeatureDto>? observedFeatures;
  final List<KeyConversationDto>? keyConversations;
  final ReportEvidenceDto? evidence;
  final ReportFollowUpDto? followUp;
  final List<String>? guardianQuestions;
  final bool? isExpertReviewRecommended;
}

final class AnalysisObservationDto {
  const AnalysisObservationDto({
    required this.overallSummary,
    required this.observedEmotion,
    required this.emotionConfidence,
    required this.positiveSignals,
    required this.attentionPoints,
    required this.guardianGuidance,
    required this.isExpertReviewRequired,
    required this.disclaimerText,
  });
  factory AnalysisObservationDto.fromJson(Map<String, dynamic> json) =>
      AnalysisObservationDto(
        overallSummary: json['overallSummary'] as String,
        observedEmotion: json['observedEmotion'] as String,
        emotionConfidence: (json['emotionConfidence'] as num).toDouble(),
        positiveSignals: json['positiveSignals'] as String,
        attentionPoints: json['attentionPoints'] as String,
        guardianGuidance: json['guardianGuidance'] as String,
        isExpertReviewRequired: json['isExpertReviewRequired'] as bool,
        disclaimerText: json['disclaimerText'] as String,
      );
  final String overallSummary,
      observedEmotion,
      positiveSignals,
      attentionPoints,
      guardianGuidance,
      disclaimerText;
  final double emotionConfidence;
  final bool isExpertReviewRequired;
}

final class AnalysisStatusDto {
  const AnalysisStatusDto({
    required this.analysisId,
    required this.analysisType,
    required this.analysisStatus,
    required this.confidence,
    required this.modelName,
    required this.modelVersion,
    required this.requestedAt,
    required this.completedAt,
    required this.detectedObjects,
    required this.visualFeatures,
    required this.behaviorFeatures,
    required this.conversationSummary,
    required this.observationResult,
    required this.errorCode,
    required this.message,
  });
  factory AnalysisStatusDto.fromJson(Map<String, dynamic> json) =>
      AnalysisStatusDto(
        analysisId: json['analysisId'] as int,
        analysisType: json['analysisType'] as String,
        analysisStatus: json['analysisStatus'] as String,
        confidence: (json['confidence'] as num?)?.toDouble(),
        modelName: json['modelName'] as String?,
        modelVersion: json['modelVersion'] as String?,
        requestedAt: json['requestedAt'] as String?,
        completedAt: json['completedAt'] as String?,
        detectedObjects: (json['detectedObjects'] as List?)
            ?.map(_map)
            .toList(growable: false),
        visualFeatures: json['visualFeatures'] == null
            ? null
            : _map(json['visualFeatures']),
        behaviorFeatures: json['behaviorFeatures'] == null
            ? null
            : _map(json['behaviorFeatures']),
        conversationSummary: json['conversationSummary'] == null
            ? null
            : _map(json['conversationSummary']),
        observationResult: json['observationResult'] == null
            ? null
            : AnalysisObservationDto.fromJson(_map(json['observationResult'])),
        errorCode: json['errorCode'] as String?,
        message: json['message'] as String?,
      );
  final int analysisId;
  final String analysisType, analysisStatus;
  final double? confidence;
  final String? modelName,
      modelVersion,
      requestedAt,
      completedAt,
      errorCode,
      message;
  final List<Map<String, dynamic>>? detectedObjects;
  final Map<String, dynamic>? visualFeatures,
      behaviorFeatures,
      conversationSummary;
  final AnalysisObservationDto? observationResult;
}

typedef ReportPage = ApiPage<ReportSummaryDto>;
typedef AnalysisRetryResponseDto = AnalysisAcceptedDto;
