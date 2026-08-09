/// 검사 기록 요약(`screeningSummary`) DTO.
///
/// **이 앱은 표준화 선별검사를 제공하지 않는다.** 여기 담기는 것은 보호자가 다른
/// 곳에서 받아 와 직접 옮겨 적은 결과이며, 앱이 실시하거나 채점한 값이 아니다.
///
/// 그래서 화면은 이 묶음을 그림일기 관찰과 **자리를 나눠** 보여 준다. 한 덩어리로
/// 보이면 보호자는 앱이 검사를 해 줬다고 읽는다.
library;

/// 검사 기록 한 건.
final class ScreeningRecordDto {
  const ScreeningRecordDto({
    required this.recordId,
    required this.instrumentDisplayName,
    required this.completedAt,
    required this.officialResultText,
    this.instrumentId = '',
    this.instrumentVersion,
    this.respondent = 'GUARDIAN',
    this.sourceAuthorityType = 'GUARDIAN_REPORTED',
    this.sourceAuthorityName,
    this.sourceVerified = false,
    this.officialResultCode,
    this.scoredBy,
    this.requiredDisclosure,
    this.domainResults = const [],
    this.followupLevel,
    this.followupMessage,
    this.referralOptions = const [],
  });

  /// JSON 한 건을 읽는다.
  factory ScreeningRecordDto.fromJson(Map<String, dynamic> json) =>
      ScreeningRecordDto(
        recordId: (json['recordId'] as num?)?.toInt() ?? 0,
        instrumentId: json['instrumentId'] as String? ?? '',
        instrumentDisplayName: json['instrumentDisplayName'] as String? ?? '',
        instrumentVersion: _text(json['instrumentVersion']),
        respondent: json['respondent'] as String? ?? 'GUARDIAN',
        completedAt: _date(json['completedAt']),
        sourceAuthorityType:
            json['sourceAuthorityType'] as String? ?? 'GUARDIAN_REPORTED',
        sourceAuthorityName: _text(json['sourceAuthorityName']),
        sourceVerified: json['sourceVerified'] as bool? ?? false,
        officialResultCode: _text(json['officialResultCode']),
        officialResultText: json['officialResultText'] as String? ?? '',
        scoredBy: _text(json['scoredBy']),
        requiredDisclosure: _text(json['requiredDisclosure']),
        domainResults: _domains(json['domainResults']),
        followupLevel: _text(json['followupLevel']),
        followupMessage: _text(json['followupMessage']),
        referralOptions: _texts(json['referralOptions']),
      );

  /// 기록 식별자.
  final int recordId;

  /// 도구 식별자.
  final String instrumentId;

  /// 등록부의 공식 도구명.
  final String instrumentDisplayName;

  /// 결과지에 적힌 도구 버전이며 없으면 `null`.
  final String? instrumentVersion;

  /// 결과를 보고한 사람.
  final String respondent;

  /// 검사 실시일이며 알 수 없으면 `null`.
  final DateTime? completedAt;

  /// 결과를 발급한 곳의 성격.
  final String sourceAuthorityType;

  /// 결과를 발급한 곳.
  final String? sourceAuthorityName;

  /// 출처 검증 여부.
  ///
  /// **거짓이면 공식 결과가 아니다.** 공식 서비스 연동이 없어 현재 언제나 거짓이며,
  /// 화면은 이 값을 근거로 '보호자가 입력한 기록'임을 반드시 함께 보여 준다.
  final bool sourceVerified;

  /// 결과지의 코드이며 없으면 `null`.
  final String? officialResultCode;

  /// 결과 문구를 변경 없이.
  final String officialResultText;

  /// 채점 주체이며 없으면 `null`. 이 앱은 절대 아니다.
  final String? scoredBy;

  /// 등록부가 정한 필수 고지. 결과와 항상 함께 보여 준다.
  final String? requiredDisclosure;

  /// 영역별 결과 라벨이며 점수가 아니다.
  final List<ScreeningDomainResultDto> domainResults;

  /// 다음 걸음이며 없으면 `null`.
  final String? followupLevel;

  /// 후속 안내이며 없으면 `null`.
  final String? followupMessage;

  /// 후속 상담 경로.
  final List<String> referralOptions;
}

/// 영역별 결과 한 줄.
final class ScreeningDomainResultDto {
  const ScreeningDomainResultDto({
    required this.domainName,
    required this.resultLabel,
  });

  /// JSON 한 건을 읽는다.
  factory ScreeningDomainResultDto.fromJson(Map<String, dynamic> json) =>
      ScreeningDomainResultDto(
        domainName: json['domainName'] as String? ?? '',
        resultLabel: json['resultLabel'] as String? ?? '',
      );

  /// 영역 이름.
  final String domainName;

  /// 영역 결과 라벨.
  final String resultLabel;
}

/// 검사 기록 요약 묶음.
final class ScreeningSummaryDto {
  const ScreeningSummaryDto({
    this.state = 'NOT_OFFERED',
    this.message,
    this.records = const [],
  });

  /// JSON 한 건을 읽는다.
  factory ScreeningSummaryDto.fromJson(Map<String, dynamic> json) =>
      ScreeningSummaryDto(
        state: json['state'] as String? ?? 'NOT_OFFERED',
        message: _text(json['message']),
        records: _records(json['records']),
      );

  /// 지금 상태.
  ///
  /// 기록이 있으면 `EXTERNAL_RESULT_AVAILABLE`, 없으면 `NOT_OFFERED`.
  final String state;

  /// 보호자에게 보이는 검토된 문구.
  final String? message;

  /// 보호자가 옮겨 적은 결과.
  final List<ScreeningRecordDto> records;

  /// 화면에 그릴 것이 있는가.
  ///
  /// 기록이 없어도 문구는 그린다 — **침묵이 곧 '앱이 선별을 해 준다'는 오해를 남긴다.**
  bool get hasContent => message != null || records.isNotEmpty;
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

List<ScreeningDomainResultDto> _domains(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) => ScreeningDomainResultDto.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .toList(growable: false);
}

List<ScreeningRecordDto> _records(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => ScreeningRecordDto.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}
