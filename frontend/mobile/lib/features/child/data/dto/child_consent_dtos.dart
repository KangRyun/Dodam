/// 아동(CHILD) 대상 약관 한 건.
///
/// 서버가 버전별로 발행하며 동의 이력은 `termId`(= 고정 버전 약관)로 기록된다.
/// 동의 화면은 이 목록을 그대로 보여주고 사용자가 고른 결과만 되돌려준다.
class ConsentTermDto {
  const ConsentTermDto({
    required this.termId,
    required this.termCode,
    required this.title,
    required this.required,
    required this.version,
    this.contentUrl,
    this.contentHtml,
  });

  factory ConsentTermDto.fromJson(Map<String, dynamic> json) => ConsentTermDto(
    termId: (json['termId'] as num).toInt(),
    termCode: json['termCode'] as String,
    title: json['title'] as String? ?? json['termCode'] as String,
    required: json['required'] as bool? ?? false,
    version: json['version'] as String? ?? '',
    contentUrl: json['contentUrl'] as String?,
    contentHtml: json['contentHtml'] as String?,
  );

  final int termId;
  final String termCode;
  final String title;

  /// 서버가 정한 필수 여부. 앱이 임의로 필수/선택을 바꾸지 않는다.
  final bool required;
  final String version;
  final String? contentUrl;

  /// 약관 본문(HTML). 상세 보기에 사용한다.
  final String? contentHtml;
}

/// 약관 하나에 대한 동의 의사.
///
/// 체크하지 않은 항목도 `WITHDRAW`로 함께 보낸다. 보내지 않으면 "묻지 않은 것"과
/// "거부한 것"을 서버가 구분할 수 없어 동의 이력이 불완전해진다(가드레일 9절).
class ConsentAgreementDto {
  const ConsentAgreementDto({required this.termId, required this.action});

  const ConsentAgreementDto.agree(this.termId) : action = 'AGREE';

  const ConsentAgreementDto.withdraw(this.termId) : action = 'WITHDRAW';

  final int termId;
  final String action;

  Map<String, dynamic> toJson() => {'termId': termId, 'action': action};
}
