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
      enabled: enabled,
      label: visual.label,
      child: SizedBox(
        key: ValueKey('social-login-${provider.name}'),
        width: double.infinity,
        height: AppSizes.buttonHeight,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: visual.horizontalPadding),
            backgroundColor: visual.background,
            foregroundColor: visual.foreground,
            disabledBackgroundColor: AppColors.disabled,
            disabledForegroundColor: AppColors.onDisabled,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(visual.borderRadius),
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
                      child: Image.asset(
                        visual.iconAsset,
                        width: visual.iconSize,
                        height: visual.iconSize,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    Text(
                      visual.label,
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

class _SocialVisual {
  const _SocialVisual({
    required this.label,
    required this.iconAsset,
    required this.iconSize,
    required this.background,
    required this.foreground,
    required this.border,
    required this.borderRadius,
    required this.horizontalPadding,
  });

  final String label;
  final String iconAsset;
  final double iconSize;
  final Color background;
  final Color foreground;
  final Color border;
  final double borderRadius;
  final double horizontalPadding;
}

_SocialVisual _visualFor(SocialLoginProvider provider) => switch (provider) {
  SocialLoginProvider.kakao => const _SocialVisual(
    label: '카카오로 시작',
    iconAsset: 'assets/branding/kakao_symbol.png',
    iconSize: 28,
    background: Color(0xFFFEE500),
    foreground: Color(0xD9000000),
    border: Colors.transparent,
    borderRadius: 12,
    horizontalPadding: 20,
  ),
  SocialLoginProvider.google => const _SocialVisual(
    label: 'Google 계정으로 시작',
    iconAsset: 'assets/branding/google_g.png',
    iconSize: 22,
    background: Colors.white,
    foreground: Color(0xFF1F1F1F),
    border: Color(0xFF747775),
    borderRadius: 12,
    horizontalPadding: 12,
  ),
  SocialLoginProvider.naver => const _SocialVisual(
    label: '네이버로 시작',
    iconAsset: 'assets/branding/naver_n.png',
    iconSize: 26,
    background: Color(0xFF03A94D),
    foreground: Colors.white,
    border: Colors.transparent,
    borderRadius: 12,
    horizontalPadding: 20,
  ),
};
