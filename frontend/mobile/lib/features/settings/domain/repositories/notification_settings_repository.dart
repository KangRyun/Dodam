import '../../data/dto/notification_settings_dtos.dart';

/// 알림 수신 설정 조회·수정 도메인 계약. 대상 사용자는 Access Token에서
/// 해석하므로 식별자를 받지 않는다(IDOR 차단).
///
/// 계약: `docs/api/notification-settings-read-contract.md`,
/// `docs/api/notification-settings-update-contract.md`
abstract interface class NotificationSettingsRepository {
  /// `GET /users/me/notification-settings` — 설정 행이 없으면 기본값을 준다.
  Future<NotificationSettingsDto> getNotificationSettings();

  /// USER-04 `PATCH /users/me/notification-settings` — 네 필드 전체 교체(upsert).
  Future<NotificationSettingsDto> updateNotificationSettings(
    NotificationSettingsDto settings,
  );
}
