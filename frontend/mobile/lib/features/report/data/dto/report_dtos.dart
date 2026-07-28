import '../../../../core/network/api_page.dart';
import '../../../drawing/data/dto/drawing_dtos.dart' show AnalysisAcceptedDto;

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

final class ReportFilterDto {
  const ReportFilterDto({
    this.from,
    this.to,
    this.drawingTypeCode,
    this.reportStatus,
    this.page = 0,
    this.size = 20,
  });
  final String? from, to, drawingTypeCode, reportStatus;
  final int page, size;
  Map<String, dynamic> toQueryParameters() => {
    if (from != null) 'from': from,
    if (to != null) 'to': to,
    if (drawingTypeCode != null) 'drawingTypeCode': drawingTypeCode,
    if (reportStatus != null) 'reportStatus': reportStatus,
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
    required this.drawingTypeId,
    required this.drawingTypeCode,
    required this.drawingTypeName,
    required this.selectedEmotions,
    required this.thumbnailUrl,
    required this.activityDate,
    required this.durationMs,
    required this.expertReviewAvailable,
  });
  factory ReportSummaryDto.fromJson(Map<String, dynamic> json) {
    final drawingType = _map(json['drawingType']);
    return ReportSummaryDto(
      reportId: json['reportId'] as int,
      drawingSessionId: json['drawingSessionId'] as int,
      reportVersion: json['reportVersion'] as int,
      reportStatus: json['reportStatus'] as String,
      title: json['title'] as String?,
      drawingTypeId: (drawingType['drawingTypeId'] as num?)?.toInt(),
      drawingTypeCode: drawingType['code'] as String,
      drawingTypeName: drawingType['name'] as String,
      selectedEmotions: List<String>.from(json['selectedEmotions'] as List),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      activityDate: DateTime.tryParse(json['activityDate'] as String? ?? ''),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      expertReviewAvailable: json['expertReviewAvailable'] as bool? ?? false,
    );
  }
  final int reportId, drawingSessionId, reportVersion;
  final int? drawingTypeId, durationMs;
  final String reportStatus, drawingTypeCode, drawingTypeName;
  final String? title, thumbnailUrl;
  final DateTime? activityDate;
  final List<String> selectedEmotions;
  final bool expertReviewAvailable;
}

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

/// `data.drawingSession` — 리포트가 가리키는 그림 활동 세션.
///
/// 세션이 없으면 서버가 404를 주므로 상세 응답에서는 객체 자체가 비지 않지만,
/// 진행 중(GENERATING) 응답의 부분 데이터를 견디도록 모든 값을 nullable로 둔다.
final class ReportDrawingSessionDto {
  const ReportDrawingSessionDto({
    required this.drawingSessionId,
    required this.childId,
    required this.drawingTypeCode,
    required this.drawingTypeName,
    required this.title,
    required this.inputMethod,
    required this.startedAt,
    required this.completedAt,
    required this.durationMs,
  });
  factory ReportDrawingSessionDto.fromJson(Map<String, dynamic> json) =>
      ReportDrawingSessionDto(
        drawingSessionId: (json['drawingSessionId'] as num?)?.toInt(),
        childId: (json['childId'] as num?)?.toInt(),
        drawingTypeCode: json['drawingTypeCode'] as String?,
        drawingTypeName: json['drawingTypeName'] as String?,
        title: json['title'] as String?,
        inputMethod: json['inputMethod'] as String?,
        startedAt: json['startedAt'] as String?,
        completedAt: json['completedAt'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt(),
      );
  final int? drawingSessionId, childId, durationMs;
  final String? drawingTypeCode,
      drawingTypeName,
      title,
      inputMethod,
      startedAt,
      completedAt;
}

/// `data.drawing` — 완성 그림 이미지 URL.
final class ReportDrawingDto {
  const ReportDrawingDto({
    required this.finalImageUrl,
    required this.thumbnailUrl,
  });
  factory ReportDrawingDto.fromJson(Map<String, dynamic> json) =>
      ReportDrawingDto(
        finalImageUrl: json['finalImageUrl'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
      );
  final String? finalImageUrl, thumbnailUrl;
}

/// `data.childExpression.representativeUtterances[]` 항목.
///
/// `messageId`와 `text`는 원본 메시지가 없으면 null이다. `source`는 서버가
/// `STT`(음성 답변) 또는 `TEXT`로만 채우며, 값이 비면 계약 기본값 `TEXT`를 쓴다.
final class ReportUtteranceDto {
  const ReportUtteranceDto({
    required this.messageId,
    required this.text,
    required this.source,
    required this.sttNeedsConfirmation,
  });
  factory ReportUtteranceDto.fromJson(Map<String, dynamic> json) =>
      ReportUtteranceDto(
        messageId: (json['messageId'] as num?)?.toInt(),
        text: json['text'] as String?,
        source: json['source'] as String? ?? 'TEXT',
        sttNeedsConfirmation: json['sttNeedsConfirmation'] as bool? ?? false,
      );
  final int? messageId;
  final String? text;
  final String source;
  final bool sttNeedsConfirmation;
}

/// `data.childExpression` — 아이가 고른 감정과 대표 발화.
final class ReportChildExpressionDto {
  const ReportChildExpressionDto({
    required this.selectedEmotions,
    required this.expressedEmotionText,
    required this.representativeUtterances,
  });
  factory ReportChildExpressionDto.fromJson(Map<String, dynamic> json) =>
      ReportChildExpressionDto(
        selectedEmotions: _stringList(json['selectedEmotions']),
        expressedEmotionText: json['expressedEmotionText'] as String?,
        representativeUtterances:
            (json['representativeUtterances'] as List? ?? const [])
                .map((item) => ReportUtteranceDto.fromJson(_map(item)))
                .toList(growable: false),
      );
  final List<String> selectedEmotions;
  final String? expressedEmotionText;
  final List<ReportUtteranceDto> representativeUtterances;

  bool get isEmpty =>
      selectedEmotions.isEmpty &&
      expressedEmotionText == null &&
      representativeUtterances.isEmpty;
}

/// `data.activityFacts` — 해석 없이 관찰된 활동 기록.
final class ReportActivityFactsDto {
  const ReportActivityFactsDto({
    required this.detectedObjects,
    required this.drawingDurationMs,
    required this.pauseCount,
    required this.eraseCount,
    required this.pressureAvailable,
    required this.notes,
  });
  factory ReportActivityFactsDto.fromJson(Map<String, dynamic> json) =>
      ReportActivityFactsDto(
        detectedObjects: _stringList(json['detectedObjects']),
        drawingDurationMs: (json['drawingDurationMs'] as num?)?.toInt(),
        pauseCount: (json['pauseCount'] as num?)?.toInt(),
        eraseCount: (json['eraseCount'] as num?)?.toInt(),
        pressureAvailable: json['pressureAvailable'] as bool? ?? false,
        notes: _stringList(json['notes']),
      );
  final List<String> detectedObjects, notes;
  final int? drawingDurationMs, pauseCount, eraseCount;
  final bool pressureAvailable;

  bool get isEmpty =>
      detectedObjects.isEmpty &&
      notes.isEmpty &&
      pauseCount == null &&
      eraseCount == null;
}

/// `data.conversationSummary` — 대화 진행 수치와 요약문.
final class ReportConversationSummaryDto {
  const ReportConversationSummaryDto({
    required this.questionCount,
    required this.answeredCount,
    required this.skippedCount,
    required this.summary,
  });
  factory ReportConversationSummaryDto.fromJson(Map<String, dynamic> json) =>
      ReportConversationSummaryDto(
        questionCount: (json['questionCount'] as num?)?.toInt(),
        answeredCount: (json['answeredCount'] as num?)?.toInt(),
        skippedCount: (json['skippedCount'] as num?)?.toInt(),
        summary: json['summary'] as String?,
      );
  final int? questionCount, answeredCount, skippedCount;
  final String? summary;

  bool get isEmpty =>
      questionCount == null &&
      answeredCount == null &&
      skippedCount == null &&
      summary == null;
}

/// `data.expertReview` — 전문가 검토 워크플로 상태.
final class ReportExpertReviewDto {
  const ReportExpertReviewDto({required this.status, required this.available});
  factory ReportExpertReviewDto.fromJson(Map<String, dynamic> json) =>
      ReportExpertReviewDto(
        status: json['status'] as String?,
        available: json['available'] as bool? ?? false,
      );
  final String? status;
  final bool available;
}

/// REPORT-02 `GET /reports/{reportId}`의 `data` 페이로드.
///
/// 보호자 공개 계약(`docs/api/report-detail-guardian-contract.md` §2)만 담는다.
/// 서버가 내려주지 않는 값(analysisId·modelVersion·observedFeatures 등)은
/// 화면에서 지어내지 않도록 DTO에도 두지 않는다.
final class ReportDetailDto {
  const ReportDetailDto({
    required this.reportId,
    required this.reportVersion,
    required this.reportStatus,
    required this.drawingSession,
    required this.drawing,
    required this.childExpression,
    required this.activityFacts,
    required this.conversationSummary,
    required this.guardianConversationGuide,
    required this.limitations,
    required this.expertReview,
    required this.createdAt,
  });
  factory ReportDetailDto.fromJson(Map<String, dynamic> json) =>
      ReportDetailDto(
        reportId: (json['reportId'] as num).toInt(),
        reportVersion: (json['reportVersion'] as num?)?.toInt() ?? 0,
        reportStatus: json['reportStatus'] as String? ?? 'GENERATING',
        drawingSession: json['drawingSession'] is Map
            ? ReportDrawingSessionDto.fromJson(_map(json['drawingSession']))
            : null,
        drawing: json['drawing'] is Map
            ? ReportDrawingDto.fromJson(_map(json['drawing']))
            : null,
        childExpression: json['childExpression'] is Map
            ? ReportChildExpressionDto.fromJson(_map(json['childExpression']))
            : null,
        activityFacts: json['activityFacts'] is Map
            ? ReportActivityFactsDto.fromJson(_map(json['activityFacts']))
            : null,
        conversationSummary: json['conversationSummary'] is Map
            ? ReportConversationSummaryDto.fromJson(
                _map(json['conversationSummary']),
              )
            : null,
        guardianConversationGuide: _stringList(
          json['guardianConversationGuide'],
        ),
        limitations: _stringList(json['limitations']),
        expertReview: json['expertReview'] is Map
            ? ReportExpertReviewDto.fromJson(_map(json['expertReview']))
            : null,
        createdAt: json['createdAt'] as String?,
      );
  final int reportId, reportVersion;
  final String reportStatus;
  final ReportDrawingSessionDto? drawingSession;
  final ReportDrawingDto? drawing;
  final ReportChildExpressionDto? childExpression;
  final ReportActivityFactsDto? activityFacts;
  final ReportConversationSummaryDto? conversationSummary;
  final List<String> guardianConversationGuide, limitations;
  final ReportExpertReviewDto? expertReview;
  final String? createdAt;

  /// 관찰 섹션이 하나도 없어 "표시할 기록 없음"을 보여줘야 하는 상태.
  bool get hasNoObservations =>
      (childExpression?.isEmpty ?? true) &&
      (activityFacts?.isEmpty ?? true) &&
      (conversationSummary?.isEmpty ?? true) &&
      guardianConversationGuide.isEmpty;
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
