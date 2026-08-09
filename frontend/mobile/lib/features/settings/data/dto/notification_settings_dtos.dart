/// 알림 수신 설정 4필드. 조회(GET)·수정(PATCH) 응답이 같은 스키마이고,
/// 수정 요청도 네 필드를 모두 보내는 전체 교체이므로 요청·응답을 이 DTO 하나로
/// 표현한다.
///
/// 계약: `docs/api/notification-settings-read-contract.md`(USER 조회),
/// `docs/api/notification-settings-update-contract.md`(USER-04 수정)
final class NotificationSettingsDto {
  const NotificationSettingsDto({
    required this.analysisCompleted,
    required this.community,
    required this.serviceNotice,
    required this.marketing,
  });

  factory NotificationSettingsDto.fromJson(Map<String, dynamic> json) =>
      NotificationSettingsDto(
        analysisCompleted: json['analysisCompleted'] as bool,
        community: json['community'] as bool,
        serviceNotice: json['serviceNotice'] as bool,
        marketing: json['marketing'] as bool,
      );

  final bool analysisCompleted, community, serviceNotice, marketing;

  /// USER-04 수정 요청 본문. 네 필드가 모두 필수(전체 교체)다.
  Map<String, dynamic> toJson() => {
    'analysisCompleted': analysisCompleted,
    'community': community,
    'serviceNotice': serviceNotice,
    'marketing': marketing,
  };

  NotificationSettingsDto copyWith({
    bool? analysisCompleted,
    bool? community,
    bool? serviceNotice,
    bool? marketing,
  }) => NotificationSettingsDto(
    analysisCompleted: analysisCompleted ?? this.analysisCompleted,
    community: community ?? this.community,
    serviceNotice: serviceNotice ?? this.serviceNotice,
    marketing: marketing ?? this.marketing,
  );
}
