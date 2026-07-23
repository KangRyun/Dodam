import '../../domain/clients/kakao_login_client.dart';
import '../../domain/failures/auth_failure.dart';
import '../mock/kakao_login_scenario.dart';

// 목 시나리오 기반 카카오 로그인
final class KakaoLoginClientImpl implements KakaoLoginClient {
  KakaoLoginClientImpl({
    this.scenario = KakaoLoginScenario.success,
    this.responseDelay = const Duration(milliseconds: 400),
    this.accessToken = 'mock-kakao-access-token',
  });

  KakaoLoginScenario scenario;
  final Duration responseDelay;
  final String accessToken;

  @override
  Future<KakaoLoginResult> signIn() async {
    // SDK 응답 대기
    await Future<void>.delayed(responseDelay);

    return switch (scenario) {
      KakaoLoginScenario.success => KakaoLoginSuccess(accessToken),
      KakaoLoginScenario.cancelled => const KakaoLoginCancelled(),
      KakaoLoginScenario.providerFailure => throw const AuthFailure(
        type: AuthFailureType.providerRejected,
        code: 'KAKAO_LOGIN_FAILED',
        message: '카카오 로그인을 완료하지 못했어요.',
      ),
    };
  }

  @override
  Future<void> signOut() async {}
}
