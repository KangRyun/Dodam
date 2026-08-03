import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/features/auth/domain/repositories/device_id_provider.dart';
import 'package:dodam/features/notification/application/push_registration_status_controller.dart';
import 'package:dodam/features/notification/data/repositories/remote_push_token_repository.dart';
import 'package:dodam/features/notification/domain/entities/push_message.dart';
import 'package:dodam/features/notification/domain/failures/push_token_registration_failure.dart';
import 'package:dodam/features/notification/domain/repositories/push_token_repository.dart';
import 'package:dodam/features/notification/domain/services/push_coordinator.dart';
import 'package:dodam/features/notification/domain/services/push_gateway.dart';
import 'package:dodam/features/notification/domain/services/push_permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 디바이스 Token 등록 실패를 조용히 넘기지 않는지 확인한다(S15P11B209-842).
void main() {
  RemotePushTokenRepository repositoryRejecting({
    required int statusCode,
    required String code,
  }) => RemotePushTokenRepository(
    apiClient: ApiClient(
      environment: ApiEnvironment.fromBaseUrl('https://example.test'),
      interceptors: [_RejectingInterceptor(statusCode: statusCode, code: code)],
    ),
    deviceIdProvider: const _FixedDeviceIdProvider('install-uuid'),
  );

  group('RemotePushTokenRepository', () {
    test('409는 다른 계정 선점 실패로 옮긴다', () async {
      final repository = repositoryRejecting(
        statusCode: 409,
        code: 'DEVICE_TOKEN_ALREADY_REGISTERED',
      );

      final failure = await _registerFailure(repository);

      expect(
        failure.type,
        PushTokenRegistrationFailureType.claimedByAnotherAccount,
      );
      expect(failure.code, 'DEVICE_TOKEN_ALREADY_REGISTERED');
    });

    test('503은 저장소 사용 불가 실패로 옮긴다', () async {
      final repository = repositoryRejecting(
        statusCode: 503,
        code: 'DEVICE_TOKEN_STORAGE_UNAVAILABLE',
      );

      final failure = await _registerFailure(repository);

      expect(failure.type, PushTokenRegistrationFailureType.storageUnavailable);
    });

    test('계약에 없는 오류는 원래 실패를 그대로 올린다', () async {
      final repository = repositoryRejecting(
        statusCode: 500,
        code: 'COMMON_500',
      );

      await expectLater(
        repository.register('fcm-token'),
        throwsA(isA<ApiResponseFailure>()),
      );
    });
  });

  group('PushCoordinator', () {
    late _FakeGateway gateway;
    late _FakePresenter presenter;
    late _FakePermissionService permissionService;
    late List<PushTokenRegistrationFailure?> results;

    PushCoordinator build(PushTokenRepository tokenRepository) =>
        PushCoordinator(
          gateway: gateway,
          presenter: presenter,
          tokenRepository: tokenRepository,
          permissionService: permissionService,
          onOpen: (_) {},
          isChildModeActive: () => false,
          isGuardianSessionActive: () => true,
          onTokenRegistrationResult: results.add,
        );

    setUp(() {
      gateway = _FakeGateway()..token = 'fcm-token';
      presenter = _FakePresenter();
      permissionService = _FakePermissionService();
      results = [];
    });

    tearDown(() {
      gateway.dispose();
      presenter.dispose();
    });

    test('등록이 거절되면 실패를 알린다', () async {
      await build(
        _RejectingTokenRepository(
          const PushTokenRegistrationFailure(
            type: PushTokenRegistrationFailureType.claimedByAnotherAccount,
          ),
        ),
      ).start();

      expect(results, hasLength(1));
      expect(
        results.single?.type,
        PushTokenRegistrationFailureType.claimedByAnotherAccount,
      );
    });

    test('등록이 성공하면 실패 없음을 알린다', () async {
      await build(_RecordingTokenRepository()).start();

      expect(results, [null]);
    });

    test('일시적 실패는 상태로 굳히지 않는다', () async {
      await build(_ThrowingTokenRepository()).start();

      // 네트워크 오류로 실패한 등록은 다음 갱신·재로그인이 다시 시도한다.
      expect(results, isEmpty);
    });

    test('Token이 갱신되면 회복을 다시 알린다', () async {
      final tokenRepository = _RejectFirstTokenRepository();
      await build(tokenRepository).start();
      gateway.emitTokenRefresh('fcm-token-2');
      await pumpEventQueue();

      expect(results, hasLength(2));
      expect(results.first, isNotNull);
      expect(results.last, isNull);
    });
  });

  group('PushRegistrationStatusController', () {
    test('실패를 보고하면 구독자에게 알린다', () {
      final controller = PushRegistrationStatusController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.report(
        const PushTokenRegistrationFailure(
          type: PushTokenRegistrationFailureType.storageUnavailable,
        ),
      );

      expect(controller.hasFailure, isTrue);
      expect(notifications, 1);
    });

    test('같은 사유가 다시 확인되면 다시 알리지 않는다', () {
      final controller = PushRegistrationStatusController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      for (var i = 0; i < 3; i++) {
        controller.report(
          const PushTokenRegistrationFailure(
            type: PushTokenRegistrationFailureType.claimedByAnotherAccount,
          ),
        );
      }

      expect(notifications, 1);
    });

    test('등록이 성공하면 남은 경고를 지운다', () {
      final controller = PushRegistrationStatusController()
        ..report(
          const PushTokenRegistrationFailure(
            type: PushTokenRegistrationFailureType.claimedByAnotherAccount,
          ),
        );
      addTearDown(controller.dispose);

      controller.report(null);

      expect(controller.hasFailure, isFalse);
    });

    test('닫은 뒤에도 같은 사유가 다시 확인되면 표시한다', () {
      final controller = PushRegistrationStatusController()
        ..report(
          const PushTokenRegistrationFailure(
            type: PushTokenRegistrationFailureType.claimedByAnotherAccount,
          ),
        )
        ..dismiss();
      addTearDown(controller.dispose);
      expect(controller.hasFailure, isFalse);

      controller.report(
        const PushTokenRegistrationFailure(
          type: PushTokenRegistrationFailureType.claimedByAnotherAccount,
        ),
      );

      expect(controller.hasFailure, isTrue);
    });

    test('dispose 뒤 보고는 무시한다', () {
      final controller = PushRegistrationStatusController()..dispose();

      controller.report(
        const PushTokenRegistrationFailure(
          type: PushTokenRegistrationFailureType.storageUnavailable,
        ),
      );

      expect(controller.hasFailure, isFalse);
    });
  });
}

Future<PushTokenRegistrationFailure> _registerFailure(
  RemotePushTokenRepository repository,
) async {
  try {
    await repository.register('fcm-token');
  } on PushTokenRegistrationFailure catch (failure) {
    return failure;
  }
  fail('등록이 실패하지 않았다');
}

final class _RejectingInterceptor extends Interceptor {
  _RejectingInterceptor({required this.statusCode, required this.code});

  final int statusCode;
  final String code;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: statusCode,
          data: {
            'success': false,
            'code': code,
            'message': '이미 다른 계정에 등록된 디바이스 토큰입니다.',
            'data': null,
          },
        ),
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

final class _RecordingTokenRepository implements PushTokenRepository {
  final List<String> registered = [];

  @override
  Future<void> register(String pushToken) async => registered.add(pushToken);

  @override
  Future<void> unregister() async {}
}

final class _RejectingTokenRepository implements PushTokenRepository {
  _RejectingTokenRepository(this.failure);

  final PushTokenRegistrationFailure failure;

  @override
  Future<void> register(String pushToken) async => throw failure;

  @override
  Future<void> unregister() async {}
}

final class _ThrowingTokenRepository implements PushTokenRepository {
  @override
  Future<void> register(String pushToken) async =>
      throw StateError('network down');

  @override
  Future<void> unregister() async {}
}

/// 첫 등록만 거절하고 이후에는 성공한다. Token 갱신으로 회복되는 경로 검증용.
final class _RejectFirstTokenRepository implements PushTokenRepository {
  int calls = 0;

  @override
  Future<void> register(String pushToken) async {
    calls += 1;
    if (calls == 1) {
      throw const PushTokenRegistrationFailure(
        type: PushTokenRegistrationFailureType.claimedByAnotherAccount,
      );
    }
  }

  @override
  Future<void> unregister() async {}
}

final class _FakeGateway implements PushGateway {
  final _tokenRefreshes = StreamController<String>.broadcast();
  final _foreground = StreamController<PushMessage>.broadcast();
  final _opened = StreamController<PushMessage>.broadcast();
  String? token;

  void emitTokenRefresh(String value) => _tokenRefreshes.add(value);

  void dispose() {
    _tokenRefreshes.close();
    _foreground.close();
    _opened.close();
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get tokenRefreshes => _tokenRefreshes.stream;

  @override
  Stream<PushMessage> get foregroundMessages => _foreground.stream;

  @override
  Stream<PushMessage> get openedMessages => _opened.stream;

  @override
  Future<PushMessage?> getInitialMessage() async => null;
}

final class _FakePresenter implements PushPresenter {
  final _taps = StreamController<PushMessage>.broadcast();
  bool initialized = false;

  void dispose() => _taps.close();

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> show(PushMessage message) async {}

  @override
  Stream<PushMessage> get taps => _taps.stream;
}

final class _FakePermissionService implements PushPermissionService {
  @override
  Future<PushPermissionStatus> request() async => PushPermissionStatus.granted;

  @override
  Future<bool> openSettings() async => false;
}
