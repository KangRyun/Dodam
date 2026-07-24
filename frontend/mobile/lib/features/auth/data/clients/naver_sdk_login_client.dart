import '../../domain/clients/naver_login_client.dart';
import '../../domain/failures/auth_failure.dart';
import 'provider_sdk_gateway.dart';

/// Naver Login SDK 결과를 도담의 Naver 로그인 계약으로 변환한다.
final class NaverSdkLoginClient implements NaverLoginClient {
  NaverSdkLoginClient({ProviderSdkGateway? gateway})
    : _gateway = gateway ?? NaverProviderSdkGateway();

  final ProviderSdkGateway _gateway;

  @override
  Future<NaverLoginResult> signIn() async {
    try {
      final token = await _gateway.signIn();
      if (token == null || token.trim().isEmpty) {
        throw const AuthFailure(
          type: AuthFailureType.invalidCredential,
          code: 'NAVER_TOKEN_MISSING',
          message: '네이버 인증 정보를 확인하지 못했어요.',
        );
      }
      return NaverLoginSuccess(token);
    } on ProviderSdkFailure catch (failure) {
      if (failure.type == ProviderSdkFailureType.cancelled) {
        return const NaverLoginCancelled();
      }
      throw AuthFailure(
        type: failure.type == ProviderSdkFailureType.configuration
            ? AuthFailureType.configuration
            : AuthFailureType.providerRejected,
        code: failure.type == ProviderSdkFailureType.configuration
            ? 'NAVER_CONFIGURATION_INVALID'
            : 'NAVER_LOGIN_FAILED',
        message: '네이버 로그인을 완료하지 못했어요.',
        cause: failure,
      );
    }
  }

  @override
  Future<void> signOut() => _gateway.signOut();
}
