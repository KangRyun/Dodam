import 'dart:async';

import 'package:dodam/features/guardian_pin/application/guardian_pin_controller.dart';
import 'package:dodam/features/guardian_pin/data/dto/guardian_pin_dtos.dart';
import 'package:dodam/features/guardian_pin/domain/failures/guardian_pin_failure.dart';
import 'package:dodam/features/guardian_pin/domain/repositories/guardian_pin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('최초 설정은 신규 PIN과 확인 PIN이 일치할 때 한 번만 요청한다', () async {
    final repository = _FakeGuardianPinRepository();
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.configure,
    );

    controller.updateInput('0123');
    await controller.submit();
    expect(controller.step, GuardianPinStep.configureConfirm);
    expect(controller.inputLength, 0);
    expect(repository.configureCalls, 0);

    controller.updateInput('0123');
    expect(await controller.submit(), isTrue);
    expect(repository.configureCalls, 1);
    expect(repository.lastConfiguredPin, '0123');
    expect(controller.status, GuardianPinFlowStatus.success);
    expect(controller.inputLength, 0);
  });

  test('최초 설정 확인 불일치는 API를 호출하지 않고 비밀값을 지운다', () async {
    final repository = _FakeGuardianPinRepository();
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.configure,
    );

    controller.updateInput('0123');
    await controller.submit();
    controller.updateInput('4567');
    await controller.submit();

    expect(repository.configureCalls, 0);
    expect(controller.step, GuardianPinStep.configureNew);
    expect(controller.inputLength, 0);
    expect(controller.message, contains('일치하지 않아요'));
    expect('$controller', isNot(contains('0123')));
    expect('$controller', isNot(contains('4567')));
  });

  test('검증 성공은 leading zero를 그대로 한 번 제출한다', () async {
    final repository = _FakeGuardianPinRepository();
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );

    controller.updateInput('0007');
    expect(await controller.submit(), isTrue);

    expect(repository.verifyCalls, 1);
    expect(repository.lastVerifiedPin, '0007');
    expect(controller.isCompleted, isTrue);
  });

  test('입력 중에도 PIN 원문은 공개 debug 문자열에 포함되지 않는다', () {
    final controller = GuardianPinController(
      repository: _FakeGuardianPinRepository(),
      mode: GuardianPinMode.verify,
    );

    controller.updateInput('9876');

    expect('$controller', isNot(contains('9876')));
    expect(controller.message, isNull);
  });

  test('PIN 불일치는 서버 remainingAttempts를 그대로 표시한다', () async {
    final repository = _FakeGuardianPinRepository(
      verifyError: GuardianPinFailure(
        type: GuardianPinFailureType.mismatch,
        code: 'PIN_MISMATCH',
        status: _status(remainingAttempts: 3),
      ),
    );
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );

    controller.updateInput('1234');
    await controller.submit();

    expect(controller.failureType, GuardianPinFailureType.mismatch);
    expect(controller.message, contains('3회'));
    expect(controller.inputLength, 0);
  });

  test('5번째 실패 잠금 응답은 추가 입력과 API 호출을 막는다', () async {
    final repository = _FakeGuardianPinRepository(
      verifyError: GuardianPinFailure(
        type: GuardianPinFailureType.locked,
        code: 'PIN_LOCKED',
        status: _status(
          locked: true,
          remainingAttempts: 0,
          retryAfterSeconds: 30,
        ),
      ),
    );
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );

    controller.updateInput('1234');
    await controller.submit();
    controller.updateInput('9999');
    await controller.submit();

    expect(controller.isLocked, isTrue);
    expect(controller.message, contains('30초'));
    expect(controller.inputLength, 0);
    expect(repository.verifyCalls, 1);
  });

  test('잠금 해제는 자동 성공이 아니라 서버 상태 재조회 후 idle로만 돌아간다', () async {
    final repository = _FakeGuardianPinRepository(
      verifyError: GuardianPinFailure(
        type: GuardianPinFailureType.locked,
        code: 'PIN_LOCKED',
        status: _status(locked: true, remainingAttempts: 0),
      ),
      statusResult: _status(),
    );
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );
    controller.updateInput('1234');
    await controller.submit();

    expect(await controller.refreshStatus(), isTrue);
    expect(repository.statusCalls, 1);
    expect(controller.status, GuardianPinFlowStatus.idle);
    expect(controller.isCompleted, isFalse);
    expect(controller.isLocked, isFalse);
  });

  test('PIN 변경은 현재 PIN·새 PIN·확인을 순서대로 받고 한 번 요청한다', () async {
    final repository = _FakeGuardianPinRepository();
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.change,
    );

    controller.updateInput('0123');
    await controller.submit();
    expect(controller.step, GuardianPinStep.changeNew);
    controller.updateInput('4567');
    await controller.submit();
    expect(controller.step, GuardianPinStep.changeConfirm);
    controller.updateInput('4567');
    expect(await controller.submit(), isTrue);

    expect(repository.changeCalls, 1);
    expect(repository.lastCurrentPin, '0123');
    expect(repository.lastNewPin, '4567');
  });

  test('PIN 변경 확인 불일치는 API 0회이고 처음 단계로 돌아간다', () async {
    final repository = _FakeGuardianPinRepository();
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.change,
    );

    for (final pin in ['0123', '4567', '9999']) {
      controller.updateInput(pin);
      await controller.submit();
    }

    expect(repository.changeCalls, 0);
    expect(controller.step, GuardianPinStep.changeCurrent);
    expect(controller.inputLength, 0);
  });

  test('제출 연타는 in-flight API를 한 번만 호출한다', () async {
    final completer = Completer<GuardianPinStatusDto>();
    final repository = _FakeGuardianPinRepository(
      verifyFuture: completer.future,
    );
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );
    controller.updateInput('1234');

    final first = controller.submit();
    final second = controller.submit();
    expect(repository.verifyCalls, 1);
    expect(await second, isFalse);
    completer.complete(_status());
    expect(await first, isTrue);
  });

  test('mode 변경 뒤 늦은 응답은 stale 상태를 덮어쓰지 않는다', () async {
    final completer = Completer<GuardianPinStatusDto>();
    final repository = _FakeGuardianPinRepository(
      verifyFuture: completer.future,
    );
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );
    controller.updateInput('1234');
    final pending = controller.submit();

    controller.restart(GuardianPinMode.change);
    completer.complete(_status());
    expect(await pending, isFalse);
    expect(controller.mode, GuardianPinMode.change);
    expect(controller.step, GuardianPinStep.changeCurrent);
    expect(controller.status, GuardianPinFlowStatus.idle);
  });

  test('dispose 이후 늦은 응답은 상태 알림 없이 무시된다', () async {
    final completer = Completer<GuardianPinStatusDto>();
    final repository = _FakeGuardianPinRepository(
      verifyFuture: completer.future,
    );
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.updateInput('1234');
    final pending = controller.submit();
    final beforeDispose = notifications;

    controller.dispose();
    completer.complete(_status());

    expect(await pending, isFalse);
    expect(notifications, beforeDispose);
  });

  final failureMessages = <GuardianPinFailureType, String>{
    GuardianPinFailureType.mismatch: '일치하지 않아요',
    GuardianPinFailureType.locked: '잠겨 있어요',
    GuardianPinFailureType.notConfigured: '설정된 PIN이 없어요',
    GuardianPinFailureType.alreadyConfigured: '이미 PIN이 설정',
    GuardianPinFailureType.resetRequired: '재인증',
    GuardianPinFailureType.unavailable: '사용할 수 없어요',
    GuardianPinFailureType.invalidInput: '숫자 4자리',
    GuardianPinFailureType.invalidPin: '숫자 4자리',
    GuardianPinFailureType.accessTokenInvalid: '로그인 정보',
    GuardianPinFailureType.authenticationRequired: '로그인 정보',
    GuardianPinFailureType.accountSuspended: '현재 계정',
    GuardianPinFailureType.userNotFound: '보호자 정보',
    GuardianPinFailureType.dataConflict: '현재 상태',
  };

  for (final entry in failureMessages.entries) {
    test('${entry.key.name} typed failure를 쉬운 문구로 표시한다', () async {
      final repository = _FakeGuardianPinRepository(
        verifyError: GuardianPinFailure(
          type: entry.key,
          code: 'TECHNICAL_CODE',
        ),
      );
      final controller = GuardianPinController(
        repository: repository,
        mode: GuardianPinMode.verify,
      );
      controller.updateInput('1234');

      await controller.submit();

      expect(controller.message, contains(entry.value));
      expect(controller.message, isNot(contains('TECHNICAL_CODE')));
      expect(controller.inputLength, 0);
    });
  }

  test('unknown failure는 기술 문자열 없이 일반 재시도 문구를 제공한다', () async {
    final repository = _FakeGuardianPinRepository(
      verifyError: StateError('secret-internal-detail'),
    );
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );
    controller.updateInput('1234');

    await controller.submit();

    expect(controller.message, contains('다시 시도'));
    expect(controller.message, isNot(contains('secret-internal-detail')));
  });

  test('nullable retryAfterSeconds와 lockedUntil 잠금 응답도 안전하다', () async {
    final repository = _FakeGuardianPinRepository(
      verifyError: const GuardianPinFailure(
        type: GuardianPinFailureType.locked,
        code: 'PIN_LOCKED',
      ),
    );
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );
    controller.updateInput('1234');

    await controller.submit();

    expect(controller.isLocked, isTrue);
    expect(controller.message, contains('상태를 다시 확인'));
  });

  test('retryAfterSeconds 없이 lockedUntil만 있으면 서버 안내 시각을 표시한다', () async {
    final repository = _FakeGuardianPinRepository(
      verifyError: GuardianPinFailure(
        type: GuardianPinFailureType.locked,
        code: 'PIN_LOCKED',
        status: _status(
          locked: true,
          remainingAttempts: 0,
          lockedUntil: DateTime(2026, 8, 4, 15, 7),
        ),
      ),
    );
    final controller = GuardianPinController(
      repository: repository,
      mode: GuardianPinMode.verify,
    );
    controller.updateInput('1234');

    await controller.submit();

    expect(controller.message, contains('15:07'));
    expect(controller.isLocked, isTrue);
  });
}

GuardianPinStatusDto _status({
  bool locked = false,
  int remainingAttempts = 5,
  int? retryAfterSeconds,
  DateTime? lockedUntil,
}) => GuardianPinStatusDto(
  pinConfigured: true,
  locked: locked,
  remainingAttempts: remainingAttempts,
  retryAfterSeconds: retryAfterSeconds,
  lockedUntil: lockedUntil,
  serverTime: DateTime.utc(2026, 8, 4),
);

final class _FakeGuardianPinRepository implements GuardianPinRepository {
  _FakeGuardianPinRepository({
    this.verifyError,
    this.verifyFuture,
    GuardianPinStatusDto? statusResult,
  }) : statusResult = statusResult ?? _status();

  final Object? verifyError;
  final Future<GuardianPinStatusDto>? verifyFuture;
  final GuardianPinStatusDto statusResult;
  int configureCalls = 0;
  int verifyCalls = 0;
  int changeCalls = 0;
  int statusCalls = 0;
  String? lastConfiguredPin;
  String? lastVerifiedPin;
  String? lastCurrentPin;
  String? lastNewPin;

  @override
  Future<GuardianPinStatusDto> configure(String pin) async {
    configureCalls += 1;
    lastConfiguredPin = pin;
    return _status();
  }

  @override
  Future<GuardianPinStatusDto> verify(String pin) async {
    verifyCalls += 1;
    lastVerifiedPin = pin;
    final future = verifyFuture;
    if (future != null) return future;
    final error = verifyError;
    if (error != null) throw error;
    return _status();
  }

  @override
  Future<GuardianPinStatusDto> change({
    required String currentPin,
    required String newPin,
  }) async {
    changeCalls += 1;
    lastCurrentPin = currentPin;
    lastNewPin = newPin;
    return _status();
  }

  @override
  Future<GuardianPinStatusDto> getStatus() async {
    statusCalls += 1;
    return statusResult;
  }

  @override
  Future<GuardianPinStatusDto> reset() => throw UnimplementedError();
}
