import '../../domain/clients/kakao_login_client.dart';
import '../../domain/failures/auth_failure.dart';
import 'provider_sdk_gateway.dart';

/// Kakao SDK 결과를 도담의 Kakao 로그인 계약으로 변환한다.
final class KakaoSdkLoginClient implements KakaoLoginClient {
  KakaoSdkLoginClient({ProviderSdkGateway? gateway})
    : _gateway = gateway ?? KakaoProviderSdkGateway();

  final ProviderSdkGateway _gateway;

  @override
  Future<KakaoLoginResult> signIn() async {
    try {
      final token = await _gateway.signIn();
      if (token == null || token.trim().isEmpty) {
        throw const AuthFailure(
          type: AuthFailureType.invalidCredential,
          code: 'KAKAO_TOKEN_MISSING',
          message: '카카오 인증 정보를 확인하지 못했어요.',
        );
      }
      return KakaoLoginSuccess(token);
    } on ProviderSdkFailure catch (failure) {
      if (failure.type == ProviderSdkFailureType.cancelled) {
        return const KakaoLoginCancelled();
      }
      throw AuthFailure(
        type: failure.type == ProviderSdkFailureType.configuration
            ? AuthFailureType.configuration
            : AuthFailureType.providerRejected,
        code: failure.type == ProviderSdkFailureType.configuration
            ? 'KAKAO_CONFIGURATION_INVALID'
            : 'KAKAO_LOGIN_FAILED',
        message: '카카오 로그인을 완료하지 못했어요.',
        cause: failure,
      );
    }
  }

  @override
  Future<void> signOut() => _gateway.signOut();
}
