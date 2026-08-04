import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/features/guardian_pin/data/repositories/remote_guardian_pin_repository.dart';
import 'package:dodam/features/guardian_pin/domain/failures/guardian_pin_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _RecordingInterceptor server;
  late RemoteGuardianPinRepository repository;

  setUp(() {
    server = _RecordingInterceptor();
    repository = RemoteGuardianPinRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [server],
      ),
    );
  });

  test('GET·POST·PATCH·DELETE·verification endpoint와 본문 계약을 지킨다', () async {
    await repository.getStatus();
    await repository.configure('0123');
    await repository.change(currentPin: '0123', newPin: '4567');
    await repository.reset();
    await repository.verify('9999');

    expect(server.requests.map((request) => request.method), [
      'GET',
      'POST',
      'PATCH',
      'DELETE',
      'POST',
    ]);
    expect(server.requests.map((request) => request.path), [
      'users/me/guardian-pin',
      'users/me/guardian-pin',
      'users/me/guardian-pin',
      'users/me/guardian-pin',
      'users/me/guardian-pin/verifications',
    ]);
    expect(server.requests[1].data, {'pin': '0123'});
    expect(server.requests[2].data, {'currentPin': '0123', 'newPin': '4567'});
    expect(server.requests[4].data, {'pin': '9999'});
  });

  test('공통 envelope data를 GuardianPinStatusDto로 파싱한다', () async {
    final status = await repository.getStatus();

    expect(status.pinConfigured, isTrue);
    expect(status.remainingAttempts, 5);
    expect(status.serverTime.isUtc, isTrue);
  });

  test('잘못된 PIN은 network 요청 전에 typed PIN_INVALID로 거부한다', () async {
    await expectLater(
      repository.verify('12a4'),
      throwsA(
        isA<GuardianPinFailure>()
            .having(
              (failure) => failure.type,
              'type',
              GuardianPinFailureType.invalidPin,
            )
            .having((failure) => failure.code, 'code', 'PIN_INVALID'),
      ),
    );
    expect(server.requests, isEmpty);
  });

  final mappings = <String, GuardianPinFailureType>{
    'PIN_MISMATCH': GuardianPinFailureType.mismatch,
    'PIN_LOCKED': GuardianPinFailureType.locked,
    'PIN_NOT_CONFIGURED': GuardianPinFailureType.notConfigured,
    'PIN_ALREADY_CONFIGURED': GuardianPinFailureType.alreadyConfigured,
    'PIN_RESET_REQUIRED': GuardianPinFailureType.resetRequired,
    'PIN_UNAVAILABLE': GuardianPinFailureType.unavailable,
    'COMMON_400_001': GuardianPinFailureType.invalidInput,
    'PIN_INVALID': GuardianPinFailureType.invalidPin,
    'AUTH_401_002': GuardianPinFailureType.accessTokenInvalid,
    'AUTH_401_006': GuardianPinFailureType.authenticationRequired,
    'AUTH_403_001': GuardianPinFailureType.accountSuspended,
    'USER_404_001': GuardianPinFailureType.userNotFound,
    'COMMON_409_001': GuardianPinFailureType.dataConflict,
  };

  for (final entry in mappings.entries) {
    test('${entry.key}를 ${entry.value.name} typed error로 매핑한다', () async {
      server.errorCode = entry.key;

      await expectLater(
        repository.getStatus(),
        throwsA(
          isA<GuardianPinFailure>()
              .having((failure) => failure.type, 'type', entry.value)
              .having((failure) => failure.code, 'code', entry.key),
        ),
      );
    });
  }

  test('PIN_MISMATCH 실패 data의 상태를 함께 보존한다', () async {
    server.errorCode = 'PIN_MISMATCH';
    server.errorData = _statusData(remainingAttempts: 3);

    await expectLater(
      repository.verify('0123'),
      throwsA(
        isA<GuardianPinFailure>().having(
          (failure) => failure.status?.remainingAttempts,
          'remainingAttempts',
          3,
        ),
      ),
    );
  });

  test('PIN_LOCKED의 nullable 또는 malformed data는 typed error를 유지한다', () async {
    server.errorCode = 'PIN_LOCKED';
    server.errorData = {'locked': 'not-a-bool'};

    await expectLater(
      repository.verify('0123'),
      throwsA(
        isA<GuardianPinFailure>()
            .having(
              (failure) => failure.type,
              'type',
              GuardianPinFailureType.locked,
            )
            .having((failure) => failure.status, 'status', isNull),
      ),
    );
  });

  test('unknown Backend code는 기존 ApiResponseFailure fallback을 유지한다', () async {
    server.errorCode = 'SOMETHING_NEW';

    await expectLater(
      repository.getStatus(),
      throwsA(isA<ApiResponseFailure>()),
    );
  });

  test('message가 바뀌어도 code만으로 같은 오류를 판정한다', () async {
    server
      ..errorCode = 'PIN_MISMATCH'
      ..errorMessage = 'completely different text';

    await expectLater(
      repository.verify('0123'),
      throwsA(
        isA<GuardianPinFailure>().having(
          (failure) => failure.type,
          'type',
          GuardianPinFailureType.mismatch,
        ),
      ),
    );
  });
}

Map<String, dynamic> _statusData({int remainingAttempts = 5}) => {
  'pinConfigured': true,
  'locked': false,
  'remainingAttempts': remainingAttempts,
  'retryAfterSeconds': null,
  'lockedUntil': null,
  'serverTime': '2026-08-04T01:02:03Z',
};

final class _RecordingInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];
  String? errorCode;
  String errorMessage = 'server message';
  Object? errorData;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final code = errorCode;
    if (code != null) {
      handler.reject(
        DioException.badResponse(
          statusCode: code == 'PIN_MISMATCH' ? 401 : 409,
          requestOptions: options,
          response: Response<Object?>(
            requestOptions: options,
            statusCode: code == 'PIN_MISMATCH' ? 401 : 409,
            data: {
              'success': false,
              'code': code,
              'message': errorMessage,
              'data': errorData,
            },
          ),
        ),
      );
      return;
    }
    handler.resolve(
      Response<Object?>(
        requestOptions: options,
        statusCode: 200,
        data: {'success': true, 'data': _statusData()},
      ),
    );
  }
}
