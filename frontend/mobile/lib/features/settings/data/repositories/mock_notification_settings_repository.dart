import '../../domain/repositories/notification_settings_repository.dart';
import '../dto/notification_settings_dtos.dart';

/// 백엔드 미연결 개발·데모·테스트용 목 구현.
///
/// 계약이 정한 기본값(`marketing`만 `false`)을 조회로 돌려주고, 수정은 받은 값을
/// 그대로 되돌려 준다. 저장 상태를 들지 않아 `const`로 둘 수 있다 — 실제 upsert는
/// 서버 몫이라 여기서 재현하지 않는다.
///
/// 계약: `docs/api/notification-settings-read-contract.md` §0-3(행이 없으면 기본값),
/// `docs/api/notification-settings-update-contract.md` §0-3(응답은 조회와 동일 스키마)
final class MockNotificationSettingsRepository
    implements NotificationSettingsRepository {
  const MockNotificationSettingsRepository();

  @override
  Future<NotificationSettingsDto> getNotificationSettings() async =>
      const NotificationSettingsDto(
        analysisCompleted: true,
        community: true,
        serviceNotice: true,
        marketing: false,
      );

  @override
  Future<NotificationSettingsDto> updateNotificationSettings(
    NotificationSettingsDto settings,
  ) async => settings;
}
