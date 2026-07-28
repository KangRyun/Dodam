import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/network/auth/access_token_provider.dart';
import '../../../../core/network/auth/token_refresher.dart';
import '../../../../core/network/json_data.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/authenticated_user.dart';
import '../../domain/entities/consent_agreement_input.dart';
import '../../domain/entities/new_user_onboarding_input.dart';
import '../../domain/entities/oauth_credential.dart';
import '../../domain/enums/auth_provider.dart';
import '../../domain/enums/user_role.dart';
import '../../domain/failures/auth_failure.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_session_store.dart';
import '../../domain/repositories/device_id_provider.dart';

/// Provider Token을 서비스 Token으로 교환하고 인증 세션을 영속화한다.
final class RemoteAuthRepository
    implements AuthRepository, AccessTokenProvider, TokenRefresher {
  factory RemoteAuthRepository({
    required ApiClient Function() apiClient,
    required DeviceIdProvider deviceIdProvider,
    required AuthSessionStore sessionStore,
  }) => RemoteAuthRepository._(apiClient, deviceIdProvider, sessionStore);

  RemoteAuthRepository._(
    this._apiClient,
    this._deviceIdProvider,
    this._sessionStore,
  );

  final ApiClient Function() _apiClient;
  final DeviceIdProvider _deviceIdProvider;
  final AuthSessionStore _sessionStore;
  AuthSession? _currentSession;

  @override
  Future<AuthSession> signIn(OAuthCredential credential) async {
    if (!credential.isValid) {
      throw const AuthFailure(
        type: AuthFailureType.invalidCredential,
        code: 'AUTH_INVALID_CREDENTIAL',
        message: '소셜 인증 정보가 올바르지 않아요.',
      );
    }

    try {
      final response = await _apiClient().post<Map<String, dynamic>>(
        'auth/oauth/${credential.provider.name}',
        data: {
          'accessToken': credential.type == OAuthCredentialType.accessToken
              ? credential.value
              : null,
          'idToken': credential.type == OAuthCredentialType.idToken
              ? credential.value
              : null,
          'deviceId': await _deviceIdProvider.getDeviceId(),
        },
      );
      final session = _parseLoginSession(
        jsonObject(response.data)['data'],
        credential.provider,
      );
      return _saveSession(session);
    } on ApiFailure catch (failure) {
      throw _mapFailure(failure, credentialRequest: true);
    }
  }

  @override
  Future<AuthSession> completeOnboarding(NewUserOnboardingInput input) async {
    final session = _currentSession;
    if (session == null) {
      throw const AuthFailure(
        type: AuthFailureType.tokenExpired,
        code: 'AUTH_SESSION_REQUIRED',
        message: '로그인 정보를 확인할 수 없어요. 다시 로그인해 주세요.',
      );
    }
    final email = input.email ?? session.user.email;
    if (email == null || email.trim().isEmpty) {
      throw const AuthFailure(
        type: AuthFailureType.invalidCredential,
        code: 'ONBOARDING_EMAIL_REQUIRED',
        message: '이메일을 입력해 주세요.',
      );
    }

    try {
      final termsResponse = await _apiClient().get<Map<String, dynamic>>(
        'consents/terms',
        queryParameters: const {'targetScope': 'USER'},
      );
      final terms = jsonObject(termsResponse.data)['data'] as List<dynamic>;
      final agreements = terms
          .map((rawTerm) {
            final term = jsonObject(rawTerm);
            final consent = _consentByTermCode(term['termCode'] as String);
            return {
              'termId': term['termId'],
              'action': consent != null && input.consents.isAgreed(consent)
                  ? 'AGREE'
                  : 'WITHDRAW',
            };
          })
          .toList(growable: false);

      final response = await _apiClient().put<Map<String, dynamic>>(
        'users/me/onboarding',
        data: {
          'role': input.profile.role.wireName,
          'nickname': input.profile.nickname,
          'email': email,
          'profileImageFileId': null,
          'consents': agreements,
        },
      );
      final userData = jsonObject(jsonObject(response.data)['data']);
      return _saveSession(
        session.copyWith(user: _parseUser(userData, session.user.provider)),
      );
    } on ApiFailure catch (failure) {
      throw _mapFailure(failure);
    }
  }

  @override
  Future<AuthTokens> refreshTokens(String refreshToken) async {
    final session = _currentSession;
    if (session == null || refreshToken.isEmpty) {
      throw const AuthFailure(
        type: AuthFailureType.tokenExpired,
        code: 'AUTH_REFRESH_TOKEN_REQUIRED',
        message: '로그인 정보가 만료되었어요. 다시 로그인해 주세요.',
      );
    }

    try {
      final response = await _apiClient().post<Map<String, dynamic>>(
        'auth/reissue',
        data: {
          'refreshToken': refreshToken,
          'deviceId': await _deviceIdProvider.getDeviceId(),
        },
      );
      final refreshed = _parseLoginSession(
        jsonObject(response.data)['data'],
        session.user.provider,
      );
      await _saveSession(refreshed);
      return refreshed.tokens;
    } on ApiFailure catch (failure) {
      throw _mapFailure(failure);
    }
  }

  @override
  Future<String?> readAccessToken() async =>
      _currentSession?.tokens.accessToken;

  @override
  Future<bool> refreshAccessToken() async {
    final session = _currentSession;
    if (session == null) return false;
    try {
      await refreshTokens(session.tokens.refreshToken);
      return true;
    } on AuthFailure catch (failure) {
      if (_isTerminalRefreshFailure(failure)) {
        _currentSession = null;
        await _sessionStore.clear();
      }
      return false;
    }
  }

  @override
  Future<AuthSession?> restoreSession() async {
    _currentSession = await _sessionStore.read();
    return _currentSession;
  }

  @override
  Future<void> signOut() async {
    _currentSession = null;
    await _sessionStore.clear();
  }

  Future<AuthSession> _saveSession(AuthSession session) async {
    _currentSession = session;
    await _sessionStore.save(session);
    return session;
  }

  AuthSession _parseLoginSession(Object? rawData, AuthProvider provider) {
    final data = jsonObject(rawData);
    final expiresInSeconds = (data['accessTokenExpiresInSeconds'] as num)
        .toInt();
    return AuthSession(
      user: _parseUser(jsonObject(data['user']), provider),
      tokens: AuthTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        accessTokenExpiresAt: DateTime.now().add(
          Duration(seconds: expiresInSeconds),
        ),
      ),
    );
  }

  AuthenticatedUser _parseUser(
    Map<String, dynamic> data,
    AuthProvider provider,
  ) {
    final userId = (data['userId'] as num).toInt().toString();
    final role = data['role'] as String?;
    return AuthenticatedUser(
      id: userId,
      provider: provider,
      providerUserId: userId,
      role: role == null
          ? null
          : UserRole.values.firstWhere((value) => value.wireName == role),
      onboardingCompleted: data['onboardingCompleted'] as bool,
      // Provider 종류가 아니라 백엔드가 판정한 이메일 추가 수집 여부를 따른다.
      emailRequired: data['emailRequired'] as bool? ?? false,
      email: data['email'] as String?,
      nickname: data['nickname'] as String?,
    );
  }

  ConsentCode? _consentByTermCode(String termCode) => switch (termCode) {
    'SERVICE_TOS' || 'SERVICE_TERMS' => ConsentCode.serviceTerms,
    'CHILD_PERSONAL_INFO' => ConsentCode.childPrivacy,
    'DRAWING_ANALYSIS' => ConsentCode.drawingAnalysis,
    'VOICE_PROCESSING' => ConsentCode.voiceProcessing,
    'EXPERT_SHARING' => ConsentCode.expertSharing,
    'AI_TRAINING' => ConsentCode.aiTraining,
    'MARKETING' => ConsentCode.marketingNotifications,
    _ => null,
  };

  bool _isTerminalRefreshFailure(AuthFailure failure) =>
      failure.type == AuthFailureType.tokenExpired ||
      failure.type == AuthFailureType.accountSuspended;

  AuthFailure _mapFailure(
    ApiFailure failure, {
    bool credentialRequest = false,
  }) {
    if (failure is ApiTransportFailure) {
      return AuthFailure(
        type: failure.type == ApiTransportFailureType.cancelled
            ? AuthFailureType.cancelled
            : AuthFailureType.network,
        code: 'NETWORK_ERROR',
        message: '인터넷 연결을 확인하고 다시 시도해 주세요.',
        cause: failure,
      );
    }

    final responseFailure = failure as ApiResponseFailure;
    final code = responseFailure.error?.code;
    final type = switch (code) {
      'AUTH_401_001' when credentialRequest =>
        AuthFailureType.invalidCredential,
      'AUTH_401_002' ||
      'AUTH_401_003' ||
      'AUTH_401_004' ||
      'AUTH_401_005' ||
      'AUTH_401_006' => AuthFailureType.tokenExpired,
      'AUTH_403_001' => AuthFailureType.accountSuspended,
      _ when responseFailure.statusCode == 401 =>
        credentialRequest
            ? AuthFailureType.invalidCredential
            : AuthFailureType.tokenExpired,
      _ => AuthFailureType.serverRejected,
    };
    return AuthFailure(
      type: type,
      code: code,
      message:
          responseFailure.error?.message ??
          (type == AuthFailureType.tokenExpired
              ? '로그인 정보가 만료되었어요. 다시 로그인해 주세요.'
              : '로그인 요청을 처리하지 못했어요.'),
      cause: failure,
    );
  }
}
