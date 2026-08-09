import 'package:dio/dio.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/features/settings/data/repositories/mock_account_withdrawal_repository.dart';
import 'package:dodam/features/settings/data/repositories/remote_account_withdrawal_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('USER-05는 DELETE /users/me에 확인 문구만 담아 보낸다', () async {
    final interceptor = _WithdrawalInterceptor();
    final repository = RemoteAccountWithdrawalRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    await repository.withdraw(confirmation: 'DELETE');

    final request = interceptor.requests.single;
    expect(request.method, 'DELETE');
    expect(request.uri.path, '/api/v1/users/me');
    final body = Map<String, dynamic>.from(request.data as Map);
    expect(body, {'confirmation': 'DELETE'});
    // 서버 DeleteUserRequest에 없는 필드는 보내지 않는다.
    expect(body.containsKey('password'), isFalse);
    expect(body.containsKey('deleteChildData'), isFalse);
  });

  test('본문 없는 204 응답도 성공으로 처리한다', () async {
    final repository = RemoteAccountWithdrawalRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [_WithdrawalInterceptor()],
      ),
    );

    await expectLater(repository.withdraw(confirmation: 'DELETE'), completes);
  });

  test('확인 값 불일치는 USER_400_002 실패로 전달한다', () async {
    final repository = RemoteAccountWithdrawalRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [_ConfirmationMismatchInterceptor()],
      ),
    );

    await expectLater(
      repository.withdraw(confirmation: 'delete'),
      throwsA(
        isA<ApiResponseFailure>()
            .having((failure) => failure.statusCode, 'statusCode', 400)
            .having((failure) => failure.error?.code, 'code', 'USER_400_002'),
      ),
    );
  });

  test('Mock 구현도 서버와 같은 확인 문구 규칙을 지킨다', () async {
    const repository = MockAccountWithdrawalRepository();

    await expectLater(repository.withdraw(confirmation: 'DELETE'), completes);
    await expectLater(
      repository.withdraw(confirmation: 'delete'),
      throwsA(
        isA<ApiResponseFailure>().having(
          (failure) => failure.error?.code,
          'code',
          'USER_400_002',
        ),
      ),
    );
  });
}

final class _WithdrawalInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<void>(requestOptions: options, statusCode: 204),
    );
  }
}

final class _ConfirmationMismatchInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 400,
          data: const {
            'success': false,
            'code': 'USER_400_002',
            'message': '회원 탈퇴 확인 값이 올바르지 않습니다.',
          },
        ),
      ),
      true,
    );
  }
}
