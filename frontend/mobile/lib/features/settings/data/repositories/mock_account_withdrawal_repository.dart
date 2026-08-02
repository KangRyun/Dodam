import '../../../../core/network/network.dart';
import '../../domain/repositories/account_withdrawal_repository.dart';

/// 회원 탈퇴 Mock 구현.
///
/// 서버와 같은 확인 문자열 검증을 수행해, 실 연동 전에도 화면이 실제와 같은
/// 실패 경로를 만난다. 성공 시에는 아무것도 반환하지 않는다(`204`).
final class MockAccountWithdrawalRepository
    implements AccountWithdrawalRepository {
  const MockAccountWithdrawalRepository();

  @override
  Future<void> withdraw({required String confirmation}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (confirmation != withdrawalConfirmationKeyword) {
      throw const ApiResponseFailure(
        statusCode: 400,
        error: ApiError(
          code: 'USER_400_002',
          message: '회원 탈퇴 확인 값이 올바르지 않습니다.',
        ),
      );
    }
  }
}
