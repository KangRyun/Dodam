/// 전문가 의뢰 요약(`referral-summary`) DTO (S15P11B209-1012).
///
/// **이 문서는 진단도 소견도 아니다.** 전문가가 판단하는 데 필요한 원자료를 모아
/// 정리한 것이며, 앱의 해석을 대신 주장하지 않는다.
///
/// **순서에 의미가 있다.** 아이가 실제로 한 말이 앞이고 앱이 본 것은 뒤다. 전문가가
/// 먼저 읽는 것이 앱의 가설이면 판단이 그 방향으로 끌려간다(앵커링). 화면도 이 순서를
/// 바꾸지 않는다.
library;

/// 아이가 한 말 한 줄.
final class ReferralChildVoiceDto {
  const ReferralChildVoiceDto({
    required this.text,
    this.elicitationType,
    this.spontaneous = false,
    this.sttNeedsConfirmation = false,
  });

  /// JSON 한 건을 읽는다.
  factory ReferralChildVoiceDto.fromJson(Map<String, dynamic> json) =>
      ReferralChildVoiceDto(
        // 공백만 있는 답은 답이 아니다. trim 을 여기서 해야 아래 필터가 걸러 낸다.
        text: (json['text'] as String? ?? '').trim(),
        elicitationType: _text(json['elicitationType']),
        spontaneous: json['spontaneous'] as bool? ?? false,
        sttNeedsConfirmation:
            json['sttNeedsConfirmation'] as bool? ?? false,
      );

  /// 아이가 한 말이며 학교·주소 형태는 서버가 이미 가렸다.
  final String text;

  /// 그 말을 끌어낸 질문 방식이며 알 수 없으면 `null`.
  final String? elicitationType;

  /// 아이가 자기 말로 만든 문장인가.
  ///
  /// **선택지에서 고른 답은 거짓이다.** 고른 답을 자발 발화로 읽으면 아이가 실제보다
  /// 많이 말한 것처럼 보인다.
  final bool spontaneous;

  /// 음성 인식 확인이 필요한 답인가. 참이면 인용 근거로 쓰지 않는다.
  final bool sttNeedsConfirmation;
}

/// 활동 한 회차.
final class ReferralSessionDto {
  const ReferralSessionDto({
    this.reportId,
    this.activityType,
    this.activityDate,
    this.headline,
    this.mainEvent,
    this.realityStatus = 'UNKNOWN',
    this.timeScope = 'UNKNOWN',
    this.childVoices = const [],
  });

  /// JSON 한 건을 읽는다.
  factory ReferralSessionDto.fromJson(Map<String, dynamic> json) =>
      ReferralSessionDto(
        reportId: (json['reportId'] as num?)?.toInt(),
        activityType: _text(json['activityType']),
        activityDate: _date(json['activityDate']),
        headline: _text(json['headline']),
        mainEvent: _text(json['mainEvent']),
        realityStatus: json['realityStatus'] as String? ?? 'UNKNOWN',
        timeScope: json['timeScope'] as String? ?? 'UNKNOWN',
        childVoices: _voices(json['childVoices']),
      );

  /// 리포트 식별자이며 없으면 `null`.
  final int? reportId;

  /// 활동 유형 코드이며 알 수 없으면 `null`.
  final String? activityType;

  /// 활동 날짜이며 알 수 없으면 `null`.
  final DateTime? activityDate;

  /// 그 회차 이야기의 핵심이며 없으면 `null`.
  final String? headline;

  /// 중심 사건이며 분명하지 않으면 `null`.
  final String? mainEvent;

  /// 실제·상상 구분. **아이가 말한 경우에만** `UNKNOWN` 밖의 값이 온다.
  final String realityStatus;

  /// 사건 시점이며 아이가 말하지 않았으면 `UNKNOWN`이다.
  ///
  /// 활동 날짜는 사건 날짜의 근거가 아니다 — 오늘 그린 그림이 지난주 일을 담을 수 있다.
  final String timeScope;

  /// 아이가 실제로 한 말.
  final List<ReferralChildVoiceDto> childVoices;
}

/// 두 회차 이상에서 되풀이된 관찰.
final class ReferralRepeatedObservationDto {
  const ReferralRepeatedObservationDto({
    required this.title,
    this.observationCode,
    this.occurrenceCount = 0,
    this.firstSeenOn,
    this.lastSeenOn,
  });

  /// JSON 한 건을 읽는다.
  factory ReferralRepeatedObservationDto.fromJson(Map<String, dynamic> json) =>
      ReferralRepeatedObservationDto(
        observationCode: _text(json['observationCode']),
        title: json['title'] as String? ?? '',
        occurrenceCount: (json['occurrenceCount'] as num?)?.toInt() ?? 0,
        firstSeenOn: _date(json['firstSeenOn']),
        lastSeenOn: _date(json['lastSeenOn']),
      );

  /// 관찰 코드이며 없으면 `null`.
  final String? observationCode;

  /// 보호자에게 보이던 제목.
  final String title;

  /// 되풀이된 회차 수. **두 회차 이상만 서버가 보낸다.**
  final int occurrenceCount;

  /// 처음 확인된 날이며 알 수 없으면 `null`.
  final DateTime? firstSeenOn;

  /// 마지막으로 확인된 날이며 알 수 없으면 `null`.
  final DateTime? lastSeenOn;
}

/// 안전 신호와 앱이 취한 처리.
final class ReferralSafetySignalDto {
  const ReferralSafetySignalDto({
    required this.reasonCode,
    this.severity,
    this.occurredOn,
    this.handling,
  });

  /// JSON 한 건을 읽는다.
  factory ReferralSafetySignalDto.fromJson(Map<String, dynamic> json) =>
      ReferralSafetySignalDto(
        reasonCode: json['reasonCode'] as String? ?? '',
        severity: _text(json['severity']),
        occurredOn: _date(json['occurredOn']),
        handling: _text(json['handling']),
      );

  /// 위기 사유 코드.
  final String reasonCode;

  /// 심각도이며 없으면 `null`.
  final String? severity;

  /// 확인된 날이며 알 수 없으면 `null`.
  final DateTime? occurredOn;

  /// 앱이 취한 처리이며 없으면 `null`.
  ///
  /// **처리 내역이 없으면 전문가는 방치됐는지 알 수 없다.** 비어 있으면 화면이
  /// 그 사실을 적는다.
  final String? handling;
}

/// 답변이 무엇으로 이루어졌는지.
final class ReferralAnswerCompositionDto {
  const ReferralAnswerCompositionDto({
    this.spokenAnswerCount = 0,
    this.optionAnswerCount = 0,
    this.skippedCount = 0,
    this.sttUnconfirmedCount = 0,
  });

  /// JSON 한 건을 읽는다.
  factory ReferralAnswerCompositionDto.fromJson(Map<String, dynamic> json) =>
      ReferralAnswerCompositionDto(
        spokenAnswerCount: (json['spokenAnswerCount'] as num?)?.toInt() ?? 0,
        optionAnswerCount: (json['optionAnswerCount'] as num?)?.toInt() ?? 0,
        skippedCount: (json['skippedCount'] as num?)?.toInt() ?? 0,
        sttUnconfirmedCount:
            (json['sttUnconfirmedCount'] as num?)?.toInt() ?? 0,
      );

  /// 아이가 자기 말로 답한 수.
  final int spokenAnswerCount;

  /// 선택지에서 고른 수.
  final int optionAnswerCount;

  /// 건너뛴 수.
  final int skippedCount;

  /// 음성 인식 확인이 필요한 수.
  final int sttUnconfirmedCount;

  /// 답한 것과 건너뛴 것을 합친 수.
  int get totalCount =>
      spokenAnswerCount + optionAnswerCount + skippedCount;
}

/// 의뢰 요약 한 건.
final class ReferralSummaryDto {
  const ReferralSummaryDto({
    this.childDisplayName,
    this.generatedAt,
    this.purpose,
    this.sessions = const [],
    this.repeatedObservations = const [],
    this.safetySignals = const [],
    this.answerComposition = const ReferralAnswerCompositionDto(),
    this.voiceRecordingAvailable = false,
    this.notIncluded = const [],
    this.reviewNotice,
  });

  /// JSON 한 건을 읽는다.
  factory ReferralSummaryDto.fromJson(Map<String, dynamic> json) =>
      ReferralSummaryDto(
        childDisplayName: _text(json['childDisplayName']),
        generatedAt: _date(json['generatedAt']),
        purpose: _text(json['purpose']),
        sessions: _sessions(json['sessions']),
        repeatedObservations: _observations(json['repeatedObservations']),
        safetySignals: _signals(json['safetySignals']),
        answerComposition: json['answerComposition'] is Map
            ? ReferralAnswerCompositionDto.fromJson(
                Map<String, dynamic>.from(json['answerComposition'] as Map),
              )
            : const ReferralAnswerCompositionDto(),
        voiceRecordingAvailable:
            json['voiceRecordingAvailable'] as bool? ?? false,
        notIncluded: _texts(json['notIncluded']),
        reviewNotice: _text(json['reviewNotice']),
      );

  /// 아이 표시명(별명)이며 없으면 `null`. **실명·생년월일은 담기지 않는다.**
  final String? childDisplayName;

  /// 요약을 만든 시각이며 알 수 없으면 `null`.
  final DateTime? generatedAt;

  /// 이 문서가 무엇인지 알리는 고정 문구.
  final String? purpose;

  /// 최근 활동 회차이며 최신순이다.
  final List<ReferralSessionDto> sessions;

  /// 두 회차 이상에서 되풀이된 관찰.
  final List<ReferralRepeatedObservationDto> repeatedObservations;

  /// 안전 신호와 처리 내역.
  final List<ReferralSafetySignalDto> safetySignals;

  /// 답변 구성.
  final ReferralAnswerCompositionDto answerComposition;

  /// 아이 음성 원본이 앱에 남아 있는가. **재생 링크는 담기지 않는다.**
  final bool voiceRecordingAvailable;

  /// 이 요약에 담지 않은 것.
  ///
  /// **빠진 것을 모르면 전문가는 없는 것을 '문제 없음'으로 읽는다.**
  final List<String> notIncluded;

  /// 보호자가 공유 전에 확인할 것이며 없으면 `null`.
  final String? reviewNotice;

  /// 회차가 하나라도 있는가.
  ///
  /// 회차가 없으면 보여 줄 원자료가 없다는 뜻이라 화면이 안내로 대체한다 —
  /// 빈 표를 내보이면 전문가가 '활동이 없었다'와 '요약이 못 만들어졌다'를 구별할 수 없다.
  bool get hasSessions => sessions.isNotEmpty;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}

List<String> _texts(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value) ?_text(item),
  ];
}

List<ReferralChildVoiceDto> _voices(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) =>
            ReferralChildVoiceDto.fromJson(Map<String, dynamic>.from(item)),
      )
      .where((voice) => voice.text.isNotEmpty)
      .toList(growable: false);
}

List<ReferralSessionDto> _sessions(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) => ReferralSessionDto.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

List<ReferralRepeatedObservationDto> _observations(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) => ReferralRepeatedObservationDto.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .where((observation) => observation.title.isNotEmpty)
      .toList(growable: false);
}

List<ReferralSafetySignalDto> _signals(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) =>
            ReferralSafetySignalDto.fromJson(Map<String, dynamic>.from(item)),
      )
      .where((signal) => signal.reasonCode.isNotEmpty)
      .toList(growable: false);
}
