import '../../../../core/network/api_page.dart';
import 'diary_insights_dto.dart';
import 'screening_summary_dto.dart';
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

/// 계약상 객체 배열을 안전하게 파싱한다. 값이 없거나 리스트가 아니면 빈 목록을
/// 돌려주므로(오류 아님), 서버가 필드를 아직 내려주지 않는 동안에도 화면이
/// 해당 섹션을 자연스럽게 숨긴다.
List<T> _objectList<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value is List
    ? [
        for (final item in value)
          if (item is Map) parse(_map(item)),
      ]
    : const [];

List<int> _intList(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is num) item.toInt(),
      ]
    : const [];

/// 문자열 값을 방어적으로 읽는다. 문자열이 아니거나 공백뿐이면 null이라
/// 화면에 빈 줄이 남지 않는다(계약 §10 — 빈 값은 오류가 아니라 숨김).
String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

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

/// REPORT-06·07 리포트 생성 상태와 재접수 결과.
final class ReportGenerationStatusDto {
  const ReportGenerationStatusDto({
    required this.reportId,
    required this.drawingSessionId,
    required this.analysisId,
    required this.reportVersion,
    required this.reportStatus,
    required this.retryable,
    required this.failureReason,
    required this.createdAt,
    required this.updatedAt,
    required this.failedAt,
  });

  factory ReportGenerationStatusDto.fromJson(Map<String, dynamic> json) =>
      ReportGenerationStatusDto(
        reportId: (json['reportId'] as num).toInt(),
        drawingSessionId: (json['drawingSessionId'] as num?)?.toInt(),
        analysisId: (json['analysisId'] as num?)?.toInt(),
        reportVersion: (json['reportVersion'] as num?)?.toInt() ?? 0,
        reportStatus: json['reportStatus'] as String? ?? 'GENERATING',
        retryable: json['retryable'] as bool? ?? false,
        failureReason: json['failureReason'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        failedAt: DateTime.tryParse(json['failedAt'] as String? ?? ''),
      );

  final int reportId, reportVersion;
  final int? drawingSessionId, analysisId;
  final String reportStatus;
  final bool retryable;
  final String? failureReason;
  final DateTime? createdAt, updatedAt, failedAt;
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
///
/// [summary]·[keywords]는 계약 §9의 "아이의 표현 요약"이며, 서버가 아직
/// 내려주지 않으면 각각 null·빈 목록이 되어 요약 섹션이 숨는다.
final class ReportChildExpressionDto {
  const ReportChildExpressionDto({
    required this.selectedEmotions,
    required this.expressedEmotionText,
    required this.representativeUtterances,
    this.summary,
    this.keywords = const [],
  });
  factory ReportChildExpressionDto.fromJson(Map<String, dynamic> json) =>
      ReportChildExpressionDto(
        selectedEmotions: _stringList(json['selectedEmotions']),
        expressedEmotionText: json['expressedEmotionText'] as String?,
        representativeUtterances:
            (json['representativeUtterances'] as List? ?? const [])
                .map((item) => ReportUtteranceDto.fromJson(_map(item)))
                .toList(growable: false),
        summary: json['summary'] as String?,
        keywords: _stringList(json['keywords']),
      );
  final List<String> selectedEmotions;
  final String? expressedEmotionText;
  final List<ReportUtteranceDto> representativeUtterances;
  final String? summary;
  final List<String> keywords;

  bool get isEmpty =>
      selectedEmotions.isEmpty &&
      expressedEmotionText == null &&
      representativeUtterances.isEmpty &&
      summary == null &&
      keywords.isEmpty;
}

/// `data.activityFacts` — 해석 없이 관찰된 객관 수치(계약 §8).
///
/// 계약은 초 단위(`totalDurationSec` 등)로 수치를 준다. 구형 응답의
/// `drawingDurationMs`(밀리초)·`detectedObjects`·`notes`도 하위 호환으로 계속
/// 읽는다. 모든 수치는 nullable이라 `null`이면 화면에서 줄을 숨기고 `0`이면
/// "0회"로 보여줄 수 있다. 어떤 값에도 심리 해석을 붙이지 않는다.
final class ReportActivityFactsDto {
  const ReportActivityFactsDto({
    required this.detectedObjects,
    required this.drawingDurationMs,
    required this.pauseCount,
    required this.eraseCount,
    required this.pressureAvailable,
    required this.notes,
    this.totalDurationSec,
    this.drawingDurationSec,
    this.undoCount,
    this.questionCount,
    this.answerCount,
    this.skipCount,
    this.detectedElementCount,
    this.pressureValue,
    this.truncated = false,
    this.aggregatedHtp = false,
  });
  factory ReportActivityFactsDto.fromJson(Map<String, dynamic> json) =>
      ReportActivityFactsDto(
        detectedObjects: _stringList(json['detectedObjects']),
        drawingDurationMs: (json['drawingDurationMs'] as num?)?.toInt(),
        pauseCount: (json['pauseCount'] as num?)?.toInt(),
        eraseCount: (json['eraseCount'] as num?)?.toInt(),
        pressureAvailable: json['pressureAvailable'] as bool? ?? false,
        notes: _stringList(json['notes']),
        totalDurationSec: (json['totalDurationSec'] as num?)?.toInt(),
        drawingDurationSec: (json['drawingDurationSec'] as num?)?.toInt(),
        undoCount: (json['undoCount'] as num?)?.toInt(),
        questionCount: (json['questionCount'] as num?)?.toInt(),
        answerCount: (json['answerCount'] as num?)?.toInt(),
        skipCount: (json['skipCount'] as num?)?.toInt(),
        detectedElementCount: (json['detectedElementCount'] as num?)?.toInt(),
        pressureValue: (json['pressureValue'] as num?)?.toDouble(),
        truncated: json['truncated'] as bool? ?? false,
        aggregatedHtp: json['aggregatedHtp'] as bool? ?? false,
      );
  final List<String> detectedObjects, notes;
  final int? drawingDurationMs, pauseCount, eraseCount;
  final bool pressureAvailable;
  final int? totalDurationSec,
      drawingDurationSec,
      undoCount,
      questionCount,
      answerCount,
      skipCount,
      detectedElementCount;
  final double? pressureValue;
  final bool truncated, aggregatedHtp;

  /// 필압 항목은 플래그가 켜져 있고 실제 값이 있을 때만 노출한다.
  bool get hasPressureValue => pressureAvailable && pressureValue != null;

  bool get isEmpty =>
      detectedObjects.isEmpty &&
      notes.isEmpty &&
      pauseCount == null &&
      eraseCount == null &&
      totalDurationSec == null &&
      drawingDurationSec == null &&
      undoCount == null &&
      questionCount == null &&
      answerCount == null &&
      skipCount == null &&
      detectedElementCount == null &&
      !hasPressureValue;
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

/// `publicInterpretations[]` — 주요 심리 경향 카드(계약 §3).
///
/// 비진단 원칙: [tendencyText]는 가능성 어조이며, 화면에서 단독으로 크게 쓰지
/// 않고 근거·[scopeText]와 함께 보여준다. [evidenceRefs]는 [ReportDetailDto]
/// 최상위 `evidenceItems`의 `evidenceId`를 참조한다.
final class ReportInterpretationDto {
  const ReportInterpretationDto({
    required this.category,
    required this.title,
    required this.tendencyText,
    required this.scopeText,
    required this.homeObservationGuide,
    required this.evidenceRefs,
    this.confidence,
  });
  factory ReportInterpretationDto.fromJson(Map<String, dynamic> json) =>
      ReportInterpretationDto(
        category: json['category'] as String?,
        title: json['title'] as String?,
        tendencyText: json['tendencyText'] as String?,
        scopeText: json['scopeText'] as String?,
        homeObservationGuide: json['homeObservationGuide'] as String?,
        evidenceRefs: _intList(json['evidenceRefs']),
        confidence: json['confidence'] as String?,
      );

  /// RELATIONSHIP|EMOTION|SELF_EXPRESSION|ACTIVITY_STYLE|ADAPTATION.
  final String? category;
  final String? title, tendencyText, scopeText, homeObservationGuide;
  final List<int> evidenceRefs;

  /// 근거 종류로 서버가 계산한 확신 등급 `STRONG`·`MODERATE`·`WEAK`이며 등급이
  /// 없으면 `null`이다(S15P11B209-982).
  ///
  /// **`null`이 정상 값이다.** V43 이전에 만들어진 카드와 AI가 등급을 싣지 않은
  /// 카드가 모두 `null`로 내려온다. 그런 카드는 배지만 빠질 뿐 카드 자체는 정상
  /// 노출한다 — 등급이 없다고 숨기면 해석이 통째로 사라진다.
  ///
  /// 등급을 매기는 주체는 서버다. 앱은 판정하지 않고 받은 값을 그대로 보여준다.
  final String? confidence;
}

/// `evidenceItems[]` — 카드가 참조하는 근거 풀(계약 §4).
///
/// [evidenceId]·[sourceType] 코드값은 화면에 노출하지 않는다(라벨만).
final class ReportEvidenceItemDto {
  const ReportEvidenceItemDto({
    required this.evidenceId,
    required this.sourceType,
    required this.text,
  });
  factory ReportEvidenceItemDto.fromJson(Map<String, dynamic> json) =>
      ReportEvidenceItemDto(
        evidenceId: (json['evidenceId'] as num?)?.toInt(),
        sourceType: json['sourceType'] as String?,
        text: json['text'] as String?,
      );
  final int? evidenceId;
  final String? sourceType, text;
}

/// `subjectReports[].qaPairs[]` — 아이와 나눈 문답(계약 §6).
final class ReportQaPairDto {
  const ReportQaPairDto({
    required this.question,
    required this.answer,
    required this.state,
    required this.inputType,
    required this.sttNeedsConfirmation,
    required this.isRepresentative,
  });
  factory ReportQaPairDto.fromJson(Map<String, dynamic> json) =>
      ReportQaPairDto(
        question: json['question'] as String?,
        answer: json['answer'] as String?,
        state: json['state'] as String? ?? 'ANSWERED',
        inputType: json['inputType'] as String? ?? 'TEXT',
        sttNeedsConfirmation: json['sttNeedsConfirmation'] as bool? ?? false,
        isRepresentative: json['isRepresentative'] as bool? ?? false,
      );
  final String? question, answer;

  /// ANSWERED | SKIPPED.
  final String state;

  /// TEXT | VOICE.
  final String inputType;
  final bool sttNeedsConfirmation, isRepresentative;
}

/// `observedFeatures[]` — "이런 모습이 보였어요"(계약 §2-1).
///
/// AI 자체 검토를 통과한 항목(`AI_REVIEWED` + `REVIEWED_GUARDIAN`)만 서버가
/// 싣는다. 보호자에게 열지 않는 항목은 **응답에 아예 오지 않으므로** 화면이
/// 거르지 않는다. 내부 코드(`featureCode`)·공개 범위(`visibilityScope`)는
/// 계약상 응답에 없으며, 설령 실려 와도 이 DTO가 읽지 않아 노출되지 않는다.
final class ReportObservedFeatureDto {
  const ReportObservedFeatureDto({
    required this.title,
    required this.description,
    required this.evidenceSummary,
  });
  factory ReportObservedFeatureDto.fromJson(Map<String, dynamic> json) =>
      ReportObservedFeatureDto(
        title: _text(json['title']),
        description: _text(json['description']),
        evidenceSummary: _text(json['evidenceSummary']),
      );
  final String? title, description, evidenceSummary;

  bool get isEmpty =>
      title == null && description == null && evidenceSummary == null;
}

/// `subjectReports[]` — 집·나무·사람 주제별 보고(계약 §5).
///
/// 순서는 서버가 HOUSE→TREE→PERSON으로 보장하지만, 화면에서도 한 번 더
/// 정렬해 안전하게 표시한다.
final class ReportSubjectReportDto {
  const ReportSubjectReportDto({
    required this.subjectType,
    required this.imageUrl,
    required this.visionObservations,
    required this.qaPairs,
    required this.interpretationRefs,
  });
  factory ReportSubjectReportDto.fromJson(Map<String, dynamic> json) =>
      ReportSubjectReportDto(
        subjectType: json['subjectType'] as String?,
        imageUrl: _text(json['imageUrl']),
        visionObservations: _stringList(json['visionObservations']),
        qaPairs: _objectList(json['qaPairs'], ReportQaPairDto.fromJson),
        interpretationRefs: _intList(json['interpretationRefs']),
      );

  /// HOUSE | TREE | PERSON.
  final String? subjectType;
  final String? imageUrl;
  final List<String> visionObservations;
  final List<ReportQaPairDto> qaPairs;

  /// 같은 응답 `publicInterpretations`의 **배열 인덱스**(0-based)다(계약 §5-1).
  /// category 값이 아니며, 화면 정렬 결과가 아니라 서버가 준 원래 순서에 대고
  /// 풀어야 다른 카드를 가리키지 않는다.
  final List<int> interpretationRefs;

  /// 이 주제의 완성 그림을 실제로 보여줄 수 있는지.
  bool get hasImage => imageUrl != null;

  /// 이 주제에 표시할 관찰 문장이나 문답이 있는지(§10 — 없으면 카드 숨김).
  bool get hasDetails => visionObservations.isNotEmpty || qaPairs.isNotEmpty;
}

/// `parentGuides[]` — 보호자 가이드(계약 §7). guideType별로 섹션이 나뉜다.
final class ReportParentGuideDto {
  const ReportParentGuideDto({required this.guideType, required this.items});
  factory ReportParentGuideDto.fromJson(Map<String, dynamic> json) =>
      ReportParentGuideDto(
        guideType: json['guideType'] as String?,
        items: _stringList(json['items']),
      );

  /// DRAWING_CONVERSATION | DAILY_PARENTING | HOME_OBSERVATION |
  /// PROFESSIONAL_SUPPORT.
  final String? guideType;
  final List<String> items;
}

/// `references[]` — 참고 자료(계약 §9).
final class ReportReferenceDto {
  const ReportReferenceDto({required this.title, required this.url});
  factory ReportReferenceDto.fromJson(Map<String, dynamic> json) =>
      ReportReferenceDto(
        title: json['title'] as String?,
        url: json['url'] as String?,
      );
  final String? title, url;
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
/// 보호자 공개 계약(`docs/api/report-detail-guardian-contract.md` §2 +
/// `docs/S15P11B209-875-report-api-contract.md`)만 담는다. 서버가 내려주지
/// 않는 값(analysisId·modelVersion·attentionPoints 등)은 화면에서 지어내지
/// 않도록 DTO에도 두지 않는다.
///
/// `observedFeatures`는 §2-1 개정으로 보호자 공개 대상이 되어 읽는다. 반면
/// `evidenceItems[].sourceRef`·`derivedFrom`은 서버 검증용이라 화면이 쓸 일이
/// 없으므로 일부러 읽지 않는다 — 모르는 키는 조용히 무시된다.
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
    this.activityType,
    this.childDisplayName,
    this.nonDiagnosticNotice,
    this.publicInterpretations = const [],
    this.evidenceItems = const [],
    this.subjectReports = const [],
    this.observedFeatures = const [],
    this.parentGuides = const [],
    this.references = const [],
    this.diaryInsights,
    this.screeningSummary,
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
        activityType: _text(json['activityType']),
        childDisplayName: _text(json['childDisplayName']),
        nonDiagnosticNotice: _text(json['nonDiagnosticNotice']),
        publicInterpretations: _objectList(
          json['publicInterpretations'],
          ReportInterpretationDto.fromJson,
        ),
        evidenceItems: _objectList(
          json['evidenceItems'],
          ReportEvidenceItemDto.fromJson,
        ),
        subjectReports: _objectList(
          json['subjectReports'],
          ReportSubjectReportDto.fromJson,
        ),
        observedFeatures: _objectList(
          json['observedFeatures'],
          ReportObservedFeatureDto.fromJson,
        ),
        parentGuides: _objectList(
          json['parentGuides'],
          ReportParentGuideDto.fromJson,
        ),
        references: _objectList(
          json['references'],
          ReportReferenceDto.fromJson,
        ),
        screeningSummary: json['screeningSummary'] is Map
            ? ScreeningSummaryDto.fromJson(_map(json['screeningSummary']))
            : null,
        diaryInsights: json['diaryInsights'] is Map
            ? DiaryInsightsDto.fromJson(_map(json['diaryInsights']))
            : null,
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

  /// 계약 §2·§10 추가 필드. 서버가 아직 내려주지 않으면 각각 null·빈 목록이라
  /// 해당 섹션이 숨는다(하위 호환).
  ///
  /// [activityType]은 `HTP | ART_DIARY | FREE_DRAWING` 등 기존 활동 코드,
  /// [childDisplayName]은 표지용 아이 이름이다.
  final String? activityType;
  final String? childDisplayName;
  final String? nonDiagnosticNotice;
  final List<ReportInterpretationDto> publicInterpretations;
  final List<ReportEvidenceItemDto> evidenceItems;
  final List<ReportSubjectReportDto> subjectReports;
  final List<ReportObservedFeatureDto> observedFeatures;
  final List<ReportParentGuideDto> parentGuides;
  final List<ReportReferenceDto> references;

  /// 이 아이의 검사 기록 요약이며 없으면 `null`.
  ///
  /// 앱은 표준화 선별검사를 제공하지 않는다. 담기는 것은 보호자가 다른 곳에서
  /// 받아 와 직접 옮겨 적은 결과이며, 그림일기 관찰과 자리를 나눠 보여 준다.
  final ScreeningSummaryDto? screeningSummary;

  /// 그림일기 리포트 V2 묶음이며 없으면 `null`.
  ///
  /// HTP 이거나, 그림일기지만 근거가 부족해 서버가 구조화를 포기하면 오지 않는다.
  /// 화면은 이 값의 유무로 V2 와 기존 리포트를 가른다.
  final DiaryInsightsDto? diaryInsights;

  /// HTP(집·나무·사람) 활동인지. 계약 §2의 최상위 `activityType`이 정본이고,
  /// 아직 그 필드를 주지 않는 구형 응답은 세션의 `drawingTypeCode`로 판정한다.
  bool get isHtpActivity =>
      activityType?.toUpperCase() == 'HTP' ||
      drawingSession?.drawingTypeCode?.toUpperCase() == 'HTP';

  /// 계약 §7의 4종 가이드를 화면 순서(그림 대화→일상 육아→가정 관찰→전문 도움)로
  /// 정렬해 돌려준다. 알 수 없는 유형은 뒤에 둔다.
  List<ReportParentGuideDto> get orderedParentGuides {
    const order = [
      'DRAWING_CONVERSATION',
      'DAILY_PARENTING',
      'HOME_OBSERVATION',
      'PROFESSIONAL_SUPPORT',
    ];
    int rank(ReportParentGuideDto guide) {
      final index = order.indexOf(guide.guideType ?? '');
      return index < 0 ? order.length : index;
    }

    return [...parentGuides.where((guide) => guide.items.isNotEmpty)]
      ..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  /// 계약 §5의 집·나무·사람 순서를 보장한다.
  List<ReportSubjectReportDto> get orderedSubjectReports {
    const order = ['HOUSE', 'TREE', 'PERSON'];
    int rank(ReportSubjectReportDto report) {
      final index = order.indexOf(report.subjectType ?? '');
      return index < 0 ? order.length : index;
    }

    return [...subjectReports]..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  /// 완성 그림 URL이 실제로 있는 주제만 계약 순서대로 돌려준다(계약 §5).
  /// HTP가 아니면 0~1개일 수 있으므로 화면은 개수를 가정하지 않는다.
  List<ReportSubjectReportDto> get subjectDrawings => [
    for (final subject in orderedSubjectReports)
      if (subject.hasImage) subject,
  ];

  /// 관찰 문장이나 문답이 있는 주제만 계약 순서대로 돌려준다(계약 §5·§10).
  List<ReportSubjectReportDto> get subjectDetails => [
    for (final subject in orderedSubjectReports)
      if (subject.hasDetails) subject,
  ];

  /// 관찰 섹션이 하나도 없어 "표시할 기록 없음"을 보여줘야 하는 상태(계약 §10):
  /// publicInterpretations + childExpression + activityFacts +
  /// conversationSummary + parentGuides가 모두 비었을 때만 참.
  ///
  /// 계약이 열거한 5종 외에 §2-1 `observedFeatures`와 §5 주제별 관찰·문답도
  /// 함께 본다. 둘 중 하나라도 화면에 실려 있는데 "표시할 기록이 없다"고
  /// 적으면 사실과 어긋나기 때문이며, 조건을 더하는 방향이라 계약이 정한
  /// "모두 비었을 때만" 규칙을 위반하지 않는다.
  bool get hasNoObservations =>
      publicInterpretations.isEmpty &&
      (childExpression?.isEmpty ?? true) &&
      (activityFacts?.isEmpty ?? true) &&
      (conversationSummary?.isEmpty ?? true) &&
      guardianConversationGuide.isEmpty &&
      orderedParentGuides.isEmpty &&
      observedFeatures.every((feature) => feature.isEmpty) &&
      subjectDetails.isEmpty;
}

/// REPORT-04 리포트 PDF 내보내기 접수 결과.
final class ReportExportDto {
  const ReportExportDto({
    required this.reportId,
    required this.exportId,
    required this.status,
    required this.downloadUrl,
  });

  factory ReportExportDto.fromJson(Map<String, dynamic> json) =>
      ReportExportDto(
        reportId: (json['reportId'] as num).toInt(),
        exportId: (json['exportId'] as num).toInt(),
        status: json['status'] as String,
        downloadUrl: json['downloadUrl'] as String?,
      );

  final int reportId;
  final int exportId;
  final String status;
  final String? downloadUrl;

  bool get isReady => status == 'COMPLETED' && downloadUrl != null;
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
