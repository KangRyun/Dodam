// 구글 SDK 로그인 결과
sealed class GoogleLoginResult {
  const GoogleLoginResult();
}

final class GoogleLoginSuccess extends GoogleLoginResult {
  const GoogleLoginSuccess(this.idToken);

  final String idToken;
}

final class GoogleLoginCancelled extends GoogleLoginResult {
  const GoogleLoginCancelled();
}

// 구글 SDK 연결 계약
abstract interface class GoogleLoginClient {
  Future<GoogleLoginResult> signIn();

  Future<void> signOut();
}
