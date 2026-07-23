// 카카오 SDK 로그인 결과
sealed class KakaoLoginResult {
  const KakaoLoginResult();
}

final class KakaoLoginSuccess extends KakaoLoginResult {
  const KakaoLoginSuccess(this.accessToken);

  final String accessToken;
}

final class KakaoLoginCancelled extends KakaoLoginResult {
  const KakaoLoginCancelled();
}

// 카카오 SDK 연결 계약
abstract interface class KakaoLoginClient {
  Future<KakaoLoginResult> signIn();

  Future<void> signOut();
}
