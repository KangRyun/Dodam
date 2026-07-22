import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/authenticated_user.dart';
import '../../domain/enums/auth_provider.dart';
import '../../domain/enums/user_role.dart';
import '../../domain/repositories/auth_session_store.dart';

final class SecureAuthSessionStore implements AuthSessionStore {
  SecureAuthSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'dodam.auth.session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> save(AuthSession session) =>
      _storage.write(key: _sessionKey, value: jsonEncode(_toJson(session)));

  @override
  Future<AuthSession?> read() async {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null || encoded.isEmpty) return null;

    try {
      return _fromJson(jsonDecode(encoded) as Map<String, dynamic>);
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);

  Map<String, dynamic> _toJson(AuthSession session) => {
    'user': {
      'id': session.user.id,
      'provider': session.user.provider.wireName,
      'providerUserId': session.user.providerUserId,
      'role': session.user.role.wireName,
      'onboardingCompleted': session.user.onboardingCompleted,
      'email': session.user.email,
      'nickname': session.user.nickname,
      'profileImageUrl': session.user.profileImageUrl,
    },
    'tokens': {
      'accessToken': session.tokens.accessToken,
      'refreshToken': session.tokens.refreshToken,
      'accessTokenExpiresAt': session.tokens.accessTokenExpiresAt
          ?.toIso8601String(),
    },
  };

  AuthSession _fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    final tokens = json['tokens'] as Map<String, dynamic>;
    final expiresAt = tokens['accessTokenExpiresAt'] as String?;

    return AuthSession(
      user: AuthenticatedUser(
        id: user['id'] as String,
        provider: AuthProvider.fromWireName(user['provider'] as String),
        providerUserId: user['providerUserId'] as String,
        role: UserRole.values.firstWhere(
          (role) => role.wireName == user['role'],
        ),
        onboardingCompleted: user['onboardingCompleted'] as bool,
        email: user['email'] as String?,
        nickname: user['nickname'] as String?,
        profileImageUrl: user['profileImageUrl'] as String?,
      ),
      tokens: AuthTokens(
        accessToken: tokens['accessToken'] as String,
        refreshToken: tokens['refreshToken'] as String,
        accessTokenExpiresAt: expiresAt == null
            ? null
            : DateTime.parse(expiresAt),
      ),
    );
  }
}
