import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_failure.dart';
import '../../../auth/domain/repositories/device_id_provider.dart';
import '../../domain/failures/push_token_registration_failure.dart';
import '../../domain/repositories/push_token_repository.dart';

/// 공개 알림 API로 푸시 Token을 등록·해제한다.
///
/// `deviceId`는 인증이 쓰는 설치 식별자([DeviceIdProvider])를 그대로 재사용한다.
/// 호출마다 새 값을 만들면 upsert가 성립하지 않아 죽은 Token이 누적된다.
final class RemotePushTokenRepository implements PushTokenRepository {
  factory RemotePushTokenRepository({
    required ApiClient apiClient,
    required DeviceIdProvider deviceIdProvider,
    String platform = 'ANDROID',
    String appVersion = _fallbackAppVersion,
  }) => RemotePushTokenRepository._(
    apiClient,
    deviceIdProvider,
    platform,
    appVersion,
  );

  RemotePushTokenRepository._(
    this._apiClient,
    this._deviceIdProvider,
    this._platform,
    this._appVersion,
  );

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
    try {
      await _apiClient.post<Map<String, dynamic>>(
        _path,
        data: {
          'deviceId': deviceId,
          'platform': _platform,
          'pushToken': token,
          'appVersion': _appVersion,
        },
      );
    } on ApiResponseFailure catch (failure) {
      final type = _registrationFailureType(failure);
      // 계약이 정한 거절 사유가 아니면 원래 실패를 그대로 올린다. 여기서
      // 뭉개면 상위가 "푸시를 못 받는다"와 "일시적 오류"를 구분할 수 없다.
      if (type == null) rethrow;
      throw PushTokenRegistrationFailure(
        type: type,
        code: failure.error?.code,
        cause: failure,
      );
    }
  }

  /// 서버 응답을 등록 거절 사유로 옮긴다. 해당 없으면 `null`.
  ///
  /// 상태코드와 오류 코드 중 하나만 맞아도 같은 사유로 본다. 계약 §4 오류 표는
  /// 두 값을 짝으로 정하지만, 게이트웨이가 코드를 지우거나 상태코드를 바꿔
  /// 전달하는 경우에도 판정이 뒤집히지 않게 한다.
  static PushTokenRegistrationFailureType? _registrationFailureType(
    ApiResponseFailure failure,
  ) => switch ((failure.statusCode, failure.error?.code)) {
    (409, _) || (_, 'DEVICE_TOKEN_ALREADY_REGISTERED') =>
      PushTokenRegistrationFailureType.claimedByAnotherAccount,
    (503, _) || (_, 'DEVICE_TOKEN_STORAGE_UNAVAILABLE') =>
      PushTokenRegistrationFailureType.storageUnavailable,
    _ => null,
  };

  @override
  Future<void> unregister() async {
    final deviceId = await _deviceIdProvider.getDeviceId();
    await _apiClient.delete<void>('$_path/$deviceId');
  }
}
