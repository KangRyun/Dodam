import '../../data/dto/notification_inbox_dtos.dart';

/// 알림함(수신 알림 목록·읽음) 도메인 계약. 푸시 디바이스 토큰 등록·해제는
/// [PushTokenRepository]가 담당하며 이 인터페이스는 NOTI-03/04/05만 다룬다.
///
/// 계약: `docs/api/notification-inbox-contract.md`
abstract interface class NotificationInboxRepository {
  /// NOTI-03 `GET /notifications` — 최신순 알림 목록.
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  });

  /// NOTI-04 `PATCH /notifications/{id}/read` — 단건 읽음(멱등).
  Future<NotificationReadDto> markRead(int notificationId);

  /// NOTI-05 `PATCH /notifications/read-all` — 전체(또는 유형별) 읽음(멱등).
  Future<NotificationReadAllDto> markAllRead({String? type});
}
