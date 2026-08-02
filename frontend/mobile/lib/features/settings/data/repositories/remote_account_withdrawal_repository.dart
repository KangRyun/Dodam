import '../../../../core/network/network.dart';
import '../../domain/repositories/account_withdrawal_repository.dart';

/// 회원 탈퇴 실 API 구현.
///
/// 성공 응답은 본문 없는 `204`이며 공통 봉투를 쓰지 않는다
/// (`docs/api/public-api-contract-v1.md` — 204와 Binary 응답은 Envelope 제외).
/// 따라서 [envelopeObject] 해제 없이 호출 성공 여부만 본다.
///
/// 계약: `docs/api/API_명세서_최종.md` §6 USER-05 `DELETE /users/me`
final class RemoteAccountWithdrawalRepository
    implements AccountWithdrawalRepository {
  const RemoteAccountWithdrawalRepository(this._apiClient);

  final ApiClient _apiClient;

  /// 요청 본문에는 서버가 실제로 받는 `confirmation`만 담는다.
  ///
  /// 명세 §6.2는 `password?`와 `deleteChildData`도 적어 두었으나 서버
  /// `DeleteUserRequest`는 `confirmation` 한 필드만 가진다. 없는 기능을 보낸
  /// 것처럼 보이지 않도록 실제 계약면만 채운다.
  @override
  Future<void> withdraw({required String confirmation}) async {
    await _apiClient.delete<void>(
      'users/me',
      data: {'confirmation': confirmation},
    );
  }
}
