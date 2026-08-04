import '../../../../core/network/api_failure.dart';
import '../../data/dto/guardian_pin_dtos.dart';

enum GuardianPinFailureType {
  mismatch,
  locked,
  notConfigured,
  alreadyConfigured,
  resetRequired,
  unavailable,
  invalidInput,
  invalidPin,
  accessTokenInvalid,
  authenticationRequired,
  accountSuspended,
  userNotFound,
  dataConflict,
}

final class GuardianPinFailure implements Exception {
  const GuardianPinFailure({
    required this.type,
    required this.code,
    this.status,
    this.cause,
  });

  final GuardianPinFailureType type;
  final String code;
  final GuardianPinStatusDto? status;
  final ApiResponseFailure? cause;

  @override
  String toString() => 'GuardianPinFailure(type: $type, code: $code)';
}

abstract final class GuardianPinValidator {
  static final RegExp _fourAsciiDigits = RegExp(r'^[0-9]{4}$');

  static bool isValid(String pin) => _fourAsciiDigits.hasMatch(pin);
}
