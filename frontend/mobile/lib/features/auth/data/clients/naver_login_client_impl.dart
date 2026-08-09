import '../../domain/clients/naver_login_client.dart';
import '../../domain/failures/auth_failure.dart';
import '../mock/naver_login_scenario.dart';

// 목 시나리오 기반 네이버 로그인
final class NaverLoginClientImpl implements NaverLoginClient {
  NaverLoginClientImpl({
    this.scenario = NaverLoginScenario.success,
    this.responseDelay = const Duration(milliseconds: 400),
    this.accessToken = 'mock-naver-access-token',
  });

  NaverLoginScenario scenario;
  final Duration responseDelay;
  final String accessToken;

  @override
  Future<NaverLoginResult> signIn() async {
    // SDK 응답 대기
    await Future<void>.delayed(responseDelay);

    return switch (scenario) {
      NaverLoginScenario.success => NaverLoginSuccess(accessToken),
      NaverLoginScenario.cancelled => const NaverLoginCancelled(),
      NaverLoginScenario.providerFailure => throw const AuthFailure(
        type: AuthFailureType.providerRejected,
        code: 'NAVER_LOGIN_FAILED',
        message: '네이버 로그인을 완료하지 못했어요.',
      ),
    };
  }

  @override
  Future<void> signOut() async {}
}
