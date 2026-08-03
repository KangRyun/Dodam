import '../../../../core/network/api_page.dart';

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

/// NOTI-03 목록 조회 Query. (알림 계약 §5)
///
/// [type]은 계약 §5의 `NotificationType` 어휘만 허용하며 null이면 전체 유형이다.
final class NotificationFilterDto {
  const NotificationFilterDto({
    this.type,
    this.unreadOnly = false,
    this.page = 0,
    this.size = 20,
  });

  final String? type;
  final bool unreadOnly;
  final int page, size;

  Map<String, dynamic> toQueryParameters() => {
    if (type != null) 'type': type,
    'unreadOnly': unreadOnly,
    'page': page,
    'size': size,
  };
}

/// NOTI-03 목록 항목. (알림 계약 §5)
///
/// `type`·`deliveryStatus`·`relatedResourceType`은 계약 어휘 문자열 그대로
/// 보관한다. 서버는 이동 URL을 만들지 않으므로 `relatedResourceType`/
/// `relatedResourceId`만 제공하고 화면 라우팅은 상위 레이어가 결정한다.
final class NotificationItemDto {
  const NotificationItemDto({
    required this.notificationId,
    required this.type,
    required this.title,
    required this.content,
    required this.relatedResourceType,
    required this.relatedResourceId,
    required this.data,
    required this.deliveryStatus,
    required this.readAt,
    required this.sentAt,
    required this.createdAt,
  });

  factory NotificationItemDto.fromJson(Map<String, dynamic> json) =>
      NotificationItemDto(
        notificationId: json['notificationId'] as int,
        type: json['type'] as String,
        title: json['title'] as String,
        content: json['content'] as String?,
        relatedResourceType: json['relatedResourceType'] as String?,
        relatedResourceId: json['relatedResourceId'] as int?,
        // `data`는 평탄화된 Map<String,String>이며 없으면 {} 이다. (계약 §5)
        data: json['data'] == null
            ? const <String, String>{}
            : Map<String, String>.from(_map(json['data'])),
        deliveryStatus: json['deliveryStatus'] as String,
        readAt: json['readAt'] as String?,
        sentAt: json['sentAt'] as String?,
        createdAt: json['createdAt'] as String,
      );

  final int notificationId;
  final String type, title, deliveryStatus, createdAt;
  final String? content, relatedResourceType, readAt, sentAt;
  final int? relatedResourceId;
  final Map<String, String> data;

  bool get isRead => readAt != null;

  /// 읽음 처리 결과를 반영한 사본. 목록·팝업이 서버 재조회 없이 카드 하나만
  /// 미열람에서 열람으로 바꿀 때 쓴다.
  NotificationItemDto copyWithReadAt(String readAt) => NotificationItemDto(
    notificationId: notificationId,
    type: type,
    title: title,
    content: content,
    relatedResourceType: relatedResourceType,
    relatedResourceId: relatedResourceId,
    data: data,
    deliveryStatus: deliveryStatus,
    readAt: readAt,
    sentAt: sentAt,
    createdAt: createdAt,
  );
}

/// NOTI-04 단건 읽음 처리 응답. 멱등하므로 이미 읽은 알림은 최초 `readAt`을
/// 그대로 돌려준다. (알림 계약 §6)
final class NotificationReadDto {
  const NotificationReadDto({
    required this.notificationId,
    required this.readAt,
  });

  factory NotificationReadDto.fromJson(Map<String, dynamic> json) =>
      NotificationReadDto(
        notificationId: json['notificationId'] as int,
        readAt: json['readAt'] as String,
      );

  final int notificationId;
  final String readAt;
}

/// NOTI-05 전체 읽음 처리 응답. `readAt`은 이번 호출로 새로 읽음 처리된 건이
/// 없으면(`updatedCount == 0`) null이다. (알림 계약 §6.5)
final class NotificationReadAllDto {
  const NotificationReadAllDto({
    required this.updatedCount,
    required this.readAt,
  });

  factory NotificationReadAllDto.fromJson(Map<String, dynamic> json) =>
      NotificationReadAllDto(
        updatedCount: json['updatedCount'] as int,
        readAt: json['readAt'] as String?,
      );

  final int updatedCount;
  final String? readAt;
}

typedef NotificationPage = ApiPage<NotificationItemDto>;
