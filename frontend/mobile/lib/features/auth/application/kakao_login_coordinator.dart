import '../domain/clients/kakao_login_client.dart';
import '../domain/failures/auth_failure.dart';
import '../presentation/models/auth_state.dart';
import 'social_login_service.dart';

// 카카오 인증 결과와 서비스 로그인 연결
final class KakaoLoginCoordinator {
  KakaoLoginCoordinator(this._kakaoLoginClient, this._socialLoginService);

  final KakaoLoginClient _kakaoLoginClient;
  final SocialLoginService _socialLoginService;
  Future<AuthState>? _inFlightSignIn;

  Future<AuthState> signIn() {
    // 중복 로그인 요청 방지
    final inFlight = _inFlightSignIn;
    if (inFlight != null) return inFlight;

    final request = _performSignIn();
    _inFlightSignIn = request;
    request.whenComplete(() {
      if (identical(_inFlightSignIn, request)) {
        _inFlightSignIn = null;
      }
    });
    return request;
  }

  Future<AuthState> _performSignIn() async {
    try {
      final result = await _kakaoLoginClient.signIn();
      // Kakao Access Token을 서비스 인증으로 전달
      return switch (result) {
        KakaoLoginSuccess(:final accessToken) =>
          _socialLoginService.signInWithKakao(accessToken),
        KakaoLoginCancelled() => const AuthState.unauthenticated(),
      };
    } on AuthFailure catch (failure) {
      return AuthState.failure(failure);
    } on Object catch (error) {
      return AuthState.failure(
        AuthFailure(
          type: AuthFailureType.unknown,
          code: 'KAKAO_LOGIN_UNKNOWN',
          message: '카카오 로그인 중 문제가 발생했어요.',
          cause: error,
        ),
      );
    }
  }
}
