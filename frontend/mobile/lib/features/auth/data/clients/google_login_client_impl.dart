import '../../domain/clients/google_login_client.dart';
import '../../domain/failures/auth_failure.dart';
import '../mock/google_login_scenario.dart';

// 목 시나리오 기반 구글 로그인
final class GoogleLoginClientImpl implements GoogleLoginClient {
  GoogleLoginClientImpl({
    this.scenario = GoogleLoginScenario.success,
    this.responseDelay = const Duration(milliseconds: 400),
    this.idToken = 'mock-google-id-token',
  });

  GoogleLoginScenario scenario;
  final Duration responseDelay;
  final String idToken;

  @override
  Future<GoogleLoginResult> signIn() async {
    // SDK 응답 대기
    await Future<void>.delayed(responseDelay);

    return switch (scenario) {
      GoogleLoginScenario.success => GoogleLoginSuccess(idToken),
      GoogleLoginScenario.cancelled => const GoogleLoginCancelled(),
      GoogleLoginScenario.providerFailure => throw const AuthFailure(
        type: AuthFailureType.providerRejected,
        code: 'GOOGLE_LOGIN_FAILED',
        message: '구글 로그인을 완료하지 못했어요.',
      ),
    };
  }
}
