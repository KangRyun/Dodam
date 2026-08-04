import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/network/auth/auth_header_interceptor.dart';
import '../../../../core/network/json_data.dart';
import '../../domain/failures/guardian_pin_failure.dart';
import '../../domain/repositories/guardian_pin_repository.dart';
import '../dto/guardian_pin_dtos.dart';

final class RemoteGuardianPinRepository implements GuardianPinRepository {
  const RemoteGuardianPinRepository(this._apiClient);

  static const _path = 'users/me/guardian-pin';
  static const _pinMismatch = 'PIN_MISMATCH';

  final ApiClient _apiClient;

  @override
  Future<GuardianPinStatusDto> getStatus() =>
      _send(() => _apiClient.get<Object?>(_path));

  @override
  Future<GuardianPinStatusDto> configure(String pin) async {
    _validate(pin);
    return await _send(
      () => _apiClient.post<Object?>(
        _path,
        data: GuardianPinRequestDto(pin).toJson(),
      ),
    );
  }

  @override
  Future<GuardianPinStatusDto> change({
    required String currentPin,
    required String newPin,
  }) async {
    _validate(currentPin);
    _validate(newPin);
    return await _send(
      () => _apiClient.patch<Object?>(
        _path,
        data: GuardianPinChangeRequestDto(
          currentPin: currentPin,
          newPin: newPin,
        ).toJson(),
        options: _pinMismatchRetryPolicy,
      ),
    );
  }

  @override
  Future<GuardianPinStatusDto> reset() =>
      _send(() => _apiClient.delete<Object?>(_path));

  @override
  Future<GuardianPinStatusDto> verify(String pin) async {
    _validate(pin);
    return await _send(
      () => _apiClient.post<Object?>(
        '$_path/verifications',
        data: GuardianPinRequestDto(pin).toJson(),
        options: _pinMismatchRetryPolicy,
      ),
    );
  }

  Options get _pinMismatchRetryPolicy => Options(
    extra: const {
      authRetryExcludedErrorCodesExtraKey: <String>{_pinMismatch},
    },
  );

  Future<GuardianPinStatusDto> _send(
    Future<Response<Object?>> Function() request,
  ) async {
    try {
      final response = await request();
      return GuardianPinStatusDto.fromJson(envelopeObject(response.data));
    } on ApiResponseFailure catch (failure) {
      final mapped = _mapFailure(failure);
      if (mapped == null) rethrow;
      throw mapped;
    }
  }

  void _validate(String pin) {
    if (!GuardianPinValidator.isValid(pin)) {
      throw const GuardianPinFailure(
        type: GuardianPinFailureType.invalidPin,
        code: 'PIN_INVALID',
      );
    }
  }

  GuardianPinFailure? _mapFailure(ApiResponseFailure failure) {
    final code = failure.error?.code;
    final type = switch (code) {
      'PIN_MISMATCH' => GuardianPinFailureType.mismatch,
      'PIN_LOCKED' => GuardianPinFailureType.locked,
      'PIN_NOT_CONFIGURED' => GuardianPinFailureType.notConfigured,
      'PIN_ALREADY_CONFIGURED' => GuardianPinFailureType.alreadyConfigured,
      'PIN_RESET_REQUIRED' => GuardianPinFailureType.resetRequired,
      'PIN_UNAVAILABLE' => GuardianPinFailureType.unavailable,
      'COMMON_400_001' => GuardianPinFailureType.invalidInput,
      'PIN_INVALID' => GuardianPinFailureType.invalidPin,
      'AUTH_401_002' => GuardianPinFailureType.accessTokenInvalid,
      'AUTH_401_006' => GuardianPinFailureType.authenticationRequired,
      'AUTH_403_001' => GuardianPinFailureType.accountSuspended,
      'USER_404_001' => GuardianPinFailureType.userNotFound,
      'COMMON_409_001' => GuardianPinFailureType.dataConflict,
      _ => null,
    };
    if (type == null || code == null) return null;
    return GuardianPinFailure(
      type: type,
      code: code,
      status: _errorStatusOrNull(failure.responseBody),
      cause: failure,
    );
  }

  GuardianPinStatusDto? _errorStatusOrNull(Object? body) {
    try {
      if (body is! Map || body['data'] is! Map) return null;
      return GuardianPinStatusDto.fromJson(
        Map<String, dynamic>.from(body['data']! as Map),
      );
    } on Object {
      return null;
    }
  }
}
