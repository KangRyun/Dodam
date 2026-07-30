import '../../../../core/network/api_page.dart';

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

Map<String, dynamic>? _mapOrNull(Object? value) =>
    value == null ? null : _map(value);

List<Map<String, dynamic>> _mapList(Object? value) => [
  for (final item in (value as List<dynamic>?) ?? const []) _map(item),
];

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
    // 백엔드(HISTORY-01)는 drawingTypeCode·sessionStatus 파라미터명을 쓴다.
    if (drawingType != null) 'drawingTypeCode': drawingType,
    if (status != null) 'sessionStatus': status,
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

/// HTP 활동 한 묶음에 포함된 집·나무·사람 그림 한 장.
final class HtpActivityDrawingDto {
  const HtpActivityDrawingDto({
    required this.drawingSubject,
    required this.drawingSessionId,
    required this.thumbnailUrl,
  });

  factory HtpActivityDrawingDto.fromJson(Map<String, dynamic> json) =>
      HtpActivityDrawingDto(
        drawingSubject: json['drawingSubject'] as String,
        drawingSessionId: json['drawingSessionId'] as int,
        thumbnailUrl: json['thumbnailUrl'] as String?,
      );

  final String drawingSubject;
  final int drawingSessionId;
  final String? thumbnailUrl;
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
    this.activityKind = 'GENERAL',
    this.htpAssessmentId,
    this.htpStatus,
    this.htpDrawings = const [],
  });
  factory ActivitySummaryDto.fromJson(Map<String, dynamic> json) =>
      ActivitySummaryDto(
        // 백엔드 활동 기록 목록(HISTORY-01)은 drawingSessionId를 준다. 레거시 목·테스트는
        // activityId를 쓰므로 둘 다 받는다.
        activityId: (json['drawingSessionId'] ?? json['activityId']) as int,
        title: json['title'] as String?,
        drawingType: ActivityDrawingTypeDto.fromJson(_map(json['drawingType'])),
        inputMethod: json['inputMethod'] as String,
        sessionStatus: json['sessionStatus'] as String,
        selectedEmotions: List<String>.from(json['selectedEmotions'] as List),
        thumbnailUrl: json['thumbnailUrl'] as String?,
        analysisStatus: json['analysisStatus'] as String?,
        report: _summaryReportFromJson(json),
        startedAt: json['startedAt'] as String,
        completedAt: json['completedAt'] as String?,
        activityKind: json['activityKind'] as String? ?? 'GENERAL',
        htpAssessmentId: json['htpAssessmentId'] as int?,
        htpStatus: json['htpStatus'] as String?,
        htpDrawings: _mapList(
          json['htpDrawings'],
        ).map(HtpActivityDrawingDto.fromJson).toList(growable: false),
      );
  final int activityId;
  final String? title, thumbnailUrl, analysisStatus, completedAt;
  final ActivityDrawingTypeDto drawingType;
  final String inputMethod, sessionStatus, startedAt;
  final List<String> selectedEmotions;
  final ActivityReportSummaryDto? report;
  final String activityKind;
  final int? htpAssessmentId;
  final String? htpStatus;
  final List<HtpActivityDrawingDto> htpDrawings;

  bool get isHtp => activityKind == 'HTP' && htpAssessmentId != null;
}

/// 목록 항목의 리포트 요약을 만든다.
///
/// 백엔드(HISTORY-01)는 평면 `reportId`/`reportStatus`로, 레거시 목·테스트는 중첩
/// `report{}`로 준다. 둘 다 받아 없으면 null.
ActivityReportSummaryDto? _summaryReportFromJson(Map<String, dynamic> json) {
  final nested = json['report'];
  if (nested != null) return ActivityReportSummaryDto.fromJson(_map(nested));
  final reportId = json['reportId'];
  final reportStatus = json['reportStatus'];
  if (reportId == null || reportStatus == null) return null;
  return ActivityReportSummaryDto(
    reportId: reportId as int,
    reportStatus: reportStatus as String,
  );
}

/// 활동 상세의 `latestAsset` — 백엔드
/// `DrawingSessionAssetSummaryResponse`(drawingAssetId 기준)와 같은 모양이다.
///
/// 응답에는 파일 URL이 없고 식별자만 있다. 서버가 쓰는 것과 같은 규칙으로
/// 인증 조회 상대 경로를 만들어 [fileUrl]로 노출한다.
final class ActivityAssetDto {
  const ActivityAssetDto({
    required this.drawingAssetId,
    required this.assetType,
    required this.assetVersion,
    required this.mimeType,
    this.widthPx,
    this.heightPx,
    this.capturedAt,
    this.createdAt,
  });
  factory ActivityAssetDto.fromJson(Map<String, dynamic> json) =>
      ActivityAssetDto(
        drawingAssetId: json['drawingAssetId'] as int,
        assetType: json['assetType'] as String,
        assetVersion: json['assetVersion'] as int,
        mimeType: json['mimeType'] as String,
        // 이미지 크기 컬럼이 추가되기 전 Asset은 null이다.
        widthPx: json['widthPx'] as int?,
        heightPx: json['heightPx'] as int?,
        capturedAt: json['capturedAt'] as String?,
        createdAt: json['createdAt'] as String?,
      );
  final int drawingAssetId, assetVersion;
  final int? widthPx, heightPx;
  final String assetType, mimeType;
  final String? capturedAt, createdAt;

  /// JWT 인증이 필요한 그림 파일 조회 상대 URL.
  String get fileUrl => '/api/v1/drawing-assets/$drawingAssetId/file';
}

/// 활동 상세의 `latestAnalysis` — 백엔드
/// `DrawingSessionAnalysisSummaryResponse`와 같은 모양이다.
final class ActivityAnalysisSummaryDto {
  const ActivityAnalysisSummaryDto({
    required this.drawingAnalysisId,
    required this.analysisStatus,
    this.analysisScope,
    this.analysisType,
    this.requestedAt,
    this.completedAt,
  });
  factory ActivityAnalysisSummaryDto.fromJson(Map<String, dynamic> json) =>
      ActivityAnalysisSummaryDto(
        drawingAnalysisId: json['drawingAnalysisId'] as int,
        analysisStatus: json['analysisStatus'] as String,
        analysisScope: json['analysisScope'] as String?,
        analysisType: json['analysisType'] as String?,
        requestedAt: json['requestedAt'] as String?,
        completedAt: json['completedAt'] as String?,
      );
  final int drawingAnalysisId;
  final String analysisStatus;
  final String? analysisScope, analysisType, requestedAt, completedAt;
}

/// `GET /api/v1/drawing-sessions/{drawingSessionId}`의 `data` 페이로드.
///
/// 백엔드 `DrawingSessionDetailResponse`를 그대로 읽는다. 이전 버전은 구형
/// 계약(`activityId`·최상위 `childId`·`assets[]`·중첩 `conversation{}`·
/// `expressedEmotionText`)을 기대했지만 실제 응답에는 없는 필드였다.
/// 연관 리소스가 없으면 해당 값은 null이고 선택 감정은 빈 목록이다.
final class ActivityDetailDto {
  const ActivityDetailDto({
    required this.activityId,
    required this.childId,
    required this.childNickname,
    required this.title,
    required this.drawingType,
    required this.inputMethod,
    required this.sessionStatus,
    required this.currentStage,
    required this.selectedEmotions,
    required this.startedAt,
    required this.completedAt,
    required this.latestAsset,
    required this.latestAnalysis,
    required this.conversationId,
    required this.reportId,
    this.recoverableDraft = false,
  });
  factory ActivityDetailDto.fromJson(Map<String, dynamic> json) {
    final child = _map(json['child']);
    return ActivityDetailDto(
      activityId: json['drawingSessionId'] as int,
      childId: child['childId'] as int,
      childNickname: child['nickname'] as String?,
      title: json['title'] as String?,
      drawingType: ActivityDrawingTypeDto.fromJson(_map(json['drawingType'])),
      inputMethod: json['inputMethod'] as String,
      sessionStatus: json['sessionStatus'] as String,
      currentStage: json['currentStage'] as String,
      selectedEmotions: List<String>.from(
        json['selectedEmotions'] as List? ?? const [],
      ),
      startedAt: json['startedAt'] as String,
      completedAt: json['completedAt'] as String?,
      latestAsset: switch (_mapOrNull(json['latestAsset'])) {
        final asset? => ActivityAssetDto.fromJson(asset),
        _ => null,
      },
      latestAnalysis: switch (_mapOrNull(json['latestAnalysis'])) {
        final analysis? => ActivityAnalysisSummaryDto.fromJson(analysis),
        _ => null,
      },
      conversationId: json['conversationId'] as int?,
      reportId: json['reportId'] as int?,
      recoverableDraft: json['recoverableDraft'] as bool? ?? false,
    );
  }
  final int activityId, childId;
  final String? childNickname, title, completedAt;
  final ActivityDrawingTypeDto drawingType;
  final String inputMethod, sessionStatus, currentStage, startedAt;
  final List<String> selectedEmotions;
  final ActivityAssetDto? latestAsset;
  final ActivityAnalysisSummaryDto? latestAnalysis;
  final int? conversationId;
  final int? reportId;
  final bool recoverableDraft;
}

// ── 대화 내역(CONV-02) ────────────────────────────────────────────────

/// 질문 메시지에 노출된 선택지 Snapshot 하나.
final class ActivityConversationOptionDto {
  const ActivityConversationOptionDto({
    required this.optionId,
    required this.type,
    required this.label,
    required this.value,
    this.emoji,
  });
  factory ActivityConversationOptionDto.fromJson(Map<String, dynamic> json) =>
      ActivityConversationOptionDto(
        optionId: json['optionId'].toString(),
        type: json['type'] as String? ?? '',
        label: json['label'] as String? ?? '',
        value: json['value'] as String? ?? '',
        emoji: json['emoji'] as String?,
      );
  final String optionId, type, label, value;
  final String? emoji;
}

/// 선택형 답변에서 아동이 실제로 고른 항목 하나.
final class ActivityConversationSelectedOptionDto {
  const ActivityConversationSelectedOptionDto({
    required this.optionId,
    required this.labelSnapshot,
    this.type,
    this.value,
  });
  factory ActivityConversationSelectedOptionDto.fromJson(
    Map<String, dynamic> json,
  ) => ActivityConversationSelectedOptionDto(
    optionId: json['optionId'].toString(),
    labelSnapshot: json['labelSnapshot'] as String? ?? '',
    type: json['type'] as String?,
    value: json['value'] as String?,
  );
  final String optionId, labelSnapshot;
  final String? type, value;
}

/// 선택형 답변 메시지에 저장된 선택 응답.
final class ActivityConversationSelectedResponseDto {
  const ActivityConversationSelectedResponseDto({
    this.selectedOptions = const [],
    this.directText,
  });
  factory ActivityConversationSelectedResponseDto.fromJson(
    Map<String, dynamic> json,
  ) => ActivityConversationSelectedResponseDto(
    selectedOptions: [
      for (final item in _mapList(json['selectedOptions']))
        ActivityConversationSelectedOptionDto.fromJson(item),
    ],
    directText: json['directText'] as String?,
  );
  final List<ActivityConversationSelectedOptionDto> selectedOptions;
  final String? directText;
}

/// 질문이 가리킨 그림 속 대상 객체 Snapshot.
///
/// 상세 화면은 이름만 쓰므로 Bounding Box는 읽지 않는다.
final class ActivityConversationTargetDto {
  const ActivityConversationTargetDto({this.objectCode, this.objectName});
  factory ActivityConversationTargetDto.fromJson(Map<String, dynamic> json) =>
      ActivityConversationTargetDto(
        objectCode: json['objectCode'] as String?,
        objectName: json['objectName'] as String?,
      );
  final String? objectCode, objectName;
}

/// `GET /api/v1/conversations/{conversationId}/messages`의 단일 메시지.
///
/// 백엔드 `ConversationMessageResponse`를 그대로 읽는다. 유형에 따라 채워지는
/// 필드가 다르며 해당 없는 필드는 null이거나 빈 목록이다. [messageType]은
/// 공개 API 값(`QUESTION`·`ANSWER_VOICE`·`ANSWER_OPTION`·`ANSWER_TEXT`·
/// `SYSTEM`)이지만, 알 수 없는 값이 와도 원문을 그대로 담아 화면이 안전하게
/// 처리할 수 있게 한다.
final class ActivityConversationMessageDto {
  const ActivityConversationMessageDto({
    required this.messageId,
    required this.sequence,
    required this.senderType,
    required this.messageType,
    this.parentMessageId,
    this.rawText,
    this.sttText,
    this.speechStatus,
    this.sttConfidence,
    this.needsGuardianConfirmation = false,
    this.isSkipped = false,
    this.options = const [],
    this.selectedResponse,
    this.targetObject,
    this.createdAt,
  });
  factory ActivityConversationMessageDto.fromJson(Map<String, dynamic> json) =>
      ActivityConversationMessageDto(
        messageId: json['messageId'] as int,
        sequence: json['sequence'] as int? ?? 0,
        senderType: json['senderType'] as String? ?? '',
        messageType: json['messageType'] as String? ?? '',
        parentMessageId: json['parentMessageId'] as int?,
        rawText: json['rawText'] as String?,
        sttText: json['sttText'] as String?,
        speechStatus: json['speechStatus'] as String?,
        sttConfidence: (json['sttConfidence'] as num?)?.toDouble(),
        needsGuardianConfirmation:
            json['needsGuardianConfirmation'] as bool? ?? false,
        isSkipped: json['isSkipped'] as bool? ?? false,
        options: [
          for (final item in _mapList(json['options']))
            ActivityConversationOptionDto.fromJson(item),
        ],
        selectedResponse: switch (_mapOrNull(json['selectedResponse'])) {
          final selected? => ActivityConversationSelectedResponseDto.fromJson(
            selected,
          ),
          _ => null,
        },
        targetObject: switch (_mapOrNull(json['targetObject'])) {
          final target? => ActivityConversationTargetDto.fromJson(target),
          _ => null,
        },
        createdAt: json['createdAt'] as String?,
      );

  final int messageId, sequence;
  final int? parentMessageId;
  final String senderType, messageType;
  final String? rawText, sttText, speechStatus, createdAt;
  final double? sttConfidence;
  final bool needsGuardianConfirmation, isSkipped;
  final List<ActivityConversationOptionDto> options;
  final ActivityConversationSelectedResponseDto? selectedResponse;
  final ActivityConversationTargetDto? targetObject;

  bool get isQuestion => messageType == 'QUESTION';
}

/// CONV-02 메시지 목록 한 페이지. 공통 페이지 계약을 그대로 쓴다.
typedef ActivityConversationMessagePage =
    ApiPage<ActivityConversationMessageDto>;

typedef ActivityPage = ApiPage<ActivitySummaryDto>;
