import '../../../../core/network/api_client.dart';
import '../../../auth/domain/repositories/device_id_provider.dart';
import '../../domain/repositories/push_token_repository.dart';

/// 공개 알림 API로 푸시 Token을 등록·해제한다.
///
/// `deviceId`는 인증이 쓰는 설치 식별자([DeviceIdProvider])를 그대로 재사용한다.
/// 호출마다 새 값을 만들면 upsert가 성립하지 않아 죽은 Token이 누적된다.
final class RemotePushTokenRepository implements PushTokenRepository {
  RemotePushTokenRepository({
    required ApiClient apiClient,
    required DeviceIdProvider deviceIdProvider,
    String platform = 'ANDROID',
    String appVersion = _fallbackAppVersion,
  }) : _apiClient = apiClient,
       _deviceIdProvider = deviceIdProvider,
       _platform = platform,
       _appVersion = appVersion;

  static const _path = 'notifications/device-tokens';

  /// 빌드 정보 주입(S15P11B209-629) 전까지 쓰는 기본값이다.
  static const _fallbackAppVersion = '1.0.0';

  final ApiClient _apiClient;
  final DeviceIdProvider _deviceIdProvider;
  final String _platform;
  final String _appVersion;

  @override
  Future<void> register(String pushToken) async {
    final token = pushToken.trim();
    if (token.isEmpty) return;

    final deviceId = await _deviceIdProvider.getDeviceId();
    await _apiClient.post<Map<String, dynamic>>(
      _path,
      data: {
        'deviceId': deviceId,
        'platform': _platform,
        'pushToken': token,
        'appVersion': _appVersion,
      },
    );
  }

  @override
  Future<void> unregister() async {
    final deviceId = await _deviceIdProvider.getDeviceId();
    await _apiClient.delete<void>('$_path/$deviceId');
  }
}
