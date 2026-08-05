import '../../domain/failures/guardian_pin_failure.dart';
import '../../domain/repositories/guardian_pin_repository.dart';
import '../dto/guardian_pin_dtos.dart';

/// 백엔드 미연결 개발·데모·테스트용 목 구현.
///
/// 실패 횟수·잠금 판정은 원래 서버 몫이라 화면이 계산하지 않는다. 여기서는
/// 목 구현이 "서버 자리"에 서서 그 값을 만들어 주고, 화면은 실제 서버에서와
/// 똑같이 응답에 담긴 상태만 읽는다.
final class MockGuardianPinRepository implements GuardianPinRepository {
  MockGuardianPinRepository({String? initialPin, this.maxAttempts = 5})
    : _pin = initialPin,
      _remainingAttempts = maxAttempts;

  final int maxAttempts;
  String? _pin;
  int _remainingAttempts;

  @override
  Future<GuardianPinStatusDto> getStatus() async => _status();

  @override
  Future<GuardianPinStatusDto> configure(String pin) async {
    _validate(pin);
    if (_pin != null) {
      throw const GuardianPinFailure(
        type: GuardianPinFailureType.alreadyConfigured,
        code: 'PIN_ALREADY_CONFIGURED',
      );
    }
    _pin = pin;
    _remainingAttempts = maxAttempts;
    return _status();
  }

  @override
  Future<GuardianPinStatusDto> change({
    required String currentPin,
    required String newPin,
  }) async {
    _validate(currentPin);
    _validate(newPin);
    _requireConfigured();
    _requireUnlocked();
    if (currentPin != _pin) return _rejectMismatch();
    _pin = newPin;
    _remainingAttempts = maxAttempts;
    return _status();
  }

  @override
  Future<GuardianPinStatusDto> reset() async {
    _pin = null;
    _remainingAttempts = maxAttempts;
    return _status();
  }

  @override
  Future<GuardianPinStatusDto> verify(String pin) async {
    _validate(pin);
    _requireConfigured();
    _requireUnlocked();
    if (pin != _pin) return _rejectMismatch();
    _remainingAttempts = maxAttempts;
    return _status();
  }

  Never _rejectMismatch() {
    _remainingAttempts -= 1;
    if (_remainingAttempts <= 0) {
      _remainingAttempts = 0;
      throw GuardianPinFailure(
        type: GuardianPinFailureType.locked,
        code: 'PIN_LOCKED',
        status: _status(),
      );
    }
    throw GuardianPinFailure(
      type: GuardianPinFailureType.mismatch,
      code: 'PIN_MISMATCH',
      status: _status(),
    );
  }

  void _requireConfigured() {
    if (_pin != null) return;
    throw const GuardianPinFailure(
      type: GuardianPinFailureType.notConfigured,
      code: 'PIN_NOT_CONFIGURED',
    );
  }

  void _requireUnlocked() {
    if (_remainingAttempts > 0) return;
    throw GuardianPinFailure(
      type: GuardianPinFailureType.locked,
      code: 'PIN_LOCKED',
      status: _status(),
    );
  }

  void _validate(String pin) {
    if (GuardianPinValidator.isValid(pin)) return;
    throw const GuardianPinFailure(
      type: GuardianPinFailureType.invalidPin,
      code: 'PIN_INVALID',
    );
  }

  GuardianPinStatusDto _status() => GuardianPinStatusDto(
    pinConfigured: _pin != null,
    locked: _remainingAttempts <= 0,
    remainingAttempts: _remainingAttempts,
    retryAfterSeconds: _remainingAttempts <= 0 ? 60 : null,
    lockedUntil: null,
    serverTime: DateTime.now().toUtc(),
  );
}
