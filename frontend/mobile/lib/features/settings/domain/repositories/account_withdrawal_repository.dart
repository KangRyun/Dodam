/// 회원 탈퇴 도메인 계약.
///
/// 대상 사용자는 Access Token에서 해석하므로 식별자를 받지 않는다(IDOR 차단).
///
/// 계약: `docs/api/API_명세서_최종.md` §6 USER-05 `DELETE /users/me`
abstract interface class AccountWithdrawalRepository {
  /// USER-05 `DELETE /users/me` — 계정을 `DELETED` 상태로 전환한다.
  ///
  /// [confirmation]은 오작동 방지 확인 문자열이며 서버가 정확히
  /// [withdrawalConfirmationKeyword]인지 다시 검증한다. 화면에서 먼저 막더라도
  /// 판정 권한은 서버에 있으므로 입력값을 그대로 전달한다.
  ///
  /// 성공 시 본문 없는 `204`가 오므로 반환값이 없다.
  Future<void> withdraw({required String confirmation});
}

/// 탈퇴 확인 입력이 정확히 일치해야 하는 문자열.
///
/// 서버 `UserDeletionService`가 같은 값으로 검증하며 다르면
/// `USER_400_002`(`WITHDRAWAL_CONFIRMATION_MISMATCH`)로 거절한다.
const String withdrawalConfirmationKeyword = 'DELETE';
