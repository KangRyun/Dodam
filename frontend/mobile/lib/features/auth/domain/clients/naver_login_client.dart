// 네이버 SDK 로그인 결과
sealed class NaverLoginResult {
  const NaverLoginResult();
}

final class NaverLoginSuccess extends NaverLoginResult {
  const NaverLoginSuccess(this.accessToken);

  final String accessToken;
}

final class NaverLoginCancelled extends NaverLoginResult {
  const NaverLoginCancelled();
}

// 네이버 SDK 연결 계약
abstract interface class NaverLoginClient {
  Future<NaverLoginResult> signIn();

  Future<void> signOut();
}
