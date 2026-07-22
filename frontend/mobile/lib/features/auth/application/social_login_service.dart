import '../domain/entities/oauth_credential.dart';
import '../domain/enums/auth_provider.dart';
import '../domain/failures/auth_failure.dart';
import '../domain/repositories/auth_repository.dart';
import '../presentation/models/auth_state.dart';

class SocialLoginService {
  SocialLoginService(this._authRepository);

  final AuthRepository _authRepository;
  Future<AuthState>? _inFlightSignIn;

  bool get isSigningIn => _inFlightSignIn != null;

  Future<AuthState> signInWithKakao(String accessToken) => _signIn(
    provider: AuthProvider.kakao,
    type: OAuthCredentialType.accessToken,
    token: accessToken,
  );

  Future<AuthState> signInWithGoogle(String idToken) => _signIn(
    provider: AuthProvider.google,
    type: OAuthCredentialType.idToken,
    token: idToken,
  );

  Future<AuthState> signInWithNaver(String accessToken) => _signIn(
    provider: AuthProvider.naver,
    type: OAuthCredentialType.accessToken,
    token: accessToken,
  );

  Future<AuthState> _signIn({
    required AuthProvider provider,
    required OAuthCredentialType type,
    required String token,
  }) {
    final inFlight = _inFlightSignIn;
    if (inFlight != null) return inFlight;

    final request = _performSignIn(
      OAuthCredential(provider: provider, type: type, value: token),
    );
    _inFlightSignIn = request;
    request.whenComplete(() {
      if (identical(_inFlightSignIn, request)) {
        _inFlightSignIn = null;
      }
    });
    return request;
  }

  Future<AuthState> _performSignIn(OAuthCredential credential) async {
    try {
      final session = await _authRepository.signIn(credential);
      return AuthState.fromSession(session);
    } on AuthFailure catch (failure) {
      return AuthState.failure(failure);
    } on Object catch (error) {
      return AuthState.failure(
        AuthFailure(
          type: AuthFailureType.unknown,
          code: 'AUTH_UNKNOWN',
          message: '로그인 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.',
          cause: error,
        ),
      );
    }
  }
}
