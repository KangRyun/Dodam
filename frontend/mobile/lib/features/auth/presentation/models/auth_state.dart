import '../../domain/entities/auth_session.dart';
import '../../domain/enums/auth_status.dart';
import '../../domain/failures/auth_failure.dart';

class AuthState {
  const AuthState._({required this.status, this.session, this.failure});

  const AuthState.initial() : this._(status: AuthStatus.initial);

  const AuthState.loading() : this._(status: AuthStatus.loading);

  const AuthState.unauthenticated()
    : this._(status: AuthStatus.unauthenticated);

  const AuthState.authenticated(AuthSession session)
    : this._(status: AuthStatus.authenticated, session: session);

  const AuthState.onboardingRequired(AuthSession session)
    : this._(status: AuthStatus.onboardingRequired, session: session);

  const AuthState.failure(AuthFailure failure)
    : this._(status: AuthStatus.failure, failure: failure);

  factory AuthState.fromSession(AuthSession session) =>
      session.requiresOnboarding
      ? AuthState.onboardingRequired(session)
      : AuthState.authenticated(session);

  final AuthStatus status;
  final AuthSession? session;
  final AuthFailure? failure;

  bool get isBusy => status == AuthStatus.loading;
  bool get isSignedIn =>
      status == AuthStatus.authenticated ||
      status == AuthStatus.onboardingRequired;
}
