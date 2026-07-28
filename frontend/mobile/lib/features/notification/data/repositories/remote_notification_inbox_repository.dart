import '../../../../core/network/network.dart';
import '../../domain/repositories/notification_inbox_repository.dart';
import '../dto/notification_inbox_dtos.dart';

/// 알림함 실 API 구현. 응답은 공통 봉투 `{success, code, message, data}`로
/// 오므로 [envelopeObject]로 `data`를 벗겨 파싱한다.
///
/// 계약: `docs/api/notification-inbox-contract.md`
final class RemoteNotificationInboxRepository
    implements NotificationInboxRepository {
  const RemoteNotificationInboxRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  }) async {
    final response = await _apiClient.get<Object?>(
      'notifications',
      queryParameters: filter.toQueryParameters(),
    );
    return ApiPage.fromJson(
      envelopeObject(response.data),
      NotificationItemDto.fromJson,
    );
  }

  @override
  Future<NotificationReadDto> markRead(int notificationId) async {
    final response = await _apiClient.patch<Object?>(
      'notifications/$notificationId/read',
    );
    return NotificationReadDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<NotificationReadAllDto> markAllRead({String? type}) async {
    final response = await _apiClient.patch<Object?>(
      'notifications/read-all',
      queryParameters: {'type': ?type},
    );
    return NotificationReadAllDto.fromJson(envelopeObject(response.data));
  }
}
