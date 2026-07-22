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
        final scenario = switch (provider) {
          AuthProvider.kakao => MockAuthScenario.existingGuardian,
          AuthProvider.google => MockAuthScenario.cancelled,
          AuthProvider.naver => MockAuthScenario.networkFailure,
        };
        final loginService = SocialLoginService(
          AuthRepositoryImpl(scenario: scenario),
        );
        final state = switch (provider) {
          AuthProvider.kakao => await loginService.signInWithKakao(
            'preview-kakao-access-token',
          ),
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
