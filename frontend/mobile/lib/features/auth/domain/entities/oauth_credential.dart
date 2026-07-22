import '../enums/auth_provider.dart';

enum OAuthCredentialType { authorizationCode, accessToken, idToken }

class OAuthCredential {
  const OAuthCredential({
    required this.provider,
    required this.type,
    required this.value,
  });

  final AuthProvider provider;
  final OAuthCredentialType type;
  final String value;

  bool get isValid => value.trim().isNotEmpty;
}
