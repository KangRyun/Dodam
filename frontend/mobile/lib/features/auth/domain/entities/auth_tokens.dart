class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.accessTokenExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime? accessTokenExpiresAt;

  bool isAccessTokenExpired({DateTime? now}) {
    final expiresAt = accessTokenExpiresAt;
    if (expiresAt == null) return false;

    return !expiresAt.isAfter(now ?? DateTime.now());
  }

  AuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? accessTokenExpiresAt,
  }) => AuthTokens(
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthTokens &&
          accessToken == other.accessToken &&
          refreshToken == other.refreshToken &&
          accessTokenExpiresAt == other.accessTokenExpiresAt;

  @override
  int get hashCode =>
      Object.hash(accessToken, refreshToken, accessTokenExpiresAt);
}
