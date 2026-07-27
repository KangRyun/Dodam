/// 푸시가 가리키는 이동 대상 자원 유형이다.
///
/// 서버는 이동 URL·딥링크를 만들지 않고 유형과 식별자만 준다
/// (`docs/api/push-notification-delivery-contract.md` §0-3).
enum PushResourceType {
  report,
  drawingSession,
  post;

  static PushResourceType? tryParse(String? value) => switch (value) {
    'REPORT' => PushResourceType.report,
    'DRAWING_SESSION' => PushResourceType.drawingSession,
    'POST' => PushResourceType.post,
    _ => null,
  };
}

/// FCM `data`-only 메시지를 앱이 다루는 형태로 옮긴 값이다.
///
/// 계약(§3)상 모든 값이 문자열로 오므로 여기서 한 번만 파싱하고,
/// 이후 화면·라우팅은 이 타입만 본다.
final class PushMessage {
  const PushMessage({
    required this.notificationId,
    required this.type,
    required this.title,
    required this.content,
    this.resourceType,
    this.resourceId,
  });

  /// `notifications` 행 식별자다. 중복 표시 방지와 알림함 대조에 쓴다.
  final int notificationId;

  /// 계약이 허용한 알림 유형 문자열이다.
  final String type;

  final String title;
  final String content;

  /// 이동 대상 자원 유형이며 연결된 자원이 없으면 `null`이다.
  final PushResourceType? resourceType;

  /// 이동 대상 자원 식별자이며 [resourceType]과 항상 함께 있거나 함께 없다.
  final int? resourceId;

  /// 계약이 허용한 알림 유형이다(알림함 계약과 동일한 9종).
  static const allowedTypes = <String>{
    'ANALYSIS_COMPLETED',
    'ANALYSIS_FAILED',
    'REPORT_COMPLETED',
    'NEW_EXPERT_POST',
    'COMMENT_CREATED',
    'CONSENT_UPDATED',
    'RETENTION_NOTICE',
    'ACTIVITY_REMINDER',
    'RISK_REVIEW_GUIDE',
  };

  /// FCM `data` 맵을 파싱하며, 계약을 벗어난 메시지는 `null`을 돌려준다.
  ///
  /// 잘못된 메시지로 화면을 띄우지 않기 위해 fail-closed로 판정한다. 필수 키
  /// 누락·미허용 유형·정수가 아닌 식별자는 모두 폐기 대상이다.
  static PushMessage? tryParse(Map<String, dynamic>? data) {
    if (data == null) return null;

    final notificationId = int.tryParse(_string(data['notificationId']) ?? '');
    final type = _string(data['type']);
    final title = _string(data['title']);
    final content = _string(data['content']);
    if (notificationId == null || type == null || title == null) return null;
    if (!allowedTypes.contains(type)) return null;

    final resourceType = PushResourceType.tryParse(
      _string(data['relatedResourceType']),
    );
    final resourceId = int.tryParse(_string(data['relatedResourceId']) ?? '');

    // 유형과 식별자는 쌍이다. 한쪽만 오면 라우팅이 불가능하므로 둘 다 버린다.
    final paired = resourceType != null && resourceId != null;

    return PushMessage(
      notificationId: notificationId,
      type: type,
      title: title,
      content: content ?? '',
      resourceType: paired ? resourceType : null,
      resourceId: paired ? resourceId : null,
    );
  }

  /// 공백만 있는 값을 누락으로 취급해 정규화한다.
  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
