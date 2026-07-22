import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';

enum SocialLoginProvider { kakao, google, naver }

class SocialLoginButton extends StatelessWidget {
  const SocialLoginButton({
    required this.provider,
    required this.onPressed,
    this.isLoading = false,
    super.key,
  });

  final SocialLoginProvider provider;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(provider);
    final enabled = onPressed != null && !isLoading;

    return Semantics(
      button: true,
      label: '${visual.name}로 시작하기',
      child: SizedBox(
        width: double.infinity,
        height: AppSizes.buttonHeight,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: visual.background,
            foregroundColor: visual.foreground,
            disabledBackgroundColor: AppColors.disabled,
            disabledForegroundColor: AppColors.onDisabled,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: visual.border),
            ),
          ),
          child: isLoading
              ? CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: visual.foreground,
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _ProviderMark(provider: provider),
                    ),
                    Text(
                      '${visual.name}로 시작하기',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ProviderMark extends StatelessWidget {
  const _ProviderMark({required this.provider});

  final SocialLoginProvider provider;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 28,
    child: Center(
      child: Text(
        switch (provider) {
          SocialLoginProvider.kakao => 'K',
          SocialLoginProvider.google => 'G',
          SocialLoginProvider.naver => 'N',
        },
        style: TextStyle(
          color: switch (provider) {
            SocialLoginProvider.kakao => const Color(0xFF391B1B),
            SocialLoginProvider.google => const Color(0xFF4285F4),
            SocialLoginProvider.naver => Colors.white,
          },
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _SocialVisual {
  const _SocialVisual({
    required this.name,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final String name;
  final Color background;
  final Color foreground;
  final Color border;
}

_SocialVisual _visualFor(SocialLoginProvider provider) => switch (provider) {
  SocialLoginProvider.kakao => const _SocialVisual(
    name: '카카오',
    background: Color(0xFFFEEA45),
    foreground: Color(0xFF2D2323),
    border: Colors.transparent,
  ),
  SocialLoginProvider.google => const _SocialVisual(
    name: '구글',
    background: Colors.white,
    foreground: AppColors.ink,
    border: AppColors.outline,
  ),
  SocialLoginProvider.naver => const _SocialVisual(
    name: '네이버',
    background: Color(0xFF03C75A),
    foreground: Colors.white,
    border: Colors.transparent,
  ),
};
