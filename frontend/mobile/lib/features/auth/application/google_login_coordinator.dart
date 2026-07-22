import '../domain/clients/google_login_client.dart';
import '../domain/failures/auth_failure.dart';
import '../presentation/models/auth_state.dart';
import 'social_login_service.dart';

// 구글 인증 결과와 서비스 로그인 연결
final class GoogleLoginCoordinator {
  GoogleLoginCoordinator(this._googleLoginClient, this._socialLoginService);

  final GoogleLoginClient _googleLoginClient;
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
      final result = await _googleLoginClient.signIn();
      // Google ID Token을 서비스 인증으로 전달
      return switch (result) {
        GoogleLoginSuccess(:final idToken) =>
          _socialLoginService.signInWithGoogle(idToken),
        GoogleLoginCancelled() => const AuthState.unauthenticated(),
      };
    } on AuthFailure catch (failure) {
      return AuthState.failure(failure);
    } on Object catch (error) {
      return AuthState.failure(
        AuthFailure(
          type: AuthFailureType.unknown,
          code: 'GOOGLE_LOGIN_UNKNOWN',
          message: '구글 로그인 중 문제가 발생했어요.',
          cause: error,
        ),
      );
    }
  }
}
