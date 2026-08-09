import 'package:dodam/core/network/api_error.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/features/settings/application/account_withdrawal_controller.dart';
import 'package:dodam/features/settings/domain/repositories/account_withdrawal_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('안내 확인과 정확한 확인 문구가 모두 있어야 요청할 수 있다', () {
    final repository = _FakeAccountWithdrawalRepository();
    final controller = AccountWithdrawalController(repository);
    addTearDown(controller.dispose);

    expect(controller.status, AccountWithdrawalStatus.idle);
    expect(controller.canSubmit, isFalse);

    controller.setNoticeAcknowledged(acknowledged: true);
    expect(controller.canSubmit, isFalse);

    controller.updateConfirmationInput('DELETE');
    expect(controller.canSubmit, isTrue);

    controller.setNoticeAcknowledged(acknowledged: false);
    expect(controller.canSubmit, isFalse);
  });

  test('확인 문구는 대소문자와 공백까지 정확히 일치해야 한다', () {
    final controller = AccountWithdrawalController(
      _FakeAccountWithdrawalRepository(),
    );
    addTearDown(controller.dispose);
    controller.setNoticeAcknowledged(acknowledged: true);

    for (final invalid in ['delete', 'Delete', ' DELETE', 'DELETE ', 'DELETE!']) {
      controller.updateConfirmationInput(invalid);
      expect(
        controller.isConfirmationValid,
        isFalse,
        reason: '"$invalid"는 확인 문구로 인정하면 안 된다',
      );
      expect(controller.canSubmit, isFalse);
    }

    controller.updateConfirmationInput('DELETE');
    expect(controller.isConfirmationValid, isTrue);
  });

  test('조건을 갖추지 못하면 Repository를 호출하지 않는다', () async {
    final repository = _FakeAccountWithdrawalRepository();
    final controller = AccountWithdrawalController(repository);
    addTearDown(controller.dispose);

    controller.updateConfirmationInput('DELETE');
    expect(await controller.submit(), isFalse);
    expect(repository.receivedConfirmations, isEmpty);
  });

  test('성공하면 입력한 확인 문구를 그대로 보내고 success로 전이한다', () async {
    final repository = _FakeAccountWithdrawalRepository();
    final controller = AccountWithdrawalController(repository);
    addTearDown(controller.dispose);

    final states = <AccountWithdrawalStatus>[];
    controller.addListener(() => states.add(controller.status));

    controller.setNoticeAcknowledged(acknowledged: true);
    controller.updateConfirmationInput('DELETE');

    expect(await controller.submit(), isTrue);
    expect(repository.receivedConfirmations, ['DELETE']);
    expect(controller.status, AccountWithdrawalStatus.success);
    expect(
      states,
      containsAllInOrder([
        AccountWithdrawalStatus.submitting,
        AccountWithdrawalStatus.success,
      ]),
    );
  });

  // 성공 뒤에도 버튼이 열려 있으면, 로그아웃 정리를 기다리는 수 초 동안 되돌릴 수
  // 없는 DELETE 가 한 번 더 나간다.
  test('탈퇴에 성공한 뒤에는 다시 요청할 수 없다', () async {
    final repository = _FakeAccountWithdrawalRepository();
    final controller = AccountWithdrawalController(repository);
    addTearDown(controller.dispose);

    controller.setNoticeAcknowledged(acknowledged: true);
    controller.updateConfirmationInput('DELETE');
    expect(await controller.submit(), isTrue);

    expect(controller.canSubmit, isFalse);
    expect(await controller.submit(), isFalse);
    expect(repository.receivedConfirmations, ['DELETE']);
  });

  test('확인 값 불일치(USER_400_002)는 전용 문구로 안내한다', () async {
    final repository = _FakeAccountWithdrawalRepository(
      failure: const ApiResponseFailure(
        statusCode: 400,
        error: ApiError(
          code: 'USER_400_002',
          message: '회원 탈퇴 확인 값이 올바르지 않습니다.',
        ),
      ),
    );
    final controller = AccountWithdrawalController(repository);
    addTearDown(controller.dispose);

    controller.setNoticeAcknowledged(acknowledged: true);
    controller.updateConfirmationInput('DELETE');

    expect(await controller.submit(), isFalse);
    expect(controller.status, AccountWithdrawalStatus.failure);
    expect(controller.failureMessage, contains('확인 문구가 올바르지 않아요'));
    expect(controller.canRetry, isFalse);
  });

  test('이미 탈퇴한 계정(404)은 재시도 대신 로그인 복귀를 안내한다', () async {
    final repository = _FakeAccountWithdrawalRepository(
      failure: const ApiResponseFailure(
        statusCode: 404,
        error: ApiError(code: 'USER_404_001', message: '사용자 정보를 찾을 수 없습니다.'),
      ),
    );
    final controller = AccountWithdrawalController(repository);
    addTearDown(controller.dispose);

    controller.setNoticeAcknowledged(acknowledged: true);
    controller.updateConfirmationInput('DELETE');

    expect(await controller.submit(), isFalse);
    expect(controller.failureMessage, contains('이미 탈퇴 처리된 계정'));
    expect(controller.canRetry, isFalse);
  });

  test('연결 실패는 공통 실패 문구를 쓰고 재시도를 허용한다', () async {
    final repository = _FakeAccountWithdrawalRepository(
      failure: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    final controller = AccountWithdrawalController(repository);
    addTearDown(controller.dispose);

    controller.setNoticeAcknowledged(acknowledged: true);
    controller.updateConfirmationInput('DELETE');

    expect(await controller.submit(), isFalse);
    expect(controller.failureMessage, contains('인터넷 연결'));
    expect(controller.canRetry, isTrue);
  });

  test('입력을 고치면 직전 실패 문구를 지운다', () async {
    final repository = _FakeAccountWithdrawalRepository(
      failure: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    final controller = AccountWithdrawalController(repository);
    addTearDown(controller.dispose);

    controller.setNoticeAcknowledged(acknowledged: true);
    controller.updateConfirmationInput('DELETE');
    await controller.submit();
    expect(controller.failureMessage, isNotNull);

    controller.updateConfirmationInput('DELET');
    expect(controller.status, AccountWithdrawalStatus.idle);
    expect(controller.failureMessage, isNull);
  });

  test('요청 도중 dispose해도 notify로 예외가 나지 않는다', () async {
    final repository = _FakeAccountWithdrawalRepository();
    final controller = AccountWithdrawalController(repository);

    controller.setNoticeAcknowledged(acknowledged: true);
    controller.updateConfirmationInput('DELETE');

    final pending = controller.submit();
    controller.dispose();

    expect(await pending, isFalse);
  });
}

final class _FakeAccountWithdrawalRepository
    implements AccountWithdrawalRepository {
  _FakeAccountWithdrawalRepository({this.failure});

  final Object? failure;
  final List<String> receivedConfirmations = [];

  @override
  Future<void> withdraw({required String confirmation}) async {
    receivedConfirmations.add(confirmation);
    await Future<void>.delayed(Duration.zero);
    if (failure case final failure?) throw failure;
  }
}
