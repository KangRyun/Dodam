import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const SocialLoginPreview());
}

class SocialLoginPreview extends StatelessWidget {
  const SocialLoginPreview({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '도담 소셜 로그인 미리보기',
    home: SocialLoginScreen(
      onSignIn: (provider) async {
        // Provider별 로그인 결과 미리보기
        if (provider == AuthProvider.google) {
          final coordinator = GoogleLoginCoordinator(
            GoogleLoginClientImpl(),
            SocialLoginService(
              AuthRepositoryImpl(scenario: MockAuthScenario.existingGuardian),
            ),
          );
          final state = await coordinator.signIn();
          debugPrint('Preview login result: ${state.status.name}');
          if (state.failure case final failure?) throw failure;
          return;
        }

        final scenario = switch (provider) {
          AuthProvider.kakao => MockAuthScenario.existingGuardian,
          AuthProvider.google => MockAuthScenario.existingGuardian,
          AuthProvider.naver => MockAuthScenario.networkFailure,
        };
        final loginService = SocialLoginService(
          AuthRepositoryImpl(scenario: scenario),
        );
        // Provider별 목 로그인 흐름
        final state = switch (provider) {
          AuthProvider.kakao => await KakaoLoginCoordinator(
            KakaoLoginClientImpl(
              responseDelay: const Duration(milliseconds: 500),
              accessToken: 'preview-kakao-access-token',
            ),
            loginService,
          ).signIn(),
          AuthProvider.google => await loginService.signInWithGoogle(
            'preview-google-id-token',
          ),
          AuthProvider.naver => await loginService.signInWithNaver(
            'preview-naver-access-token',
          ),
        };
        debugPrint('Preview login result: ${state.status.name}');
        if (state.failure case final failure?) throw failure;
      },
    ),
  );
}
