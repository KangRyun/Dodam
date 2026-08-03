import '../../../../core/network/auth/access_token_provider.dart';
import '../../../../core/network/auth/token_refresher.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/authenticated_user.dart';
import '../../domain/entities/new_user_onboarding_input.dart';
import '../../domain/entities/oauth_credential.dart';
import '../../domain/enums/auth_provider.dart';
import '../../domain/enums/user_role.dart';
import '../../domain/failures/auth_failure.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_session_store.dart';
import '../mock/mock_auth_scenario.dart';
import '../storage/in_memory_auth_session_store.dart';
import '../../../settings/domain/repositories/guardian_profile_repository.dart';

class AuthRepositoryImpl
    implements
        AuthRepository,
        AccessTokenProvider,
        TokenRefresher,
        GuardianProfileRepository {
  AuthRepositoryImpl({
    this.scenario = MockAuthScenario.existingGuardian,
    this.providerScenarios = const {},
    this.responseDelay = const Duration(milliseconds: 500),
    AuthSessionStore? sessionStore,
  }) : _sessionStore = sessionStore ?? InMemoryAuthSessionStore();

  MockAuthScenario scenario;
  final Map<AuthProvider, MockAuthScenario> providerScenarios;
  final Duration responseDelay;
  final AuthSessionStore _sessionStore;
  AuthSession? _currentSession;
  final Map<AuthProvider, AuthenticatedUser> _registeredUsers = {};

  @override
  Future<AuthSession> signIn(OAuthCredential credential) async {
    await Future<void>.delayed(responseDelay);

    if (!credential.isValid) {
      throw const AuthFailure(
        type: AuthFailureType.invalidCredential,
        code: 'AUTH_INVALID_CREDENTIAL',
        message: '소셜 인증 정보가 올바르지 않아요.',
      );
    }

    final registeredUser = _registeredUsers[credential.provider];
    if (registeredUser != null) {
      return _saveSession(AuthSession(user: registeredUser, tokens: _tokens()));
    }

    final activeScenario = providerScenarios[credential.provider] ?? scenario;
    switch (activeScenario) {
      case MockAuthScenario.cancelled:
        throw const AuthFailure(
          type: AuthFailureType.cancelled,
          code: 'AUTH_CANCELLED',
          message: '로그인이 취소되었어요.',
        );
      case MockAuthScenario.networkFailure:
        throw const AuthFailure(
          type: AuthFailureType.network,
          code: 'NETWORK_ERROR',
          message: '인터넷 연결을 확인하고 다시 시도해 주세요.',
        );
      case MockAuthScenario.suspendedAccount:
        throw const AuthFailure(
          type: AuthFailureType.accountSuspended,
          code: 'AUTH_ACCOUNT_SUSPENDED',
          message: '현재 이용이 제한된 계정이에요.',
        );
      case MockAuthScenario.existingGuardian:
        return _saveSession(
          _session(
            credential: credential,
            role: UserRole.guardian,
            onboardingCompleted: true,
            email: 'guardian@dodam.test',
            nickname: '민지엄마',
          ),
        );
      case MockAuthScenario.existingExpert:
        return _saveSession(
          _session(
            credential: credential,
            role: UserRole.expert,
            onboardingCompleted: true,
            email: 'expert@dodam.test',
            nickname: '김하늘 상담사',
          ),
        );
      case MockAuthScenario.newGuardian:
        return _saveSession(
          _session(
            credential: credential,
            role: UserRole.guardian,
            onboardingCompleted: false,
            email: 'new-user@dodam.test',
          ),
        );
      case MockAuthScenario.newUserWithoutEmail:
        return _saveSession(
          _session(
            credential: credential,
            role: UserRole.guardian,
            onboardingCompleted: false,
            emailRequired: true,
          ),
        );
    }
  }

  @override
  Future<AuthSession> completeOnboarding(NewUserOnboardingInput input) async {
    await Future<void>.delayed(responseDelay);

    final currentSession = _currentSession;
    if (currentSession == null) {
      throw const AuthFailure(
        type: AuthFailureType.serverRejected,
        code: 'AUTH_SESSION_REQUIRED',
        message: '로그인 정보를 확인할 수 없어요. 다시 로그인해 주세요.',
      );
    }

    final completedUser = currentSession.user.copyWith(
      role: input.profile.role,
      onboardingCompleted: true,
      emailRequired: false,
      email: input.email ?? currentSession.user.email,
      nickname: input.profile.nickname,
    );
    _registeredUsers[completedUser.provider] = completedUser;

    return _saveSession(currentSession.copyWith(user: completedUser));
  }

  @override
  Future<AuthTokens> refreshTokens(String refreshToken) async {
    await Future<void>.delayed(responseDelay);
    if (refreshToken.isEmpty || _currentSession == null) {
      throw const AuthFailure(
        type: AuthFailureType.tokenExpired,
        code: 'AUTH_REFRESH_TOKEN_EXPIRED',
        message: '로그인 정보가 만료되었어요. 다시 로그인해 주세요.',
      );
    }

    final tokens = AuthTokens(
      accessToken: 'mock-access-token-refreshed',
      refreshToken: refreshToken,
      accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    _currentSession = _currentSession!.copyWith(tokens: tokens);
    await _sessionStore.save(_currentSession!);
    return tokens;
  }

  // 현재 인증 세션의 Access Token 제공
  @override
  Future<String?> readAccessToken() async =>
      _currentSession?.tokens.accessToken;

  // 현재 Refresh Token으로 Token pair 교체
  @override
  Future<bool> refreshAccessToken() async {
    final session = _currentSession;
    if (session == null) return false;

    try {
      await refreshTokens(session.tokens.refreshToken);
      return true;
    } on AuthFailure {
      _currentSession = null;
      await _sessionStore.clear();
      return false;
    }
  }

  @override
  Future<AuthSession?> restoreSession() async {
    await Future<void>.delayed(responseDelay);
    final session = await _sessionStore.read();
    _currentSession = session;
    return session;
  }

  @override
  Future<AuthenticatedUser> getCurrentUserProfile() async {
    await Future<void>.delayed(responseDelay);
    final session = _currentSession ?? await _sessionStore.read();
    if (session == null) {
      throw const AuthFailure(
        type: AuthFailureType.tokenExpired,
        code: 'AUTH_SESSION_REQUIRED',
        message: '로그인 정보를 확인할 수 없어요. 다시 로그인해 주세요.',
      );
    }
    return session.user;
  }

  @override
  Future<AuthenticatedUser> updateCurrentUserProfile({
    required String nickname,
  }) async {
    await Future<void>.delayed(responseDelay);
    final session = _currentSession ?? await _sessionStore.read();
    if (session == null) {
      throw const AuthFailure(
        type: AuthFailureType.tokenExpired,
        code: 'AUTH_SESSION_REQUIRED',
        message: '로그인 정보를 확인할 수 없어요. 다시 로그인해 주세요.',
      );
    }
    final user = session.user.copyWith(nickname: nickname.trim());
    await _saveSession(session.copyWith(user: user));
    return user;
  }

  @override
  Future<void> signOut() async {
    await Future<void>.delayed(responseDelay);
    _currentSession = null;
    await _sessionStore.clear();
  }

  Future<AuthSession> _saveSession(AuthSession session) async {
    _currentSession = session;
    await _sessionStore.save(session);
    return session;
  }

  AuthSession _session({
    required OAuthCredential credential,
    required UserRole role,
    required bool onboardingCompleted,
    bool emailRequired = false,
    String? email,
    String? nickname,
  }) => AuthSession(
    user: AuthenticatedUser(
      id: 'mock-user-${credential.provider.name}',
      provider: credential.provider,
      providerUserId: 'mock-provider-user-001',
      role: role,
      onboardingCompleted: onboardingCompleted,
      emailRequired: emailRequired,
      email: email,
      nickname: nickname,
    ),
    tokens: _tokens(),
  );

  AuthTokens _tokens() => AuthTokens(
    accessToken: 'mock-access-token',
    refreshToken: 'mock-refresh-token',
    accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
}
