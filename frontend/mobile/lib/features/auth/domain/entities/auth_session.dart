import 'auth_tokens.dart';
import 'authenticated_user.dart';

class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final AuthenticatedUser user;
  final AuthTokens tokens;

  bool get requiresOnboarding => !user.onboardingCompleted;
  bool get requiresAdditionalEmail => requiresOnboarding && user.needsEmail;

  AuthSession copyWith({AuthenticatedUser? user, AuthTokens? tokens}) =>
      AuthSession(user: user ?? this.user, tokens: tokens ?? this.tokens);
}
