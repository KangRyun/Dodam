import '../enums/auth_provider.dart';

enum OAuthCredentialType { accessToken, idToken }

class OAuthCredential {
  const OAuthCredential({
    required this.provider,
    required this.type,
    required this.value,
  });

  final AuthProvider provider;
  final OAuthCredentialType type;
  final String value;

  bool get isValid => value.trim().isNotEmpty && hasExpectedType;

  bool get hasExpectedType => switch (provider) {
    AuthProvider.kakao ||
    AuthProvider.naver => type == OAuthCredentialType.accessToken,
    AuthProvider.google => type == OAuthCredentialType.idToken,
  };
}
