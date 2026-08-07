/// 그림일기 리포트 V2 (`diaryInsights`) DTO.
///
/// 리포트 상세 응답의 optional 필드다. **없으면 기존 리포트 화면을 그대로 쓴다** —
/// HTP 리포트이거나, 그림일기지만 근거가 부족해 서버가 구조화를 포기한 경우다.
/// 빈 껍데기를 만들지 않는 것이 이 계약의 핵심이라, 화면도 값의 유무로 갈린다.
///
/// 빈 배열은 정상이다. 그 섹션을 숨기라는 뜻이며, 채우려고 일반론을 만들지 않는다.
library;

/// 근거가 어떤 질문에서 나왔는지 가리키는 참조.
final class DiaryEvidenceRefDto {
  const DiaryEvidenceRefDto({this.kind, this.id});

  /// JSON 한 건을 읽는다.
  factory DiaryEvidenceRefDto.fromJson(Map<String, dynamic> json) =>
      DiaryEvidenceRefDto(
        kind: json['kind'] as String?,
        id: json['id'] as String?,
      );

  /// 근거 종류(예: `QA_ANSWER`).
  final String? kind;

  /// 서버가 발급한 근거 식별자.
  final String? id;
}

/// 이번 그림일기의 핵심 이야기.
final class DiaryStorySnapshotDto {
  const DiaryStorySnapshotDto({
    this.headline,
    this.summary,
    this.realityStatus = 'UNKNOWN',
    this.timeScope = 'UNKNOWN',
    this.mainEvent,
    this.evidenceRefs = const [],
  });

  /// JSON 한 건을 읽는다.
  factory DiaryStorySnapshotDto.fromJson(Map<String, dynamic> json) =>
      DiaryStorySnapshotDto(
        headline: _text(json['headline']),
        summary: _text(json['summary']),
        realityStatus: json['realityStatus'] as String? ?? 'UNKNOWN',
        timeScope: json['timeScope'] as String? ?? 'UNKNOWN',
        mainEvent: _text(json['mainEvent']),
        evidenceRefs: _refs(json['evidenceRefs']),
      );

  /// 이야기의 핵심을 짧게 적은 제목.
  final String? headline;

  /// 사건·아이 행동·상대 반응을 이은 요약.
  final String? summary;

  /// `REAL`·`IMAGINED`·`MIXED`·`UNKNOWN`.
  ///
  /// 아이가 말한 경우에만 `UNKNOWN` 밖의 값이 온다. 화면은 상상 이야기를
  /// 있었던 일처럼 보여 주지 않고, 모르면 아무 말도 붙이지 않는다.
  final String realityStatus;

  /// `TODAY`·`YESTERDAY`·`RECENT`·`PAST`·`UNKNOWN`.
  ///
  /// 아이가 시점을 말하지 않았으면 `UNKNOWN` 이다. 활동한 날짜로 대신 채우면 안 된다.
  final String timeScope;

  /// 중심 사건이며 분명하지 않으면 `null`.
  final String? mainEvent;

  /// 이 요약을 뒷받침하는 근거.
  final List<DiaryEvidenceRefDto> evidenceRefs;
}

/// 이야기 흐름의 한 단계.
final class DiaryNarrativeStepDto {
  const DiaryNarrativeStepDto({
    required this.stepType,
    required this.text,
    this.evidenceRefs = const [],
  });

  /// JSON 한 건을 읽는다.
  factory DiaryNarrativeStepDto.fromJson(Map<String, dynamic> json) =>
      DiaryNarrativeStepDto(
        stepType: json['stepType'] as String? ?? '',
        text: json['text'] as String? ?? '',
        evidenceRefs: _refs(json['evidenceRefs']),
      );

  /// `EVENT`·`CHILD_ACTION`·`OTHER_RESPONSE`·`EMOTION`·`WISH`·`OUTCOME`.
  final String stepType;

  /// 그 단계에서 확인된 내용.
  final String text;

  /// 이 단계를 뒷받침하는 근거.
  final List<DiaryEvidenceRefDto> evidenceRefs;
}

/// 아이가 실제로 한 말 한 건.
final class DiaryChildVoiceDto {
  const DiaryChildVoiceDto({
    required this.text,
    required this.elicitationType,
    this.answerType,
    this.sourceRef,
    this.sttNeedsConfirmation = false,
  });

  /// JSON 한 건을 읽는다.
  factory DiaryChildVoiceDto.fromJson(Map<String, dynamic> json) =>
      DiaryChildVoiceDto(
        text: json['text'] as String? ?? '',
        elicitationType: json['elicitationType'] as String? ?? '',
        answerType: json['answerType'] as String?,
        sourceRef: json['sourceRef'] is Map
            ? DiaryEvidenceRefDto.fromJson(
                Map<String, dynamic>.from(json['sourceRef'] as Map),
              )
            : null,
        sttNeedsConfirmation: json['sttNeedsConfirmation'] as bool? ?? false,
      );

  /// 아이가 한 말 그대로.
  final String text;

  /// 그 말을 끌어낸 질문 방식.
  ///
  /// 선택지에서 고른 답을 아이가 스스로 만든 문장처럼 보여 주지 않기 위한 구분이다.
  final String elicitationType;

  /// 답변 입력 방식이며 없으면 `null`.
  final String? answerType;

  /// 이 발화의 근거이며 없으면 `null`.
  final DiaryEvidenceRefDto? sourceRef;

  /// 음성 인식 확인이 필요한 답이면 `true`.
  final bool sttNeedsConfirmation;
}

/// 이번 활동에서 확인된 표현. 지속적인 심리 경향이 아니다.
final class DiarySessionObservationDto {
  const DiarySessionObservationDto({
    required this.title,
    required this.description,
    this.insightType = 'CONFIRMED_EXPRESSION',
    this.domain = 'STORY',
    this.hypothesis,
    this.alternativeExplanations = const [],
    this.clarificationQuestion,
    this.observationCode,
    this.scopeText,
    this.evidenceRefs = const [],
  });

  /// JSON 한 건을 읽는다.
  factory DiarySessionObservationDto.fromJson(Map<String, dynamic> json) =>
      DiarySessionObservationDto(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        insightType: json['insightType'] as String? ?? 'CONFIRMED_EXPRESSION',
        domain: json['domain'] as String? ?? 'STORY',
        hypothesis: _text(json['hypothesis']),
        alternativeExplanations: _texts(json['alternativeExplanations']),
        clarificationQuestion: _text(json['clarificationQuestion']),
        observationCode: json['observationCode'] as String?,
        scopeText: _text(json['scopeText']),
        evidenceRefs: _refs(json['evidenceRefs']),
      );

  /// 주장의 세기.
  ///
  /// `CONFIRMED_EXPRESSION`(아이가 한 말)·`SESSION_HYPOTHESIS`(다른 설명과 함께여야
  /// 성립)·`EXPLORE_NEXT`(뜻을 정하지 않은 단서). 화면은 이 값으로 카드의 표시를 가른다.
  final String insightType;

  /// 인사이트 영역.
  final String domain;

  /// 이번 회차 한정 가설이며 없으면 `null`.
  final String? hypothesis;

  /// 다르게 볼 수 있는 설명.
  ///
  /// **가설과 반드시 함께 보여 준다.** 하나의 해석만 보이면 보호자는 그것을 결론으로 읽는다.
  final List<String> alternativeExplanations;

  /// 다음에 확인할 질문이며 없으면 `null`.
  final String? clarificationQuestion;

  /// 보호자에게 보이는 제목.
  final String title;

  /// 근거에 묶인 이번 활동 한정 설명.
  final String description;

  /// 관찰 코드이며 화면에는 쓰지 않는다.
  final String? observationCode;

  /// 범위를 알리는 문구. 카드에 함께 보여 줘야 지속적인 특질로 읽히지 않는다.
  final String? scopeText;

  /// 서로 다른 근거.
  final List<DiaryEvidenceRefDto> evidenceRefs;
}

/// 보호자가 아이에게 그대로 물어볼 수 있는 질문.
final class DiaryCaregiverQuestionDto {
  const DiaryCaregiverQuestionDto({
    required this.question,
    this.purpose,
    this.evidenceRefs = const [],
  });

  /// JSON 한 건을 읽는다.
  factory DiaryCaregiverQuestionDto.fromJson(Map<String, dynamic> json) =>
      DiaryCaregiverQuestionDto(
        question: json['question'] as String? ?? '',
        purpose: _text(json['purpose']),
        evidenceRefs: _refs(json['evidenceRefs']),
      );

  /// 질문 한 문장.
  final String question;

  /// 이 질문으로 더 들어볼 내용이며 없으면 `null`.
  final String? purpose;

  /// 이 질문이 이어지는 근거.
  final List<DiaryEvidenceRefDto> evidenceRefs;
}

/// 이번 리포트의 근거가 무엇으로 이루어졌는지.
final class DiaryDataQualityDto {
  const DiaryDataQualityDto({
    this.confirmedVoiceCount = 0,
    this.optionAnswerCount = 0,
    this.skippedCount = 0,
    this.sttConfirmationCount = 0,
    this.evidenceCount = 0,
    this.visionSummaryAvailable = false,
  });

  /// JSON 한 건을 읽는다.
  factory DiaryDataQualityDto.fromJson(Map<String, dynamic> json) =>
      DiaryDataQualityDto(
        confirmedVoiceCount: _int(json['confirmedVoiceCount']),
        optionAnswerCount: _int(json['optionAnswerCount']),
        skippedCount: _int(json['skippedCount']),
        sttConfirmationCount: _int(json['sttConfirmationCount']),
        evidenceCount: _int(json['evidenceCount']),
        visionSummaryAvailable: json['visionSummaryAvailable'] as bool? ?? false,
      );

  /// 음성으로 확정된 답변 수.
  final int confirmedVoiceCount;

  /// 선택지에서 고른 답변 수.
  final int optionAnswerCount;

  /// 건너뛴 질문 수.
  final int skippedCount;

  /// 음성 인식 확인이 필요한 답변 수.
  final int sttConfirmationCount;

  /// 사용된 근거 수.
  final int evidenceCount;

  /// 그림 관찰 서술이 있었으면 `true`.
  final bool visionSummaryAvailable;
}

/// 이번 활동에서 확인하지 못한 것 한 건.
final class DiaryUnknownItemDto {
  const DiaryUnknownItemDto({required this.code, required this.text});

  /// JSON 한 건을 읽는다.
  factory DiaryUnknownItemDto.fromJson(Map<String, dynamic> json) =>
      DiaryUnknownItemDto(
        code: json['code'] as String? ?? '',
        text: json['text'] as String? ?? '',
      );

  /// 서버가 정한 코드.
  final String code;

  /// 보호자에게 보이는 문구.
  final String text;
}

/// 그림일기 리포트 V2 묶음.
final class DiaryInsightsDto {
  const DiaryInsightsDto({
    this.storySnapshot,
    this.narrativeFlow = const [],
    this.childVoiceItems = const [],
    this.sessionObservations = const [],
    this.caregiverQuestions = const [],
    this.listeningTip,
    this.unknownItems = const [],
    this.dataQuality = const DiaryDataQualityDto(),
  });

  /// JSON 한 건을 읽는다.
  factory DiaryInsightsDto.fromJson(Map<String, dynamic> json) =>
      DiaryInsightsDto(
        storySnapshot: json['storySnapshot'] is Map
            ? DiaryStorySnapshotDto.fromJson(
                Map<String, dynamic>.from(json['storySnapshot'] as Map),
              )
            : null,
        narrativeFlow: _list(json['narrativeFlow'], DiaryNarrativeStepDto.fromJson),
        childVoiceItems: _list(json['childVoiceItems'], DiaryChildVoiceDto.fromJson),
        sessionObservations: _list(
          json['sessionObservations'],
          DiarySessionObservationDto.fromJson,
        ),
        caregiverQuestions: _list(
          json['caregiverQuestions'],
          DiaryCaregiverQuestionDto.fromJson,
        ),
        listeningTip: _text(json['listeningTip']),
        unknownItems: _list(json['unknownItems'], DiaryUnknownItemDto.fromJson),
        dataQuality: json['dataQuality'] is Map
            ? DiaryDataQualityDto.fromJson(
                Map<String, dynamic>.from(json['dataQuality'] as Map),
              )
            : const DiaryDataQualityDto(),
      );

  /// 이번 이야기의 핵심이며 없으면 `null`.
  final DiaryStorySnapshotDto? storySnapshot;

  /// 확인된 이야기 단계만 시간 순서대로.
  final List<DiaryNarrativeStepDto> narrativeFlow;

  /// 아이가 실제로 한 말.
  final List<DiaryChildVoiceDto> childVoiceItems;

  /// 이번 활동에서만 확인된 표현 0~2개.
  final List<DiarySessionObservationDto> sessionObservations;

  /// 보호자가 이어 갈 질문 0~2개.
  final List<DiaryCaregiverQuestionDto> caregiverQuestions;

  /// 이번 이야기를 들을 때의 태도 한 문장이며 없으면 `null`.
  final String? listeningTip;

  /// 이번 활동에서 확인하지 못한 것.
  ///
  /// 섹션이 비어 나가면 보호자는 '문제가 없었다'로 읽는다 — 무엇을 알 수 없었는지
  /// 이름을 붙여 보여 준다.
  final List<DiaryUnknownItemDto> unknownItems;

  /// 근거 구성 정보.
  final DiaryDataQualityDto dataQuality;

  /// 화면에 보여 줄 내용이 하나라도 있는가.
  ///
  /// 서버가 근거 부족이면 아예 `null` 을 주지만, 듣기 안내 한 줄만 남는 경우까지
  /// V2 화면을 여는 것은 의미가 없다 — 그때는 기존 화면이 더 많은 정보를 준다.
  ///
  /// `childVoiceItems` 는 세지 않는다. 그 목록은 서버가 요청의 문답에서 그대로
  /// 파생하므로 문답이 있으면 언제나 채워진다 — 세면 이 판단이 늘 참이 된다.
  bool get hasContent =>
      storySnapshot != null ||
      narrativeFlow.isNotEmpty ||
      sessionObservations.isNotEmpty ||
      caregiverQuestions.isNotEmpty;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _int(Object? value) => value is num ? value.toInt() : 0;

List<String> _texts(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value) ?_text(item),
  ];
}

List<DiaryEvidenceRefDto> _refs(Object? value) =>
    _list(value, DiaryEvidenceRefDto.fromJson);

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => parse(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}
