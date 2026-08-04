import 'package:flutter/foundation.dart';

import '../data/dto/guardian_pin_dtos.dart';
import '../domain/failures/guardian_pin_failure.dart';
import '../domain/repositories/guardian_pin_repository.dart';

enum GuardianPinMode { configure, verify, change }

enum GuardianPinStep {
  configureNew,
  configureConfirm,
  verify,
  changeCurrent,
  changeNew,
  changeConfirm,
}

enum GuardianPinFlowStatus { idle, submitting, success, failure }

/// 보호자 PIN 입력 흐름의 presentation 상태를 관리한다.
///
/// PIN은 private 필드에만 잠시 보관하고 단계 이동·요청 시작·성공·실패 때 즉시
/// 지운다. 공개 상태와 [toString]에는 입력 길이만 노출한다.
final class GuardianPinController extends ChangeNotifier {
  GuardianPinController({
    required this.repository,
    required GuardianPinMode mode,
  }) : _mode = mode,
       _step = _initialStep(mode);

  final GuardianPinRepository repository;

  GuardianPinMode _mode;
  GuardianPinStep _step;
  GuardianPinFlowStatus _status = GuardianPinFlowStatus.idle;
  GuardianPinStatusDto? _serverStatus;
  GuardianPinFailureType? _failureType;
  String? _message;
  String _input = '';
  String _currentPin = '';
  String _newPin = '';
  bool _disposed = false;
  int _generation = 0;
  int _inputRevision = 0;
  int _completionRevision = 0;

  GuardianPinMode get mode => _mode;
  GuardianPinStep get step => _step;
  GuardianPinFlowStatus get status => _status;
  GuardianPinStatusDto? get serverStatus => _serverStatus;
  GuardianPinFailureType? get failureType => _failureType;
  String? get message => _message;
  int get inputLength => _input.length;
  int get inputRevision => _inputRevision;
  int get completionRevision => _completionRevision;
  bool get isSubmitting => _status == GuardianPinFlowStatus.submitting;
  bool get isCompleted => _status == GuardianPinFlowStatus.success;
  bool get isLocked =>
      _failureType == GuardianPinFailureType.locked ||
      _serverStatus?.locked == true;
  bool get canEdit => !_disposed && !isSubmitting && !isLocked && !isCompleted;
  bool get canSubmit => canEdit && GuardianPinValidator.isValid(_input);

  String get title => switch (_mode) {
    GuardianPinMode.configure => '보호자 PIN 설정',
    GuardianPinMode.verify => '보호자 확인',
    GuardianPinMode.change => '보호자 PIN 변경',
  };

  String get instruction => switch (_step) {
    GuardianPinStep.configureNew => '사용할 숫자 4자리를 입력해 주세요.',
    GuardianPinStep.configureConfirm => '같은 PIN을 한 번 더 입력해 주세요.',
    GuardianPinStep.verify => '보호자 PIN 숫자 4자리를 입력해 주세요.',
    GuardianPinStep.changeCurrent => '현재 PIN을 입력해 주세요.',
    GuardianPinStep.changeNew => '새로 사용할 PIN을 입력해 주세요.',
    GuardianPinStep.changeConfirm => '새 PIN을 한 번 더 입력해 주세요.',
  };

  String get submitLabel => switch (_step) {
    GuardianPinStep.configureNew ||
    GuardianPinStep.changeCurrent ||
    GuardianPinStep.changeNew => '다음',
    GuardianPinStep.configureConfirm => '설정하기',
    GuardianPinStep.verify => '확인하기',
    GuardianPinStep.changeConfirm => '변경하기',
  };

  void updateInput(String value) {
    if (!canEdit || value.length > 4) return;
    if (value.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(value)) return;
    if (_input == value) return;
    _input = value;
    if (_status == GuardianPinFlowStatus.failure) {
      _status = GuardianPinFlowStatus.idle;
      _failureType = null;
      _message = null;
    }
    _notify();
  }

  void deleteLastDigit() {
    if (!canEdit || _input.isEmpty) return;
    updateInput(_input.substring(0, _input.length - 1));
  }

  void clearInput() {
    if (!canEdit || _input.isEmpty) return;
    _clearActiveInput();
    _notify();
  }

  /// 진행 중 요청을 무효화하고 다른 독립 흐름을 시작한다.
  void restart(GuardianPinMode mode) {
    if (_disposed) return;
    _generation += 1;
    _mode = mode;
    _step = _initialStep(mode);
    _status = GuardianPinFlowStatus.idle;
    _serverStatus = null;
    _failureType = null;
    _message = null;
    _clearSecrets();
    _notify();
  }

  Future<bool> submit() async {
    if (!canSubmit) return false;

    switch (_step) {
      case GuardianPinStep.configureNew:
        _newPin = _input;
        _moveTo(GuardianPinStep.configureConfirm);
        return false;
      case GuardianPinStep.changeCurrent:
        _currentPin = _input;
        _moveTo(GuardianPinStep.changeNew);
        return false;
      case GuardianPinStep.changeNew:
        _newPin = _input;
        _moveTo(GuardianPinStep.changeConfirm);
        return false;
      case GuardianPinStep.configureConfirm:
        if (_newPin != _input) {
          _localMismatch(resetStep: GuardianPinStep.configureNew);
          return false;
        }
        return _configure(_newPin);
      case GuardianPinStep.verify:
        return _verify(_input);
      case GuardianPinStep.changeConfirm:
        if (_newPin != _input) {
          _localMismatch(resetStep: GuardianPinStep.changeCurrent);
          return false;
        }
        return _change(currentPin: _currentPin, newPin: _newPin);
    }
  }

  /// 잠금 해제 여부는 시간을 계산하지 않고 서버 상태를 다시 조회해 확정한다.
  Future<bool> refreshStatus() async {
    if (_disposed || isSubmitting) return false;
    final generation = _beginRequest();
    try {
      final status = await repository.getStatus();
      if (!_isCurrent(generation)) return false;
      _serverStatus = status;
      if (status.locked) {
        _status = GuardianPinFlowStatus.failure;
        _failureType = GuardianPinFailureType.locked;
        _message = _lockedMessage(status);
      } else {
        _status = GuardianPinFlowStatus.idle;
        _failureType = null;
        _message = null;
      }
      _notify();
      return !status.locked;
    } on Object catch (error) {
      if (!_isCurrent(generation)) return false;
      _applyFailure(error);
      return false;
    }
  }

  Future<bool> _configure(String pin) =>
      _request(() => repository.configure(pin));

  Future<bool> _verify(String pin) => _request(() => repository.verify(pin));

  Future<bool> _change({required String currentPin, required String newPin}) =>
      _request(() => repository.change(currentPin: currentPin, newPin: newPin));

  Future<bool> _request(
    Future<GuardianPinStatusDto> Function() operation,
  ) async {
    final generation = _beginRequest();
    try {
      final status = await operation();
      if (!_isCurrent(generation)) return false;
      _serverStatus = status;
      _status = GuardianPinFlowStatus.success;
      _failureType = null;
      _message = '보호자 PIN 확인이 완료됐어요.';
      _completionRevision += 1;
      _clearSecrets();
      _notify();
      return true;
    } on Object catch (error) {
      if (!_isCurrent(generation)) return false;
      _applyFailure(error);
      return false;
    }
  }

  int _beginRequest() {
    final generation = ++_generation;
    _status = GuardianPinFlowStatus.submitting;
    _failureType = null;
    _message = null;
    _clearSecrets();
    _notify();
    return generation;
  }

  void _applyFailure(Object error) {
    _status = GuardianPinFlowStatus.failure;
    _clearSecrets();
    if (error is GuardianPinFailure) {
      _failureType = error.type;
      _serverStatus = error.status;
      _message = _messageFor(error.type, error.status);
    } else {
      _failureType = null;
      _serverStatus = null;
      _message = '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.';
    }
    _step = _initialStep(_mode);
    _notify();
  }

  String _messageFor(
    GuardianPinFailureType type,
    GuardianPinStatusDto? status,
  ) => switch (type) {
    GuardianPinFailureType.mismatch =>
      status == null
          ? 'PIN이 일치하지 않아요. 다시 입력해 주세요.'
          : 'PIN이 일치하지 않아요. 남은 시도 횟수는 ${status.remainingAttempts}회예요.',
    GuardianPinFailureType.locked => _lockedMessage(status),
    GuardianPinFailureType.notConfigured => '설정된 PIN이 없어요. 먼저 PIN을 설정해 주세요.',
    GuardianPinFailureType.alreadyConfigured => '이미 PIN이 설정되어 있어요.',
    GuardianPinFailureType.resetRequired => 'PIN을 다시 설정하려면 보호자 재인증이 필요해요.',
    GuardianPinFailureType.unavailable =>
      '지금은 PIN 기능을 사용할 수 없어요. 잠시 후 다시 시도해 주세요.',
    GuardianPinFailureType.invalidInput ||
    GuardianPinFailureType.invalidPin => '숫자 4자리 PIN을 입력해 주세요.',
    GuardianPinFailureType.accessTokenInvalid ||
    GuardianPinFailureType.authenticationRequired => '로그인 정보를 다시 확인해 주세요.',
    GuardianPinFailureType.accountSuspended => '현재 계정에서는 이 기능을 사용할 수 없어요.',
    GuardianPinFailureType.userNotFound => '보호자 정보를 확인하지 못했어요.',
    GuardianPinFailureType.dataConflict => '현재 상태를 다시 확인한 뒤 시도해 주세요.',
  };

  String _lockedMessage(GuardianPinStatusDto? status) {
    final retrySeconds = status?.retryAfterSeconds;
    if (retrySeconds != null) {
      return 'PIN 입력이 잠겨 있어요. 서버 안내에 따라 $retrySeconds초 후 상태를 다시 확인해 주세요.';
    }
    final lockedUntil = status?.lockedUntil?.toLocal();
    if (lockedUntil != null) {
      final hour = lockedUntil.hour.toString().padLeft(2, '0');
      final minute = lockedUntil.minute.toString().padLeft(2, '0');
      return 'PIN 입력이 잠겨 있어요. 서버 기준 안내 시각 $hour:$minute 이후 상태를 다시 확인해 주세요.';
    }
    return 'PIN 입력이 잠겨 있어요. 잠시 후 상태를 다시 확인해 주세요.';
  }

  void _localMismatch({required GuardianPinStep resetStep}) {
    _status = GuardianPinFlowStatus.failure;
    _failureType = GuardianPinFailureType.mismatch;
    _message = '두 PIN이 일치하지 않아요. 처음부터 다시 입력해 주세요.';
    _step = resetStep;
    _clearSecrets();
    _notify();
  }

  void _moveTo(GuardianPinStep step) {
    _step = step;
    _status = GuardianPinFlowStatus.idle;
    _failureType = null;
    _message = null;
    _clearActiveInput();
    _notify();
  }

  void _clearActiveInput() {
    _input = '';
    _inputRevision += 1;
  }

  void _clearSecrets() {
    _input = '';
    _currentPin = '';
    _newPin = '';
    _inputRevision += 1;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _clearSecrets();
    super.dispose();
  }

  @override
  String toString() =>
      'GuardianPinController(mode: $_mode, step: $_step, status: $_status, '
      'inputLength: $inputLength, locked: $isLocked)';

  static GuardianPinStep _initialStep(GuardianPinMode mode) => switch (mode) {
    GuardianPinMode.configure => GuardianPinStep.configureNew,
    GuardianPinMode.verify => GuardianPinStep.verify,
    GuardianPinMode.change => GuardianPinStep.changeCurrent,
  };
}
