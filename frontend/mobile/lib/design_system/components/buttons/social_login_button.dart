import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      key: ValueKey('social-login-${provider.name}-icon'),
                      dimension: 20,
                      child: SvgPicture.asset(
                        visual.iconAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        visual.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
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
    required this.background,
    required this.foreground,
    required this.border,
    required this.borderRadius,
  });

  final String label;
  final String iconAsset;
  final Color background;
  final Color foreground;
  final Color border;
  final double borderRadius;
}

_SocialVisual _visualFor(SocialLoginProvider provider) => switch (provider) {
  SocialLoginProvider.kakao => const _SocialVisual(
    label: '카카오로 시작',
    iconAsset: 'assets/branding/kakao_symbol.svg',
    background: Color(0xFFFEE500),
    foreground: Color(0xD9000000),
    border: Colors.transparent,
    borderRadius: 12,
  ),
  SocialLoginProvider.google => const _SocialVisual(
    label: 'Google 계정으로 시작',
    iconAsset: 'assets/branding/google_g.svg',
    background: Colors.white,
    foreground: Color(0xFF1F1F1F),
    border: Color(0xFF747775),
    borderRadius: 12,
  ),
  SocialLoginProvider.naver => const _SocialVisual(
    label: '네이버로 시작',
    iconAsset: 'assets/branding/naver_n.svg',
    background: Color(0xFF03A94D),
    foreground: Colors.white,
    border: Colors.transparent,
    borderRadius: 12,
  ),
};
