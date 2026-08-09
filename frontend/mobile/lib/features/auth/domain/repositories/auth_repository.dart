import '../entities/auth_session.dart';
import '../entities/auth_tokens.dart';
import '../entities/new_user_onboarding_input.dart';
import '../entities/oauth_credential.dart';

abstract interface class AuthRepository {
  Future<AuthSession> signIn(OAuthCredential credential);

  Future<AuthSession> completeOnboarding(NewUserOnboardingInput input);

  Future<AuthTokens> refreshTokens(String refreshToken);

  Future<AuthSession?> restoreSession();

  Future<void> signOut();
}
