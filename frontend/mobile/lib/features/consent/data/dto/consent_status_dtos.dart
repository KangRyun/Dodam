/// `GET /consents` 응답의 약관별 현재 동의 상태.
///
/// 제목은 담기지 않으므로(약관 코드·버전·필수여부·동의여부만), 화면 표시용 제목은
/// `GET /consents/terms`의 [ConsentTermDto]와 `termId`로 조인해 얻는다.
class ConsentStatusItemDto {
  const ConsentStatusItemDto({
    required this.termId,
    required this.termCode,
    required this.required,
    required this.version,
    required this.agreed,
  });

  factory ConsentStatusItemDto.fromJson(Map<String, dynamic> json) =>
      ConsentStatusItemDto(
        termId: (json['termId'] as num).toInt(),
        termCode: json['termCode'] as String,
        required: json['required'] as bool? ?? false,
        version: json['version'] as String? ?? '',
        agreed: json['agreed'] as bool? ?? false,
      );

  final int termId;
  final String termCode;

  /// 서비스 이용 필수 약관 여부. 필수는 화면에서 철회 토글을 비활성으로 표시만 한다.
  final bool required;
  final String version;

  /// 가장 최근 행위가 동의이면 true.
  final bool agreed;
}

/// `GET /consents` 응답. [childId]가 있으면 그 아동 범위 현황이다.
class ConsentStatusDto {
  const ConsentStatusDto({
    this.childId,
    required this.requiredConsentsSatisfied,
    required this.items,
  });

  factory ConsentStatusDto.fromJson(Map<String, dynamic> json) =>
      ConsentStatusDto(
        childId: (json['childId'] as num?)?.toInt(),
        requiredConsentsSatisfied:
            json['requiredConsentsSatisfied'] as bool? ?? false,
        items: ((json['items'] as List?) ?? const [])
            .map(
              (item) => ConsentStatusItemDto.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );

  final int? childId;

  /// 적용 범위의 모든 필수 약관에 동의했는지 여부.
  final bool requiredConsentsSatisfied;
  final List<ConsentStatusItemDto> items;
}
