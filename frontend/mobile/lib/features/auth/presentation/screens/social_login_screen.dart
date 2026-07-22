import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/enums/auth_provider.dart';

typedef SocialSignInCallback = Future<void> Function(AuthProvider provider);

class SocialLoginScreen extends StatefulWidget {
  const SocialLoginScreen({
    required this.onSignIn,
    this.onExpertGuideTap,
    this.onTermsTap,
    this.onPrivacyPolicyTap,
    super.key,
  });

  final SocialSignInCallback onSignIn;
  final VoidCallback? onExpertGuideTap;
  final VoidCallback? onTermsTap;
  final VoidCallback? onPrivacyPolicyTap;

  @override
  State<SocialLoginScreen> createState() => _SocialLoginScreenState();
}

class _SocialLoginScreenState extends State<SocialLoginScreen> {
  AuthProvider? _activeProvider;

  bool get _isSigningIn => _activeProvider != null;

  Future<void> _signIn(AuthProvider provider) async {
    if (_isSigningIn) return;

    setState(() => _activeProvider = provider);
    try {
      await widget.onSignIn(provider);
    } finally {
      if (mounted) setState(() => _activeProvider = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 700;
          final horizontalPadding = isTablet ? AppSpacing.xxl : AppSpacing.lg;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: AppSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - (AppSpacing.lg * 2),
              ),
              child: Center(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: EdgeInsets.all(isTablet ? AppSpacing.xl : 0),
                  decoration: isTablet
                      ? BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.outline),
                        )
                      : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: AppSpacing.xxl),
                      _SocialButtons(
                        activeProvider: _activeProvider,
                        enabled: !_isSigningIn,
                        onPressed: _signIn,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _ExpertGuideLink(onTap: widget.onExpertGuideTap),
                      const SizedBox(height: AppSpacing.xl),
                      _PolicyNotice(
                        onTermsTap: widget.onTermsTap,
                        onPrivacyPolicyTap: widget.onPrivacyPolicyTap,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      _BrandMark(),
      SizedBox(height: AppSpacing.lg),
      Text(
        '그림과 대화로\n아이의 마음을 만나봐요',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 28,
          height: 1.32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
      ),
      SizedBox(height: AppSpacing.sm),
      Text(
        '아이가 편안하게 마음을 표현하도록\n도담이가 곁에서 함께할게요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.inkMuted, fontSize: 16, height: 1.5),
      ),
    ],
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '도담 로고',
    child: Container(
      width: 88,
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.leafSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: const Text('🖍️', style: TextStyle(fontSize: 44)),
    ),
  );
}

class _SocialButtons extends StatelessWidget {
  const _SocialButtons({
    required this.activeProvider,
    required this.enabled,
    required this.onPressed,
  });

  final AuthProvider? activeProvider;
  final bool enabled;
  final ValueChanged<AuthProvider> onPressed;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SocialLoginButton(
        provider: SocialLoginProvider.kakao,
        isLoading: activeProvider == AuthProvider.kakao,
        onPressed: enabled ? () => onPressed(AuthProvider.kakao) : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      SocialLoginButton(
        provider: SocialLoginProvider.google,
        isLoading: activeProvider == AuthProvider.google,
        onPressed: enabled ? () => onPressed(AuthProvider.google) : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      SocialLoginButton(
        provider: SocialLoginProvider.naver,
        isLoading: activeProvider == AuthProvider.naver,
        onPressed: enabled ? () => onPressed(AuthProvider.naver) : null,
      ),
    ],
  );
}

class _ExpertGuideLink extends StatelessWidget {
  const _ExpertGuideLink({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    icon: const Icon(Icons.school_rounded, size: 18),
    label: const Text('상담사·치료사이신가요? 전문가 이용 안내'),
    style: TextButton.styleFrom(
      foregroundColor: AppColors.inkMuted,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

class _PolicyNotice extends StatelessWidget {
  const _PolicyNotice({this.onTermsTap, this.onPrivacyPolicyTap});

  final VoidCallback? onTermsTap;
  final VoidCallback? onPrivacyPolicyTap;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text(
        '계속하면 ',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
      ),
      _PolicyButton(label: '이용약관', onPressed: onTermsTap),
      const Text(
        ' 및 ',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
      ),
      _PolicyButton(label: '개인정보 처리방침', onPressed: onPrivacyPolicyTap),
      const Text(
        '에 동의합니다.',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
      ),
    ],
  );
}

class _PolicyButton extends StatelessWidget {
  const _PolicyButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, AppSizes.minTouchTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      foregroundColor: AppColors.ink,
      textStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.underline,
      ),
    ),
    child: Text(label),
  );
}
