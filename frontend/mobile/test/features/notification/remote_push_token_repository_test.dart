import 'package:dio/dio.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/auth/domain/repositories/device_id_provider.dart';
import 'package:dodam/features/notification/data/repositories/remote_push_token_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _CapturingInterceptor interceptor;
  late RemotePushTokenRepository repository;

  setUp(() {
    interceptor = _CapturingInterceptor();
    repository = RemotePushTokenRepository(
      apiClient: ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
      deviceIdProvider: const _FixedDeviceIdProvider('install-uuid'),
      appVersion: '1.2.3',
    );
  });

  test('등록은 설치 식별자와 함께 계약 필드를 보낸다', () async {
    await repository.register('fcm-token');

    final request = interceptor.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, endsWith('/notifications/device-tokens'));
    expect(request.data, {
      'deviceId': 'install-uuid',
      'platform': 'ANDROID',
      'pushToken': 'fcm-token',
      'appVersion': '1.2.3',
    });
  });

  test('갱신도 같은 등록 경로와 같은 설치 식별자를 쓴다', () async {
    await repository.register('token-1');
    await repository.register('token-2');

    // (userId, deviceId) upsert라 별도 갱신 API가 없다.
    expect(interceptor.requests, hasLength(2));
    expect(interceptor.bodies.map((body) => body['pushToken']), [
      'token-1',
      'token-2',
    ]);
    expect(interceptor.bodies.map((body) => body['deviceId']).toSet(), {
      'install-uuid',
    });
  });

  test('빈 Token은 서버를 호출하지 않는다', () async {
    await repository.register('   ');

    expect(interceptor.requests, isEmpty);
  });

  test('해제는 설치 식별자를 경로에 실어 DELETE한다', () async {
    await repository.unregister();

    final request = interceptor.requests.single;
    expect(request.method, 'DELETE');
    expect(
      request.uri.path,
      endsWith('/notifications/device-tokens/install-uuid'),
    );
  });
}

final class _CapturingInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  /// 등록 요청 본문만 모은다.
  List<Map<String, Object?>> get bodies => requests
      .map((request) => request.data)
      .whereType<Map<String, Object?>>()
      .toList();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);

    if (options.method == 'DELETE') {
      handler.resolve(
        Response<dynamic>(requestOptions: options, statusCode: 204),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': {'deviceId': 'install-uuid', 'registered': true},
        },
      ),
    );
  }
}

final class _FixedDeviceIdProvider implements DeviceIdProvider {
  const _FixedDeviceIdProvider(this._deviceId);

  final String _deviceId;

  @override
  Future<String> getDeviceId() async => _deviceId;
}
