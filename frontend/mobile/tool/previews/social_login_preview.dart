import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';

void main() {
  final repository = AuthRepositoryImpl(
    scenario: MockAuthScenario.existingGuardian,
  );
  final loginService = SocialLoginService(repository);

  runApp(SocialLoginPreview(loginService: loginService));
}

class SocialLoginPreview extends StatelessWidget {
  const SocialLoginPreview({required this.loginService, super.key});

  final SocialLoginService loginService;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '도담 소셜 로그인 미리보기',
    home: SocialLoginScreen(
      onSignIn: (provider) async {
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
      },
    ),
  );
}
