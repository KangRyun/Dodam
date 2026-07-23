import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OAuth SDK Login Client', () {
    test('Kakao SDK Access Token을 반환한다', () async {
      final client = KakaoSdkLoginClient(
        gateway: _FakeProviderSdkGateway(token: 'kakao-access-token'),
      );

      final result = await client.signIn();

      expect(
        result,
        isA<KakaoLoginSuccess>().having(
          (success) => success.accessToken,
          'accessToken',
          'kakao-access-token',
        ),
      );
    });

    test('Kakao SDK 설정 오류를 식별 가능한 인증 실패로 매핑한다', () async {
      final client = KakaoSdkLoginClient(
        gateway: _FakeProviderSdkGateway(
          failure: const ProviderSdkFailure(
            ProviderSdkFailureType.configuration,
          ),
        ),
      );

      await expectLater(
        client.signIn(),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.code,
            'code',
            'KAKAO_CONFIGURATION_INVALID',
          ),
        ),
      );
    });

    test('Google SDK ID Token 누락을 인증 실패로 매핑한다', () async {
      final client = GoogleSdkLoginClient(gateway: _FakeProviderSdkGateway());

      await expectLater(
        client.signIn(),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.type,
            'type',
            AuthFailureType.invalidCredential,
          ),
        ),
      );
    });

    test('Google SDK ID Token을 반환한다', () async {
      final client = GoogleSdkLoginClient(
        gateway: _FakeProviderSdkGateway(token: 'google-id-token'),
      );

      final result = await client.signIn();

      expect(
        result,
        isA<GoogleLoginSuccess>().having(
          (success) => success.idToken,
          'idToken',
          'google-id-token',
        ),
      );
    });

    test('Naver SDK 사용자 취소를 취소 결과로 매핑한다', () async {
      final client = NaverSdkLoginClient(
        gateway: _FakeProviderSdkGateway(
          failure: const ProviderSdkFailure(ProviderSdkFailureType.cancelled),
        ),
      );

      final result = await client.signIn();

      expect(result, isA<NaverLoginCancelled>());
    });

    test('Naver iOS SDK의 취소 오류 메시지를 사용자 취소로 분류한다', () {
      expect(
        NaverProviderSdkGateway.failureTypeForErrorMessage(
          'Login cancelled by user',
        ),
        ProviderSdkFailureType.cancelled,
      );
      expect(
        NaverProviderSdkGateway.failureTypeForErrorMessage('Server error'),
        ProviderSdkFailureType.rejected,
      );
    });

    test('Naver SDK Access Token을 반환한다', () async {
      final client = NaverSdkLoginClient(
        gateway: _FakeProviderSdkGateway(token: 'naver-access-token'),
      );

      final result = await client.signIn();

      expect(
        result,
        isA<NaverLoginSuccess>().having(
          (success) => success.accessToken,
          'accessToken',
          'naver-access-token',
        ),
      );
    });

    test('Provider 로그아웃을 SDK Gateway에 위임한다', () async {
      final gateway = _FakeProviderSdkGateway(token: 'token');
      final client = KakaoSdkLoginClient(gateway: gateway);

      await client.signOut();

      expect(gateway.signOutCallCount, 1);
    });
  });
}

final class _FakeProviderSdkGateway implements ProviderSdkGateway {
  _FakeProviderSdkGateway({this.token, this.failure});

  final String? token;
  final ProviderSdkFailure? failure;
  int signOutCallCount = 0;

  @override
  Future<String?> signIn() async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return token;
  }

  @override
  Future<void> signOut() async {
    signOutCallCount += 1;
  }
}
