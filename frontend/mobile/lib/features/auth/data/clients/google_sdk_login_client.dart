import '../../domain/clients/google_login_client.dart';
import '../../domain/failures/auth_failure.dart';
import 'provider_sdk_gateway.dart';

/// Google Sign-In SDK 결과를 도담의 Google 로그인 계약으로 변환한다.
final class GoogleSdkLoginClient implements GoogleLoginClient {
  GoogleSdkLoginClient({ProviderSdkGateway? gateway})
    : _gateway = gateway ?? GoogleProviderSdkGateway();

  final ProviderSdkGateway _gateway;

  @override
  Future<GoogleLoginResult> signIn() async {
    try {
      final token = await _gateway.signIn();
      if (token == null || token.trim().isEmpty) {
        throw const AuthFailure(
          type: AuthFailureType.invalidCredential,
          code: 'GOOGLE_ID_TOKEN_MISSING',
          message: 'Google 인증 정보를 확인하지 못했어요.',
        );
      }
      return GoogleLoginSuccess(token);
    } on ProviderSdkFailure catch (failure) {
      if (failure.type == ProviderSdkFailureType.cancelled) {
        return const GoogleLoginCancelled();
      }
      throw AuthFailure(
        type: failure.type == ProviderSdkFailureType.configuration
            ? AuthFailureType.configuration
            : AuthFailureType.providerRejected,
        code: failure.type == ProviderSdkFailureType.configuration
            ? 'GOOGLE_CONFIGURATION_INVALID'
            : 'GOOGLE_LOGIN_FAILED',
        message: 'Google 로그인을 완료하지 못했어요.',
        cause: failure,
      );
    }
  }

  @override
  Future<void> signOut() => _gateway.signOut();
}
