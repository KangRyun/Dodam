import 'package:flutter/foundation.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/api_failure_presentation.dart';
import '../domain/repositories/account_withdrawal_repository.dart';

/// 회원 탈퇴 요청의 진행 상태.
enum AccountWithdrawalStatus { idle, submitting, success, failure }

/// 회원 탈퇴 확인 입력과 요청 상태를 관리한다.
///
/// 확인 문자열 판정은 화면이 아니라 여기서 한다. 화면은 [canSubmit]만 보고
/// 버튼 활성화를 정한다.
final class AccountWithdrawalController extends ChangeNotifier {
  AccountWithdrawalController(this._repository);

  final AccountWithdrawalRepository _repository;

  AccountWithdrawalStatus _status = AccountWithdrawalStatus.idle;
  Object? _error;
  String _confirmationInput = '';
  bool _noticeAcknowledged = false;
  bool _disposed = false;
  int _generation = 0;

  AccountWithdrawalStatus get status => _status;
  Object? get error => _error;
  bool get isSubmitting => _status == AccountWithdrawalStatus.submitting;

  /// 사용자가 입력한 확인 문자열.
  String get confirmationInput => _confirmationInput;

  /// 데이터 처리 안내를 읽고 동의했는지 여부.
  bool get noticeAcknowledged => _noticeAcknowledged;

  /// 확인 문자열이 계약 값과 **정확히** 일치하는지.
  ///
  /// 앞뒤 공백을 다듬거나 대소문자를 무시하지 않는다. 서버가 같은 기준으로
  /// 판정하므로 여기서 관대하게 굴면 화면만 통과하고 서버에서 막힌다.
  bool get isConfirmationValid =>
      _confirmationInput == withdrawalConfirmationKeyword;

  /// 탈퇴 요청을 보낼 수 있는 상태인지.
  ///
  /// 성공한 뒤에는 다시 열리지 않는다. 성공 직후 화면은 로그아웃 정리(푸시 해제·
  /// `POST auth/logout`)를 기다리는 동안 살아 있는데, 그때 버튼이 다시 활성화되면
  /// 되돌릴 수 없는 `DELETE`가 한 번 더 나간다.
  bool get canSubmit =>
      _noticeAcknowledged &&
      isConfirmationValid &&
      !isSubmitting &&
      _status != AccountWithdrawalStatus.success;

  /// 실패 시 화면에 띄울 문구. 실패가 없으면 `null`.
  String? get failureMessage {
    final error = _error;
    if (error == null) return null;
    if (error is ApiResponseFailure) {
      final code = error.error?.code;
      if (code == _confirmationMismatchCode) {
        return '확인 문구가 올바르지 않아요. $withdrawalConfirmationKeyword를 정확히 입력해 주세요.';
      }
      if (error.statusCode == 404) {
        return '이미 탈퇴 처리된 계정이에요. 로그인 화면으로 돌아가 주세요.';
      }
    }
    return ApiFailurePresentation.of(error).message;
  }

  /// 같은 요청을 다시 시도해서 결과가 달라질 수 있는지.
  bool get canRetry =>
      _error != null && ApiFailurePresentation.of(_error).canRetry;

  void updateConfirmationInput(String value) {
    if (_confirmationInput == value) return;
    _confirmationInput = value;
    // 입력을 고치는 순간 이전 실패 문구를 지운다. 남겨두면 방금 고친 값에
    // 대한 오류처럼 읽힌다.
    if (_status == AccountWithdrawalStatus.failure) {
      _status = AccountWithdrawalStatus.idle;
      _error = null;
    }
    _notify();
  }

  void setNoticeAcknowledged({required bool acknowledged}) {
    if (_noticeAcknowledged == acknowledged) return;
    _noticeAcknowledged = acknowledged;
    _notify();
  }

  /// 탈퇴를 요청하고 성공 여부를 반환한다.
  ///
  /// [canSubmit]이 거짓이면 호출하지 않고 거짓을 반환한다.
  Future<bool> submit() async {
    if (!canSubmit) return false;

    final generation = ++_generation;
    _status = AccountWithdrawalStatus.submitting;
    _error = null;
    _notify();

    try {
      await _repository.withdraw(confirmation: _confirmationInput);
      if (_disposed || generation != _generation) return false;
      _status = AccountWithdrawalStatus.success;
      _notify();
      return true;
    } on Object catch (error) {
      if (_disposed || generation != _generation) return false;
      _status = AccountWithdrawalStatus.failure;
      _error = error;
      _notify();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  static const String _confirmationMismatchCode = 'USER_400_002';
}
