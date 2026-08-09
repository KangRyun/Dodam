import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';

void main() => runApp(const AuthOnboardingFlowPreview());

class AuthOnboardingFlowPreview extends StatefulWidget {
  const AuthOnboardingFlowPreview({super.key});

  @override
  State<AuthOnboardingFlowPreview> createState() =>
      _AuthOnboardingFlowPreviewState();
}

class _AuthOnboardingFlowPreviewState extends State<AuthOnboardingFlowPreview> {
  AuthProvider? _provider;
  NewUserOnboardingInput? _completedInput;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '도담 인증 흐름 미리보기',
    home: _completedInput != null
        ? _OnboardingCompletePreview(
            input: _completedInput!,
            onRestart: () => setState(() {
              _provider = null;
              _completedInput = null;
            }),
          )
        : _provider == null
        ? SocialLoginScreen(
            onSignIn: (provider) async {
              await Future<void>.delayed(const Duration(milliseconds: 500));
              if (mounted) setState(() => _provider = provider);
            },
          )
        : NewUserOnboardingFlowScreen(
            needsEmail: _provider == AuthProvider.kakao,
            onBack: () => setState(() => _provider = null),
            onComplete: (input) async {
              await Future<void>.delayed(const Duration(milliseconds: 500));
              if (mounted) setState(() => _completedInput = input);
            },
          ),
  );
}

class _OnboardingCompletePreview extends StatelessWidget {
  const _OnboardingCompletePreview({
    required this.input,
    required this.onRestart,
  });

  final NewUserOnboardingInput input;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('●', style: TextStyle(color: AppColors.leaf)),
              const SizedBox(height: AppSpacing.md),
              const Text(
                '시작할 준비가 됐어요!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${input.profile.nickname}님, 도담에 오신 것을 환영해요.\n다음 이슈에서 역할에 맞는 홈 화면으로 연결돼요.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: '처음부터 다시 보기',
                onPressed: onRestart,
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
