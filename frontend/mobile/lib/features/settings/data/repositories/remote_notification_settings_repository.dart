import '../../../../core/network/network.dart';
import '../../domain/repositories/notification_settings_repository.dart';
import '../dto/notification_settings_dtos.dart';

/// 알림 수신 설정 실 API 구현. 응답은 공통 봉투 `{success, code, message, data}`로
/// 오므로 [envelopeObject]로 `data`를 벗겨 파싱한다.
///
/// 계약: `docs/api/notification-settings-read-contract.md`,
/// `docs/api/notification-settings-update-contract.md`
final class RemoteNotificationSettingsRepository
    implements NotificationSettingsRepository {
  const RemoteNotificationSettingsRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<NotificationSettingsDto> getNotificationSettings() async {
    final response = await _apiClient.get<Object?>(
      'users/me/notification-settings',
    );
    return NotificationSettingsDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<NotificationSettingsDto> updateNotificationSettings(
    NotificationSettingsDto settings,
  ) async {
    final response = await _apiClient.patch<Object?>(
      'users/me/notification-settings',
      data: settings.toJson(),
    );
    return NotificationSettingsDto.fromJson(envelopeObject(response.data));
  }
}
