/// Minimal bridge for attaching the auth feature's current access token.
///
/// The auth feature can implement this later without changing AuthRepository.
abstract interface class AccessTokenProvider {
  Future<String?> readAccessToken();
}
